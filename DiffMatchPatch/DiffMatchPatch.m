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


#import "DiffMatchPatch.h"
#import "DiffMatchPatchInternals.h"

// Object Classes
#import "DMDiff.h"
#import "DMPatch.h"

// Text parsing and conversion
#import "DiffMatchPatchCFUtilities.h"
#import "NSString+UriCompatibility.h"
#import "NSString+EscapeHTMLCharacters.h"


#pragma mark -
#pragma mark Helpers which define the default properties


DiffProperties diff_defaultDiffProperties()
{
	DiffProperties diffProperties;
	diffProperties.checkLines = FALSE;		// Perform a slower, more accurate diff
	diffProperties.deadline = 0.0;			// No timeout
	return diffProperties;
}


MatchProperties match_defaultMatchProperties()
{
	MatchProperties properties;
	properties.matchThreshold = 0.5f;
	properties.matchDistance = 1000;
	properties.matchMaximumBits = 32;
	return properties;
}


PatchProperties patch_defaultPatchProperties()
{
	PatchProperties properties;
	properties.diffProperties = diff_defaultDiffProperties();
	properties.matchProperties = match_defaultMatchProperties();
	
	properties.diffEditingCost = 4;
	properties.patchDeleteThreshold = 0.5f;
	properties.patchMargin = 4;
	
	return properties;
}



#pragma mark -
#pragma mark Diff Functions


// Described in DiffMatchPatch.h
NSArray *diff_diffsBetweenTexts(NSString *text1, NSString *text2)
{
	DiffProperties properties = diff_defaultDiffProperties();
	return diff_diffsBetweenTextsWithProperties(text1, text2, properties);
}


// Described in DiffMatchPatch.h
NSArray *diff_diffsBetweenTextsWithOptions(NSString *text1, NSString *text2, BOOL highQuality, NSTimeInterval timeLimit)
{
	timeLimit = MAX(0.0, timeLimit);
	if(timeLimit > 0.0)
		timeLimit = [NSDate timeIntervalSinceReferenceDate] + timeLimit;
	
	DiffProperties properties = diff_defaultDiffProperties();
	properties.checkLines = !highQuality;
	properties.deadline = timeLimit;
	
	return diff_diffsBetweenTextsWithProperties(text1, text2, properties);
}



/**
 * Find the differences between two texts.  Simplifies the problem by
 * stripping any common prefix or suffix off the texts before diffing.
 * 
 * @param text1			Old NSString to be diffed.
 * @param text2			New NSString to be diffed.
 * @param properties	See the DiffProperties struct for settings
 * @return NSMutableArray of DMDiff objects.
 */

NSMutableArray *diff_diffsBetweenTextsWithProperties(NSString *text1, NSString *text2, DiffProperties properties)
{	
	// Check for null inputs.
	if(text1 == nil || text2 == nil) {
		NSLog(@"Null inputs. (diff_diffsBetweenTextsWithProperties)");
		return nil;
	}
	
	
	// Test if the deadline is zero or has already passed
	if(fabsf(properties.deadline) < 0.00000001) {
		properties.deadline = [[NSDate distantFuture] timeIntervalSinceReferenceDate];
	} else {
		NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
		
		if(properties.deadline < currentTime) {
			// The deadline has already passed so use a fairly tight deadline
			properties.deadline = currentTime + 0.3f;	// 300 milliseconds
		}
	}
	
	
	// Check for equality (speedup).
	NSMutableArray *diffs;
	
	if([text1 isEqualToString:text2]) {
		diffs = [NSMutableArray array];
		
		if(text1.length != 0) {
			[diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:text1]];
		}
		
		return diffs;
	}
	
	// Trim off common prefix (speedup).
	NSUInteger commonlength = (NSUInteger)diff_commonPrefix((__bridge CFStringRef)text1, (__bridge CFStringRef)text2);
	NSString *commonprefix = [text1 substringToIndex:commonlength];
	text1 = [text1 substringFromIndex:commonlength];
	text2 = [text2 substringFromIndex:commonlength];
	
	// Trim off common suffix (speedup).
	commonlength = (NSUInteger)diff_commonSuffix((__bridge CFStringRef)text1, (__bridge CFStringRef)text2);
	NSString *commonsuffix = [text1 substringFromIndex:text1.length - commonlength];
	text1 = [text1 substringToIndex:(text1.length - commonlength)];
	text2 = [text2 substringToIndex:(text2.length - commonlength)];
	
	// Compute the diff on the middle block.
	diffs = diff_computeDiffsBetweenTexts(text1, text2, properties);
	
	// Restore the prefix and suffix.
	if(commonprefix.length != 0) {
		[diffs insertObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:commonprefix] atIndex:0];
	}
	
	if(commonsuffix.length != 0) {
		[diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:commonsuffix]];
	}
	
	diff_cleanupMerge(&diffs);
	return diffs;
}



/**
 * Compute the differences between two texts. Assumes that the texts do not
 * have any common prefix or suffix.
 * 
 * @param text1 Old NSString to be diffed.
 * @param text2 New NSString to be diffed.
 * @param checklines Speedup flag.  If NO, then don't run a
 *     line-level diff first to identify the changed areas.
 *     If YES, then run a faster slightly less optimal diff.
 * @param deadline Time the diff should be complete by.
 * @return NSMutableArray of Diff objects.
 */

NSMutableArray *diff_computeDiffsBetweenTexts(NSString *text1, NSString *text2, DiffProperties properties) {
	NSMutableArray *diffs = [[NSMutableArray alloc] init];
	
	if(text1.length == 0) {
		// Just add some text (speedup).
		[diffs addObject:[DMDiff diffWithOperation:DIFF_INSERT andText:text2]];
		return diffs;
	}
	
	if(text2.length == 0) {
		// Just delete some text (speedup).
		[diffs addObject:[DMDiff diffWithOperation:DIFF_DELETE andText:text1]];
		return diffs;
	}
	
	NSString *longtext = text1.length > text2.length ? text1 : text2;
	NSString *shorttext = text1.length > text2.length ? text2 : text1;
	NSUInteger i = [longtext rangeOfString:shorttext].location;
	
	if(i != NSNotFound) {
		// Shorter text is inside the longer text (speedup).
		DMDiffOperation op = (text1.length > text2.length) ? DIFF_DELETE : DIFF_INSERT;
		[diffs addObject:[DMDiff diffWithOperation:op andText:[longtext substringToIndex:i]]];
		[diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:shorttext]];
		[diffs addObject:[DMDiff diffWithOperation:op andText:[longtext substringFromIndex:(i + shorttext.length)]]];
		return diffs;
	}
	
	if(shorttext.length == 1) {
		// Single character string.
		// After the previous speedup, the character can't be an equality.
		[diffs addObject:[DMDiff diffWithOperation:DIFF_DELETE andText:text1]];
		[diffs addObject:[DMDiff diffWithOperation:DIFF_INSERT andText:text2]];
		return diffs;
	}
	
	// Check to see if the problem can be split in two.
	NSArray *hm = nil;
	
	// Only risk returning a non-optimal diff if we have limited time.
	if(properties.deadline != [[NSDate distantFuture] timeIntervalSinceReferenceDate]) {
		hm = (__bridge_transfer NSArray *)diff_halfMatchCreate((__bridge CFStringRef)text1, (__bridge CFStringRef)text2);
	}
	
	if(hm != nil) {
		@autoreleasepool {
			// A half-match was found, sort out the return data.
			NSString *text1_a = hm[0];
			NSString *text1_b = hm[1];
			NSString *text2_a = hm[2];
			NSString *text2_b = hm[3];
			NSString *mid_common = hm[4];
			
			// Send both pairs off for separate processing.
			NSMutableArray *diffs_a = diff_diffsBetweenTextsWithProperties(text1_a, text2_a, properties);
			NSMutableArray *diffs_b = diff_diffsBetweenTextsWithProperties(text1_b, text2_b, properties);
			
			// Merge the results.
			[diffs_a addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:mid_common]];
			[diffs_a addObjectsFromArray:diffs_b];
			
			diffs = diffs_a;
		}
		
		return diffs;
	}
	
	if(properties.checkLines && text1.length > 100 && text2.length > 100) {
		return diff_computeDiffsUsingLineMode(text1, text2, properties);
	}
	
	return diff_bisectOfStrings(text1, text2, properties);
}



/**
 * Do a quick line-level diff on both strings, then rediff the parts for
 * greater accuracy.
 * This speedup can produce non-minimal diffs.
 * @param text1 Old NSString to be diffed.
 * @param text2 New NSString to be diffed.
 * @param deadline Time when the diff should be complete by.
 * @return NSMutableArray of Diff objects.
 */

NSMutableArray *diff_computeDiffsUsingLineMode(NSString *text1, NSString *text2, DiffProperties properties)
{
	DiffProperties nextDiffProperties = properties;
	nextDiffProperties.checkLines = FALSE;
	
	// Scan the text on a line-by-line basis first.
	NSArray *b = diff_linesToCharsForStrings(text1, text2);
	text1 = (NSString *)b[0];
	text2 = (NSString *)b[1];
	NSMutableArray *linearray = (NSMutableArray *)b[2];
	
	NSMutableArray *diffs = diff_diffsBetweenTextsWithProperties(text1, text2, nextDiffProperties);
	
	// Convert the diff back to original text.
	diff_charsToLines(&diffs, linearray);
	
	// Eliminate freak matches (e.g. blank lines)
	diff_cleanupSemantic(&diffs);
	
	// Rediff any Replacement blocks, this time character-by-character.
	// Add a dummy entry at the end.
	[diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:@""]];
	NSUInteger indexOfCurrentDiff = 0;
	NSUInteger count_delete = 0;
	NSUInteger count_insert = 0;
	NSString *text_delete = @"";
	NSString *text_insert = @"";
	
	while(indexOfCurrentDiff < diffs.count) {
		switch(((DMDiff *)diffs[indexOfCurrentDiff]).operation) {
			case DIFF_INSERT:
				count_insert++;
				text_insert = [text_insert stringByAppendingString:((DMDiff *)diffs[indexOfCurrentDiff]).text];
				break;
				
			case DIFF_DELETE:
				count_delete++;
				text_delete = [text_delete stringByAppendingString:((DMDiff *)diffs[indexOfCurrentDiff]).text];
				break;
				
			case DIFF_EQUAL:
				// Upon reaching an equality, check for prior redundancies.
				if(count_delete >= 1 && count_insert >= 1) {
					// Delete the offending records and add the merged ones.
					NSMutableArray *a = diff_diffsBetweenTextsWithProperties(text_delete, text_insert, nextDiffProperties);
					[diffs removeObjectsInRange:NSMakeRange(indexOfCurrentDiff - count_delete - count_insert, count_delete + count_insert)];
					indexOfCurrentDiff = indexOfCurrentDiff - count_delete - count_insert;
					NSUInteger insertionIndex = indexOfCurrentDiff;
					
					for(DMDiff *thisDiff in a) {
						[diffs insertObject:thisDiff atIndex:insertionIndex];
						insertionIndex++;
					}
					
					indexOfCurrentDiff = indexOfCurrentDiff + a.count;
				}
				
				count_insert = 0;
				count_delete = 0;
				text_delete = @"";
				text_insert = @"";
				break;
		}
		
		indexOfCurrentDiff++;
	}
	
	[diffs removeLastObject];                   // Remove the dummy entry at the end.
	
	return diffs;
}



