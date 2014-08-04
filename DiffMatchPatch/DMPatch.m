/*
 * Diff Match and Patch
 *
 * Copyright 2010 geheimwerk.de.
 * http://code.google.com/p/google-diff-match-patch/
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Author: fraser@google.com (Neil Fraser)
 * ObjC port: jan@geheimwerk.de (Jan Weiß)
 * Refactoring & mangling: @inquisitivesoft (Harry Jordan)
 */
 

#import "DMPatch.h"
#import "DMDiff.h"

#import "DiffMatchPatchInternals.h"			// DMPatch uses the MAX_OF_CONST_AND_DIFF macro
#import "DiffMatchPatchCFUtilities.h"
#import "NSString+UriCompatibility.h"


@implementation DMPatch


- (id)init
{
	self = [super init];
	
	if(self) {
		self.diffs = [NSMutableArray array];
	}
	
	return self;
}


- (id)copyWithZone:(NSZone *)zone
{
	DMPatch *newPatch = [[[self class] allocWithZone:zone] init];
	
	newPatch.diffs = [[NSMutableArray alloc] initWithArray:self.diffs copyItems:YES];
	newPatch.start1 = self.start1;
	newPatch.start2 = self.start2;
	newPatch.length1 = self.length1;
	newPatch.length2 = self.length2;
	
	return newPatch;
}


- (NSString *)description
{
	return [[super description] stringByAppendingFormat:@" %@", [self patchText]];
}


/**
 * Emulate GNU diff's format.
 * Header: @@ -382,8 +481,9 @@
 * Indicies are printed as 1-based, not 0-based.
 * @return The GNU diff NSString.
 */
- (NSString *)patchText
{
	NSString *coords1;
	NSString *coords2;
	
	if(self.length1 == 0) {
		coords1 = [NSString stringWithFormat:@"%lu,0",
				   (unsigned long)self.start1];
	} else if(self.length1 == 1) {
		coords1 = [NSString stringWithFormat:@"%lu",
				   (unsigned long)self.start1 + 1];
	} else {
		coords1 = [NSString stringWithFormat:@"%lu,%lu",
				   (unsigned long)self.start1 + 1, (unsigned long)self.length1];
	}
	
	if(self.length2 == 0) {
		coords2 = [NSString stringWithFormat:@"%lu,0",
				   (unsigned long)self.start2];
	} else if(self.length2 == 1) {
		coords2 = [NSString stringWithFormat:@"%lu",
				   (unsigned long)self.start2 + 1];
	} else {
		coords2 = [NSString stringWithFormat:@"%lu,%lu",
				   (unsigned long)self.start2 + 1, (unsigned long)self.length2];
	}
	
	NSMutableString *text = [NSMutableString stringWithFormat:@"@@ -%@ +%@ @@\n",
							 coords1, coords2];
	
	// Escape the body of the patch with %xx notation.
	for(DMDiff *aDiff in self.diffs) {
		switch(aDiff.operation) {
			case DIFF_INSERT:
				[text appendString:@"+"];
				break;
				
			case DIFF_DELETE:
				[text appendString:@"-"];
				break;
				
			case DIFF_EQUAL:
				[text appendString:@" "];
				break;
		}
		
		[text appendString:[aDiff.text encodedURIString]];
		[text appendString:@"\n"];
	}
	
	return text;
}



/**
 * Increase the context until it is unique,
 * but don't let the pattern expand beyond DIFF_MATCH_MAX_BITS.
 * @param patch The patch to grow.
 * @param text Source text.
 */

- (void)addContext:(NSString *)text withMargin:(NSInteger)patchMargin maximumBits:(NSUInteger)maximumBits
{
	if(text.length == 0)
		return;
	
	NSString *pattern = [text substringWithRange:NSMakeRange(self.start2, self.length1)];
	NSUInteger padding = 0;
	
	// Look for the first and last matches of pattern in text.  If two
	// different matches are found, increase the pattern length.
	while([text rangeOfString:pattern options:NSLiteralSearch].location
		!= [text rangeOfString:pattern options:(NSLiteralSearch | NSBackwardsSearch)].location
			&& pattern.length < (maximumBits - patchMargin - patchMargin)) {
		padding += patchMargin;
		
		NSRange patternRange = NSMakeRange(MAX_OF_CONST_AND_DIFF(0, self.start2, padding), MIN(text.length, self.start2 + self.length1 + padding));
		patternRange.length -= patternRange.location;
		pattern = [text substringWithRange:patternRange];
	}
	
	// Add one chunk for good luck.
	padding += patchMargin;
	
	// Add the prefix.
	NSRange prefixRange = NSMakeRange(MAX_OF_CONST_AND_DIFF(0, self.start2, padding), 0);
	prefixRange.length = self.start2 - prefixRange.location;
	NSString *prefix = [text substringWithRange:prefixRange];
	
	if(prefix.length != 0) {
		[self.diffs insertObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:prefix] atIndex:0];
	}
	
	
	// Add the suffix.
	NSRange suffixRange = NSMakeRange((self.start2 + self.length1), MIN(text.length - self.start2 - self.length1, padding));
	NSString *suffix = [text substringWithRange:suffixRange];
	
	if(suffix.length != 0) {
		[self.diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:suffix]];
	}
	
	// Roll back the start points.
	self.start1 -= prefix.length;
	self.start2 -= prefix.length;
	// Extend the lengths.
	self.length1 += prefix.length + suffix.length;
	self.length2 += prefix.length + suffix.length;
}


@end