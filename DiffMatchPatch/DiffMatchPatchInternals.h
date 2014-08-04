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
 *
 * This file contains declares the functions that DiffMatchPatch
 * uses internally. You might want to use these for more fine grained
 * control and particularly for testing.
 * 
 * As a convention, functions which take an object by reference
 * e.g. diff_cleanupSemantic(NSMutableArray **diffs) will change the
 * objects content in some way.
 * 
 */


// Structs which are used internally to define properties

struct DiffProperties {
	BOOL checkLines;			// Set to YES for a faster but less optimal diff
	NSTimeInterval deadline;
};

typedef struct DiffProperties DiffProperties;


struct MatchProperties {
	CGFloat matchThreshold;
	NSUInteger matchDistance;
	NSUInteger matchMaximumBits;	// The number of bits in an int
};

typedef struct MatchProperties MatchProperties;


struct PatchProperties {
	DiffProperties diffProperties;
	MatchProperties matchProperties;
	
	CGFloat patchMargin;
	CGFloat patchDeleteThreshold;
	NSUInteger diffEditingCost;
};

typedef struct PatchProperties PatchProperties;


typedef enum {
	DiffWordTokens = 1,
	DiffParagraphTokens = 2,
	DiffSentenceTokens = 3,
	DiffLineBreakDelimiteredTokens = 4
} DiffTokenMode;


// Define default properties
DiffProperties diff_defaultDiffProperties();
MatchProperties match_defaultMatchProperties();
PatchProperties patch_defaultPatchProperties();


// Internal functions for diffing
NSMutableArray *diff_diffsBetweenTextsWithProperties(NSString *oldText, NSString *newText, DiffProperties properties);
NSUInteger diff_translateLocationFromText1ToText2(NSArray *diffs, NSUInteger location);
NSMutableArray *diff_computeDiffsBetweenTexts(NSString *text1, NSString *text2, DiffProperties properties);
NSMutableArray *diff_computeDiffsUsingLineMode(NSString *text1, NSString *text2, DiffProperties properties);

NSArray *diff_linesToCharsForStrings(NSString *text1, NSString * text2);
NSArray *diff_tokensToCharsForStrings(NSString *text1, NSString *text2, DiffTokenMode mode);
void diff_charsToLines(NSArray **diffs, NSArray *lineArray);
void diff_charsToTokens(NSArray **diffs, NSArray *tokenArray);

NSMutableArray *diff_bisectOfStrings(NSString *text1, NSString *text2, DiffProperties properties);
NSMutableArray *diff_bisectSplitOfStrings(NSString *text1, NSString *text2, NSUInteger x, NSUInteger y, DiffProperties properties);

void diff_cleanupSemantic(NSMutableArray **diffs);
void diff_cleanupMerge(NSMutableArray **diffs);
void diff_cleanupSemanticLossless(NSMutableArray **diffs);
NSInteger diff_cleanupSemanticScoreOfStrings(NSString *text1, NSString *text2);


// Internal functions for matching
NSUInteger match_locationOfMatchInTextWithProperties(NSString *text, NSString *pattern, NSUInteger nearLocation, MatchProperties properties);
NSUInteger match_bitapOfTextAndPattern(NSString *text, NSString *pattern, NSUInteger nearLocation, MatchProperties properties);
NSMutableDictionary *match_alphabetFromPattern(NSString *pattern);
double match_bitapScoreForErrorCount(NSUInteger e, NSUInteger x, NSUInteger nearLocation, NSString *pattern, MatchProperties properties);


// Internal functions for patching
NSArray *patch_patchesFromTextsWithProperties(NSString *text1, NSString *text2, PatchProperties properties);
NSArray *patch_patchesFromDiffs(NSArray *diffs, PatchProperties properties);
NSArray *patch_patchesFromTextAndDiffs(NSString *text1, NSArray *diffs, PatchProperties properties);
NSString *patch_applyPatchesToTextWithProperties(NSArray *sourcePatches, NSString *text, NSIndexSet **indexesOfAppliedPatches, PatchProperties properties);

NSString *patch_addPaddingToPatches(NSMutableArray **patches, PatchProperties properties);
void patch_splitMax(NSMutableArray **patches, PatchProperties properties);
void patch_cleanupDiffsForEfficiency(NSMutableArray **diffs, PatchProperties properties);


// A convenience function to splice two arrays, likely of DMDiffs or DMPatches
void diff_spliceTwoArrays(NSMutableArray **input, NSUInteger start, NSUInteger count, NSArray *objects);


// MAX_OF_CONST_AND_DIFF determines the maximum of two expressions:
// The first is a constant (first parameter) while the second expression is
// the difference between the second and third parameter.  The way this is
// calculated prevents integer overflow in the result of the difference.

#if !defined(MAX_OF_CONST_AND_DIFF)
#define MAX_OF_CONST_AND_DIFF(A, B, C) ((B) <= (C) ? (A) : (B)-(C) + (A))
#endif
