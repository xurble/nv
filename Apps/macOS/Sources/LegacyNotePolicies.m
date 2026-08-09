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

    unsigned int iteration = 0;
    BOOL isUnique = NO;
    do {
        isUnique = YES;
        for (NSString *existingFilename in existingFilenames) {
            NSString *baseFilename = [existingFilename stringByDeletingPathExtension];
            if ([baseFilename caseInsensitiveCompare:uniqueFilename] == NSOrderedSame) {
                isUnique = NO;
                uniqueFilename = [uniqueFilename stringByDeletingPathExtension];
                uniqueFilename = [uniqueFilename stringByAppendingPathExtension:
                    [[NSNumber numberWithInt:++iteration] stringValue]];
                break;
            }
        }
    } while (!isUnique);

    return [uniqueFilename stringByAppendingPathExtension:pathExtension];
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
