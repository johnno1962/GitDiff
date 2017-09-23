//
//  NSColor+NSString.m
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import "NSColor+NSString.h"

static NSMutableDictionary<NSString *, NSColor *> *cache;

@implementation NSColor (NSString)

+ (NSColor *)colorWithString:(NSString *)string {
    if (!string)
        string = NULL_COLOR_STRING;

    if (!cache)
        cache = [NSMutableDictionary new];
    else {
        NSColor *existing = cache[string];
        if (existing)
            return existing;
    }

    return cache[string] = [NSColor colorWithCIColor:[CIColor colorWithString:string]];
}

- (NSString *)stringRepresentation {
    return [CIColor colorWithCGColor:self.CGColor].stringRepresentation;
}

- (NSColor *)stripAlpha {
    const CGFloat *components = CGColorGetComponents(self.CGColor);
    return components ? [NSColor colorWithRed:components[0]
                                        green:components[1]
                                         blue:components[2]
                                        alpha:1.]
                      : [NSColor redColor];
}

@end
