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

NS_ASSUME_NONNULL_BEGIN

/// Produces the legacy per-note filename after sanitization, truncation, and
/// case-insensitive collision handling. `existingFilenames` must omit the note
/// currently being renamed.
FOUNDATION_EXPORT NSString *NVLegacyUniqueFilename(
    NSString *title,
    NSString *pathExtension,
    NSArray<NSString *> *existingFilenames
);

FOUNDATION_EXPORT NSArray<NSString *> *NVLegacyLabelCompatibleWords(NSString *labels);

FOUNDATION_EXPORT NSRange NVLegacyNextRangeForWords(
    NSString *haystack,
    NSArray<NSString *> *words,
    NSStringCompareOptions options,
    NSRange searchRange
);

/// Advances the legacy cached UTF-8 search positions for a title, body, and
/// label string. A nil field pointer remains nil after subsequent terms.
FOUNDATION_EXPORT BOOL NVLegacyAdvanceUTF8Search(
    char * _Nullable * _Nonnull titlePosition,
    char * _Nullable * _Nonnull contentsPosition,
    char * _Nullable * _Nonnull labelsPosition,
    const char *needle
);

/// Preserves the legacy title ordering and its creation-date/UUID tie breakers.
FOUNDATION_EXPORT NSInteger NVLegacyCompareNoteOrder(
    NSString *firstTitle,
    CFAbsoluteTime firstCreatedDate,
    CFUUIDBytes firstIdentifier,
    NSString *secondTitle,
    CFAbsoluteTime secondCreatedDate,
    CFUUIDBytes secondIdentifier
);

typedef NS_ENUM(NSInteger, NVLegacyCollectionMergeAction) {
    NVLegacyCollectionMergeAdd = 0,
    NVLegacyCollectionMergeSkipIdentical,
    NVLegacyCollectionMergePreserveDivergent
};

/// Characterizes the live collection merge. UUID identity is authoritative;
/// title, labels, and contents determine whether a matching UUID is identical
/// or must be preserved as a separate merged copy.
FOUNDATION_EXPORT NVLegacyCollectionMergeAction NVLegacyCollectionMergeActionForMatch(
    BOOL UUIDMatches,
    BOOL titleMatches,
    BOOL labelsMatch,
    BOOL contentsMatch
);

/// Returns a case-insensitively unique title for a divergent incoming note.
FOUNDATION_EXPORT NSString *NVLegacyMergedCopyTitle(
    NSString *incomingTitle,
    NSArray<NSString *> *existingTitles
);

NS_ASSUME_NONNULL_END
