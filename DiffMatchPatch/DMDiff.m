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


#import "DMDiff.h"


@implementation DMDiff

/**
 * Constructor.  Initializes the diff with the provided values.
 * @param operation One of DIFF_INSERT, DIFF_DELETE or DIFF_EQUAL.
 * @param text The text being applied.
 */
+ (id)diffWithOperation:(DMDiffOperation)anOperation andText:(NSString *)aText
{
	return [[self alloc] initWithOperation:anOperation andText:aText];
}


- (id)initWithOperation:(DMDiffOperation)anOperation andText:(NSString *)aText
{
	self = [super init];
	
	if(self) {
		self.operation = anOperation;
		self.text = aText;
	}
	
	return self;
}


- (id)copyWithZone:(NSZone *)zone
{
	return [[[self class] allocWithZone:zone] initWithOperation:self.operation andText:self.text];
}


/**
 * Display a human-readable version of this Diff.
 * @return text version.
 */
- (NSString *)description
{
	NSString *prettyText = [self.text stringByReplacingOccurrencesOfString:@"\n" withString:@"\u00b6"];
	NSString *operationName = nil;
	
	switch(self.operation) {
		case DIFF_DELETE:
			operationName = @"DELETE";
			break;
			
		case DIFF_INSERT:
			operationName = @"INSERT";
			break;
			
		case DIFF_EQUAL:
			operationName = @"EQUAL";
			break;
			
		default:
			break;
	}
	
	return [NSString stringWithFormat:@"%@ (%@,\"%@\")", [super description], operationName, prettyText];
}


/**
 * Is this Diff equivalent to another Diff?
 * @param obj Another Diff to compare against.
 * @return YES or NO.
 */
- (BOOL)isEqual:(id)obj
{
	// If parameter is nil return NO.
	if(obj == nil)
		return NO;
	
	// If parameter cannot be cast to Diff return NO.
	if(![obj isKindOfClass:[DMDiff class]])
		return NO;
	
	// Return YES if the fields match.
	DMDiff *p = (DMDiff *)obj;
	return p.operation == self.operation && [p.text isEqualToString:self.text];
}

- (BOOL)isEqualToDiff:(DMDiff *)obj
{
	// If parameter is nil return NO.
	if(obj == nil)
		return NO;
	
	// Return YES if the fields match.
	return obj.operation == self.operation && [obj.text isEqualToString:self.text];
}

- (NSUInteger)hash
{
	return [_text hash] ^ (NSUInteger)_operation;
}

@end
