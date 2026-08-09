#import <Foundation/Foundation.h>

#import "LegacyNotePolicies.h"

static NSUInteger failureCount = 0;

static void AssertEqualObjects(id actual, id expected, NSString *message)
{
    if (![actual isEqual:expected]) {
        NSLog(@"FAIL: %@ (expected %@, got %@)", message, expected, actual);
        failureCount++;
    }
}

static void AssertEqualRanges(NSRange actual, NSRange expected, NSString *message)
{
    if (!NSEqualRanges(actual, expected)) {
        NSLog(@"FAIL: %@ (expected %@, got %@)", message,
              NSStringFromRange(expected), NSStringFromRange(actual));
        failureCount++;
    }
}

static void AssertTrue(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        failureCount++;
    }
}

int main(void)
{
    @autoreleasepool {
        AssertEqualObjects(
            NVLegacyUniqueFilename(@"Plans: 2026", @"txt", @[]),
            @"Plans- 2026.txt",
            @"colons remain mapped to hyphens"
        );
        AssertEqualObjects(
            NVLegacyUniqueFilename(@".private", @"txt", @[]),
            @"_private.txt",
            @"a leading period remains reserved"
        );
        AssertEqualObjects(
            NVLegacyUniqueFilename(@"Meeting", @"txt", @[@"meeting.txt", @"Meeting.1.txt"]),
            @"Meeting.2.txt",
            @"collisions remain case-insensitive and monotonically numbered"
        );

        NSString *longTitle = [@"x" stringByPaddingToLength:300 withString:@"x" startingAtIndex:0];
        NSString *longFilename = NVLegacyUniqueFilename(longTitle, @"html", @[]);
        if ([longFilename length] != 251) {
            NSLog(@"FAIL: filename truncation changed (expected 251 UTF-16 units, got %lu)",
                  (unsigned long)[longFilename length]);
            failureCount++;
        }

        AssertEqualObjects(
            NVLegacyLabelCompatibleWords(@"project,urgent; personal\tarchive"),
            (@[@"project", @"urgent", @"personal", @"archive"]),
            @"legacy label separators remain compatible"
        );

        NSString *body = @"Alpha beta ALPHA";
        AssertEqualRanges(
            NVLegacyNextRangeForWords(body, @[@"missing", @"alpha"], NSCaseInsensitiveSearch,
                                      NSMakeRange(0, [body length])),
            NSMakeRange(0, 5),
            @"highlighting selects the first matching search term in term order"
        );
        AssertEqualRanges(
            NVLegacyNextRangeForWords(body, @[@"alpha"],
                                      NSCaseInsensitiveSearch | NSBackwardsSearch,
                                      NSMakeRange(0, [body length])),
            NSMakeRange(11, 5),
            @"backward highlighting selects the final match"
        );

        char title[] = "project alpha";
        char contents[] = "first alpha then beta";
        char labels[] = "work beta";
        char *titlePosition = title;
        char *contentsPosition = contents;
        char *labelsPosition = labels;
        AssertTrue(
            NVLegacyAdvanceUTF8Search(&titlePosition, &contentsPosition, &labelsPosition, "alpha"),
            @"search matching includes title and contents"
        );
        AssertTrue(titlePosition == title + 8 && contentsPosition == contents + 6 && labelsPosition == NULL,
                   @"search matching preserves the cached field positions");
        AssertTrue(
            NVLegacyAdvanceUTF8Search(&titlePosition, &contentsPosition, &labelsPosition, "beta"),
            @"a subsequent term narrows the surviving cached fields"
        );
        AssertTrue(titlePosition == NULL && contentsPosition == contents + 17,
                   @"search term ordering retains only fields containing every term in order");

        CFUUIDBytes lowerIdentifier = {0};
        CFUUIDBytes higherIdentifier = {0};
        higherIdentifier.byte15 = 1;
        AssertTrue(
            NVLegacyCompareNoteOrder(@"Alpha", 10, lowerIdentifier,
                                     @"beta", 1, higherIdentifier) < 0,
            @"title ordering remains case-insensitive"
        );
        AssertTrue(
            NVLegacyCompareNoteOrder(@"Alpha", 1, lowerIdentifier,
                                     @"alpha", 2, higherIdentifier) < 0,
            @"creation date remains the first title tie breaker"
        );
        AssertTrue(
            NVLegacyCompareNoteOrder(@"Alpha", 1, lowerIdentifier,
                                     @"alpha", 1, higherIdentifier) < 0,
            @"stable UUID bytes remain the final title tie breaker"
        );
    }

    if (failureCount > 0) {
        NSLog(@"%lu legacy note policy test(s) failed", (unsigned long)failureCount);
        return 1;
    }
    NSLog(@"All legacy note policy tests passed");
    return 0;
}