/**
 * Find the 'middle snake' of a diff, split the problem in two and return the recursively constructed diff.
 * See Myers 1986 paper: An O(ND) Difference Algorithm and Its Variations.
 * @param text1 Old string to be diffed.
 * @param text2 New string to be diffed.
 * @param deadline Time at which to bail if not yet complete.
 * @return NSMutableArray of Diff objects.
 */

NSMutableArray *diff_bisectOfStrings(NSString *text1, NSString *text2, DiffProperties properties)
{
	BOOL validDeadline = properties.deadline != [[NSDate distantFuture] timeIntervalSinceReferenceDate];
	
	NSMutableArray *diffs = nil;
	BOOL haveFoundDiffs = FALSE;
	
	CFStringRef _text1 = (__bridge CFStringRef)text1;
	CFStringRef _text2 = (__bridge CFStringRef)text2;	
	
	// Cache the text lengths to prevent multiple calls.
	CFIndex text1_length = CFStringGetLength(_text1);
	CFIndex text2_length = CFStringGetLength(_text2);
	CFIndex max_d = (text1_length + text2_length + 1) / 2;
	CFIndex v_offset = max_d;
	CFIndex v_length = 2 * max_d;
	CFIndex *v1 = malloc(v_length * sizeof(CFIndex));
	CFIndex *v2 = malloc(v_length * sizeof(CFIndex));
	
	for(CFIndex x = 0; x < v_length; x++) {
		v1[x] = -1;
		v2[x] = -1;
	}
	
	v1[v_offset + 1] = 0;
	v2[v_offset + 1] = 0;
	CFIndex delta = text1_length - text2_length;
	
	// Prepare access to chars arrays for text1 (massive speedup).
	const UniChar *text1_chars;
	UniChar *text1_buffer = NULL;
	diff_CFStringPrepareUniCharBuffer(_text1, &text1_chars, &text1_buffer, CFRangeMake(0, text1_length));
	
	// Prepare access to chars arrays for text2 (massive speedup).
	const UniChar *text2_chars;
	UniChar *text2_buffer = NULL;
	diff_CFStringPrepareUniCharBuffer(_text2, &text2_chars, &text2_buffer, CFRangeMake(0, text2_length));
	
	// If the total number of characters is odd, then the front path will collide with the reverse path.
	BOOL front = (delta % 2 != 0);
	
	// Offsets for start and end of k loop. Prevents mapping of space beyond the grid.
	CFIndex k1start = 0;
	CFIndex k1end = 0;
	CFIndex k2start = 0;
	CFIndex k2end = 0;
	
	for(CFIndex d = 0; d < max_d; d++) {
		// Bail out if deadline is reached.
		if(validDeadline && ([NSDate timeIntervalSinceReferenceDate] > properties.deadline)) {
			break;
		}
		
		// Walk the front path one step.
		for(CFIndex k1 = -d + k1start; k1 <= d - k1end; k1 += 2) {
			CFIndex k1_offset = v_offset + k1;
			CFIndex x1;
			
			if(k1 == -d || (k1 != d && v1[k1_offset - 1] < v1[k1_offset + 1])) {
				x1 = v1[k1_offset + 1];
			} else {
				x1 = v1[k1_offset - 1] + 1;
			}
			
			CFIndex y1 = x1 - k1;
			
			while(x1 < text1_length && y1 < text2_length && text1_chars[x1] == text2_chars[y1]) {
				x1++;
				y1++;
			}
			
			v1[k1_offset] = x1;
			
			if(x1 > text1_length) {
				// Ran off the right of the graph.
				k1end += 2;
			} else if(y1 > text2_length) {
				// Ran off the bottom of the graph.
				k1start += 2;
			} else if(front) {
				CFIndex k2_offset = v_offset + delta - k1;
				
				if(k2_offset >= 0 && k2_offset < v_length && v2[k2_offset] != -1) {
					// Mirror x2 onto top-left coordinate system.
					CFIndex x2 = text1_length - v2[k2_offset];
					
					if(x1 >= x2) {
						// Overlap detected.
						diffs = diff_bisectSplitOfStrings(text1, text2, x1, y1, properties);
						haveFoundDiffs = TRUE;
						break;
					}
				}
			}
		}
		
		if(haveFoundDiffs)
			break;
		
		// Walk the reverse path one step.
		for(CFIndex k2 = -d + k2start; k2 <= d - k2end; k2 += 2) {
			CFIndex k2_offset = v_offset + k2;
			CFIndex x2;
			
			if(k2 == -d || (k2 != d && v2[k2_offset - 1] < v2[k2_offset + 1])) {
				x2 = v2[k2_offset + 1];
			} else {
				x2 = v2[k2_offset - 1] + 1;
			}
			
			CFIndex y2 = x2 - k2;
			
			while((x2 < text1_length && y2 < text2_length) && (text1_chars[text1_length - x2 - 1] == text2_chars[text2_length - y2 - 1])) {
				x2++;
				y2++;
			}
			
			v2[k2_offset] = x2;
			
			if(x2 > text1_length) {
				// Ran off the left of the graph.
				k2end += 2;
			} else if(y2 > text2_length) {
				// Ran off the top of the graph.
				k2start += 2;
			} else if(!front) {
				CFIndex k1_offset = v_offset + delta - k2;
				
				if(k1_offset >= 0 && k1_offset < v_length && v1[k1_offset] != -1) {
					CFIndex x1 = v1[k1_offset];
					CFIndex y1 = v_offset + x1 - k1_offset;
					// Mirror x2 onto top-left coordinate system.
					x2 = text1_length - x2;
					
					if(x1 >= x2) {
						// Overlap detected.
						diffs = diff_bisectSplitOfStrings(text1, text2, x1, y1, properties);
						haveFoundDiffs = TRUE;
						break;
					}
				}
			}
		}
		
		if(haveFoundDiffs)
			break;
	}
	
	
	// Free buffers
	if(text1_buffer != NULL) {
		free(text1_buffer);
	};
	
	if(text2_buffer != NULL) {
		free(text2_buffer);
	};
	
	free(v1);
	free(v2);
	
	
	// Diff took too long and hit the deadline or
	// number of diffs equals number of characters, no commonality at all.
	if(!diffs) {
		diffs = [[NSMutableArray alloc] initWithCapacity:2];
		[diffs addObject:[DMDiff diffWithOperation:DIFF_DELETE andText:text1]];
		[diffs addObject:[DMDiff diffWithOperation:DIFF_INSERT andText:text2]];
	}
	
	return diffs;
}



/**
 * Given the location of the 'middle snake', split the diff in two parts and recurse.
 * @param text1 Old string to be diffed.
 * @param text2 New string to be diffed.
 * @param x Index of split point in text1.
 * @param y Index of split point in text2.
 * @param deadline Time at which to bail if not yet complete.
 * @return NSMutableArray of Diff objects.
 */

 NSMutableArray *diff_bisectSplitOfStrings(NSString *text1, NSString *text2, NSUInteger x, NSUInteger y, DiffProperties properties)
{
	NSString *text1a = [text1 substringToIndex:x];
	NSString *text2a = [text2 substringToIndex:y];
	NSString *text1b = [text1 substringFromIndex:x];
	NSString *text2b = [text2 substringFromIndex:y];
	
	// Compute both diffs serially.
	NSMutableArray *diffs = diff_diffsBetweenTextsWithProperties(text1a, text2a, properties);
	NSMutableArray *diffsb = diff_diffsBetweenTextsWithProperties(text1b, text2b, properties);
	
	[diffs addObjectsFromArray:diffsb];
	return diffs;
}



/**
 * Split two texts into a list of strings.  Reduce the texts to a string of
 * hashes where each Unicode character represents one line.
 * @param text1 First NSString.
 * @param text2 Second NSString.
 * @return Three element NSArray, containing the encoded text1, the
 *     encoded text2 and the NSMutableArray of unique strings. The zeroth element
 *     of the NSArray of unique strings is intentionally blank.
 */

NSArray *diff_linesToCharsForStrings(NSString *text1, NSString *text2)
{
	NSMutableArray *lineArray = [NSMutableArray array];		// NSString objects
	CFMutableDictionaryRef lineHash = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, NULL);
	// keys: NSString, values:raw CFIndex
	// e.g. [lineArray objectAtIndex:4] == "Hello\n"
	// e.g. [lineHash objectForKey:"Hello\n"] == 4
	
	// "\x00" is a valid character, but various debuggers don't like it.
	// So we'll insert a junk entry to avoid generating a nil character.
	[lineArray addObject:@""];
	
	NSString *chars1 = (NSString *)CFBridgingRelease(diff_linesToCharsMungeCFStringCreate((__bridge CFStringRef)text1, (__bridge CFMutableArrayRef)lineArray, lineHash));
	NSString *chars2 = (NSString *)CFBridgingRelease(diff_linesToCharsMungeCFStringCreate((__bridge CFStringRef)text2, (__bridge CFMutableArrayRef)lineArray, lineHash));
	NSArray *result = @[chars1, chars2, lineArray];
	CFRelease(lineHash);
	
	return result;
}



/**
 * Split two texts into a list of strings.  Reduce the texts to a string of
 * hashes where each Unicode character represents one token (or boundary between tokens).
 * A token can be a type of text fragment: a word, sentence, paragraph or line.
 * The type is determined by the mode object.
 * @param text1 First NSString.
 * @param text2 Second NSString.
 * @param mode value determining the tokenization mode.
 * @return Three element NSArray, containing the encoded text1, the
 *     encoded text2 and the NSMutableArray of unique strings. The zeroth element
 *     of the NSArray of unique strings is intentionally blank.
 */

NSArray *diff_tokensToCharsForStrings(NSString *text1, NSString *text2, DiffTokenMode mode)
{
	CFOptionFlags tokenizerOptions = 0;
	
	switch(mode) {
		case DiffWordTokens:
			tokenizerOptions = kCFStringTokenizerUnitWordBoundary;
			break;
			
		case DiffSentenceTokens:
			tokenizerOptions = kCFStringTokenizerUnitSentence;
			break;
			
		case DiffLineBreakDelimiteredTokens:
			tokenizerOptions = kCFStringTokenizerUnitLineBreak;
			break;
			
		case DiffParagraphTokens:
		default:
			tokenizerOptions = kCFStringTokenizerUnitParagraph;
			break;
	}
	
	
	NSMutableArray *tokenArray = [NSMutableArray array];	// NSString objects
	CFMutableDictionaryRef tokenHash = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, NULL);	
	// keys: NSString, values:raw CFIndex
	// e.g. [tokenArray objectAtIndex:4] == "Hello"
	// e.g. [tokenHash objectForKey:"Hello"] == 4
	
	// "\x00" is a valid character, but various debuggers don't like it.
	// So we'll insert a junk entry to avoid generating a nil character.
	[tokenArray addObject:@""];
	
	NSString *tokens1 = (__bridge_transfer NSString *)diff_tokensToCharsMungeCFStringCreate((__bridge CFStringRef)text1, (__bridge CFMutableArrayRef)tokenArray, tokenHash, tokenizerOptions);
	NSString *tokens2 = (__bridge_transfer NSString *)diff_tokensToCharsMungeCFStringCreate((__bridge CFStringRef)text2, (__bridge CFMutableArrayRef)tokenArray, tokenHash, tokenizerOptions);
	NSArray *result = @[tokens1, tokens2, tokenArray];
	
	CFRelease(tokenHash);
	
	return result;
}



