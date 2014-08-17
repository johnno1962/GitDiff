//
//  GitDelta.mm
//  Git difference highlighter plugin.
//
//  Repo: https://github.com/johnno1962/GitDiff
//
//  $Id: //depot/GitDiff/Classes/GitDiff.mm#51 $
//
//  Created by John Holdsworth on 26/07/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//

#import "GitDiff.h"
#import <objc/runtime.h>
#import "GitDiffColorsWindowController.h"

extern "C" {
    #import "DiffMatchPatch.h"
    #import "DMDiff.h"
}

#define REFRESH_INTERVAL 60

static GitDiff *gitDiffPlugin;

@interface GitDiff()

@property NSMutableDictionary *diffsByFile;
@property Class sourceDocClass;
@property NSTextView *popover;
@property GitDiffColorsWindowController *colorsWindowController;

@end

@implementation GitDiff

+ (void)pluginDidLoad:(NSBundle *)plugin
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		gitDiffPlugin = [[self alloc] init];
		gitDiffPlugin.colorsWindowController = [[GitDiffColorsWindowController alloc] initWithPluginBundle:plugin];
		gitDiffPlugin.diffsByFile = [NSMutableDictionary new];
		    
		[gitDiffPlugin insertMenuItems];
        
		gitDiffPlugin.popover = [[NSTextView alloc] initWithFrame:NSZeroRect];
		gitDiffPlugin.popover.wantsLayer = YES;
		gitDiffPlugin.popover.layer.cornerRadius = 6.0;

		gitDiffPlugin.sourceDocClass = NSClassFromString(@"IDESourceCodeDocument");
		[self swizzleClass:[NSDocument class]
		          exchange:@selector(_finishSavingToURL:ofType:forSaveOperation:changeCount:)
		              with:@selector(gitdiff_finishSavingToURL:ofType:forSaveOperation:changeCount:)];

		Class aClass = NSClassFromString(@"IDEEditorDocument");
		[self swizzleClass:aClass
		          exchange:@selector(closeToRevert)
		              with:@selector(gitdiff_closeToRevert)];

		aClass = NSClassFromString(@"DVTTextSidebarView");
		[self swizzleClass:aClass
		          exchange:@selector(_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToReplace:getParaRectBlock:)
		              with:@selector(gitdiff_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToReplace:getParaRectBlock:)];
		[self swizzleClass:aClass
		          exchange:@selector(annotationAtSidebarPoint:)
		              with:@selector(gitdiff_annotationAtSidebarPoint:)];

		aClass = NSClassFromString(@"DVTMarkedScroller");
		[self swizzleClass:aClass
		          exchange:@selector(drawKnobSlotInRect:highlight:)
		              with:@selector(gitdiff_drawKnobSlotInRect:highlight:)];
    });
}

+ (void)swizzleClass:(Class)aClass exchange:(SEL)origMethod with:(SEL)altMethod
{
    method_exchangeImplementations(class_getInstanceMethod(aClass, origMethod),
                                   class_getInstanceMethod(aClass, altMethod));
}

- (void)insertMenuItems
{
    NSMenu *editorMenu = [[[NSApp mainMenu] itemWithTitle:@"Edit"] submenu];
    
    if ( editorMenu ) {
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"GitDiff Colors..."
                                                          action:@selector(gitDiffColorsMenuItemSelected:)
                                                   keyEquivalent:@""];
        menuItem.target = self;
        
        [editorMenu addItem:[NSMenuItem separatorItem]];
        [editorMenu addItem:menuItem];
    }
}

- (void)gitDiffColorsMenuItemSelected:(id)sender
{
    [gitDiffPlugin.colorsWindowController showWindow:self];
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
    std::map<NSUInteger,std::string> deleted; // text deleted by line
    std::map<NSUInteger,NSUInteger> modified; // line number delta started by line
    std::map<NSUInteger,std::string> added; // line has been added or modified
    NSUInteger lines;
    time_t updated;
}
@end

@implementation GitFileDiffs

+ (void)asyncUpdateFilepath:(NSString *)path {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        (void)[[self alloc] initWithFilepath:path];
    });
}

static jmp_buf jmp_env;

static void handler( int sig ) {
    longjmp( jmp_env, sig );
}

