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
 * 
 * If you need more fine grained options
 * have a look at DiffMatchPatchInternals.h
 * 
 */

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"

#import <Foundation/Foundation.h>

#pragma mark -
#pragma mark Generating Diffs

/**
 * Find the differences between two texts.
 * 
 * @param text1			Old NSString to be diffed.
 * @param text2			New NSString to be diffed.
 * @return Returns an NSArray of DMDiff objects.
 */

NSArray *diff_diffsBetweenTexts(NSString *text1, NSString *text2);


/**
 * Find the differences between two texts, with a few options
 * 
 * @param text1			Old NSString to be diffed.
 * @param text2			New NSString to be diffed.
 * @param highQuality	Set to FALSE for a faster but less optimal diff
 *						Setting this to high quality will be around 2 to 3 times slower
 *
 * @param timeLimit		The number in seconds (from the current time) to allow the function to process the diff.
 *						Enter 0.0 to allow the function an unlimited period.
 *
 * @return Returns an array of DMDiff objects.
 */

NSArray *diff_diffsBetweenTextsWithOptions(NSString *text1, NSString *text2, BOOL highQuality, NSTimeInterval timeLimit);


#pragma mark -
#pragma mark Formatting Diffs into a human readable output


/**
 * Calculate the first text from an array of DMDiff objects
 * 
 * @param diffs			The array of DMDiff objects.
 * @return Returns the first text
 */

NSString *diff_text1(NSArray *diffs);


/**
 * Calculate the second text from an array of DMDiff objects
 * 
 * @param diffs		The array of DMDiff objects.
 * @return Returns the first text
 */

NSString *diff_text2(NSArray *diffs);


/**
 * Create a HTML output from an array of DMDiff objects
 * 
 * @param diffs		The array of DMDiff objects.
 * @return A HTML string
 */

NSString *diff_prettyHTMLFromDiffs(NSArray *diffs);


/**
 * Create a delta string from an array of DMDiff objects
 * 
 * @param diffs		The array of DMDiff objects.
 * @return A delta string
 */

NSString *diff_deltaFromDiffs(NSArray *diffs);


/**
 * Given the original text1, and an encoded NSString which describes the
 * operations required to transform text1 into text2, compute the full diff.
 * 
 * @param text1 Source NSString for the diff.
 * @param delta Delta text.
 * @param error NSError if invalid input.
 * @return NSArray of DMDiff objects or nil if invalid.
 */

NSArray *diff_diffsFromOriginalTextAndDelta(NSString *text1, NSString *delta, NSError **error);


/**
 * Calculate the levenshtein distance for an array of DMDiff objects
 * See http://en.wikipedia.org/wiki/Levenshtein_distance#Definition for more info
 * 
 * @param diffs The array of DMDiff objects.
 * @return The levenshtein score for the diffs.
 */

NSUInteger diff_levenshtein(NSArray *diffs);


#pragma mark -
#pragma mark Searching text using fuzzy matching

/**
 * Locate the best instance of 'pattern' in 'text' near 'nearestLocation'.
 * Returns NSNotFound if no match found.
 * 
 * @param text					The text to search.
 * @param pattern				The pattern to search for.
 * @param approximateLocation	The location to search around.
 * @return Index of the best match or NSNotFound.
 */

NSUInteger match_locationOfMatchInText(NSString *text, NSString *pattern, NSUInteger approximateLocation);


/**
 * Locate the best instance of 'pattern' in 'text' near 'nearestLocation'.
 * Returns NSNotFound if no match found.
 * 
 * @param text					The text to search.
 * @param pattern				The pattern to search for.
 * @param approximateLocation	The location to search around.
 * @param matchThreshold		How closely the minimum matching text should match the search pattern. The default is 0.5f
 * @param matchDistance			How far away from the approximateLocation to search. The default is 1000 characters
 * @return Index of the best match or NSNotFound.
 */

NSUInteger match_locationOfMatchInTextWithOptions(NSString *text, NSString *pattern, NSUInteger approximateLocation, CGFloat matchThreshold, NSUInteger matchDistance);


#pragma mark -
#pragma mark Patching text

/**
 * Generate an array of DMPatches from two texts
 * 
 * @param text1		The first text
 * @param text2		The second text
 * @return An array of DMPatches
 */

NSArray *patch_patchesFromTexts(NSString *text1, NSString *text2);


/**
 * Take a list of patches and return a textual representation.
 * 
 * @param patches NSMutableArray of Patch objects.
 * @return Text representation of patches.
 */

NSString *patch_patchesToText(NSArray *patches);


/**
 * Parse a textual representation of patches and return a NSMutableArray of DMPatch objects.
 * 
 * @param textline Text representation of patches.
 * @param error NSError if invalid input.
 * @return NSArray of Patch objects.
 */

NSArray *patch_parsePatchesFromText(NSString *text, NSError **error);


/**
 * Merge a set of patches onto the text.  Return a patched text, as well
 * as an index set of for each value for which patches were applied.
 * 
 * @param patches					An NSArray of DMPatch objects
 * @param text						The old text
 * @param indexesOfAppliedPatches	An NSIndexSet of the patches, passed by reference (optional)
 *									Pass NULL if not required
 * @return The patched text
 */

NSString *patch_applyPatchesToText(NSArray *sourcePatches, NSString *text, NSIndexSet **indexesOfAppliedPatches);