/**
 * Rehydrate the text in a diff from an NSString of line hashes to real lines
 * of text.
 * @param NSArray of Diff objects.
 * @param NSArray of unique strings.
 */

void diff_charsToLines(NSArray **diffs, NSArray *lineArray)
{
	if(diffs == NULL)
		return;
	
	for(DMDiff *diff in *diffs) {
		diff.text = (__bridge_transfer NSString *)diff_charsToTokenCFStringCreate((__bridge CFStringRef)diff.text, (__bridge CFArrayRef)lineArray);
	}
}



/**
 * Rehydrate the text in a diff from an NSString of token hashes to real text tokens.
 * @param NSArray of Diff objects.
 * @param NSArray of unique strings.
 */

void diff_charsToTokens(NSArray **diffs, NSArray *tokenArray)
{
	if(diffs == NULL)
		return;
	
	for(DMDiff *diff in *diffs) {
		diff.text = (__bridge_transfer NSString *)diff_charsToTokenCFStringCreate((__bridge CFStringRef)diff.text, (__bridge CFArrayRef)tokenArray);
	}
}



/**
 * Reorder and merge like edit sections.  Merge equalities.
 * Any edit section can move as long as it doesn't cross an equality.
 * @param diffs NSMutableArray of Diff objects.
 */

void diff_cleanupMerge(NSMutableArray **inputDiffs)
{
	if(inputDiffs == NULL || [*inputDiffs count] == 0) {
		return;
	}
	
	NSMutableArray *diffs = *inputDiffs;
	[diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:@""]];	// Add a dummy entry at the end.
	
	NSUInteger indexOfCurrentDiff = 0;
	NSUInteger count_delete = 0;
	NSUInteger count_insert = 0;
	NSString *text_delete = @"";
	NSString *text_insert = @"";
	NSUInteger commonlength;
	
	while(indexOfCurrentDiff < diffs.count) {
		DMDiff *thisDiff = diffs[indexOfCurrentDiff];
		
		switch(thisDiff.operation) {
			case DIFF_INSERT:
				count_insert++;
				text_insert = [text_insert stringByAppendingString:thisDiff.text];
				indexOfCurrentDiff++;
				break;
			
			case DIFF_DELETE:
				count_delete++;
				text_delete = [text_delete stringByAppendingString:thisDiff.text];
				indexOfCurrentDiff++;
				break;
			
			case DIFF_EQUAL:
				// Upon reaching an equality, check for prior redundancies.
				if(count_delete + count_insert > 1) {
					if(count_delete != 0 && count_insert != 0) {
						// Factor out any common prefixes.
						commonlength = (NSUInteger)diff_commonPrefix((__bridge CFStringRef)text_insert, (__bridge CFStringRef)text_delete);
						
						if(commonlength != 0) {
							if((indexOfCurrentDiff - count_delete - count_insert) > 0 && ((DMDiff *)[diffs objectAtIndex:(indexOfCurrentDiff - count_delete - count_insert - 1)]).operation == DIFF_EQUAL) {
								((DMDiff *)[diffs objectAtIndex:(indexOfCurrentDiff - count_delete - count_insert - 1)]).text = [((DMDiff *)[diffs objectAtIndex:(indexOfCurrentDiff - count_delete - count_insert - 1)]).text stringByAppendingString:[text_insert substringToIndex:commonlength]];
							} else {
								[diffs insertObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:[text_insert substringToIndex:commonlength]] atIndex:0];
								indexOfCurrentDiff++;
							}
							text_insert = [text_insert substringFromIndex:commonlength];
							text_delete = [text_delete substringFromIndex:commonlength];
						}
						
						// Factor out any common suffixes.
						commonlength = (NSUInteger)diff_commonSuffix((__bridge CFStringRef)text_insert, (__bridge CFStringRef)text_delete);
						
						if(commonlength != 0) {
							thisDiff.text = [[text_insert substringFromIndex:(text_insert.length - commonlength)] stringByAppendingString:thisDiff.text];
							text_insert = [text_insert substringWithRange:NSMakeRange(0, text_insert.length - commonlength)];
							text_delete = [text_delete substringWithRange:NSMakeRange(0, text_delete.length - commonlength)];
						}
					}
					
					// Delete the offending records and add the merged ones.
					if(count_delete == 0) {
						diff_spliceTwoArrays(&diffs, indexOfCurrentDiff - count_insert, count_delete + count_insert, [NSMutableArray arrayWithObject:[DMDiff diffWithOperation:DIFF_INSERT andText:text_insert]]);
					} else if(count_insert == 0) {
						diff_spliceTwoArrays(&diffs, indexOfCurrentDiff - count_delete, count_delete + count_insert, [NSMutableArray arrayWithObject:[DMDiff diffWithOperation:DIFF_DELETE andText:text_delete]]);
					} else {
						diff_spliceTwoArrays(&diffs, indexOfCurrentDiff - count_delete - count_insert, count_delete + count_insert, [NSMutableArray arrayWithObjects:[DMDiff diffWithOperation:DIFF_DELETE andText:text_delete], [DMDiff diffWithOperation:DIFF_INSERT andText:text_insert], nil]);
					}
					
					indexOfCurrentDiff = indexOfCurrentDiff - count_delete - count_insert +
					(count_delete != 0 ? 1 : 0) + (count_insert != 0 ? 1 : 0) + 1;
				} else if(indexOfCurrentDiff != 0 && [diffs[indexOfCurrentDiff - 1] operation] == DIFF_EQUAL) {
					// Merge this equality with the previous one.
					DMDiff *prevDiff = diffs[indexOfCurrentDiff - 1];
					prevDiff.text = [prevDiff.text stringByAppendingString:thisDiff.text];
					[diffs removeObjectAtIndex:indexOfCurrentDiff];
				} else {
					indexOfCurrentDiff++;
				}
				
				count_insert = 0;
				count_delete = 0;
				text_delete = @"";
				text_insert = @"";
				break;
		}
	}
	
	if(((DMDiff *)diffs.lastObject).text.length == 0) {
		[diffs removeLastObject];  // Remove the dummy entry at the end.
	}
	
	// Second pass: look for single edits surrounded on both sides by
	// equalities which can be shifted sideways to eliminate an equality.
	// e.g: A<ins>BA</ins>C -> <ins>AB</ins>AC
	BOOL changes = NO;
	indexOfCurrentDiff = 1;
	
	// Intentionally ignore the first and last element (as they don't need checking).
	while(indexOfCurrentDiff < (diffs.count - 1)) {
		DMDiff *prevDiff = diffs[indexOfCurrentDiff - 1];
		DMDiff *thisDiff = diffs[indexOfCurrentDiff];
		DMDiff *nextDiff = diffs[indexOfCurrentDiff + 1];
		
		if(prevDiff.operation == DIFF_EQUAL && nextDiff.operation == DIFF_EQUAL) {
			// This is a single edit surrounded by equalities.
			if([thisDiff.text hasSuffix:prevDiff.text]) {
				// Shift the edit over the previous equality.
				thisDiff.text = [prevDiff.text stringByAppendingString:[thisDiff.text substringToIndex:(thisDiff.text.length - prevDiff.text.length)]];
				nextDiff.text = [prevDiff.text stringByAppendingString:nextDiff.text];
				diff_spliceTwoArrays(inputDiffs, indexOfCurrentDiff - 1, 1, nil);
				changes = YES;
			} else if([thisDiff.text hasPrefix:nextDiff.text]) {
				// Shift the edit over the next equality.
				prevDiff.text = [prevDiff.text stringByAppendingString:nextDiff.text];
				thisDiff.text = [[thisDiff.text substringFromIndex:nextDiff.text.length] stringByAppendingString:nextDiff.text];
				diff_spliceTwoArrays(inputDiffs, indexOfCurrentDiff + 1, 1, nil);
				changes = YES;
			}
		}
		
		indexOfCurrentDiff++;
	}
	
	// If shifts were made, the diff needs reordering and another shift sweep.
	if(changes) {
		diff_cleanupMerge(inputDiffs);
	}
}



/**
 * Look for single edits surrounded on both sides by equalities
 * which can be shifted sideways to align the edit to a word boundary.
 * e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
 * @param diffs NSMutableArray of Diff objects.
 */

void diff_cleanupSemanticLossless(NSMutableArray **mutableDiffs)
{
	if(mutableDiffs == NULL || [*mutableDiffs count] == 0) {
		return;
	}
	
	
	NSMutableArray *diffs = *mutableDiffs;
	NSUInteger indexOfCurrentDiff = 1;
	
	// Intentionally ignore the first and last element (as they don't need checking).
	while(indexOfCurrentDiff < (diffs.count - 1)) {
		DMDiff *prevDiff = diffs[indexOfCurrentDiff - 1];
		DMDiff *thisDiff = diffs[indexOfCurrentDiff];
		DMDiff *nextDiff = diffs[indexOfCurrentDiff + 1];
		
		if(prevDiff.operation == DIFF_EQUAL && nextDiff.operation == DIFF_EQUAL) {
			// This is a single edit surrounded by equalities.
			NSString *equality1 = prevDiff.text;
			NSString *edit = thisDiff.text;
			NSString *equality2 = nextDiff.text;
			
			// First, shift the edit as far left as possible.
			NSUInteger commonOffset = (NSUInteger)diff_commonSuffix((__bridge CFStringRef)equality1, (__bridge CFStringRef)edit);
			
			if(commonOffset > 0) {
				NSString *commonString = [edit substringFromIndex:(edit.length - commonOffset)];
				equality1 = [equality1 substringToIndex:(equality1.length - commonOffset)];
				edit = [commonString stringByAppendingString:[edit substringToIndex:(edit.length - commonOffset)]];
				equality2 = [commonString stringByAppendingString:equality2];
			}
			
			// Second, step right character by character,
			// looking for the best fit.
			NSString *bestEquality1 = equality1;
			NSString *bestEdit = edit;
			NSString *bestEquality2 = equality2;
			CFIndex bestScore = diff_cleanupSemanticScore((__bridge CFStringRef)equality1, (__bridge CFStringRef)edit) + diff_cleanupSemanticScore((__bridge CFStringRef)edit, (__bridge CFStringRef)equality2);
			
			while((edit.length != 0 && equality2.length != 0) && ([edit characterAtIndex:0] == [equality2 characterAtIndex:0])) {
				equality1 = [equality1 stringByAppendingString:[edit substringToIndex:1]];
				edit = [[edit substringFromIndex:1] stringByAppendingString:[equality2 substringToIndex:1]];
				equality2 = [equality2 substringFromIndex:1];
				CFIndex score = diff_cleanupSemanticScore((__bridge CFStringRef)equality1, (__bridge CFStringRef)edit) + diff_cleanupSemanticScore((__bridge CFStringRef)edit, (__bridge CFStringRef)equality2);
				
				// The >= encourages trailing rather than leading whitespace on edits.
				if(score >= bestScore) {
					bestScore = score;
					bestEquality1 = equality1;
					bestEdit = edit;
					bestEquality2 = equality2;
				}
			}
			
			if(prevDiff.text != bestEquality1) {
				// We have an improvement, save it back to the diff.
				if(bestEquality1.length != 0) {
					prevDiff.text = bestEquality1;
				} else {
					[diffs removeObjectAtIndex:indexOfCurrentDiff - 1];
					indexOfCurrentDiff--;
				}
				
				thisDiff.text = bestEdit;
				
				if(bestEquality2.length != 0) {
					nextDiff.text = bestEquality2;
				} else {
					[diffs removeObjectAtIndex:indexOfCurrentDiff + 1];
					indexOfCurrentDiff--;
				}
			}
		}
		
		indexOfCurrentDiff++;
	}
}



