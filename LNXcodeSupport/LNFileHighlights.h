//
//  LNFileHighlights.h
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NSColor+NSString.h"

@interface LNHighlightElement : NSObject

@property NSInteger start;
@property NSColor *_Nonnull color;
@property NSString *_Nullable text;
@property NSString *_Nullable range;

- (void)setAttributedText:(NSAttributedString *_Nonnull)text;
- (NSAttributedString *_Nullable)attributedText;

@end

@interface LNFileHighlights : NSObject

@property NSTimeInterval updated;

- (instancetype _Nullable)initWithData:(NSData *_Nullable)json service:(NSString *_Nonnull)serviceName;

- (LNHighlightElement *_Nullable)objectAtIndexedSubscript:(NSInteger)line;
- (void)setObject:(LNHighlightElement *_Nullable)element atIndexedSubscript:(NSInteger)line;

- (void)foreachHighlight:(void (^_Nonnull)(NSInteger line, LNHighlightElement *_Nonnull element))block;
- (void)foreachHighlightRange:(void (^_Nonnull)(NSRange range, LNHighlightElement *_Nonnull element))block;

- (NSData *_Nonnull)jsonData;
- (void)invalidate;

@end
