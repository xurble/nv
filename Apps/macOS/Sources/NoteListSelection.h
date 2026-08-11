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
    along with Spiral.  If not, see <http://www.gnu.org/licenses/>. */

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