/**
 * Reduce the number of edits by eliminating operationally trivial
 * equalities.
 * @param diffs NSMutableArray of Diff objects.
 */

void patch_cleanupDiffsForEfficiency(NSMutableArray **diffs, PatchProperties properties)
{
	if(diffs == NULL || [*diffs count] == 0) {
		return;
	}
	
	BOOL changes = NO;
	// Stack of indices where equalities are found.
	CFMutableArrayRef equalities = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
	
	// Always equal to equalities.lastObject.text
	NSString *lastequality = nil;
	CFIndex indexOfCurrentDiff = 0;	// Index of current position.
	BOOL pre_ins = NO;		// Is there an insertion operation before the last equality.
	BOOL pre_del = NO;		// Is there a deletion operation before the last equality.
	BOOL post_ins = NO;		// Is there an insertion operation after the last equality.
	BOOL post_del = NO;		// Is there a deletion operation after the last equality.
	
	NSUInteger indexToChange = 0;
	DMDiff *diffToChange = nil;
	
	while(indexOfCurrentDiff < [*diffs count]) {
		DMDiff *thisDiff = [*diffs objectAtIndex:indexOfCurrentDiff];
		
		if(thisDiff.operation == DIFF_EQUAL) {
			// Equality found.
			if(thisDiff.text.length < properties.diffEditingCost && (post_ins || post_del)) {
				// Candidate found.
				CFArrayAppendValue(equalities, (void *)indexOfCurrentDiff);
				pre_ins = post_ins;
				pre_del = post_del;
				lastequality = thisDiff.text;
			} else {
				// Not a candidate, and can never become one.
				CFArrayRemoveAllValues(equalities);
				lastequality = nil;
			}
			
			post_ins = post_del = NO;
		} else {                                                                                                                                                                                                                                                                                                                        
			// An insertion or deletion.
			if(thisDiff.operation == DIFF_DELETE) {
				post_del = YES;
			} else {
				post_ins = YES;
			}
			
			/*
			 * Five types to be split:
			 * <ins>A</ins><del>B</del>XY<ins>C</ins><del>D</del>
			 * <ins>A</ins>X<ins>C</ins><del>D</del>
			 * <ins>A</ins><del>B</del>X<ins>C</ins>
			 * <ins>A</del>X<ins>C</ins><del>D</del>
			 * <ins>A</ins><del>B</del>X<del>C</del>
			 */
			if((lastequality != nil) && ((pre_ins && pre_del && post_ins && post_del) 
				|| ((lastequality.length < properties.diffEditingCost / 2)
					&& ((pre_ins ? 1 : 0) + (pre_del ? 1 : 0) + (post_ins ? 1 : 0) + (post_del ? 1 : 0)) == 3))) {
				// Duplicate record.
				CFIndex indexOfLastEquality = diff_CFArrayLastValueAsCFIndex(equalities);
				[*diffs insertObject:[DMDiff diffWithOperation:DIFF_DELETE andText:lastequality] atIndex:indexOfLastEquality];
				
				// Change second copy to insert.
				indexToChange = indexOfLastEquality + 1;
				diffToChange = [*diffs objectAtIndex:indexToChange];
				
				// The following assumes, that the diff we are changing is currently not used in a collection where its hash determines its position (e.g. a dictionary)
				diffToChange.operation = DIFF_INSERT;
				
				diff_CFArrayRemoveLastValue(equalities);	// Throw away the equality we just deleted.
				lastequality = nil;
				
				if(pre_ins && pre_del) {
				   // No changes made which could affect previous entry, keep going.
				   post_ins = post_del = YES;
				   CFArrayRemoveAllValues(equalities);
				} else {
				   if(CFArrayGetCount(equalities) > 0) {
					   diff_CFArrayRemoveLastValue(equalities);
				   }
					
				   indexOfCurrentDiff = CFArrayGetCount(equalities) > 0 ? indexOfLastEquality : -1;
				   post_ins = post_del = NO;
				}
				
				changes = YES;
			}
		}
		
		indexOfCurrentDiff++;
	}
	
	if(changes) {
		diff_cleanupMerge(diffs);
	}
	
	CFRelease(equalities);
}



/**
 * Convert a Diff list into a pretty HTML report.
 * @param diffs NSMutableArray of Diff objects.
 * @return HTML representation.
 */

NSString *diff_prettyHTMLFromDiffs(NSArray *diffs)
{
	NSMutableString *html = [NSMutableString string];
	
	for(DMDiff *diff in diffs) {
		NSString *diffText = [diff.text stringByEscapingHTML];
		
		switch(diff.operation) {
			case DIFF_INSERT:
				[html appendFormat:@"<ins>%@</ins>", diffText];
				break;
				
			case DIFF_DELETE:
				[html appendFormat:@"<del>%@</del>", diffText];
				break;
				
			case DIFF_EQUAL:
				[html appendFormat:@"<span>%@</span>", diffText];
				break;
		}
	}
	
	return html;
}



/**
 * Compute and return the source text (all equalities and deletions).
 * @param diffs NSMutableArray of Diff objects.
 * @return Source text.
 */

NSString *diff_text1(NSArray *diffs)
{
	NSMutableString *text = [NSMutableString string];
	
	for(DMDiff *diff in diffs) {
		if(diff.operation != DIFF_INSERT) {
			[text appendString:diff.text];
		}
	}
	
	return text;
}

/**
 * Compute and return the destination text (all equalities and insertions).
 * @param diffs NSMutableArray of Diff objects.
 * @return Destination text.
 */

NSString *diff_text2(NSArray *diffs)
{
	NSMutableString *text = [NSMutableString string];
	
	for(DMDiff *diff in diffs) {
		if(diff.operation != DIFF_DELETE) {
			[text appendString:diff.text];
		}
	}
	
	return text;
}



/**
 * Crush the diff into an encoded NSString which describes the operations
 * required to transform text1 into text2.
 * E.g. =3\t-2\t+ing  -> Keep 3 chars, delete 2 chars, insert 'ing'.
 * Operations are tab-separated.  Inserted text is escaped using %xx
 * notation.
 * @param diffs array of DMDiff objects.
 * @return Delta text.
 */

NSString *diff_deltaFromDiffs(NSArray *diffs)
{
	NSMutableString *delta = [NSMutableString string];
	
	for(DMDiff *diff in diffs) {
		switch(diff.operation) {
			case DIFF_INSERT:
				[delta appendFormat:@"+%@\t", [[diff.text encodedURIString] stringByReplacingOccurrencesOfString:@"%20" withString:@" "]];
				break;
				
			case DIFF_DELETE:
				[delta appendFormat:@"-%" PRId32 "\t", (int32_t)diff.text.length];
				break;
				
			case DIFF_EQUAL:
				[delta appendFormat:@"=%" PRId32 "\t", (int32_t)diff.text.length];
				break;
		}
	}
	
	if(delta.length != 0) {
		// Strip off trailing tab character.
		return [delta substringToIndex:(delta.length - 1)];
	}
	
	return delta;
}



/**
 * Given the original text1, and an encoded NSString which describes the
 * operations required to transform text1 into text2, compute the full diff.
 * @param text1 Source NSString for the diff.
 * @param delta Delta text.
 * @param error NSError if invalid input.
 * @return NSMutableArray of DMDiff objects or nil if invalid.
 */

