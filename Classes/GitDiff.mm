//
//  GitDiff.mm
//  Git difference highlighter plugin.
//
//  Repo: https://github.com/johnno1962/GitDiff
//
//  $Id: //depot/GitDiff/Classes/GitDiff.mm#84 $
//
//  Created by John Holdsworth on 26/07/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//

#import "GitDiff.h"
#import <objc/runtime.h>
#import "GitDiffColorsWindowController.h"
#import "XcodePrivate.h"

@interface GitChangeManager : NSObject

+ (instancetype)sharedManager;
+ (id)currentEditor;

- (void)nextChangeAction:(id)sender;
- (void)previousChangeAction:(id)sender;

@end

extern "C" {
    #import "DiffMatchPatch.h"
    #import "DMDiff.h"
}

#define REFRESH_INTERVAL 60

static GitDiff *gitDiffPlugin;

@interface GitDiff()

@property NSMutableDictionary *diffsByFile;
@property Class sourceDocClass, locationClass;
@property GitDiffColorsWindowController *colorsWindowController;
@property NSTextView *popover;
@property NSRange undoRange;
@property NSString *undoText;

@end

@implementation GitDiff

+ (void)pluginDidLoad:(NSBundle *)pluginBundle
{
	static dispatch_once_t onceToken;
    NSString *currentApplicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];

    if ([currentApplicationName isEqual:@"Xcode"])
        dispatch_once(&onceToken, ^{
            GitDiff *plugin = gitDiffPlugin = [[self alloc] init];

            if ( !(plugin.colorsWindowController = [[GitDiffColorsWindowController alloc] initWithPluginBundle:pluginBundle]) ) {
                NSLog( @"GitDiff: nib not loaded exiting" );
                return;
            }

            plugin.popover = [[NSTextView alloc] initWithFrame:NSZeroRect];
            plugin.diffsByFile = [NSMutableDictionary new];

            dispatch_async(dispatch_get_main_queue(), ^{
                plugin.sourceDocClass = NSClassFromString(@"IDESourceCodeDocument");
                plugin.locationClass = NSClassFromString(@"DVTTextDocumentLocation");
                [plugin insertMenuItems];
            });

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
                      exchange:@selector(_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToHighlight:linesToReplace:textView:getParaRectBlock:)
                          with:@selector(gitdiff_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToHighlight:linesToReplace:textView:getParaRectBlock:)];

            [self swizzleClass:aClass
                      exchange:@selector(annotationAtSidebarPoint:)
                          with:@selector(gitdiff_annotationAtSidebarPoint:)];
            [self swizzleClass:aClass
                      exchange:@selector(mouseExited:)
                          with:@selector(gitdiff_mouseExited:)];

            aClass = NSClassFromString(@"DVTMarkedScroller");
            [self swizzleClass:aClass
                      exchange:@selector(drawKnobSlotInRect:highlight:)
                          with:@selector(gitdiff_drawKnobSlotInRect:highlight:)];

            aClass = NSClassFromString(@"IDESourceCodeEditor");
            Method m = class_getInstanceMethod( aClass, @selector(_currentOneBasedLineNubmer) );
            if ( m )
                class_addMethod( aClass, @selector(_currentOneBasedLineNumber),
                                method_getImplementation( m ), method_getTypeEncoding( m ) );

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

    if (!editorMenu) return;

    NSMenu *gitDiffMenu = [[NSMenu alloc] initWithTitle:@"GitDiff"];

    [editorMenu addItem:[NSMenuItem separatorItem]];

    [gitDiffMenu addItem:({
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"Configuration"
                                                          action:@selector(gitDiffColorsMenuItemSelected:)
                                                   keyEquivalent:@""];
        menuItem.target = self;
        menuItem;
    })];

    [gitDiffMenu addItem:[NSMenuItem separatorItem]];

    struct { NSString *title; SEL action; } items[] = {
        @"Stage File", @selector(stageAction:),
        @"Unstage File", @selector(unstageAction:),
        @"Next Change", @selector(nextChangeAction:),
        @"Previous Change", @selector(previousChangeAction:) };

    for ( int i=0 ; i<sizeof items/sizeof items[0] ; i++ ) {
        [gitDiffMenu addItem:({
            NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:items[i].title
                                                              action:items[i].action
                                                       keyEquivalent:@""];
            menuItem.target = [GitChangeManager sharedManager];
            menuItem;
        })];
    }

    NSString *versionString = [[NSBundle bundleForClass:[self class]] objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSMenuItem *gitDiffMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"GitDiff (%@)", versionString]
                                                            action:nil
                                                     keyEquivalent:@""];

    gitDiffMenuItem.submenu = gitDiffMenu;

    [editorMenu addItem:gitDiffMenuItem];
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
    NSSet *diffLines;
    NSUInteger lines;
    time_t updated;
}
@end