// parse "git diff" output
- (id)initWithFilepath:(NSString *)path
{
    if ( (self = [super init]) ) {
        NSString *command = [NSString stringWithFormat:@"cd \"%@\" && /usr/bin/git diff \"%@\"",
                             [path stringByDeletingLastPathComponent], path];
        void (*savepipe)(int) = signal( SIGPIPE, handler );

        int signum;
        switch ( signum = setjmp( jmp_env ) ) {
            case 0: {
                FILE *diffs = popen([command UTF8String], "r");

                if ( diffs ) {
                    char buffer[10000];
                    int line, start, modline, delcnt, addcnt;

                    for ( int i=0 ; i<4 ; i++ )
                        fgets(buffer, sizeof buffer, diffs);

                    while ( fgets(buffer, sizeof buffer, diffs) ) {
                        switch ( buffer[0] ) {

                            case '@':
                                sscanf( buffer, "@@ -%*d,%*d +%d,%*d @@", &line );
                                break;

                            case '-':
                                deleted[start] += buffer+1;
                                modified[modline++] = start;
                                delcnt++;
                                break;

                            case '+':
                                added[line] = "";
                                if ( addcnt < delcnt ) {
                                    added[start] += buffer+1;
                                }
                                if ( ++addcnt > delcnt ) {
                                    modified.erase(line);
                                }
                            default:
                                modline = ++line;
                                if ( buffer[0] != '+' ) {
                                    delcnt = addcnt = 0;
                                    start = line;
                                }
                        }
                    }
                    
                    pclose(diffs);
                }
                else {
                    NSLog( @"GitDiff Plugin: Could not run diff command: %@", command );
                }
            }
                break;
            default:
                NSLog( @"GitDiff Plugin: SIGNAL: %d", signum );
        }

        updated = time(NULL);
        signal( SIGPIPE, savepipe );
        gitDiffPlugin.diffsByFile[path] = self;
    }

    return self;
}

@end

@implementation NSDocument(IDESourceCodeDocument)

- (void)gitdiffUpdate {
    if ( [self isKindOfClass:gitDiffPlugin.sourceDocClass] ) {
        // could be synchronous with a very small delay building
        [GitFileDiffs asyncUpdateFilepath:[[self fileURL] path]];
    }
}

// source file is being saved
- (void)gitdiff_finishSavingToURL:(id)a0 ofType:(id)a1 forSaveOperation:(NSUInteger)a2 changeCount:(id)a3
{
    [self gitdiff_finishSavingToURL:a0 ofType:a1 forSaveOperation:a2 changeCount:a3];
    [self gitdiffUpdate];
}

// revert on change on disk
- (void)gitdiff_closeToRevert {
    [self gitdiff_closeToRevert];
    [self gitdiffUpdate];
}

@end

@implementation NSView(GitDiffs)

- (NSTextView *)sourceTextView
{
    return [[self superview] respondsToSelector:@selector(delegate)] ? (NSTextView *)[(id)[self superview] delegate] : nil;
}

- (GitFileDiffs *)gitDiffs
{
    NSTextView *sourceTextView = [self sourceTextView];
    if ( ![sourceTextView respondsToSelector:@selector(delegate)] ) {
        return nil;
    }

    NSDocument *doc = [(id)[sourceTextView delegate] document];
    NSString *path = [[doc fileURL] path];

    GitFileDiffs *diffs = gitDiffPlugin.diffsByFile[path];
    if ( !diffs ) {
        diffs = [[GitFileDiffs alloc] initWithFilepath:path];
    }
    else if ( diffs->updated + REFRESH_INTERVAL < time(NULL) ) {
        diffs->updated = time(NULL);
        [GitFileDiffs asyncUpdateFilepath:path];
    }

    return diffs;
}

@end

@implementation NSString(GitDiff)
- (NSUInteger)gdLineCount {
    return [[self componentsSeparatedByString:@"\n"] count];
}
@end

@interface  NSRulerView(DVTTextSidebarView)
- (void)getParagraphRect:(CGRect *)a0 firstLineRect:(CGRect *)a1 forLineNumber:(NSUInteger)a2;
- (NSUInteger)lineNumberForPoint:(CGPoint)a0;
- (double)sidebarWidth;
@end

@implementation NSRulerView(GitDiff)

// the line numbers sidebar is being redrawn
- (void)gitdiff_drawLineNumbersInSidebarRect:(CGRect)rect
                               foldedIndexes:(NSUInteger *)indexes
                                       count:(NSUInteger)indexCount
                               linesToInvert:(id)a3
                              linesToReplace:(id)a4
                            getParaRectBlock:rectBlock
{
    GitFileDiffs *diffs = [self gitDiffs];
    if ( diffs ) {

        for ( NSUInteger i=0 ; i<indexCount ; i++ ) {
            NSUInteger line = indexes[i];
            NSColor *highlight = !exists( diffs->added, line ) ? nil :
                exists( diffs->modified, line ) ? gitDiffPlugin.colorsWindowController.modifiedColor : gitDiffPlugin.colorsWindowController.addedColor;
            CGRect a0, a1;

            if ( highlight ) {
                [highlight setFill];
                [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:line];
                a0.origin.x += (a0.size.width - 2.);
                a0.size.width = 2.;
                NSRectFill( a0 );
            }
            else if ( exists( diffs->deleted, line ) ) {
                [gitDiffPlugin.colorsWindowController.deletedColor setFill];
                [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:line];
                a0.size.height = 1.;
                NSRectFill( a0 );
            }
        }
    }

    [self gitdiff_drawLineNumbersInSidebarRect:rect
                                 foldedIndexes:indexes
                                         count:indexCount
                                 linesToInvert:a3
                                linesToReplace:a4
                              getParaRectBlock:rectBlock];
}

