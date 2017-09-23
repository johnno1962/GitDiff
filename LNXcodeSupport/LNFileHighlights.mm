//
//  LNFileHighlights.m
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import "LNFileHighlights.h"

#import <map>

// JSON wire format
typedef NSDictionary<NSString *, NSString *> LNHighlightMap;
typedef NSDictionary<NSString *, LNHighlightMap *> LNHighlightInfo;

@implementation LNHighlightElement

- (void)updadateFrom:(LNHighlightMap *)map {
    if (NSString *start = map[@"start"])
        self.start = start.integerValue;
    if (NSString *color = map[@"color"])
        self.color = [NSColor colorWithString:color];
    // hover text
    if (NSString *text = map[@"text"])
        self.text = text == (id)[NSNull null] ? nil : text;
    // undo range
    if (NSString *range = map[@"range"])
        self.range = range == (id)[NSNull null] ? nil : range;
}

- (id)copyWithZone:(NSZone *)zone {
    LNHighlightElement *copy = [[self class] new];
    copy.start = self.start;
    copy.color = self.color;
    copy.text  = self.text;
    copy.range = self.range;
    return copy;
}

- (BOOL)isEqual:(LNHighlightElement *)object {
    return self.start == object.start &&
           [self.color isEqual:object.color] &&
           [self.text isEqualToString:object.text] &&
           [self.range isEqualToString:object.range];
}

// http://stackoverflow.com/questions/22620615/cocoa-how-to-save-nsattributedstring-to-json

- (void)setAttributedText:(NSAttributedString *_Nonnull)text {
    NSMutableData *data = [NSMutableData new];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    archiver.outputFormat = NSPropertyListXMLFormat_v1_0;
    [archiver encodeObject:text forKey:NSKeyedArchiveRootObjectKey];
    self.text = [[NSString alloc] initWithData:archiver.encodedData encoding:NSUTF8StringEncoding];
}

- (NSAttributedString *_Nullable)attributedText {
    if (!self.text)
        return nil;
    if ([self.text hasPrefix:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
         "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"])
        return [NSKeyedUnarchiver unarchiveObjectWithData:[self.text dataUsingEncoding:NSUTF8StringEncoding]];
    else
        return [[NSAttributedString alloc] initWithString:self.text];
}

@end

@implementation LNFileHighlights {
    std::map<NSInteger, LNHighlightElement *> elemants;
}

- (instancetype)initWithData:(NSData *)json service:(NSString *)serviceName {
    if ((self = [super init]) && json) {
        NSError *error;
        LNHighlightInfo *info = [NSJSONSerialization JSONObjectWithData:json options:0 error:&error];
        if (error)
            NSLog(@"%@ -[LNFileHighlights initWithData: %@]", serviceName, error);

        for (NSString *line in [info.allKeys
                 sortedArrayUsingComparator:^NSComparisonResult(id _Nonnull obj1, id _Nonnull obj2) {
                     return [obj1 intValue] < [obj2 intValue] ? NSOrderedAscending : NSOrderedDescending;
                 }]) {
            LNHighlightMap *map = info[line];
            LNHighlightElement *element;

            if (NSString *alias = map[@"alias"]) {
                LNHighlightElement *original = elemants[alias.intValue];
                if (map.count == 1)
                    element = original;
                else {
                    element = [original copy];
                    [element updadateFrom:map];
                }
            } else {
                element = [LNHighlightElement new];
                [element updadateFrom:map];
            }

            elemants[line.intValue] = element;
        }
    }

    self.updated = [NSDate timeIntervalSinceReferenceDate];
    return self;
}

- (void)setObject:(LNHighlightElement *)element atIndexedSubscript:(NSInteger)line {
    elemants[line] = element;
}

- (LNHighlightElement *)objectAtIndexedSubscript:(NSInteger)line {
    return elemants.find(line) != elemants.end() ? elemants[line] : nil;
}

- (void)foreachHighlight:(void (^)(NSInteger line, LNHighlightElement *element))block {
    for (auto it = elemants.begin(); it != elemants.end(); ++it)
        block(it->first, it->second);
}

- (void)foreachHighlightRange:(void (^)(NSRange range, LNHighlightElement *element))block {
    __block LNHighlightElement *lastElement = nil;
    __block NSInteger lastLine = -1;

    auto callbackOnNewElement = ^(LNHighlightElement *element) {
        if (lastElement && element != lastElement)
            block(NSMakeRange(lastElement.start, lastLine - lastElement.start + 1), lastElement);
    };

    for (auto it = elemants.begin(); it != elemants.end(); ++it) {
        callbackOnNewElement(it->second);
        lastElement = it->second;
        lastLine = it->first;
    }

    callbackOnNewElement(nil);
}

- (NSData *)jsonData {
    NSMutableDictionary *highlights = [NSMutableDictionary new];
    __block LNHighlightElement *lastElement = nil;
    __block NSInteger lastLine = 0;

    for (auto it = elemants.begin(); it != elemants.end(); ++it) {
        NSInteger line = it->first;
        if (it->second == lastElement)
            highlights[@(line).stringValue] = @{ @"alias" : @(lastLine).stringValue };
        else {
            lastLine = line;
            lastElement = it->second;
            highlights[@(line).stringValue] = @{ @"start" : @(lastElement.start).stringValue,
                                                 @"color" : lastElement.color.stringRepresentation ?: NULL_COLOR_STRING,
                                                 @"text"  : lastElement.text ?: [NSNull null],
                                                 @"range" : lastElement.range ?: [NSNull null] };
        }
    };

    return [NSJSONSerialization dataWithJSONObject:highlights options:0 error:NULL];
}

- (void)invalidate {
    elemants.clear();
}

@end
