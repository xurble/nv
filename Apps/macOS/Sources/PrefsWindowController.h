/*
 * Objective-C entry point for the Swift settings window.
 *
 * Keeping this small facade preserves the long-standing AppController/NIB
 * connection while allowing the settings implementation itself to live in
 * Swift.
 */

#import <Cocoa/Cocoa.h>

@interface PrefsWindowController : NSObject {
    id modernSettingsController;
}

- (void)showWindow:(id)sender;
- (BOOL)getNewNotesRefFromOpenPanel:(FSRef *)notesDirectoryRef
                       returnedPath:(NSString **)path
            mergeExistingCollection:(BOOL *)mergeExistingCollection;

@end