@implementation GitFileDiffs

+ (void)asyncUpdateFilepath:(NSString *)path
{
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
    if ( path && (self = [super init]) ) {
        NSMutableArray *extraPrefixArgs = [NSMutableArray new];

        BOOL ignoreSpaceChange = [[NSUserDefaults standardUserDefaults] boolForKey:@"GitDiffIgnoreSpaceChange"];
        if (ignoreSpaceChange) {
            [extraPrefixArgs addObject:@"-b"];
        }

        BOOL compareToHEAD = [[NSUserDefaults standardUserDefaults] boolForKey:@"GitDiffCompareToHEAD"];
        if (compareToHEAD) {
            [extraPrefixArgs addObject:@"HEAD"];
        }
        
        NSString *command = [NSString stringWithFormat:@"cd \"%@\" && /usr/bin/git diff --no-ext-diff --no-color %@ \"%@\"",
                             [path stringByDeletingLastPathComponent], [extraPrefixArgs componentsJoinedByString:@" "], path];
        NSMutableSet *diffSet = [[NSMutableSet alloc] init];
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
                                [diffSet addObject:@(start)];
                                break;

                            case '+':
                                added[line] = "";
                                if ( addcnt < delcnt ) {
                                    added[start] += buffer+1;
                                }
                                if ( ++addcnt > delcnt ) {
                                    modified.erase(line);
                                    [diffSet addObject:@(start)];
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

        self->diffLines = [diffSet copy];
        updated = time(NULL);
        signal( SIGPIPE, savepipe );
        gitDiffPlugin.diffsByFile[path] = self;
    }

    return self;
}

- (BOOL)hasChanges
{
    return !(modified.empty() && added.empty() && deleted.empty());
}

@end

@implementation NSDocument(IDESourceCodeDocument)

- (void)gitdiffUpdate
{
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
- (void)gitdiff_closeToRevert
{
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

    return [diffs hasChanges] ? diffs : nil;
}

@end

@implementation NSString(GitDiff)
- (NSUInteger)gdLineCount
{
    return [[self componentsSeparatedByString:@"\n"] count];
}
@end

@interface  NSRulerView(DVTTextSidebarView)
- (void)getParagraphRect:(CGRect *)a0 firstLineRect:(CGRect *)a1 forLineNumber:(NSUInteger)a2;
- (NSUInteger)lineNumberForPoint:(CGPoint)a0;
- (double)sidebarWidth;
@end

@implementation NSRulerView(GitDiff)

- (void)gitdiffIndicatorsForLineIndexes:(NSUInteger *)indexes
                                  count:(NSUInteger)indexCount {
    GitFileDiffs *diffs = [self gitDiffs];
    if ( diffs ) {

        NSInteger gutterMode = [[NSUserDefaults standardUserDefaults] integerForKey:@"GitDiffGutterMode"];

        for ( NSUInteger i=0 ; i<indexCount ; i++ ) {
            NSUInteger line = indexes[i];
            NSColor *highlight = !exists( diffs->added, line ) ? nil :
            exists( diffs->modified, line ) ? gitDiffPlugin.colorsWindowController.modifiedColor :
            gitDiffPlugin.colorsWindowController.addedColor;
            CGRect a0, a1;

            if ( highlight ) {
                [highlight setFill];
                [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:line];

                double gutterSize;
                switch (gutterMode) {
                    case GitDiffGutterTypeVerbose:
                        gutterSize = a0.size.width;
                        break;
                    case GitDiffGutterTypeMedium:
                        gutterSize = 3.;
                        break;
                    case GitDiffGutterTypeDefault:
                        gutterSize = 2.;
                        break;
                }

                a0.origin.x += (a0.size.width - gutterSize);
                a0.size.width = gutterSize - 1;
                [[NSBezierPath bezierPathWithRect:a0] fill];
            }
            else if ( exists( diffs->deleted, line ) ) {
                [gitDiffPlugin.colorsWindowController.deletedColor setFill];
                [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:line];
                a0.size.height = 1.;
                NSRectFill( a0 );
            }
        }
    }
}

// the line numbers sidebar is being redrawn
- (void)gitdiff_drawLineNumbersInSidebarRect:(CGRect)rect
                               foldedIndexes:(NSUInteger *)indexes
                                       count:(NSUInteger)indexCount
                               linesToInvert:(id)a3
                              linesToReplace:(id)a4
                            getParaRectBlock:rectBlock
{
    [self gitdiffIndicatorsForLineIndexes:indexes count:indexCount];

    [self gitdiff_drawLineNumbersInSidebarRect:rect
                                 foldedIndexes:indexes
                                         count:indexCount
                                 linesToInvert:a3
                                linesToReplace:a4
                              getParaRectBlock:rectBlock];
}

- (void)gitdiff_drawLineNumbersInSidebarRect:(CGRect)rect
                        foldedIndexes:(NSUInteger *)indexes
                                count:(NSUInteger)indexCount
                        linesToInvert:(id)a3
                     linesToHighlight:(id)a4
                       linesToReplace:(id)a5
                             textView:(id)a6
                     getParaRectBlock:rectBlock
{
    [self gitdiffIndicatorsForLineIndexes:indexes count:indexCount];

    [self gitdiff_drawLineNumbersInSidebarRect:rect
                                 foldedIndexes:indexes
                                         count:indexCount
                                 linesToInvert:a3
                              linesToHighlight:a4
                                linesToReplace:a5
                                      textView:a6
                              getParaRectBlock:rectBlock];
}

// mouseover line number for deleted code
- (id)gitdiff_annotationAtSidebarPoint:(CGPoint)p0
{
    id annotation = [self gitdiff_annotationAtSidebarPoint:p0];
    NSTextView *popover = gitDiffPlugin.popover;
    popover.backgroundColor = gitDiffPlugin.colorsWindowController.popoverColor;
    BOOL displayAnnotation = gitDiffPlugin.colorsWindowController.shouldPopover.state;

    if ( displayAnnotation && !annotation && p0.x < self.sidebarWidth ) {
        GitFileDiffs *diffs = [self gitDiffs];
        NSUInteger line = [self lineNumberForPoint:p0];

        if ( diffs && (exists( diffs->deleted, line ) ||
                (exists( diffs->added, line ) && exists( diffs->modified, line ))) )
        {
            CGRect a0, a1;
            NSUInteger start = diffs->modified[line];
            [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:start];

            std::string deleted = diffs->deleted[start];

            gitDiffPlugin.undoText = [NSString stringWithUTF8String:deleted.c_str()];

            int linesToReplace = 0;
            for ( int line = start ; exists( diffs->added, line ) && exists( diffs->modified, line ) && diffs->modified[line] == start ; line++ )
                linesToReplace++;

            gitDiffPlugin.undoRange = NSMakeRange( start, linesToReplace );

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

                    NSMutableAttributedString *next = [[NSMutableAttributedString alloc] initWithString:diff.text?:@""];
                    if ( diff.operation == DIFF_DELETE ) {
                        [next setAttributes:attributes range:NSMakeRange(0, next.length)];
                    }

                    [attrstr appendAttributedString:next];
                }

                [[popover textStorage] setAttributedString:attrstr];
            }
            else {
                [[popover textStorage] setAttributedString:[[NSAttributedString alloc] initWithString:before?:@""]];
            }

            NSTextView *sourceTextView = [self sourceTextView];
            NSFont *font = popover.font = sourceTextView.font;

            CGFloat lineHeight = font.ascender + font.descender + font.leading;
            CGFloat w = NSWidth(sourceTextView.frame);
            CGFloat h = lineHeight * [popover.string gdLineCount];

            popover.frame = NSMakeRect(NSWidth(self.frame)+1., a0.origin.y, w, h);

            [self performSelector:@selector(showUndo) withObject:nil
                       afterDelay:gitDiffPlugin.colorsWindowController.undoButtonDelay.floatValue];
            [self.scrollView addSubview:popover];
            return annotation;
        }
    }

    if ( [popover superview] ) {
        [popover removeFromSuperview];
        [gitDiffPlugin.colorsWindowController.undoButton removeFromSuperview];
    }

    return annotation;
}

