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
