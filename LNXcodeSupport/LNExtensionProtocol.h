//
//  LNExtensionService.h
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#ifndef LNExtensionService_h
#define LNExtensionService_h

#import <Foundation/Foundation.h>

typedef NSDictionary<NSString *, NSString *> *_Nullable LNConfig;
typedef void (^_Nonnull LNConfigCallback)(LNConfig config);

#define LNPopoverColorKey @"LNPopoverColor"
#define LNApplyTitleKey   @"LNApplyTitle"
#define LNApplyPromptKey  @"LNApplyPrompt"
#define LNApplyConfirmKey @"LNApplyConfirm"

typedef void (^LNHighlightCallback)(NSData *_Nullable json, NSError *_Nullable error);

@protocol LNExtensionService <NSObject>

- (void)getConfig:(LNConfigCallback)callback;

// closures work for XPC but not Distributed Objects
- (void)requestHighlightsForFile:(NSString *_Nonnull)filepath
                        callback:(LNHighlightCallback _Nonnull)callback
NS_SWIFT_NAME(requestHighlights(forFile:callback:));

- (void)ping:(int)test callback:(void (^_Nonnull)(int test))callback;

@end

// DO communication back to Xcode plugin
@protocol LNExtensionPlugin <NSObject>

- (void)updateConfig:(LNConfig)config forService:(NSString *_Nonnull)serviceName;
- (void)updateHighlights:(NSData *_Nullable)json error:(NSError *_Nullable)error forFile:(NSString *_Nonnull)filepath;

@end

@protocol LNExtensionServiceDO <LNExtensionService>

- (void)setPluginDO:(id<LNExtensionPlugin> _Nonnull)pluginDO;
- (void)requestHighlightsForFile:(NSString *_Nonnull)filepath;
- (void)getConfig;

@end

#define XCODE_LINE_NUMBER_REGISTRATION @"com.johnholdsworth.LineNumberPlugin"

@protocol LNRegistration <NSObject>

- (oneway void)registerLineNumberService:(NSString *_Nonnull)serviceName;
- (oneway void)deregisterService:(NSString *_Nonnull)serviceName;
- (oneway void)ping;

@end

#endif /* LNExtensionService_h */