- (void)gitdiff_mouseExited:(id)arg {
    [self gitdiff_mouseExited:arg];
    if ( [gitDiffPlugin.popover superview] ) {
        [gitDiffPlugin.popover removeFromSuperview];
        [gitDiffPlugin.colorsWindowController.undoButton removeFromSuperview];
    }
}

- (void)showUndo
{
    if ( [gitDiffPlugin.popover superview] ) {
        NSButton *undoButton = gitDiffPlugin.colorsWindowController.undoButton;
        undoButton.target = self;
        undoButton.action = @selector(performUndo:);

        CGRect a0, a1;
        [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:gitDiffPlugin.undoRange.location];
        CGFloat width = 13.0, height = a0.size.height;
        undoButton.frame = NSMakeRect( self.sidebarWidth-2.0-width, a0.origin.y, width, height );
        [self.scrollView addSubview:undoButton];
    }
}

- (void)performUndo:(NSButton *)sender
{
    IDESourceCodeEditor *editor = [GitChangeManager currentEditor];
    NSRange safeRange = NSMakeRange( gitDiffPlugin.undoRange.location-1, MAX(gitDiffPlugin.undoRange.length,1) );

    if ( [[NSAlert alertWithMessageText:@"GitDiff Plugin:"
                          defaultButton:@"Revert to staged" alternateButton:@"Cancel" otherButton:nil
              informativeTextWithFormat:@"Revert code at lines %d-%d to staged version?",
           (int)safeRange.location+1, (int)(safeRange.location+safeRange.length)]
          runModal] == NSAlertAlternateReturn )
        return;

    DVTTextDocumentLocation *location = [[gitDiffPlugin.locationClass alloc] initWithDocumentURL:editor.document.fileURL
                                                                                       timestamp:nil lineRange:safeRange];
    [editor selectAndHighlightDocumentLocations:@[location]];
    NSTextView *sourceTextView = editor.textView;
    NSRange selectedTextRange = [sourceTextView selectedRange];
    NSString *selectedString = [sourceTextView.textStorage.string substringWithRange:selectedTextRange];
    NSString *replacement = gitDiffPlugin.undoRange.length ? gitDiffPlugin.undoText :
                        [gitDiffPlugin.undoText stringByAppendingString:selectedString];

    if (selectedString && [sourceTextView shouldChangeTextInRange:selectedTextRange replacementString:replacement] ) {
        [sourceTextView replaceCharactersInRange:selectedTextRange withString:replacement];

        NSRange replacedRange = NSMakeRange( gitDiffPlugin.undoRange.location-1, [gitDiffPlugin.undoText gdLineCount]-1 );
        location = [[gitDiffPlugin.locationClass alloc] initWithDocumentURL:editor.document.fileURL
                                                                  timestamp:nil lineRange:replacedRange];
        [editor selectAndHighlightDocumentLocations:@[location]];
    }
}

