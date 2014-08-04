/*
 * NSString+EscapeHTMLCharacters
 * Copyright 2010 Harry Jordan.
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
 * Authored by @inquisitiveSoft (Harry Jordan)
 * 
 * Heavily inspired by http://google-toolbox-for-mac.googlecode.com/svn/trunk/Foundation/GTMNSString+HTML.m
 * in fact the mapOfHTMLEquivalentsForCharacters table is a directly copy
 */


@interface NSString (DMEscapeHTMLCharacters)

- (NSString *)stringByEscapingHTML;

@end
