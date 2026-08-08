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