NSArray *diff_diffsFromOriginalTextAndDelta(NSString *text1, NSString *delta, NSError **error)
{
	NSMutableArray *diffs = [NSMutableArray array];
	NSUInteger indexOfCurrentDiff = 0;											// Cursor in text1
	NSArray *tokens = [delta componentsSeparatedByString:@"\t"];
	NSInteger n = 0;
	
	for(NSString *token in tokens) {
		if(token.length == 0) {
			// Blank tokens are ok (from a trailing \t).
			continue;
		}
		
		// Each token begins with a one character parameter which specifies the
		// operation of this token (delete, insert, equality).
		NSString *param = [token substringFromIndex:1];
		
		switch([token characterAtIndex:0]) {
			case '+':
				{
					param = [param decodedURIString];
					
					if(param == nil) {
						if(error != NULL) {
							NSString *errorDescription = [NSString stringWithFormat:NSLocalizedString(@"Invalid character in diff_fromDelta: %@", @"Error"), param];
							*error = [NSError errorWithDomain:@"DiffMatchPatchErrorDomain" code:99 userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
						}
						
						return nil;
					}
					
					[diffs addObject:[DMDiff diffWithOperation:DIFF_INSERT andText:param]];
					break;
				}
				
			case '-':
				// Fall through.
			case '=':
				{
					n = [param integerValue];
					
					if(n == 0) {
						if(error != NULL) {
							NSString *errorDescription = [NSString stringWithFormat:NSLocalizedString(@"Invalid number in diff_fromDelta: %@", @"Error"), param];
							*error = [NSError errorWithDomain:@"DiffMatchPatchErrorDomain" code:100 userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
						}
						
						return nil;
					} else if(n < 0) {
						if(error != NULL) {
							NSString *errorDescription = [NSString stringWithFormat:NSLocalizedString(@"Negative number in diff_fromDelta: %@", @"Error"), param];
							*error = [NSError errorWithDomain:@"DiffMatchPatchErrorDomain" code:101 userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
						}
						
						return nil;
					}
					
					NSString *text = nil;
					NSRange text1Range = NSMakeRange(0, text1.length);
					
					if(NSLocationInRange(indexOfCurrentDiff, text1Range) && NSLocationInRange(indexOfCurrentDiff + (NSUInteger)n - 1, text1Range)) {
						text = [text1 substringWithRange:NSMakeRange(indexOfCurrentDiff, (NSUInteger)n)];
						indexOfCurrentDiff += (NSUInteger)n;
					} else {
						if(error != NULL) {
							NSString *errorDescription = [NSString stringWithFormat:NSLocalizedString(@"Delta length (%lu) larger than source text length (%lu).", @"Error"), (unsigned long)indexOfCurrentDiff, (unsigned long)text1.length];
							*error = [NSError errorWithDomain:@"DiffMatchPatchErrorDomain" code:102 userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
						}
						
						return nil;
					}
					
					if([token characterAtIndex:0] == '=') {
						[diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:text]];
					} else {
						[diffs addObject:[DMDiff diffWithOperation:DIFF_DELETE andText:text]];
					}
					
					break;
				}
				
			default:
				// Anything else is an error.
				if(error != NULL) {
					NSString *errorDescription = [NSString stringWithFormat:NSLocalizedString(@"Invalid diff operation in diff_fromDelta: %C", @"Error"), [token characterAtIndex:0]];
					*error = [NSError errorWithDomain:@"DiffMatchPatchErrorDomain" code:102 userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
				}
				
				return nil;
		}
	}
	
	if(indexOfCurrentDiff != text1.length) {
		if(error != NULL) {
			NSString *errorDescription = [NSString stringWithFormat:NSLocalizedString(@"Delta length (%lu) smaller than source text length (%lu).", @"Error"), (unsigned long)indexOfCurrentDiff, (unsigned long)text1.length];
			*error = [NSError errorWithDomain:@"DiffMatchPatchErrorDomain" code:103 userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
		}
		
		return nil;
	}
	
	return diffs;
}



/**
 * loc is a location in text1, compute and return the equivalent location in text2.
 *		e.g. "The cat" vs "The big cat", 1->1, 5->8
 * 
 * @param diffs NSMutableArray of DMDiff objects.
 * @param loc Location within text1.
 * @return Location within text2.
 */

NSUInteger diff_translateLocationFromText1ToText2(NSArray *diffs, NSUInteger location)
{
	NSUInteger chars1 = 0;
	NSUInteger chars2 = 0;
	NSUInteger last_chars1 = 0;
	NSUInteger last_chars2 = 0;
	DMDiff *lastDiff = nil;
	
	for(DMDiff *diff in diffs) {
		if(diff.operation != DIFF_INSERT) {
			// Equality or deletion.
			chars1 += diff.text.length;
		}
		
		if(diff.operation != DIFF_DELETE) {
			// Equality or insertion.
			chars2 += diff.text.length;
		}
		
		if(chars1 > location) {
			// Overshot the location.
			lastDiff = diff;
			break;
		}
		
		last_chars1 = chars1;
		last_chars2 = chars2;
	}
	
	if(lastDiff != nil && lastDiff.operation == DIFF_DELETE) {
		// The location was deleted.
		return last_chars2;
	}
	
	// Add the remaining character length.
	return last_chars2 + (location - last_chars1);
}



/**
 * Compute the Levenshtein distance; the number of inserted, deleted or
 * substituted characters.
 * @param diffs NSArray of Diff objects.
 * @return Number of changes.
 */

NSUInteger diff_levenshtein(NSArray *diffs)
{
	NSUInteger levenshtein = 0;
	NSUInteger insertions = 0;
	NSUInteger deletions = 0;
	
	for(DMDiff *diff in diffs) {
		switch(diff.operation) {
			case DIFF_INSERT:
				insertions += diff.text.length;
				break;
				
			case DIFF_DELETE:
				deletions += diff.text.length;
				break;
				
			case DIFF_EQUAL:
				// A deletion and an insertion is one substitution.
				levenshtein += MAX(insertions, deletions);
				insertions = 0;
				deletions = 0;
				break;
		}
	}
	
	levenshtein += MAX(insertions, deletions);
	return levenshtein;
}



/**
 * Reduce the number of edits by eliminating semantically trivial
 * equalities.
 * @param diffs NSMutableArray of Diff objects.
 */

void diff_cleanupSemantic(NSMutableArray **diffs)
{
	if(diffs == NULL || [*diffs count] == 0) {
		return;
	}
	
	// Stack of indices where equalities are found.
	CFMutableArrayRef equalities = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
	
	NSString *lastEquality = nil;		// Always equal to [diffs objectAtIndex:equalitiesLastValue].text
	NSUInteger indexOfCurrentDiff = 0;	// Index of current position.
									
	// Number of characters that changed prior to the equality.	
	NSUInteger length_insertions1 = 0;
	NSUInteger length_deletions1 = 0;
	
	// Number of characters that changed after the equality.
	NSUInteger length_insertions2 = 0;
	NSUInteger length_deletions2 = 0;
	
	NSUInteger indexToChange;
	DMDiff *diffToChange = nil;
	BOOL changes = NO;
	
	while(indexOfCurrentDiff < [*diffs count]) {
		DMDiff *thisDiff = [*diffs objectAtIndex:indexOfCurrentDiff];
		
		if(thisDiff.operation == DIFF_EQUAL) {                                                                                                                                                                                                                                                                                                // Equality found.
			CFArrayAppendValue(equalities, (void *)indexOfCurrentDiff);
			length_insertions1 = length_insertions2;
			length_deletions1 = length_deletions2;
			length_insertions2 = 0;
			length_deletions2 = 0;
			lastEquality = thisDiff.text;
		} else {                                                                                                                                                                                                                                                                                                                              // an insertion or deletion
			if(thisDiff.operation == DIFF_INSERT) {
				length_insertions2 += thisDiff.text.length;
			} else {
				length_deletions2 += thisDiff.text.length;
			}
			
			// Eliminate an equality that is smaller or equal to the edits on both sides of it.
			if(lastEquality != nil
			   && (lastEquality.length <= MAX(length_insertions1, length_deletions1))
			   && (lastEquality.length <= MAX(length_insertions2, length_deletions2))) {
				// Duplicate record.
				CFIndex indexOfLastEquality = diff_CFArrayLastValueAsCFIndex(equalities);
				[*diffs insertObject:[DMDiff diffWithOperation:DIFF_DELETE andText:lastEquality] atIndex:indexOfLastEquality];
				
				// Change second copy to insert.
				indexToChange = indexOfLastEquality + 1;
				diffToChange = [*diffs objectAtIndex:indexToChange];
				
				// The following assumes, that the diff we are changing is currently not used in a collection where its hash determines its position (e.g. a dictionary)
				diffToChange.operation = DIFF_INSERT;
				
				// Throw away the equality we just deleted.
				diff_CFArrayRemoveLastValue(equalities);
				
				if(CFArrayGetCount(equalities) > 0) {
					diff_CFArrayRemoveLastValue(equalities);
				}
				
				// Setting an unsigned value to -1 may seem weird to some,
				// but we will pass thru a ++ below:
				// => overflow => 0
				indexOfCurrentDiff = CFArrayGetCount(equalities) > 0 ? diff_CFArrayLastValueAsCFIndex(equalities) : -1;
				
				// Reset the counters.
				length_insertions1 = 0;
				length_deletions1 = 0;
				length_insertions2 = 0;
				length_deletions2 = 0;
				lastEquality = nil;
				changes = YES;
			}
		}
		
		indexOfCurrentDiff++;
	}
	
	// Normalize the diff.
	if(changes) {
		diff_cleanupMerge(diffs);
	}
	
	
	diff_cleanupSemanticLossless(diffs);
	
	// Jan: someDiff.text will NOT retain and autorelease the NSString object.
	// This is why “prevDiff.text = ” below can cause it’s previous value to be deallocated
	// instead of just released as one would expect without taking the above into account.
	// Thus we need to retain its previous value before “prevDiff.text = ” and release afterwards.
	// Alternatively, we could remove the nonatomic from the “text” @property definition.
	// This would cause much more of a perfomance hit then warranted, though.
	
	// Find any overlaps between deletions and insertions.
	// e.g: <del>abcxxx</del><ins>xxxdef</ins>
	// -> <del>abc</del>xxx<ins>def</ins>
	// e.g: <del>xxxabc</del><ins>defxxx</ins>
	// -> <ins>def</ins>xxx<del>abc</del>
	// Only extract an overlap if it is as big as the edit ahead or behind it.
	indexOfCurrentDiff = 1;
	
	while(indexOfCurrentDiff < [*diffs count]) {
		DMDiff *prevDiff = [*diffs objectAtIndex:indexOfCurrentDiff - 1];
		DMDiff *thisDiff = [*diffs objectAtIndex:indexOfCurrentDiff];
		
		if(prevDiff.operation == DIFF_DELETE && thisDiff.operation == DIFF_INSERT) {
			NSString *deletion = prevDiff.text;
			NSString *insertion = thisDiff.text;
			NSUInteger overlap_length1 = (NSUInteger)diff_commonOverlap((__bridge CFStringRef)deletion, (__bridge CFStringRef)insertion);
			NSUInteger overlap_length2 = (NSUInteger)diff_commonOverlap((__bridge CFStringRef)insertion, (__bridge CFStringRef)deletion);
			
			if(overlap_length1 >= overlap_length2) {
				if((overlap_length1 >= deletion.length / 2.0f) || (overlap_length1 >= insertion.length / 2.0f)) {
					// Overlap found. Insert an equality and trim the surrounding edits.
					[*diffs insertObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:[insertion substringToIndex:overlap_length1]] atIndex:indexOfCurrentDiff];
					prevDiff.text = [deletion substringToIndex:(deletion.length - overlap_length1)];
					
					DMDiff *nextDiff = [*diffs objectAtIndex:indexOfCurrentDiff + 1];
					nextDiff.text = [insertion substringFromIndex:overlap_length1];
					indexOfCurrentDiff++;
				}
			} else {
				if(overlap_length2 >= deletion.length / 2.0f ||
				   overlap_length2 >= insertion.length / 2.0f) {
					// Reverse overlap found.
					// Insert an equality and swap and trim the surrounding edits.
					[*diffs insertObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:[deletion substringToIndex:overlap_length2]] atIndex:indexOfCurrentDiff];
					prevDiff.operation = DIFF_INSERT;
					prevDiff.text = [insertion substringToIndex:(insertion.length - overlap_length2)];
			DMDiff *nextDiff = [*diffs objectAtIndex:indexOfCurrentDiff + 1];
					nextDiff.operation = DIFF_DELETE;
					nextDiff.text = [deletion substringFromIndex:overlap_length2];
					indexOfCurrentDiff++;
				}
			}
			
			indexOfCurrentDiff++;
		}
		
		indexOfCurrentDiff++;
	}
	
	CFRelease(equalities);
}



#pragma mark -
#pragma mark Match Functions


NSUInteger match_locationOfMatchInText(NSString *text, NSString *pattern, NSUInteger approximateLocation)
{
	MatchProperties properties = match_defaultMatchProperties();
	return match_locationOfMatchInTextWithProperties(text, pattern, approximateLocation, properties);
}


NSUInteger match_locationOfMatchInTextWithOptions(NSString *text, NSString *pattern, NSUInteger approximateLocation, CGFloat matchThreshold, NSUInteger matchDistance)
{
	MatchProperties properties = match_defaultMatchProperties();
	properties.matchThreshold = matchThreshold;
	properties.matchDistance = matchDistance;
	
	return match_locationOfMatchInTextWithProperties(text, pattern, approximateLocation, properties);
}


/**
 * Locate the best instance of 'pattern' in 'text' near 'nearestLocation'.
 * Returns NSNotFound if no match found.
 * @param text				The text to search.
 * @param pattern			The pattern to search for.
 * @param nearestLocation	The location to search around.
 * @param properties		See the MatchProperties struct in DiffMatchPatchInternals.h for more info
 * @return Index of the best match or NSNotFound.
 */

NSUInteger match_locationOfMatchInTextWithProperties(NSString *text, NSString *pattern, NSUInteger approximateLocation, MatchProperties properties)
{
	// Check for null inputs.
	if(text == nil || pattern == nil) {
		NSLog(@"Null inputs. (match_main)");
		return NSNotFound;
	}
	
	if(text.length == 0) {
		NSLog(@"Empty text. (match_main)");
		return NSNotFound;
	}
	
	NSUInteger new_loc;
	new_loc = MIN(approximateLocation, text.length);
	new_loc = MAX((NSUInteger)0, new_loc);
	
	if([text isEqualToString:pattern]) {
		// Shortcut (potentially not guaranteed by the algorithm)
		return 0;
	} else if(text.length == 0) {
		// Nothing to match.
		return NSNotFound;
	} else if(new_loc + pattern.length <= text.length
			  && [[text substringWithRange:NSMakeRange(new_loc, pattern.length)] isEqualToString:pattern]) {
		// Perfect match at the perfect spot!   (Includes case of empty pattern)
		return new_loc;
	} else {
		// Do a fuzzy compare.
		return match_bitapOfTextAndPattern(text, pattern, new_loc, properties);
	}
}



/**
 * Locate the best instance of 'pattern' in 'text' near 'loc' using the
 * Bitap algorithm.   Returns NSNotFound if no match found.
 * @param text The text to search.
 * @param pattern The pattern to search for.
 * @param loc The location to search around.
 * @return Best match index or NSNotFound.
 */

NSUInteger match_bitapOfTextAndPattern(NSString *text, NSString *pattern, NSUInteger approximateLocation, MatchProperties properties)
{
	NSCAssert((properties.matchMaximumBits == 0 || pattern.length <= properties.matchMaximumBits), @"Pattern too long for this application.");
	
	// Initialise the alphabet.
	NSMutableDictionary *alphabet = match_alphabetFromPattern(pattern);
	
	// Highest score beyond which we give up.
	double score_threshold = properties.matchThreshold;
	
	// Is there a nearby exact match? (speedup)
	NSUInteger best_loc = [text rangeOfString:pattern options:NSLiteralSearch range:NSMakeRange(approximateLocation, text.length - approximateLocation)].location;
	
	if(best_loc != NSNotFound) {
		score_threshold = MIN(match_bitapScoreForErrorCount(0, best_loc, approximateLocation, pattern, properties), score_threshold);
		
		// What about in the other direction? (speedup)
		NSUInteger searchRangeLoc = MIN(approximateLocation + pattern.length, text.length);
		NSRange searchRange = NSMakeRange(0, searchRangeLoc);
		best_loc = [text rangeOfString:pattern options:(NSLiteralSearch | NSBackwardsSearch) range:searchRange].location;
		
		if(best_loc != NSNotFound) {
			score_threshold = MIN(match_bitapScoreForErrorCount(0, best_loc, approximateLocation, pattern, properties), score_threshold);
		}
	}
	
	// Initialise the bit arrays.
	NSUInteger matchmask = 1 << (pattern.length - 1);
	best_loc = NSNotFound;
	
	NSUInteger bin_min, bin_mid;
	NSUInteger bin_max = pattern.length + text.length;
	NSUInteger *rd = NULL;
	NSUInteger *last_rd = NULL;
	
	for(NSUInteger d = 0; d < pattern.length; d++) {
		// Scan for the best match; each iteration allows for one more error.
		// Run a binary search to determine how far from 'loc' we can stray at
		// this error level.
		bin_min = 0;
		bin_mid = bin_max;
		
		while(bin_min < bin_mid) {
			double score = match_bitapScoreForErrorCount(d, (approximateLocation + bin_mid), approximateLocation, pattern, properties);
			
			if(score <= score_threshold) {
				bin_min = bin_mid;
			} else {
				bin_max = bin_mid;
			}
			
			bin_mid = (bin_max - bin_min) / 2 + bin_min;
		}
		
		// Use the result from this iteration as the maximum for the next.
		bin_max = bin_mid;
		NSUInteger start = MAX_OF_CONST_AND_DIFF(1, approximateLocation, bin_mid);
		NSUInteger finish = MIN(approximateLocation + bin_mid, text.length) + pattern.length;
		
		rd = (NSUInteger *)calloc((finish + 2), sizeof(NSUInteger));
		rd[finish + 1] = (1 << d) - 1;
		
		for(NSUInteger j = finish; j >= start; j--) {
			NSUInteger charMatch;
			
			if(text.length <= j - 1 || ![alphabet objectForKey:[text substringWithRange:NSMakeRange((j - 1), 1)]]) {
				// Out of range.
				charMatch = 0;
			} else {
				charMatch = [(NSNumber *)[alphabet objectForKey:[text substringWithRange:NSMakeRange((j - 1), 1)]] unsignedIntegerValue];
			}
			
			if(d == 0) {
				// First pass: exact match.
				rd[j] = (((rd[j + 1] << 1) | 1) & charMatch);
			} else {
				// Subsequent passes: fuzzy match.
				rd[j] = (((rd[j + 1] << 1) | 1) & charMatch)
				| (((last_rd[j + 1] | last_rd[j]) << 1) | 1) | last_rd[j + 1];
			}
			
			if((rd[j] & matchmask) != 0) {
				double score = match_bitapScoreForErrorCount(d, (j - 1), approximateLocation, pattern, properties);
				
				// This match will almost certainly be better than any existing match. But check anyway.
				if(score <= score_threshold) {
					// Told you so.
					score_threshold = score;
					best_loc = j - 1;
					
					if(best_loc > approximateLocation) {
						// When passing loc, don't exceed our current distance from loc.
						start = MAX_OF_CONST_AND_DIFF(1, 2 * approximateLocation, best_loc);
					} else {
						// Already passed loc, downhill from here.
						break;
					}
				}
			}
		}
		
		if(last_rd != NULL) {
			free(last_rd);
		}
		
		last_rd = rd;
		
		if(match_bitapScoreForErrorCount((d + 1), approximateLocation, approximateLocation, pattern, properties) > score_threshold) {
			// No hope for a (better) match at greater error levels.
			break;
		}
	}
	
	if(last_rd != NULL && last_rd != rd) {
		free(last_rd);
	}
	
	if(rd != NULL) {
		free(rd);
	}
	
	return best_loc;
}



/**
 * Compute and return the score for a match with e errors and x location.
 * @param e Number of errors in match.
 * @param x Location of match.
 * @param loc Expected location of match.
 * @param pattern Pattern being sought.
 * @return Overall score for match (0.0 = good, 1.0 = bad).
 */

double match_bitapScoreForErrorCount(NSUInteger e, NSUInteger x, NSUInteger approximateLocation, NSString *pattern, MatchProperties properties)
{
	double score;
	double accuracy = (double)e / pattern.length;
	NSUInteger proximity = (NSUInteger)ABS((long long)approximateLocation - (long long)x);
	
	if(properties.matchDistance == 0) {
		return proximity == 0 ? accuracy : 1.0;		// Dodge divide by zero error.
	}
	
	score = accuracy + (proximity / (double)properties.matchDistance);
	return score;
}



/**
 * Initialise the alphabet for the Bitap algorithm.
 * @param pattern The text to encode.
 * @return Hash of character locations
 *     (NSMutableDictionary: keys:NSString/unichar, values:NSNumber/NSUInteger).
 */

NSMutableDictionary *match_alphabetFromPattern(NSString *pattern)
{
	NSMutableDictionary *alphabet = [NSMutableDictionary dictionary];
	CFStringRef str = (__bridge CFStringRef)pattern;
	CFStringInlineBuffer inlineBuffer;
	CFIndex length;
	CFIndex cnt;
	
	length = CFStringGetLength(str);
	CFStringInitInlineBuffer(str, &inlineBuffer, CFRangeMake(0, length));
	
	UniChar unicodeCharacter;
	NSString *character = nil;
	
	for(cnt = 0; cnt < length; cnt++) {
		unicodeCharacter = CFStringGetCharacterFromInlineBuffer(&inlineBuffer, cnt);
		
		// Create a string from the unichar
		character = (__bridge_transfer NSString *)CFStringCreateWithCharacters(kCFAllocatorDefault, &unicodeCharacter, 1);
		
		if(![alphabet objectForKey:character]) {
			[alphabet setObject:@(0) forKey:character];
		}
	}
	
	NSUInteger i = 0;
	
	for(cnt = 0; cnt < length; cnt++) {
		unicodeCharacter = CFStringGetCharacterFromInlineBuffer(&inlineBuffer, cnt);
		character = (__bridge_transfer NSString *)CFStringCreateWithCharacters(kCFAllocatorDefault, &unicodeCharacter, 1);	// Create a string from a unichar
		NSUInteger value = [(NSNumber *)[alphabet objectForKey:character] unsignedIntegerValue] | (1 << (pattern.length - i - 1));
		[alphabet setObject:@(value) forKey:character];
		i++;
	}
	
	return alphabet;
}



#pragma mark -
#pragma mark Patch Functions


NSArray *patch_patchesFromTexts(NSString *text1, NSString *text2)
{
	PatchProperties properties = patch_defaultPatchProperties();
	return patch_patchesFromTextsWithProperties(text1, text2, properties);
}


/**
 * Compute a list of patches to turn text1 into text2.
 * A set of diffs will be computed.
 * @param text1 Old text.
 * @param text2 New text.
 * @return NSMutableArray of Patch objects.
 */

NSArray *patch_patchesFromTextsWithProperties(NSString *text1, NSString *text2, PatchProperties properties)
{
	// Check for null inputs.
	if(text1 == nil || text2 == nil) {
		NSLog(@"Null inputs. (patch_make)");
		return nil;
	}
	
	// No diffs provided, compute our own.
	NSMutableArray *diffs = diff_diffsBetweenTextsWithProperties(text1, text2, properties.diffProperties);
	
	if(diffs.count > 2) {
		diff_cleanupSemantic(&diffs);
		patch_cleanupDiffsForEfficiency(&diffs, properties);
	}
	
	return patch_patchesFromTextAndDiffs(text1, diffs, properties);
}



/**
 * Compute a list of patches to turn text1 into text2.
 * text1 will be derived from the provided diffs.
 * @param diffs NSMutableArray of Diff objects for text1 to text2.
 * @return NSMutableArray of Patch objects.
 */
 NSArray *patch_patchesFromDiffs(NSArray *diffs, PatchProperties properties)
{
	// Check for nil inputs not needed since nil can't be passed in C#.
	// No origin NSString *provided, comAdde our own.
	return  patch_patchesFromTextAndDiffs(diff_text1(diffs), diffs, properties);
}



/**
 * Compute a list of patches to turn text1 into text2.
 * text2 is not provided, diffs are the delta between text1 and text2.
 * @param text1 Old text.
 * @param diffs NSMutableArray of Diff objects for text1 to text2.
 * @return NSMutableArray of Patch objects.
 */
NSArray *patch_patchesFromTextAndDiffs(NSString *text1, NSArray *diffs, PatchProperties properties)
{
	// Check for null inputs.
	if(text1 == nil) {
		NSLog(@"Null inputs. (patch_make)");
		return nil;
	}
	
	NSMutableArray *patches = [NSMutableArray array];
	
	if(diffs.count == 0) {
		return patches;		// Get rid of the nil case.
	}
	
	DMPatch *patch = [DMPatch new];
	NSUInteger char_count1 = 0;		// Number of characters into the text1 NSString.
	NSUInteger char_count2 = 0;		// Number of characters into the text2 NSString.
	
	// Start with text1 (prepatch_text) and apply the diffs until we arrive at text2 (postpatch_text).
	// We recreate the patches one by one to determine context info.
	
	NSString *prepatch_text = text1;
	NSMutableString *postpatch_text = [text1 mutableCopy];
	
	for(DMDiff *diff in diffs) {
		if(patch.diffs.count == 0 && diff.operation != DIFF_EQUAL) {
			// A new patch starts here.
			patch.start1 = char_count1;
			patch.start2 = char_count2;
		}
		
		switch(diff.operation) {
			case DIFF_INSERT:
				[patch.diffs addObject:diff];
				patch.length2 += diff.text.length;
				[postpatch_text insertString:diff.text atIndex:char_count2];
				break;
				
			case DIFF_DELETE:
				patch.length1 += diff.text.length;
				[patch.diffs addObject:diff];
				[postpatch_text deleteCharactersInRange:NSMakeRange(char_count2, diff.text.length)];
				break;
				
			case DIFF_EQUAL:
				if(diff.text.length <= 2 * properties.patchMargin
				   && [patch.diffs count] != 0 && diff != diffs.lastObject) {
					// Small equality inside a patch.
					[patch.diffs addObject:diff];
					patch.length1 += diff.text.length;
					patch.length2 += diff.text.length;
				}
				
				if(diff.text.length >= 2 * properties.patchMargin) {
					// Time for a new patch.
					if(patch.diffs.count != 0) {
						[patch addContext:prepatch_text withMargin:properties.patchMargin maximumBits:properties.matchProperties.matchMaximumBits];
						[patches addObject:patch];
						patch = [DMPatch new];
						
						// Unlike Unidiff, our patch lists have a rolling context.
						// http://code.google.com/p/google-diff-match-patch/wiki/Unidiff
						// Update prepatch text & pos to reflect the application of the just completed patch.
						prepatch_text = [postpatch_text copy];
						char_count1 = char_count2;
					}
				}
				
				break;
		}
		
		// Update the current character count.
		if(diff.operation != DIFF_INSERT) {
			char_count1 += diff.text.length;
		}
		
		if(diff.operation != DIFF_DELETE) {
			char_count2 += diff.text.length;
		}
	}
	
	// Pick up the leftover patch if not empty.
	if(patch.diffs.count != 0) {
		[patch addContext:prepatch_text withMargin:properties.patchMargin maximumBits:properties.matchProperties.matchMaximumBits];
		[patches addObject:patch];
	}
	
	return patches;
}


/**
 * Merge a set of patches onto the text.  Return a patched text, as well
 * as an index set of for each value for which patches were applied.
 * 
 * @param patches					An NSArray of DMPatch objects
 * @param text						The old text
 * @param indexesOfAppliedPatches	An NSIndexSet of the patches, passed by reference (optional)
 * @return The patched text
 */

NSString *patch_applyPatchesToText(NSArray *sourcePatches, NSString *text, NSIndexSet **indexesOfAppliedPatches)
{
	PatchProperties properties = patch_defaultPatchProperties();
	return patch_applyPatchesToTextWithProperties(sourcePatches, text, indexesOfAppliedPatches, properties);
}


/**
 * Merge a set of patches onto the text.  Return a patched text, as well
 * as an index set of for each value for which patches were applied.
 * 
 * @param patches					An NSArray of DMPatch objects
 * @param text						The old text
 * @param indexesOfAppliedPatches	An NSIndexSet of the patches, passed by reference (optional)
 * @param properties				PatchProperties defining the properties used to patch the text
 * @return The patched text
 */
 
NSString *patch_applyPatchesToTextWithProperties(NSArray *sourcePatches, NSString *text, NSIndexSet **indexesOfAppliedPatches, PatchProperties properties)
{
	if(sourcePatches.count == 0) {
		if(indexesOfAppliedPatches != NULL)
			*indexesOfAppliedPatches = [[NSIndexSet alloc] init];
		
		return text;
	}
	
	// Deep copy the patches so that no changes are made to originals.
	NSMutableArray *patches = [[NSMutableArray alloc] initWithArray:sourcePatches copyItems:TRUE];
	NSMutableString *mutableText = [text mutableCopy];
	
	NSString *nullPadding = patch_addPaddingToPatches(&patches, properties);
	[mutableText insertString:nullPadding atIndex:0];
	[mutableText appendString:nullPadding];
	patch_splitMax(&patches, properties);
	
	// delta keeps track of the offset between the expected and actual
	// location of the previous patch.  If there are patches expected at
	// positions 10 and 20, but the first patch was found at 12, delta is 2
	// and the second patch has an effective expected position of 22.
	NSUInteger delta = 0;
	NSUInteger maxBits = properties.matchProperties.matchMaximumBits;
	
	NSMutableIndexSet *appliedPatches = [[NSMutableIndexSet alloc] init];
	NSUInteger patchIndex = 0;
	
	for(DMPatch *currentPatch in patches) {
		NSUInteger expected_loc = currentPatch.start2 + delta;
		NSString *text1 = diff_text1(currentPatch.diffs);
		NSUInteger start_loc;
		NSUInteger endLocation = NSNotFound;
		if(text1.length > maxBits) {
			// patch_splitMax will only provide an oversized pattern in the case of a monster delete.
			start_loc = match_locationOfMatchInText(mutableText, [text1 substringWithRange:NSMakeRange(0, maxBits)], expected_loc);
			if(start_loc != NSNotFound) {
				endLocation = match_locationOfMatchInText(mutableText, [text1 substringFromIndex:text1.length - maxBits], (expected_loc + text1.length - maxBits));
				
				if(endLocation == NSNotFound || start_loc >= endLocation) {
					// Can't find valid trailing context. Drop this patch.
					start_loc = NSNotFound;
				}
			}
		} else {
			start_loc = match_locationOfMatchInText(mutableText, text1, expected_loc);
		}
		
		if(start_loc == NSNotFound) {
			// No match found.  :(
			[appliedPatches removeIndex:patchIndex];
			// Subtract the delta for this failed patch from subsequent patches.
			delta -= currentPatch.length2 - currentPatch.length1;
		} else {
			// Found a match.   :)
			[appliedPatches addIndex:patchIndex];
			
			delta = start_loc - expected_loc;
			
			NSString *text2 = nil;
			
			if(endLocation == NSNotFound) {
				text2 = [mutableText substringWithRange:NSMakeRange(start_loc, MIN(text1.length, mutableText.length))];
			} else {
				text2 = [mutableText substringWithRange:NSMakeRange(start_loc, MIN(endLocation + maxBits, mutableText.length))];
			}
			
			if(text1 == text2) {
				// Perfect match, just shove the Replacement text in.
				[mutableText replaceCharactersInRange:NSMakeRange(start_loc, text1.length) withString:diff_text2(currentPatch.diffs)];
			} else {
				// Imperfect match.   Run a diff to get a framework of equivalent indices.
				NSMutableArray *diffs = diff_diffsBetweenTextsWithProperties(text1, text2, properties.diffProperties);
				
				if(text1.length > maxBits && (diff_levenshtein(diffs) / (float)text1.length) > properties.patchDeleteThreshold) {
					// The end points match, but the content is unacceptably bad.
					[appliedPatches removeIndex:patchIndex];
				} else {
					diff_cleanupSemanticLossless(&diffs);
					
					NSUInteger index1 = 0;
					for(DMDiff *currentDiff in currentPatch.diffs) {
						if(currentDiff.operation != DIFF_EQUAL) {
							NSUInteger index2 = diff_translateLocationFromText1ToText2(diffs, index1);
							
							if(currentDiff.operation == DIFF_INSERT) {
								// Insertion
								[mutableText insertString:currentDiff.text atIndex:(start_loc + index2)];
							} else if(currentDiff.operation == DIFF_DELETE) {
								// Deletion
								NSUInteger deletionEndPosition = diff_translateLocationFromText1ToText2(diffs, (index1 + currentDiff.text.length));
								[mutableText deleteCharactersInRange:NSMakeRange(start_loc + index2, (deletionEndPosition - index2))];
							}
						}
						
						if(currentDiff.operation != DIFF_DELETE) {
							index1 += currentDiff.text.length;
						}
					}
				}
			}
		}
		
		patchIndex++;
	}
	
	
	// Strip the padding.
	text = [mutableText substringWithRange:NSMakeRange(nullPadding.length, mutableText.length - 2 * nullPadding.length)];
	
	if(indexesOfAppliedPatches != NULL)
		*indexesOfAppliedPatches = appliedPatches;
	
	return text;
}


/**
 * Add some padding on text start and end so that edges can match something.
 * Intended to be called only from within patch_apply.
 * @param patches NSMutableArray of Patch objects.
 * @return The padding NSString added to each side.
 */
NSString *patch_addPaddingToPatches(NSMutableArray **patches, PatchProperties properties)
{
	if(patches == NULL || [*patches count] == 0)
		return nil;
	
	uint16_t paddingLength = properties.patchMargin;
	NSMutableString *nullPadding = [NSMutableString string];
	
	for(UniChar x = 1; x <= paddingLength; x++) {
		CFStringAppendCharacters((CFMutableStringRef)nullPadding, &x, 1);
	}
	
	// Bump all the patches forward.
	for(DMPatch *patch in *patches) {
		patch.start1 += paddingLength;
		patch.start2 += paddingLength;
	}
	
	// Add some padding on start of first diff.
	DMPatch *patch = [*patches objectAtIndex:0];
	NSMutableArray *diffs = patch.diffs;
	
	if(diffs.count == 0 || ((DMDiff *)diffs[0]).operation != DIFF_EQUAL) {
		// Add nullPadding equality.
		[diffs insertObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:nullPadding] atIndex:0];
		patch.start1 -= paddingLength;                                                                                                                                                                                                                                                                                                                                 // Should be 0.
		patch.start2 -= paddingLength;                                                                                                                                                                                                                                                                                                                                 // Should be 0.
		patch.length1 += paddingLength;
		patch.length2 += paddingLength;
	} else if(paddingLength > ((DMDiff *)diffs[0]).text.length) {
		// Grow first equality.
		DMDiff *firstDiff = diffs[0];
		NSUInteger extraLength = paddingLength - firstDiff.text.length;
		firstDiff.text = [[nullPadding substringFromIndex:(firstDiff.text.length)]
						  stringByAppendingString:firstDiff.text];
		patch.start1 -= extraLength;
		patch.start2 -= extraLength;
		patch.length1 += extraLength;
		patch.length2 += extraLength;
	}
	
	// Add some padding on end of last diff.
	patch = [*patches lastObject];
	diffs = patch.diffs;
	
	if(diffs.count == 0 || ((DMDiff *)diffs.lastObject).operation != DIFF_EQUAL) {
		// Add nullPadding equality.
		[diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:nullPadding]];
		patch.length1 += paddingLength;
		patch.length2 += paddingLength;
	} else if(paddingLength > ((DMDiff *)diffs.lastObject).text.length) {
		// Grow last equality.
		DMDiff *lastDiff = diffs.lastObject;
		NSUInteger extraLength = paddingLength - lastDiff.text.length;
		lastDiff.text = [lastDiff.text stringByAppendingString:[nullPadding substringToIndex:extraLength]];
		patch.length1 += extraLength;
		patch.length2 += extraLength;
	}
	
	return nullPadding;
}

/**
 * Look through the patches and break up any which are longer than the
 * maximum limit of the match algorithm.
 * Intended to be called only from within patch_apply.
 * @param patches NSMutableArray of Patch objects.
 */
void patch_splitMax(NSMutableArray **patches, PatchProperties properties)
{
	if(patches == NULL)
		return;

	NSUInteger patch_size = properties.matchProperties.matchMaximumBits;
	NSUInteger numberOfPatches = [*patches count];
	
	for(NSUInteger x = 0; x < numberOfPatches; x++) {
		if([(DMPatch *)[*patches objectAtIndex:x] length1] <= patch_size) {
			continue;
		}
		
		DMPatch *bigpatch = [*patches objectAtIndex:x];
		
		// Remove the big old patch.
		diff_spliceTwoArrays(patches, x--, 1, nil);
		NSUInteger start1 = bigpatch.start1;
		NSUInteger start2 = bigpatch.start2;
		NSString *precontext = @"";
		
		while(bigpatch.diffs.count != 0) {
			// Create one of several smaller patches.
			DMPatch *patch = [DMPatch new];
			BOOL empty = YES;
			patch.start1 = start1 - precontext.length;
			patch.start2 = start2 - precontext.length;
			
			if(precontext.length != 0) {
				patch.length1 = patch.length2 = precontext.length;
				[patch.diffs
				 addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:precontext]];
			}
			
			while(bigpatch.diffs.count != 0 && patch.length1 < patch_size - properties.patchMargin) {
				DMDiffOperation diff_type = ((DMDiff *)(bigpatch.diffs)[0]).operation;
				NSString *diff_text = ((DMDiff *)(bigpatch.diffs)[0]).text;
				
				if(diff_type == DIFF_INSERT) {
					// Insertions are harmless.
					patch.length2 += diff_text.length;
					start2 += diff_text.length;
					[patch.diffs addObject:(bigpatch.diffs)[0]];
					[bigpatch.diffs removeObjectAtIndex:0];
					empty = NO;
				} else if(diff_type == DIFF_DELETE && patch.diffs.count == 1
					  && ((DMDiff *)(patch.diffs)[0]).operation == DIFF_EQUAL
						  && diff_text.length > 2 * patch_size) {
					// This is a large deletion.  Let it pass in one chunk.
					patch.length1 += diff_text.length;
					start1 += diff_text.length;
					empty = NO;
					[patch.diffs addObject:[DMDiff diffWithOperation:diff_type andText:diff_text]];
					[bigpatch.diffs removeObjectAtIndex:0];
				} else {
					// Deletion or equality.  Only take as much as we can stomach.
					diff_text = [diff_text substringWithRange:NSMakeRange(0, MIN(diff_text.length, (patch_size - patch.length1 - properties.patchMargin)))];
					patch.length1 += diff_text.length;
					start1 += diff_text.length;
					
					if(diff_type == DIFF_EQUAL) {
						patch.length2 += diff_text.length;
						start2 += diff_text.length;
					} else {
						empty = NO;
					}
					
					[patch.diffs addObject:[DMDiff diffWithOperation:diff_type andText:diff_text]];
					
					if(diff_text == ((DMDiff *)(bigpatch.diffs)[0]).text) {
						[bigpatch.diffs removeObjectAtIndex:0];
					} else {
						DMDiff *firstDiff = (bigpatch.diffs)[0];
						firstDiff.text = [firstDiff.text substringFromIndex:diff_text.length];
					}
				}
			}
			// Compute the head context for the next patch.
			precontext = diff_text2(patch.diffs);
			precontext = [precontext substringFromIndex:MAX_OF_CONST_AND_DIFF(0, precontext.length, properties.patchMargin)];
			
			// Append the end context for this patch.
			NSString *postcontext = nil;
			NSString *text1 = diff_text1(bigpatch.diffs);
			
			if(text1.length > properties.patchMargin) {
				postcontext = [text1 substringToIndex:properties.patchMargin];
			} else {
				postcontext = text1;
			}
			
			if(postcontext.length != 0) {
				patch.length1 += postcontext.length;
				patch.length2 += postcontext.length;
				
				if(patch.diffs.count != 0 && ((DMDiff *)(patch.diffs)[(patch.diffs.count - 1)]).operation == DIFF_EQUAL) {
					DMDiff *lastDiff = [patch.diffs lastObject];
					lastDiff.text = [lastDiff.text stringByAppendingString:postcontext];
				} else {
					[patch.diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:postcontext]];
				}
			}
			
			if(!empty) {
				diff_spliceTwoArrays(patches, ++x, 0, [NSMutableArray arrayWithObject:patch]);
			}
		}
	}
}



