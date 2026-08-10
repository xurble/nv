/*Copyright (c) 2026 Gareth Simpson and Zachary Schneirov. All rights reserved.
    This file is part of Spiral, a fork of Notational Velocity.

    Spiral is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Spiral is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */

#import <AppKit/AppKit.h>

#import "ApplicationBranding.h"

static NSUInteger failureCount = 0;

static void AssertEqualObjects(id actual, id expected, NSString *message)
{
    if (![actual isEqual:expected]) {
        NSLog(@"FAIL: %@ (expected '%@', got '%@')", message, expected, actual);
        failureCount++;
    }
}

static void AssertTrue(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        failureCount++;
    }
}

int main(void)
{
    @autoreleasepool {
        NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"Main"] autorelease];
        NSMenuItem *applicationItem = [[[NSMenuItem alloc] initWithTitle:@"Notational Velocity" action:NULL keyEquivalent:@""] autorelease];
        NSMenu *applicationMenu = [[[NSMenu alloc] initWithTitle:@"Notational Velocity"] autorelease];
        NSMenuItem *aboutItem = [[[NSMenuItem alloc] initWithTitle:@"About Notational Velocity" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""] autorelease];
        NSMenuItem *quitItem = [[[NSMenuItem alloc] initWithTitle:@"Quit Notational Velocity" action:NULL keyEquivalent:@""] autorelease];
        NSMenuItem *preferencesItem = [[[NSMenuItem alloc] initWithTitle:@"Preferences…" action:NULL keyEquivalent:@""] autorelease];

        [applicationMenu addItem:aboutItem];
        [applicationMenu addItem:preferencesItem];
        [applicationMenu addItem:quitItem];
        [applicationItem setSubmenu:applicationMenu];
        [mainMenu addItem:applicationItem];

        NVApplyApplicationNameToMenu(mainMenu, @"Notational Velocity", @"Spiral");

        AssertEqualObjects([applicationItem title], @"Spiral", @"The menu-bar application title should use the product name");
        AssertEqualObjects([applicationMenu title], @"Spiral", @"The application submenu should use the product name");
        AssertEqualObjects([aboutItem title], @"About Spiral", @"About should retain its localized prefix and update the product name");
        AssertEqualObjects([quitItem title], @"Quit Spiral", @"Quit should retain its localized prefix and update the product name");
        AssertEqualObjects([preferencesItem title], @"Preferences…", @"Unrelated menu titles should remain unchanged");

        NSObject *aboutTarget = [[[NSObject alloc] init] autorelease];
        AssertTrue(NVRetargetStandardAboutMenuItem(mainMenu, aboutTarget, @selector(showAboutPanel:)),
                   @"The standard About item should be found in a nested application menu");
        AssertTrue([aboutItem target] == aboutTarget, @"The About item should target the application controller");
        AssertTrue([aboutItem action] == @selector(showAboutPanel:), @"The About item should use the custom icon-aware action");
        AssertTrue([quitItem target] != aboutTarget, @"Unrelated menu items should keep their target");

        NSView *dialogContentView = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)] autorelease];
        NSView *nestedView = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)] autorelease];
        NSImageView *applicationIconView = [[[NSImageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 64.0, 64.0)] autorelease];
        NSImageView *unrelatedImageView = [[[NSImageView alloc] initWithFrame:NSMakeRect(70.0, 0.0, 16.0, 16.0)] autorelease];
        NSImage *archivedApplicationIcon = [NSImage imageNamed:@"NSApplicationIcon"];
        NSImage *unrelatedImage = [[[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)] autorelease];
        NSImage *replacementIcon = [[[NSImage alloc] initWithSize:NSMakeSize(64.0, 64.0)] autorelease];

        AssertTrue(archivedApplicationIcon != nil, @"AppKit should expose the legacy application-icon resource");
        [applicationIconView setImage:archivedApplicationIcon];
        [unrelatedImageView setImage:unrelatedImage];
        [nestedView addSubview:applicationIconView];
        [dialogContentView addSubview:nestedView];
        [dialogContentView addSubview:unrelatedImageView];

        NVApplyApplicationIconToViewHierarchy(dialogContentView, replacementIcon);

        AssertTrue([applicationIconView image] == replacementIcon,
                   @"Legacy dialog application-icon views should use the current bundle icon");
        AssertTrue([unrelatedImageView image] == unrelatedImage,
                   @"Unrelated dialog images should remain unchanged");
    }

    if (failureCount > 0) {
        NSLog(@"%lu application-branding test(s) failed", (unsigned long)failureCount);
        return 1;
    }

    NSLog(@"All application-branding tests passed");
    return 0;
}
