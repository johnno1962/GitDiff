//
//  LNExtensionClient.m
//  LNProvider
//
//  Created by John Holdsworth on 31/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import "LNExtensionClient.h"

@interface LNExtensionClient ()

@property NSXPCConnection *connection;
@property NSConnection *connectionDO;
@property id<LNExtensionPlugin> pluginDO;
@property id<LNRegistration> registrationDO;
@property __weak id<LNConnectionDelegate> delegate;

@end

@implementation LNExtensionClient

- (instancetype)initServiceName:(NSString *)serviceName delegate:(id<LNConnectionDelegate>)delegate {
    if ((self = [super init])) {
        self.highightsByFile = [NSMutableDictionary new];
        self.serviceName = serviceName;
        self.delegate = delegate;
        [self setup];
    }
    return self;
}

- (LNFileHighlights *)objectForKeyedSubscript:(NSString *)key {
    @synchronized(self.highightsByFile) {
        return self.highightsByFile[key];
    }
}

- (NSString *)serviceNameDO {
    return [self.serviceName stringByAppendingString:@".DO"];
}

- (void)setup {
    self.connection = [[NSXPCConnection alloc] initWithServiceName:self.serviceName];
    self.connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(LNExtensionService)];
    self.service = self.connection.remoteObjectProxy;

    self.connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(LNExtensionPlugin)];
    self.connection.exportedObject = self;
    [self.connection resume];

    self.connectionDO = [NSConnection new];
    [self.connectionDO setRootObject:self];
    [self.connectionDO registerName:self.serviceNameDO];

    [self.service ping:1 callback:^(int test){
        NSLog(@"Connected to %@ -> %d", self.serviceName, test);
    }];

    [self regsiterWithXcode];
}

- (void)regsiterWithXcode {
    @try {
        [self.registrationDO ping];
    }
    @catch (NSException *e) {
        NSLog(@"Disconnected %@ %@", self.serviceName, e);
        self.registrationDO = nil;
    }

    if (!self.registrationDO) {
        self.registrationDO =
        (id)[NSConnection rootProxyForConnectionWithRegisteredName:XCODE_LINE_NUMBER_REGISTRATION host:nil];
        [(id)self.registrationDO setProtocolForProxy:@protocol(LNRegistration)];
        [(id)self.registrationDO registerLineNumberService:self.serviceName];
    }

    [self performSelector:@selector(regsiterWithXcode) withObject:nil afterDelay:5.];
}

- (void)getConfig:(LNConfigCallback)callback {
    NSLog(@"-[%@ getConfig: %p]", self, callback);
}

- (void)getConfig {
    [self.service getConfig:^(LNConfig config) {
        [self updateConfig:config forService:self.serviceName];
    }];
}

- (void)updateConfig:(LNConfig)config forService:(NSString *)serviceName {
    self.config = config;
    [self.pluginDO updateConfig:config forService:self.serviceName];
    [self.delegate updateConfig:config forService:self.serviceName];
}

- (void)_requestHighlightsForFile:(NSString *)filepath callback:(LNHighlightCallback)callback {
    [self.service requestHighlightsForFile:filepath callback:^(NSData *json, NSError *error) {
        [self updateHighlights:json error:error forFile:filepath];
        if (callback)
            callback(json, error);
    }];
}

- (void)requestHighlightsForFile:(NSString *)filepath callback:(LNHighlightCallback)callback {
    @try {
        [self _requestHighlightsForFile:filepath callback:callback];
    }
    @catch (NSException *e) {
        @try {
            [self setup];
            [self _requestHighlightsForFile:filepath callback:callback];
        }
        @catch (NSException *e) {
            NSLog(@"-[LNExtensionClient requestHighlightsForFile: %@", e);
        }
    }
}

- (void)requestHighlightsForFile:(NSString *)filepath {
    [self requestHighlightsForFile:filepath callback:^(NSData *json, NSError *error) {}];
}

- (void)updateHighlights:(NSData *)json error:(NSError *)error forFile:(NSString *)filepath {
    if (self.highightsByFile)
        @synchronized(self.highightsByFile) {
            self.highightsByFile[filepath] = [[LNFileHighlights alloc] initWithData:json service:self.serviceName];
        }
#if 0
    NSLog(@"%@: %@ %@ %@ %@ %@ %@",
          self.serviceName, filepath, self.pluginDO, error, self.highightsByFile,
          [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding], error);
#endif
    [self.pluginDO updateHighlights:json error:error forFile:filepath];
    [self.delegate updateHighlights:json error:error forFile:filepath];
}

- (void)ping:(int)test callback:(void (^)(int))callback {
    NSLog(@"-[%@ ping:callback:]", self);
}

- (void)deregister {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self.registrationDO deregisterService:self.serviceName];
}

@end