/**
 * Take a list of patches and return a textual representation.
 * @param patches NSMutableArray of Patch objects.
 * @return Text representation of patches.
 */

NSString *patch_patchesToText(NSArray *patches)
{
	NSMutableString *text = [NSMutableString string];
	
	for(DMPatch *patch in patches) {
		[text appendString:[patch patchText]];
	}
	
	return text;
}



/**
 * Parse a textual representation of patches and return a NSMutableArray of DMPatch objects.
 * @param textline Text representation of patches.
 * @param error NSError if invalid input.
 * @return NSMutableArray of Patch objects.
 */

NSArray *patch_parsePatchesFromText(NSString *textline, NSError **error)
{
	NSMutableArray *patches = [NSMutableArray array];
	
	if(textline.length == 0) {
		return patches;
	}
	
	NSArray *text = [textline componentsSeparatedByString:@"\n"];
	NSUInteger textPointer = 0;
	DMPatch *patch = nil;
	
	// NSString *patchHeader = @"^@@ -(\\d+),?(\\d*) \\+(\\d+),?(\\d*) @@$";
	NSString *patchHeaderStart = @"@@ -";
	NSString *patchHeaderMid = @"+";
	NSString *patchHeaderEnd = @"@@";
	NSString *optionalValueDelimiter = @",";
	BOOL scanSuccess, hasOptional;
	NSInteger scannedValue, optionalValue;
	NSDictionary *errorDetail = nil;
	NSString *textAtTextPointer = nil;
	
	unichar sign;
	NSString *line = nil;
	
	
	while(textPointer < text.count) {
		NSString *thisLine = text[textPointer];
		NSScanner *theScanner = [NSScanner scannerWithString:thisLine];
		patch = [DMPatch new];
		
		scanSuccess = ([theScanner scanString:patchHeaderStart intoString:NULL] && [theScanner scanInteger:&scannedValue]);
		
		if(scanSuccess) {
			patch.start1 = scannedValue;
			hasOptional = [theScanner scanString:optionalValueDelimiter intoString:NULL];
			
			if(hasOptional) {
				// First set has an optional value.
				scanSuccess = [theScanner scanInteger:&optionalValue];
				
				if(scanSuccess) {
					if(optionalValue == 0) {
						patch.length1 = 0;
					} else {
						patch.start1--;
						patch.length1 = optionalValue;
					}
				}
			} else {
				patch.start1--;
				patch.length1 = 1;
			}
			
			if(scanSuccess) {
				scanSuccess = ([theScanner scanString:patchHeaderMid intoString:NULL] && [theScanner scanInteger:&scannedValue]);
				
				if(scanSuccess) {
					patch.start2 = scannedValue;
					hasOptional = [theScanner scanString:optionalValueDelimiter intoString:NULL];
					
					if(hasOptional) {
						// Second set has an optional value.
						scanSuccess = [theScanner scanInteger:&optionalValue];
						
						if(scanSuccess) {
							if(optionalValue == 0) {
								patch.length2 = 0;
							} else {
								patch.start2--;
								patch.length2 = optionalValue;
							}
						}
					} else {
						patch.start2--;
						patch.length2 = 1;
					}
					
					if(scanSuccess) {
						scanSuccess = ([theScanner scanString:patchHeaderEnd intoString:NULL] && [theScanner isAtEnd] == YES);
					}
				}
			}
		}
		
		if(!scanSuccess) {
			if(error != NULL) {
				errorDetail = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"Invalid patch string: %@", @"Error"), text[textPointer]]};
				*error = [NSError errorWithDomain:@"DiffMatchPatchErrorDomain" code:104 userInfo:errorDetail];
			}
			
			return nil;
		}
		
		[patches addObject:patch];
		
		textPointer++;
		
		while(textPointer < text.count) {
			textAtTextPointer = text[textPointer];
			
			if(textAtTextPointer.length > 0) {
				sign = [textAtTextPointer characterAtIndex:0];
			} else {
				// Blank line?  Whatever.
				textPointer++;
				continue;
			}
			
			line = [[textAtTextPointer substringFromIndex:1] decodedURIString];
			
			if(sign == '-') {
				// Deletion.
				[patch.diffs addObject:[DMDiff diffWithOperation:DIFF_DELETE andText:line]];
			} else if(sign == '+') {
				// Insertion.
				[patch.diffs addObject:[DMDiff diffWithOperation:DIFF_INSERT andText:line]];
			} else if(sign == ' ') {
				// Minor equality.
				[patch.diffs addObject:[DMDiff diffWithOperation:DIFF_EQUAL andText:line]];
			} else if(sign == '@') {
				// Start of next patch.
				break;
			} else {
				// WTF?
				if(error != NULL) {
					errorDetail = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"Invalid patch mode '%C' in: %@", @"Error"), sign, line]};
					*error = [NSError errorWithDomain:@"DiffMatchPatchErrorDomain" code:104 userInfo:errorDetail];
				}
				
				return nil;
			}
			
			textPointer++;
		}
	}
	return patches;
}


#pragma mark -


void diff_spliceTwoArrays(NSMutableArray **input, NSUInteger start, NSUInteger count, NSArray *objects)
{
	// A JavaScript-style diff_splice function
	if(input == NULL)
		return;
	
	NSRange deletionRange = NSMakeRange(start, count);
	
	if(objects == nil) {
		[*input removeObjectsInRange:deletionRange];
	} else {
		[*input replaceObjectsInRange:deletionRange withObjectsFromArray:objects];
	}
}

