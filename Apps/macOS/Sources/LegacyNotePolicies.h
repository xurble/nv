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

NS_ASSUME_NONNULL_END
