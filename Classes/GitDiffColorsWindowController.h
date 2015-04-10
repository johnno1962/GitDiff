//
//  GitDiffColorsWindowController.h
//  GitDiff
//
//  Created by Allen Wu on 8/17/14.
//
//

#import <Cocoa/Cocoa.h>

// template from: https://github.com/fortinmike/XcodeBoost/blob/master/XcodeBoost/MFPreferencesWindowController.h

@interface GitDiffColorsWindowController : NSWindowController

@property (strong, readonly) NSColor *modifiedColor;
@property (strong, readonly) NSColor *addedColor;
@property (strong, readonly) NSColor *deletedColor;
@property (strong, readonly) NSColor *popoverColor;
@property (strong, readonly) NSColor *changedColor;
@property (weak) IBOutlet NSButton *shouldPopover;

- (instancetype)initWithPluginBundle:(NSBundle *)bundle;

@end
