/* Copyright (c) 2010, Zachary Schneirov. All rights reserved. */

#import "PrefsWindowController.h"
#import "Spiral-Swift.h"

@implementation PrefsWindowController

- (id)init {
    self = [super init];
    if (self) {
        modernSettingsController = [[ModernSettingsWindowController alloc] init];
    }
    return self;
}

- (void)dealloc {
    [modernSettingsController release];
    [super dealloc];
}

- (void)showWindow:(id)sender {
    [modernSettingsController showWindow:sender];
}

@end
