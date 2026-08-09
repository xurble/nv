#import <AppKit/AppKit.h>

#import "BookmarksController.h"
#import "NoteObject.h"

@interface GlobalPrefs : NSObject
+ (instancetype)defaultPrefs;
@end

@implementation GlobalPrefs
+ (instancetype)defaultPrefs
{
    return nil;
}
@end

NSString *titleOfNote(NoteObject *note)
{
    (void)note;
    return @"";
}

@interface BookmarksController (BookmarkShortcutTests)
- (id)tableView:(NSTableView *)tableView
        objectValueForTableColumn:(NSTableColumn *)tableColumn
        row:(NSInteger)rowIndex;
@end

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
        BookmarksController *controller = [BookmarksController alloc];
        NSTableColumn *shortcutColumn = [[[NSTableColumn alloc] initWithIdentifier:@"shortcut"] autorelease];

        AssertEqualObjects([controller tableView:nil objectValueForTableColumn:shortcutColumn row:0],
                           @"⌘ 1", @"The first bookmark should display Command-1");
        AssertEqualObjects([controller tableView:nil objectValueForTableColumn:shortcutColumn row:8],
                           @"⌘ 9", @"The ninth bookmark should display Command-9");
        AssertEqualObjects([controller tableView:nil objectValueForTableColumn:shortcutColumn row:9],
                           @"⇧⌘ 1", @"The tenth bookmark should add Shift and restart at 1");
        AssertEqualObjects([controller tableView:nil objectValueForTableColumn:shortcutColumn row:17],
                           @"⇧⌘ 9", @"The eighteenth bookmark should display Shift-Command-9");
        AssertEqualObjects([controller tableView:nil objectValueForTableColumn:shortcutColumn row:18],
                           @"⌃⇧⌘ 1", @"The nineteenth bookmark should add Control and restart at 1");
        AssertEqualObjects([controller tableView:nil objectValueForTableColumn:shortcutColumn row:26],
                           @"⌃⇧⌘ 9", @"The final bookmark should display Control-Shift-Command-9");

        [controller release];
    }

    if (failureCount > 0) {
        NSLog(@"%lu bookmark-shortcut test(s) failed", (unsigned long)failureCount);
        return 1;
    }

    NSLog(@"All bookmark-shortcut tests passed");
    return 0;
}
