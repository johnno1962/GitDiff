//
//  LNExtensionClientDO.m
//  LNProvider
//
//  Created by John Holdsworth on 01/04/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import "LNExtensionClientDO.h"

@implementation LNExtensionClientDO

- (void)setup {
    self.service = (id)[NSConnection rootProxyForConnectionWithRegisteredName:self.serviceNameDO host:nil];
    [(id)self.service setProtocolForProxy:@protocol(LNExtensionServiceDO)];
    [self.service setPluginDO:self];
    [self.service getConfig];
}

- (void)requestHighlightsForFile:(NSString *)filepath {
    @try {
        if (!self.service)
            [self setup];
        [self.service requestHighlightsForFile:filepath];
    }
    @catch (NSException *e) {
        @try {
            [self setup];
            [self.service requestHighlightsForFile:filepath];
        }
        @catch (NSException *e) {
            NSLog(@"-[LNExtensionClientDO requestHighlightsForFile: %@]", e);
            for (LNFileHighlights *highlights in self.highightsByFile.allValues)
                [highlights invalidate];
        }
    }
}

@end
