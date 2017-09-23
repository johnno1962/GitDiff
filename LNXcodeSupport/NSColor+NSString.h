//
//  NSColor+NSString.h
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define NULL_COLOR_STRING @"0 0 0 1"

@interface NSColor (NSString)

+ (NSColor *_Nonnull)colorWithString:(NSString *_Nonnull)string;

@property(readonly) NSString *_Nonnull stringRepresentation;
@property(readonly) NSColor *_Nonnull stripAlpha;

@end
