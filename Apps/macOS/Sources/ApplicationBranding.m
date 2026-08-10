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
