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


/*
 * The data structure representing a diff is an array of Diff objects:
 * [
 *  Diff(Operation.DIFF_DELETE, "Hello"),
 *  Diff(Operation.DIFF_INSERT, "Goodbye"),
 *  Diff(Operation.DIFF_EQUAL, " world.")
 * ]
 *   which means: delete "Hello", add "Goodbye" and keep " world."
 */


typedef enum {
	DIFF_DELETE = 1,
	DIFF_INSERT = 2,
	DIFF_EQUAL = 3
} DMDiffOperation;


#import <Foundation/Foundation.h>

@interface DMDiff :NSObject <NSCopying> {
}

@property (nonatomic, assign) DMDiffOperation operation;
@property (nonatomic, copy) NSString *text;

+ (id)diffWithOperation:(DMDiffOperation)anOperation andText:(NSString *)aText;
- (id)initWithOperation:(DMDiffOperation)anOperation andText:(NSString *)aText;

@end