// mouseover line number for deleted code
- (id)gitdiff_annotationAtSidebarPoint:(CGPoint)p0
{
    id annotation = [self gitdiff_annotationAtSidebarPoint:p0];
    NSTextView *popover = gitDiffPlugin.popover;
    popover.backgroundColor = gitDiffPlugin.colorsWindowController.popoverColor;

    if ( !annotation && p0.x < self.sidebarWidth ) {
        GitFileDiffs *diffs = [self gitDiffs];
        NSUInteger line = [self lineNumberForPoint:p0];

        if ( diffs && (exists( diffs->deleted, line ) ||
                (exists( diffs->added, line ) && exists( diffs->modified, line ))) )
        {
            CGRect a0, a1;
            NSUInteger start = diffs->modified[line];
            [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:start];

            std::string deleted = diffs->deleted[start];
            deleted = deleted.substr(0,deleted.length()-1);

            NSString *before = [NSString stringWithUTF8String:deleted.c_str()];

            if ( exists( diffs->added, start ) ) {
                NSDictionary *attributes = @{NSForegroundColorAttributeName : gitDiffPlugin.colorsWindowController.changedColor};
                NSMutableAttributedString *attrstr = [[NSMutableAttributedString alloc] init];

                std::string added = diffs->added[start];
                added = added.substr(0,added.length()-1);

                NSString *after = [NSString stringWithUTF8String:added.c_str()];

                for ( DMDiff *diff : diff_diffsBetweenTexts( before, after ) ) {
                    if ( diff.operation == DIFF_INSERT ) {
                        continue;
                    }

                    NSMutableAttributedString *next = [[NSMutableAttributedString alloc] initWithString:diff.text];
                    if ( diff.operation == DIFF_DELETE ) {
                        [next setAttributes:attributes range:NSMakeRange(0, next.length)];
                    }

                    [attrstr appendAttributedString:next];
                }

                [[popover textStorage] setAttributedString:attrstr];
            }
            else {
                [[popover textStorage] setAttributedString:[[NSAttributedString alloc] initWithString:before]];
            }

            NSTextView *sourceTextView = [self sourceTextView];
            NSFont *font = popover.font = sourceTextView.font;

            CGFloat lineHeight = font.ascender + font.descender + font.leading;
            CGFloat w = NSWidth(sourceTextView.frame);
            CGFloat h = lineHeight * [popover.string gdLineCount];

            popover.frame = NSMakeRect(NSWidth(self.frame)+1., a0.origin.y, w, h);

            [self.scrollView addSubview:popover];
            return annotation;
        }
    }

    if ( [popover superview] ) {
        [popover removeFromSuperview];
    }

    return annotation;
}

@end

@implementation NSScroller(GitDiff)

// scroll bar overview
- (void)gitdiff_drawKnobSlotInRect:(CGRect)a0 highlight:(char)a1
{
    [self gitdiff_drawKnobSlotInRect:a0 highlight:a1];

    GitFileDiffs *diffs = [self gitDiffs];

    if ( diffs  ) {
        if ( !diffs->lines ) {
            diffs->lines = [[self sourceTextView].string gdLineCount];
        }

        CGFloat scale = NSHeight(self.frame)/diffs->lines;

        for ( const auto &added : diffs->added ) {
            NSUInteger line = added.first;
            NSColor *highlight = exists( diffs->modified, line ) ?
                gitDiffPlugin.colorsWindowController.modifiedColor : gitDiffPlugin.colorsWindowController.addedColor;

            [highlight setFill];
            NSRectFill( NSMakeRect(0, line*scale, 3., 1.) );
        }

        for ( const auto &deleted : diffs->deleted ) {
            NSUInteger line = deleted.first;
            if ( !exists( diffs->added, line ) ) {
                [gitDiffPlugin.colorsWindowController.deletedColor setFill];
                NSRectFill( NSMakeRect(0, line*scale, 3., 1.) );
            }
        }
    }
}

@end
