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

#import "LegacyNotePolicies.h"

NSString *NVLegacyUniqueFilename(
    NSString *title,
    NSString *pathExtension,
    NSArray<NSString *> *existingFilenames
) {
    NSMutableString *sanitizedName = [[[title stringByReplacingOccurrencesOfString:@":" withString:@"-"] mutableCopy] autorelease];
    if ([sanitizedName length] > 0 && [sanitizedName characterAtIndex:0] == (unichar)'.') {
        [sanitizedName replaceCharactersInRange:NSMakeRange(0, 1) withString:@"_"];
    }

    NSString *uniqueFilename = [[sanitizedName copy] autorelease];
    NSInteger reservedCharacterCount = 3 + [pathExtension length] + 2;
    if ([uniqueFilename length] + reservedCharacterCount > 255) {
        uniqueFilename = [uniqueFilename substringToIndex:255 - reservedCharacterCount];
    }
    NSString *extensionlessBaseFilename = uniqueFilename;

    unsigned int iteration = 0;
    BOOL isUnique = NO;
    do {
        isUnique = YES;
        for (NSString *existingFilename in existingFilenames) {
            NSString *baseFilename = [pathExtension length] > 0
                ? [existingFilename stringByDeletingPathExtension]
                : existingFilename;
            if ([baseFilename caseInsensitiveCompare:uniqueFilename] == NSOrderedSame) {
                isUnique = NO;
                uniqueFilename = [pathExtension length] > 0
                    ? [uniqueFilename stringByDeletingPathExtension]
                    : extensionlessBaseFilename;
                uniqueFilename = [uniqueFilename stringByAppendingPathExtension:
                    [[NSNumber numberWithInt:++iteration] stringValue]];
                break;
            }
        }
    } while (!isUnique);

    return [pathExtension length] > 0
        ? [uniqueFilename stringByAppendingPathExtension:pathExtension]
        : uniqueFilename;
}

NSArray<NSString *> *NVLegacyLabelCompatibleWords(NSString *labels) {
    NSMutableCharacterSet *separators = [[NSCharacterSet whitespaceCharacterSet] mutableCopy];
    [separators formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@",;"]];
    NSArray *components = [labels componentsSeparatedByCharactersInSet:separators];
    [separators release];

    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:[components count]];
    for (NSString *component in components) {
        if ([component length] > 0) [titles addObject:component];
    }
    return titles;
}

NSRange NVLegacyNextRangeForWords(
    NSString *haystack,
    NSArray<NSString *> *words,
    NSStringCompareOptions options,
    NSRange searchRange
) {
    for (NSString *word in words) {
        if ([word length] > 0) {
            NSRange range = [haystack rangeOfString:word options:options range:searchRange];
            if (range.location != NSNotFound && range.length > 0) return range;
        }
    }
    return NSMakeRange(NSNotFound, 0);
}

BOOL NVLegacyAdvanceUTF8Search(
    char **titlePosition,
    char **contentsPosition,
    char **labelsPosition,
    const char *needle
) {
    if (*titlePosition) *titlePosition = strstr(*titlePosition, needle);
    if (*contentsPosition) *contentsPosition = strstr(*contentsPosition, needle);
    if (*labelsPosition) *labelsPosition = strstr(*labelsPosition, needle);
    return *titlePosition || *contentsPosition || *labelsPosition;
}

NSInteger NVLegacyCompareNoteOrder(
    NSString *firstTitle,
    CFAbsoluteTime firstCreatedDate,
    CFUUIDBytes firstIdentifier,
    NSString *secondTitle,
    CFAbsoluteTime secondCreatedDate,
    CFUUIDBytes secondIdentifier
) {
    CFComparisonResult titleResult = CFStringCompare(
        (CFStringRef)firstTitle,
        (CFStringRef)secondTitle,
        kCFCompareCaseInsensitive
    );
    if (titleResult != kCFCompareEqualTo) return (NSInteger)titleResult;

    NSInteger dateResult = firstCreatedDate - secondCreatedDate;
    if (dateResult != 0) return dateResult;
    return memcmp(&firstIdentifier, &secondIdentifier, sizeof(CFUUIDBytes));
}

NVLegacyCollectionMergeAction NVLegacyCollectionMergeActionForMatch(
    BOOL UUIDMatches,
    BOOL titleMatches,
    BOOL labelsMatch,
    BOOL contentsMatch
) {
    if (!UUIDMatches) return NVLegacyCollectionMergeAdd;
    if (titleMatches && labelsMatch && contentsMatch) return NVLegacyCollectionMergeSkipIdentical;
    return NVLegacyCollectionMergePreserveDivergent;
}

NSString *NVLegacyMergedCopyTitle(NSString *incomingTitle, NSArray<NSString *> *existingTitles) {
    NSString *baseTitle = [NSString stringWithFormat:NSLocalizedString(
        @"%@ (Merged Copy)",
        @"title used when two merged collections contain divergent versions of the same note"
    ), incomingTitle];
    NSString *candidate = baseTitle;
    NSUInteger suffix = 2;
    while (YES) {
        BOOL collides = NO;
        for (NSString *existingTitle in existingTitles) {
            if ([existingTitle caseInsensitiveCompare:candidate] == NSOrderedSame) {
                collides = YES;
                break;
            }
        }
        if (!collides) return candidate;
        candidate = [NSString stringWithFormat:@"%@ %lu", baseTitle, (unsigned long)suffix++];
    }
}
