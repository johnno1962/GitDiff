//
//  GitDelta.mm
//  Git difference highlighter plugin.
//
//  Repo: https://github.com/johnno1962/GitDiff
//
//  $Id: //depot/GitDiff/Classes/GitDiff.mm#34 $
//
//  Created by John Holdsworth on 26/07/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//

#import "GitDiff.h"
#import <objc/runtime.h>

static GitDiff *gitDiffPlugin;

@interface GitDiff()

@property IBOutlet NSColorWell *modifiedColor, *addedColor, *deletedColor, *popoverColor;

@property NSMutableDictionary *diffsByFile;
@property NSText *popover;

@end

@implementation GitDiff

+ (void)pluginDidLoad:(NSBundle *)plugin
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		gitDiffPlugin = [[self alloc] init];
        gitDiffPlugin.diffsByFile = [NSMutableDictionary new];

        if ( ![NSBundle loadNibNamed:@"GitDiff" owner:gitDiffPlugin] )
            NSLog( @"GitDiff Plugin: Could not load colors interface." );

        gitDiffPlugin.popover = [[NSText alloc] initWithFrame:NSZeroRect];
        gitDiffPlugin.popover.wantsLayer = YES;
        gitDiffPlugin.popover.layer.cornerRadius = 6.0;

        gitDiffPlugin.popover.backgroundColor = gitDiffPlugin.popoverColor.color;

        Class aClass = NSClassFromString(@"DVTTextSidebarView");
        [self swizzleClass:aClass
                  exchange:@selector(_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToReplace:getParaRectBlock:)
                      with:@selector(gitdiff_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToReplace:getParaRectBlock:)];
        [self swizzleClass:aClass
                  exchange:@selector(annotationAtSidebarPoint:)
                      with:@selector(gitdiff_annotationAtSidebarPoint:)];
    });
}

+ (void)swizzleClass:(Class)aClass exchange:(SEL)origMethod with:(SEL)altMethod
{
    method_exchangeImplementations(class_getInstanceMethod(aClass, origMethod),
                                   class_getInstanceMethod(aClass, altMethod));
}

@end

#import <map>
#import <string>

template <class _M,typename _K>
static bool exists( const _M &map, const _K &key ) {
    return map.find(key) != map.end();
}

@interface GitFileDiffs : NSObject {
@public
    std::map<unsigned long,std::string> deleted; // text deleted by line
    std::map<unsigned long,unsigned long> modified; // line number mods started by line
    std::map<unsigned long,BOOL> added; // line has been added or modified
    time_t updated;
}
@end

@implementation GitFileDiffs

// parse "git diff" output
- initFile:(NSString *)path
{
    if ( (self = [super init]) ) {

        NSString *command = [NSString stringWithFormat:@"cd \"%@\" && /usr/bin/git diff \"%@\"",
                             [path stringByDeletingLastPathComponent], path];
        FILE *diffs = popen([command UTF8String], "r");

        if ( diffs ) {
            char buffer[10000];
            int line, deline, modline, delcnt, addcnt;

            for ( int i=0 ; i<4 ; i++ )
                fgets(buffer, sizeof buffer, diffs);

            while ( fgets(buffer, sizeof buffer, diffs) ) {
                switch ( buffer[0] ) {
                    case '@': {
                        int d1, d2, d3;
                        sscanf( buffer, "@@ -%d,%d +%d,%d @@", &d1, &d2, &line, &d3 );
                        break;
                    }
                    case '-':
                        deleted[deline] += buffer+1;
                        modified[modline++] = deline;
                        delcnt++;
                        break;
                    case '+':
                        added[line] = YES;
                        if ( ++addcnt > delcnt )
                            modified.erase(line);
                    default:
                        deline = modline = ++line;
                        if ( buffer[0] != '+' )
                            delcnt = addcnt = 0;
                }
            }

            pclose(diffs);
        }
        else
            NSLog( @"GitDiff Plugin: Could not run diff command: %@", command );

        updated = time(NULL);
        gitDiffPlugin.diffsByFile[path] = self;
    }

    return self;
}

@end

@interface NSDocument(GitDiff)
- (void)_finishSavingToURL:(id)a0 ofType:(id)a1 forSaveOperation:(unsigned long)a2 changeCount:(id)a3;
@end

