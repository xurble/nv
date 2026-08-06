#import <AppKit/AppKit.h>

FOUNDATION_EXPORT void NVApplyApplicationNameToMenu(NSMenu *menu, NSString *previousName, NSString *applicationName);
FOUNDATION_EXPORT BOOL NVRetargetStandardAboutMenuItem(NSMenu *menu, id target, SEL action);
FOUNDATION_EXPORT NSImage *NVApplicationIcon(void);
FOUNDATION_EXPORT void NVApplyApplicationIconToViewHierarchy(NSView *view, NSImage *applicationIcon);
