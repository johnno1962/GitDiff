//
//  GitDelta.mm
//  Git difference highlighter plugin.
//
//  Created by John Holdsworth on 26/07/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//

#import "GitDiff.h"

#import <objc/runtime.h>
#import <map>

static GitDiff *gitDiffPlugin;
static NSMutableDictionary *fileDiffs;
static NSColor *modifiedColor, *addedColor;

@interface GitFileDiffs : NSObject {
@public
    std::map<unsigned long,BOOL> deleted, added;
}
@end

@implementation GitFileDiffs
@end

@interface GitDiff()
- (GitFileDiffs *)getDiffsForFile:(NSString *)path;
@end

@interface IDESourceCodeDocument : NSDocument
@end

@implementation IDESourceCodeDocument(GitDiff)

// source file is being saved
- (BOOL)git_writeToURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
    [gitDiffPlugin performSelectorInBackground:@selector(getDiffsForFile:) withObject:[[self fileURL] path]];
    return [self git_writeToURL:url ofType:type error:error];
}

@end

@interface DVTTextSidebarView : NSRulerView
- (void)getParagraphRect:(CGRect *)a0 firstLineRect:(CGRect *)a1 forLineNumber:(unsigned long)a2;
@end

@implementation DVTTextSidebarView(GitDiff)

// the line numbers sidebar is being redrawn
- (void)git_drawLineNumbersInSidebarRect:(CGRect)rect foldedIndexes:(unsigned long *)indexes count:(unsigned long)indexCount linesToInvert:(id)a3 linesToReplace:(id)a4 getParaRectBlock:rectBlock
{
    IDESourceCodeDocument *doc = [self valueForKeyPath:@"scrollView.delegate.delegate.document"];
    NSString *path = [[doc fileURL] path];
    GitFileDiffs *deltas = fileDiffs[path];

    if ( !deltas )
        deltas = [gitDiffPlugin getDiffsForFile:path];

    [self lockFocus];

    for ( int i=0 ; i<indexCount ; i++ ) {
        NSColor *highlight = deltas->added.find(indexes[i]) == deltas->added.end() ? nil :
            deltas->deleted.find(indexes[i]) != deltas->deleted.end() ? modifiedColor : addedColor;
        if ( highlight ) {
            CGRect a0, a1;
            [highlight setFill];
            [self getParagraphRect:&a0 firstLineRect:&a1 forLineNumber:indexes[i]];
            NSRectFill(CGRectInset(a0,1,1));
        }
     }

    [self unlockFocus];
    [self git_drawLineNumbersInSidebarRect:rect foldedIndexes:indexes count:indexCount
                             linesToInvert:a3 linesToReplace:a4 getParaRectBlock:rectBlock];
}

@end

@implementation GitDiff

+ (void)pluginDidLoad:(NSBundle *)plugin
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		gitDiffPlugin = [[self alloc] init];
        fileDiffs = [NSMutableDictionary new];

        modifiedColor = [NSColor colorWithCalibratedRed:1. green:.9 blue:.6 alpha:1.];
        addedColor = [NSColor colorWithCalibratedRed:.7 green:1. blue:.7 alpha:1.];

        Class aClass = NSClassFromString(@"DVTTextSidebarView");

        Method orig_method = class_getInstanceMethod(aClass, @selector(_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToReplace:getParaRectBlock:));
        Method alt_method = class_getInstanceMethod(aClass, @selector(git_drawLineNumbersInSidebarRect:foldedIndexes:count:linesToInvert:linesToReplace:getParaRectBlock:));

        method_exchangeImplementations(orig_method,alt_method);

        aClass = NSClassFromString(@"IDESourceCodeDocument");
        orig_method = class_getInstanceMethod(aClass, @selector(writeToURL:ofType:error:));
        alt_method = class_getInstanceMethod(aClass, @selector(git_writeToURL:ofType:error:));

        method_exchangeImplementations(orig_method,alt_method);
    });
}

// parse "git diff" output
- (GitFileDiffs *)getDiffsForFile:(NSString *)path
{
    NSString *command = [NSString stringWithFormat:@"cd '%@' && /usr/bin/git diff '%@'",
                         [path stringByDeletingLastPathComponent], path];
    FILE *diffs = popen([command UTF8String], "r");
    GitFileDiffs *deltas = [GitFileDiffs new];

    if ( diffs ) {
        char buffer[10000];
        int line, deline;

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
                    deltas->deleted[deline++] = YES;
                    break;
                case '+':
                    deltas->added[line] = YES;
                default:
                    deline = ++line;
            }
        }

        pclose(diffs);
    }
    else
        NSLog( @"Could not run diff command: %@", command );

    fileDiffs[path] = deltas;
    return deltas;
}

@end
