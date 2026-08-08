/* NoteListSelection */

#import <Foundation/Foundation.h>

// Keep an existing surviving selection. If every selected note disappeared
// during a list update, select the row that took the first selected row's
// place, or the new last row when the old selection was at the end.
static inline NSIndexSet *NVRestoredNoteSelectionIndexes(NSIndexSet *survivingIndexes,
														 NSUInteger previousFirstIndex,
														 NSUInteger rowCount) {
	if ([survivingIndexes count] || previousFirstIndex == NSNotFound || rowCount == 0)
		return survivingIndexes;

	return [NSIndexSet indexSetWithIndex:MIN(previousFirstIndex, rowCount - 1)];
}