@end

@implementation NSScroller(GitDiff)

// scroll bar overview
- (void)gitdiff_drawKnobSlotInRect:(CGRect)a0 highlight:(char)a1
{
    [self gitdiff_drawKnobSlotInRect:a0 highlight:a1];

    GitFileDiffs *diffs = [self gitDiffs];

    if ( diffs ) {
        if ( !diffs->lines ) {
            diffs->lines = [[self sourceTextView].string gdLineCount];
        }

        NSColor *modifiedColor = gitDiffPlugin.colorsWindowController.modifiedColor;
        NSColor *addedColor = gitDiffPlugin.colorsWindowController.addedColor;
        CGFloat scale = NSHeight(self.frame)/diffs->lines;

        for ( const auto &added : diffs->added ) {
            NSUInteger line = added.first;
            NSColor *highlight = exists( diffs->modified, line ) ? modifiedColor : addedColor;

            [highlight setFill];
            NSRectFill( NSMakeRect(0, line*scale, 3., 2.) );
        }

        [gitDiffPlugin.colorsWindowController.deletedColor setFill];
        for ( const auto &deleted : diffs->deleted ) {
            NSUInteger line = deleted.first;
            if ( !exists( diffs->added, line ) ) {
                NSRectFill( NSMakeRect(0, line*scale, 3., 2.) );
            }
        }
    }
}

@end

@implementation GitChangeManager

+ (instancetype)sharedManager
{
    static GitChangeManager *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [[GitChangeManager alloc] init];
    });

    return _sharedManager;
}

#pragma mark - Getters

+ (id)currentEditor
{
    NSWindowController *currentWindowController = [[NSApp keyWindow] windowController];

    if ([currentWindowController isKindOfClass:NSClassFromString(@"IDEWorkspaceWindowController")]) {
        IDEWorkspaceWindowController *workspaceController = (IDEWorkspaceWindowController *)currentWindowController;
        IDEEditorArea *editorArea = [workspaceController editorArea];
        IDEEditorContext *editorContext = [editorArea lastActiveEditorContext];
        return [editorContext editor];
    }

    return nil;
}

