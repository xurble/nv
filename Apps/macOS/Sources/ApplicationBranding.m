#import "ApplicationBranding.h"

static NSString *NVTitleByReplacingApplicationName(NSString *title, NSString *previousName, NSString *applicationName)
{
    if (![title length] || ![previousName length] || ![applicationName length])
        return title;

    return [title stringByReplacingOccurrencesOfString:previousName withString:applicationName];
}

void NVApplyApplicationNameToMenu(NSMenu *menu, NSString *previousName, NSString *applicationName)
{
    if (!menu || ![previousName length] || ![applicationName length])
        return;

    [menu setTitle:NVTitleByReplacingApplicationName([menu title], previousName, applicationName)];

    for (NSMenuItem *item in [menu itemArray]) {
        [item setTitle:NVTitleByReplacingApplicationName([item title], previousName, applicationName)];
        if ([item hasSubmenu])
            NVApplyApplicationNameToMenu([item submenu], previousName, applicationName);
    }
}

BOOL NVRetargetStandardAboutMenuItem(NSMenu *menu, id target, SEL action)
{
    if (!menu || !target || !action)
        return NO;

    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == @selector(orderFrontStandardAboutPanel:)) {
            [item setTarget:target];
            [item setAction:action];
            return YES;
        }

        if ([item hasSubmenu] && NVRetargetStandardAboutMenuItem([item submenu], target, action))
            return YES;
    }

    return NO;
}

NSImage *NVApplicationIcon(void)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *iconName = [bundle objectForInfoDictionaryKey:@"CFBundleIconFile"];
    if (![iconName length])
        iconName = [bundle objectForInfoDictionaryKey:@"CFBundleIconName"];

    if ([iconName length]) {
        NSString *extension = [iconName pathExtension];
        NSString *resourceName = [extension length] ? [iconName stringByDeletingPathExtension] : iconName;
        NSURL *iconURL = [bundle URLForResource:resourceName
                                  withExtension:[extension length] ? extension : @"icns"];
        if (iconURL) {
            NSImage *icon = [[[NSImage alloc] initWithContentsOfURL:iconURL] autorelease];
            if (icon)
                return icon;
        }
    }

    return [NSApp applicationIconImage];
}

void NVApplyApplicationIconToViewHierarchy(NSView *view, NSImage *applicationIcon)
{
    if (!view || !applicationIcon)
        return;

    if ([view isKindOfClass:[NSImageView class]]) {
        NSImageView *imageView = (NSImageView *)view;
        NSImage *currentImage = [imageView image];
        if ([[currentImage name] isEqualToString:@"NSApplicationIcon"] ||
            currentImage == [NSImage imageNamed:@"NSApplicationIcon"])
            [imageView setImage:applicationIcon];
    }

    for (NSView *subview in [view subviews])
        NVApplyApplicationIconToViewHierarchy(subview, applicationIcon);
}
