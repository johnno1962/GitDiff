//
//  XcodePrivate.h
//  GitDiff
//
//  Created by Christoffer Winterkvist on 30/10/14.
//  Copyright (c) 2014 zenangst. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface DVTTextDocumentLocation : NSObject
@property(readonly) NSRange characterRange;
@property(readonly) NSRange lineRange;
- (id)initWithDocumentURL:(id)a0 timestamp:(id)a1 lineRange:(NSRange)a2;
@end

@interface IDESourceCodeComparisonEditor : NSObject
@property(readonly) NSTextView *keyTextView;
@end

@interface IDESourceCodeEditor : NSObject <NSTextViewDelegate>

@property(retain) NSDocument *document; // T@"IDEEditorDocument",&,V_document
@property(retain) NSTextView *textView;

- (long)_currentOneBasedLineNubmer;
- (long)_currentOneBasedLineNumber;
- (id)_documentLocationForLineNumber:(long)a0;
- (void)selectDocumentLocations:(id)a0 highlightSelection:(BOOL)a1;
- (void)selectAndHighlightDocumentLocations:(id)a1;
- (void)selectDocumentLocations:(id)a1;
@end

@interface IDEEditorContext : NSObject
- (id)editor;
@end

@interface IDEEditorArea : NSObject
- (id)lastActiveEditorContext;
@end

@interface IDEWorkspaceWindowController : NSWindowController
- (id)editorArea;
@end

@interface NSRulerView (DVTTextSidebarView)
- (void)getParagraphRect:(CGRect *)a0 firstLineRect:(CGRect *)a1 forLineNumber:(NSUInteger)a2;
- (NSUInteger)lineNumberForPoint:(CGPoint)a0;
- (double)sidebarWidth;
@end

@interface _DVTMarkerList : NSObject
- (void)setMarkRect:(CGRect)a0;
- (CGRect)_rectForMark:(double)a0;
- (void)_mergeMarkRect:(CGRect)a0;
- (void)_recomputeMarkRects;
- (id)initWithSlotRect:(CGRect)a0;
- (CGRect)markRect;
- (void)clearMarks;
- (CGRect)addMark:(double)a0;
- (unsigned long)numMarkRects;
- (id)markRectList;
@end

// Xcode 9 Swift classes

@interface SourceCodeEditor : NSViewController
- (NSFont *)lineNumberFont;
- (NSDocument *)document;
@end

@interface SourceCodeEditorContainerView : NSView
- (SourceCodeEditor *)editor;
@end

@interface SourceEditorContentView : NSTextView
- (CGFloat)defaultLineHeight;
- (NSUInteger)numberOfLines;
- (CGRect)layoutBounds;
@end

@interface SourceEditorFontSmoothingTextLayer : CALayer
@end

@interface SourceEditorGutterMarginContentView : NSView
- (NSDictionary<NSNumber *, SourceEditorFontSmoothingTextLayer *> *)lineNumberLayers;
@end
