#import <AppKit/AppKit.h>

#import "HeaderViewWIthMenu.h"

static NSUInteger failureCount = 0;

static void AssertTrue(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        failureCount++;
    }
}

static NSVisualEffectView *BackgroundEffectView(NSView *containerView)
{
    for (NSView *subview in [containerView subviews]) {
        if ([subview isKindOfClass:[NSVisualEffectView class]])
            return (NSVisualEffectView *)subview;
    }
    return nil;
}

int main(void)
{
    @autoreleasepool {
        NSView *containerView = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 24.0)] autorelease];
        HeaderViewWithMenu *headerView = [[[HeaderViewWithMenu alloc] init] autorelease];
        [headerView setFrame:[containerView bounds]];
        [containerView addSubview:headerView];

        NSVisualEffectView *effectView = BackgroundEffectView(containerView);
        AssertTrue(effectView != nil, @"Installing the table header should add a material background");
        AssertTrue([effectView material] == NSVisualEffectMaterialHeaderView,
                   @"The background should use AppKit's semantic table-header material");
        AssertTrue([effectView blendingMode] == NSVisualEffectBlendingModeWithinWindow,
                   @"The material should blur content moving beneath the header");
        AssertTrue([effectView state] == NSVisualEffectStateFollowsWindowActiveState,
                   @"The material should follow the containing window's active state");
        AssertTrue(![headerView isOpaque], @"The header must allow its material background to show through");
        AssertTrue([[containerView subviews] indexOfObjectIdenticalTo:effectView] <
                   [[containerView subviews] indexOfObjectIdenticalTo:headerView],
                   @"The material must sit behind the interactive header cells");

        [containerView setFrameSize:NSMakeSize(480.0, 30.0)];
        AssertTrue(NSEqualRects([effectView frame], [containerView bounds]),
                   @"The material should continue to fill the header container after resizing");

        [headerView removeFromSuperview];
        AssertTrue(BackgroundEffectView(containerView) == nil,
                   @"Removing the table header should also remove its material background");
    }

    if (failureCount > 0) {
        NSLog(@"%lu table-header test(s) failed", (unsigned long)failureCount);
        return 1;
    }

    NSLog(@"All table-header tests passed");
    return 0;
}
