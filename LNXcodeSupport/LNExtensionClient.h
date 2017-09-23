//
//  LNExtensionClient.h
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import "LNExtensionProtocol.h"
#import "LNFileHighlights.h"

@protocol LNConnectionDelegate <LNExtensionPlugin>
@end

@interface LNExtensionClient : NSObject <LNExtensionServiceDO, LNExtensionPlugin>

@property NSString *_Nonnull serviceName;
@property id<LNExtensionServiceDO> _Nonnull service;

@property LNConfig config;
@property NSMutableDictionary<NSString *, LNFileHighlights *> *_Nonnull highightsByFile;

- (instancetype _Nonnull)initServiceName:(NSString *_Nonnull)serviceName
                                delegate:(id<LNConnectionDelegate> _Nullable)delegate;
- (LNFileHighlights *_Nullable)objectForKeyedSubscript:(NSString *_Nonnull)key;
- (NSString *_Nonnull)serviceNameDO;
- (void)deregister;

@end
