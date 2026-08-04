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

int main(void)
{
    @autoreleasepool {
        NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"Main"] autorelease];
        NSMenuItem *applicationItem = [[[NSMenuItem alloc] initWithTitle:@"Notational Velocity" action:NULL keyEquivalent:@""] autorelease];
        NSMenu *applicationMenu = [[[NSMenu alloc] initWithTitle:@"Notational Velocity"] autorelease];
        NSMenuItem *aboutItem = [[[NSMenuItem alloc] initWithTitle:@"About Notational Velocity" action:NULL keyEquivalent:@""] autorelease];
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
    }

    if (failureCount > 0) {
        NSLog(@"%lu application-branding test(s) failed", (unsigned long)failureCount);
        return 1;
    }

    NSLog(@"All application-branding tests passed");
    return 0;
}