- (id)currentEditor
{
    return [[self class] currentEditor];
}

- (NSTextView *)textView
{
    if ([[self currentEditor] isKindOfClass:NSClassFromString(@"IDESourceCodeEditor")]) {
        IDESourceCodeEditor *editor = [self currentEditor];
        return editor.textView;
    }

    if ([[self currentEditor] isKindOfClass:NSClassFromString(@"IDESourceCodeComparisonEditor")]) {
        IDESourceCodeComparisonEditor *editor = [self currentEditor];
        return editor.keyTextView;
    }

    return nil;
}

- (NSString *)currentDocument {
    NSTextView *sourceTextView = [self textView];
    if ( ![sourceTextView respondsToSelector:@selector(delegate)] ) return nil;

    NSDocument *doc = [(id)[sourceTextView delegate] document];
    return [[doc fileURL] path];
}

- (NSArray *)sortedDiffArray
{
    NSString *path = [self currentDocument];
    if ( !path ) return @[];
    GitFileDiffs *diffs = gitDiffPlugin.diffsByFile[path];

    if (!diffs || [diffs->diffLines count] == 0) return @[];

    NSArray *sortedArray = [[diffs->diffLines allObjects] sortedArrayUsingSelector:@selector(compare:)];
    return sortedArray;
}

#pragma mark - Actions

- (void)nextChangeAction:(id)sender
{
    NSArray *diffArray = [self sortedDiffArray];
    if ([diffArray count] == 0) return;

    NSNumber *currentLineNumber = @([[self currentEditor] _currentOneBasedLineNumber]);
    BOOL wrapAround = [[NSUserDefaults standardUserDefaults] boolForKey:@"GitDiffWrapNavigation"];

    for (NSNumber *line in diffArray) {
        if ([currentLineNumber compare:line] == NSOrderedAscending) {
            long long gotoLine = [line longLongValue];
            if (gotoLine > 0) --gotoLine;

            DVTTextDocumentLocation *location = [[self currentEditor] _documentLocationForLineNumber:gotoLine];
            [[self currentEditor] selectAndHighlightDocumentLocations:@[location]];
            wrapAround = NO;
            break;
        }
    }

    if (wrapAround) {
        long long gotoLine = [diffArray.firstObject longLongValue];
        if (gotoLine > 0) --gotoLine;

        DVTTextDocumentLocation *location = [[self currentEditor] _documentLocationForLineNumber:gotoLine];
        [[self currentEditor] selectAndHighlightDocumentLocations:@[location]];
    }
}

- (void)previousChangeAction:(id)sender
{
    NSArray *diffArray = [self sortedDiffArray];
    if ([diffArray count] == 0) return;

    NSNumber *currentLineNumber = @([[self currentEditor] _currentOneBasedLineNumber]);
    BOOL wrapAround = [[NSUserDefaults standardUserDefaults] boolForKey:@"GitDiffWrapNavigation"];

    for (NSNumber *line in [diffArray reverseObjectEnumerator]) {
        if ([currentLineNumber compare:line] == NSOrderedDescending) {
            long long gotoLine = [line longLongValue];
            if (gotoLine > 0) --gotoLine;

            DVTTextDocumentLocation *location = [[self currentEditor] _documentLocationForLineNumber:gotoLine];
            [[self currentEditor] selectAndHighlightDocumentLocations:@[location]];
            wrapAround = NO;
            break;
        }
    }

    if (wrapAround) {
        long long gotoLine = [diffArray.lastObject longLongValue];
        if (gotoLine > 0) --gotoLine;

        DVTTextDocumentLocation *location = [[self currentEditor] _documentLocationForLineNumber:gotoLine];
        [[self currentEditor] selectAndHighlightDocumentLocations:@[location]];
    }
}

- (void)gitAction:(NSString *)which {
    NSString *path = [self currentDocument];
    if ( path ) {
        system( [[NSString stringWithFormat:@"cd \"%@\" && /usr/bin/git %@ \"%@\"",
                  path.stringByDeletingLastPathComponent, which, path] UTF8String] );
        [GitFileDiffs asyncUpdateFilepath:path];
    }
}

- (void)stageAction:sender {
    [self gitAction:@"stage"];
}

- (void)unstageAction:sender {
    [self gitAction:@"reset HEAD"];
}

@end
