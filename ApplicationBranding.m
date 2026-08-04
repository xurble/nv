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
