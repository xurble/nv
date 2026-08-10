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

#import <Foundation/Foundation.h>

#import "NoteListSelection.h"

static NSUInteger failureCount = 0;

static void AssertIndexesEqual(NSIndexSet *actual, NSIndexSet *expected, NSString *message)
{
	if (![actual isEqualToIndexSet:expected]) {
		NSLog(@"FAIL: %@ (expected %@, got %@)", message, expected, actual);
		failureCount++;
	}
}

int main(void)
{
	@autoreleasepool {
		NSIndexSet *survivingSelection = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 2)];
		AssertIndexesEqual(NVRestoredNoteSelectionIndexes(survivingSelection, 2, 5),
						 survivingSelection,
						 @"A surviving selection should be preserved");

		AssertIndexesEqual(NVRestoredNoteSelectionIndexes([NSIndexSet indexSet], 2, 5),
						 [NSIndexSet indexSetWithIndex:2],
						 @"Deleting a middle row should select the row that replaces it");

		AssertIndexesEqual(NVRestoredNoteSelectionIndexes([NSIndexSet indexSet], 4, 4),
						 [NSIndexSet indexSetWithIndex:3],
						 @"Deleting the last row should select the preceding row");

		AssertIndexesEqual(NVRestoredNoteSelectionIndexes([NSIndexSet indexSet], 0, 0),
						 [NSIndexSet indexSet],
						 @"Deleting the only row should leave the list unselected");

		AssertIndexesEqual(NVRestoredNoteSelectionIndexes([NSIndexSet indexSet], NSNotFound, 5),
						 [NSIndexSet indexSet],
						 @"A list refresh should not invent a selection");
	}

	if (failureCount > 0) {
		NSLog(@"%lu note-list selection test(s) failed", (unsigned long)failureCount);
		return 1;
	}

	NSLog(@"All note-list selection tests passed");
	return 0;
}
