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



CF_INLINE CFStringRef diff_CFStringCreateSubstring(CFStringRef text, CFIndex start_index, CFIndex length)
{
	CFStringRef substring = CFStringCreateWithSubstring(kCFAllocatorDefault, text, CFRangeMake(start_index, length));
	return substring;
}

CF_INLINE CFStringRef diff_CFStringCreateRightSubstring(CFStringRef text, CFIndex text_length, CFIndex new_length)
{
	return diff_CFStringCreateSubstring(text, text_length - new_length, new_length);
}

CF_INLINE CFStringRef diff_CFStringCreateLeftSubstring(CFStringRef text, CFIndex new_length)
{
	return diff_CFStringCreateSubstring(text, 0, new_length);
}

CF_INLINE CFStringRef diff_CFStringCreateSubstringWithStartIndex(CFStringRef text, CFIndex start_index)
{
	return diff_CFStringCreateSubstring(text, start_index, (CFStringGetLength(text) - start_index) );
}


CF_INLINE void diff_CFStringPrepareUniCharBuffer(CFStringRef string, const UniChar **string_chars, UniChar **string_buffer, CFRange string_range)
{
	*string_chars = CFStringGetCharactersPtr(string);
	
	if(*string_chars == NULL) {
		// Fallback in case CFStringGetCharactersPtr() didn’t work.
		*string_buffer = malloc(string_range.length * sizeof(UniChar) );
		CFStringGetCharacters(string, string_range, *string_buffer);
		*string_chars = *string_buffer;
	}
}

CF_INLINE CFIndex diff_CFArrayLastValueAsCFIndex(CFMutableArrayRef theArray)
{
	return (CFIndex)CFArrayGetValueAtIndex(theArray, CFArrayGetCount(theArray) - 1);
}

CF_INLINE void diff_CFArrayRemoveLastValue(CFMutableArrayRef theArray)
{
	CFArrayRemoveValueAtIndex(theArray, CFArrayGetCount(theArray) - 1);
}


CFIndex diff_commonPrefix(CFStringRef text1, CFStringRef text2);
CFIndex diff_commonSuffix(CFStringRef text1, CFStringRef text2);
CFIndex diff_commonOverlap(CFStringRef text1, CFStringRef text2);

CFArrayRef diff_halfMatchCreate(CFStringRef text1, CFStringRef text2);
CFArrayRef diff_halfMatchICreate(CFStringRef longtext, CFStringRef shorttext, CFIndex i);
CFStringRef diff_linesToCharsMungeCFStringCreate(CFStringRef text, CFMutableArrayRef lineArray, CFMutableDictionaryRef lineHash);
CFStringRef diff_tokensToCharsMungeCFStringCreate(CFStringRef text, CFMutableArrayRef tokenArray, CFMutableDictionaryRef tokenHash, CFOptionFlags tokenizerOptions);
CFStringRef diff_wordsToCharsMungeCFStringCreate(CFStringRef text, CFMutableArrayRef tokenArray, CFMutableDictionaryRef tokenHash);
CFStringRef diff_sentencesToCharsMungeCFStringCreate(CFStringRef text, CFMutableArrayRef tokenArray, CFMutableDictionaryRef tokenHash);
CFStringRef diff_paragraphsToCharsMungeCFStringCreate(CFStringRef text, CFMutableArrayRef tokenArray, CFMutableDictionaryRef tokenHash);
CFStringRef diff_lineBreakDelimiteredToCharsMungeCFStringCreate(CFStringRef text, CFMutableArrayRef tokenArray, CFMutableDictionaryRef tokenHash);
CFStringRef diff_rangesToCharsMungeCFStringCreate(CFStringRef text, CFMutableArrayRef substringArray, CFMutableDictionaryRef substringHash, CFRange *ranges, size_t ranges_count);
CFStringRef diff_charsToTokenCFStringCreate(CFStringRef charsString, CFArrayRef tokenArray);
CFIndex diff_cleanupSemanticScore(CFStringRef one, CFStringRef two);