@interface IDESourceCodeDocument : NSDocument
@end

@implementation IDESourceCodeDocument(GitDiff)

// source file is being saved
- (void)_finishSavingToURL:(id)a0 ofType:(id)a1 forSaveOperation:(unsigned long)a2 changeCount:(id)a3
{
    [super _finishSavingToURL:a0 ofType:a1 forSaveOperation:a2 changeCount:a3];
    [[GitFileDiffs alloc] performSelectorInBackground:@selector(initFile:) withObject:[[self fileURL] path]];
}

@end

@interface DVTTextSidebarView : NSRulerView
- (void)getParagraphRect:(CGRect *)a0 firstLineRect:(CGRect *)a1 forLineNumber:(unsigned long)a2;
- (unsigned long)lineNumberForPoint:(CGPoint)a0;
- (double)sidebarWidth;
@end

@implementation DVTTextSidebarView(GitDiff)

- (NSTextView *)sourceTextView
{
    return (NSTextView *)[(id)[self scrollView] delegate];
}

- (GitFileDiffs *)gitDiffs
{
    NSTextView *sourceTextView = [self sourceTextView];
    if ( ![sourceTextView respondsToSelector:@selector(delegate)] )
        return nil;

    IDESourceCodeDocument *doc = [(id)[sourceTextView delegate] document];
    NSString *path = [[doc fileURL] path];

    GitFileDiffs *diffs = gitDiffPlugin.diffsByFile[path];
    if ( !diffs || time(NULL) > diffs->updated + 60 )
        diffs = [[GitFileDiffs alloc] initFile:path];

    return diffs;
}

// the line numbers sidebar is being redrawn
- (void)gitdiff_drawLineNumbersInSidebarRect:(CGRect)rect foldedIndexes:(unsigned long *)indexes count:(unsigned long)indexCount linesToInvert:(id)a3 linesToReplace:(id)a4 getParaRectBlock:rectBlock
{
    GitFileDiffs *diffs = [self gitDiffs];

    if ( diffs ) {
        [self lockFocus];

        for ( int i=0 ; i<indexCount ; i++ ) {
            unsigned long line = indexes[i];
            NSColor *highlight = !exists( diffs->added, line ) ? nil :
                exists( diffs->modified, line ) ? gitDiffPlugin.modifiedColor.color : gitDiffPlugin.addedColor.color;
            CGRect a0, a1;

            if ( highlight ) {
                [highlight setFill];
                [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:line];
                NSRectFill( CGRectInset(a0,1.,1.) );
            }
            else if ( exists( diffs->deleted, line ) ) {
                [gitDiffPlugin.deletedColor.color setFill];
                [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:line];
                a0.size.height = 1.;
                NSRectFill( a0 );
            }
        }

        [self unlockFocus];
    }

    [self gitdiff_drawLineNumbersInSidebarRect:rect foldedIndexes:indexes count:indexCount
                             linesToInvert:a3 linesToReplace:a4 getParaRectBlock:rectBlock];
}

// mouseover line number for deleted
- (id)gitdiff_annotationAtSidebarPoint:(CGPoint)p0
{
    NSText *popover = gitDiffPlugin.popover;
    id annotation = [self gitdiff_annotationAtSidebarPoint:p0];

    if ( !annotation && p0.x < self.sidebarWidth ) {
        GitFileDiffs *diffs = [self gitDiffs];
        unsigned long line = [self lineNumberForPoint:p0];

        if ( diffs && (exists( diffs->deleted, line ) ||
                (exists( diffs->added, line ) && exists( diffs->modified, line ))) ) {
            CGRect a0, a1;
            unsigned long start = diffs->modified[line];
            [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:start];

            std::string deleted = diffs->deleted[start];
            deleted = deleted.substr(0,deleted.length()-1);

            popover.font = [self sourceTextView].font;
            popover.string = [NSMutableString stringWithUTF8String:deleted.c_str()];
            popover.frame = NSMakeRect(self.frame.size.width+1., a0.origin.y, 700., 10.);
            [popover sizeToFit];

            [self.scrollView addSubview:popover];
            return annotation;
        }
    }

    if ( [popover superview] )
        [popover removeFromSuperview];

    return annotation;
}

@end
