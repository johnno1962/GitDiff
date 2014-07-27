//
//  GitDelta.mm
//  Git difference highlighter plugin.
//
//  Created by John Holdsworth on 26/07/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//

#import "GitDiff.h"

#import <objc/runtime.h>
#import <string>
#import <map>

#define EXISTS( _map, _entry ) (_map.find(_entry) != _map.end())

static GitDiff *gitDiffPlugin;

@interface GitDiff()

@property NSMutableDictionary *diffsByFile;
@property NSColor *deletedColor, *modifiedColor, *addedColor;
@property NSText *popover;

@end

@implementation GitDiff

+ (void)pluginDidLoad:(NSBundle *)plugin
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		gitDiffPlugin = [[self alloc] init];
        gitDiffPlugin.diffsByFile = [NSMutableDictionary new];

        gitDiffPlugin.deletedColor  = [NSColor colorWithCalibratedRed:1. green:.5 blue:.5 alpha:1.];
        gitDiffPlugin.modifiedColor = [NSColor colorWithCalibratedRed:1. green:.9 blue:.6 alpha:1.];
        gitDiffPlugin.addedColor    = [NSColor colorWithCalibratedRed:.7 green:1. blue:.7 alpha:1.];

        gitDiffPlugin.popover = [[NSText alloc] initWithFrame:NSZeroRect];
        gitDiffPlugin.popover.backgroundColor = gitDiffPlugin.modifiedColor;

        Class aClass = NSClassFromString(@"IDESourceCodeDocument");

        Method orig_method = class_getInstanceMethod(aClass, @selector(writeToURL:ofType:error:));
        Method alt_method = class_getInstanceMethod(aClass, @selector(git_writeToURL:ofType:error:));

        method_exchangeImplementations(orig_method,alt_method);

        aClass = NSClassFromString(@"DVTTextSidebarView");

        orig_method = class_getInstanceMethod(aClass, @selector(_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToReplace:getParaRectBlock:));
        alt_method = class_getInstanceMethod(aClass, @selector(git_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToReplace:getParaRectBlock:));

        method_exchangeImplementations(orig_method,alt_method);

        orig_method = class_getInstanceMethod(aClass, @selector(annotationAtSidebarPoint:));
        alt_method = class_getInstanceMethod(aClass, @selector(git_annotationAtSidebarPoint:));

        method_exchangeImplementations(orig_method,alt_method);
    });
}

@end

@interface GitFileDiffs : NSObject {
@public
    std::map<unsigned long,std::string> deleted;
    std::map<unsigned long,unsigned long> modified;
    std::map<unsigned long,BOOL> added;
    time_t updated;
}
@end

@implementation GitFileDiffs

// parse "git diff" output
- initFile:(NSString *)path
{
    if ( (self = [super init]) ) {

        NSString *command = [NSString stringWithFormat:@"cd '%@' && /usr/bin/git diff '%@'",
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
                    {
                        auto modent = modified.find(line);
                        if ( ++addcnt > delcnt && modent != modified.end() )
                            modified.erase(modent);
                    }
                    default:
                        deline = modline = ++line;
                        if ( buffer[0] != '+' )
                            delcnt = addcnt = 0;
                }
            }

            pclose(diffs);
        }
        else
            NSLog( @"Could not run diff command: %@", command );

        gitDiffPlugin.diffsByFile[path] = self;
        updated = time(NULL);
    }

    return self;
}

@end

@interface IDESourceCodeDocument : NSDocument
@end

@implementation IDESourceCodeDocument(GitDiff)

// source file is being saved
- (BOOL)git_writeToURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
    [[GitFileDiffs alloc] performSelectorInBackground:@selector(initFile:) withObject:[[self fileURL] path]];
    return [self git_writeToURL:url ofType:type error:error];
}

@end

@interface DVTTextSidebarView : NSRulerView
- (void)getParagraphRect:(CGRect *)a0 firstLineRect:(CGRect *)a1 forLineNumber:(unsigned long)a2;
- (unsigned long)lineNumberForPoint:(CGPoint)a0;
- (double)sidebarWidth;
@end

@implementation DVTTextSidebarView(GitDiff)

- (NSTextView *)sourceTextView {
    return (NSTextView *)[(id)[self scrollView] delegate];
}

- (GitFileDiffs *)gitDiffs
{
    IDESourceCodeDocument *doc = [(id)[[self sourceTextView] delegate] document];
    NSString *path = [[doc fileURL] path];

    GitFileDiffs *diffs = gitDiffPlugin.diffsByFile[path];
    if ( !diffs )
        diffs = [[GitFileDiffs alloc] initFile:path];

    return diffs;
}

// the line numbers sidebar is being redrawn
- (void)git_drawLineNumbersInSidebarRect:(CGRect)rect foldedIndexes:(unsigned long *)indexes count:(unsigned long)indexCount linesToInvert:(id)a3 linesToReplace:(id)a4 getParaRectBlock:rectBlock
{
    GitFileDiffs *diffs = [self gitDiffs];

    [self lockFocus];

    for ( int i=0 ; i<indexCount ; i++ ) {
        unsigned long line = indexes[i];
        NSColor *highlight = !EXISTS( diffs->added, line ) ? nil :
            EXISTS( diffs->modified, line ) ? gitDiffPlugin.modifiedColor : gitDiffPlugin.addedColor;
        CGRect a0, a1;

        if ( highlight ) {
            [highlight setFill];
            [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:line];
            NSRectFill( CGRectInset(a0,1.,1.) );
        }
        else if ( EXISTS( diffs->deleted, line ) ) {
            [gitDiffPlugin.deletedColor setFill];
            [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:line];
            a0.size.height = 1.;
            NSRectFill( a0 );
        }
    }

    [self unlockFocus];

    [self git_drawLineNumbersInSidebarRect:rect foldedIndexes:indexes count:indexCount
                             linesToInvert:a3 linesToReplace:a4 getParaRectBlock:rectBlock];
}

- (id)git_annotationAtSidebarPoint:(CGPoint)p0
{
    NSText *popover = gitDiffPlugin.popover;
    id annotation = [self git_annotationAtSidebarPoint:p0];

    if ( !annotation && p0.x < self.sidebarWidth ) {
        GitFileDiffs *diffs = [self gitDiffs];
        unsigned long line = [self lineNumberForPoint:p0];

        if ( EXISTS( diffs->deleted, line ) ||
                (EXISTS( diffs->added, line ) && EXISTS( diffs->modified, line )) ) {
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
