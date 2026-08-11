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
        AssertEqualObjects(
            NVLegacyUniqueFilename(@"Meeting", @"", @[]),
            @"Meeting",
            @"new notes may omit the file extension"
        );
        AssertEqualObjects(
            NVLegacyUniqueFilename(@"Meeting", @"", @[@"meeting", @"Meeting.1"]),
            @"Meeting.2",
            @"extensionless collisions remain case-insensitive and monotonically numbered"
        );
        AssertEqualObjects(
            NVLegacyUniqueFilename(@"Release 1.2", @"", @[]),
            @"Release 1.2",
            @"periods in extensionless note titles remain part of the title"
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

        AssertTrue(
            NVLegacyCollectionMergeActionForMatch(NO, NO, NO, NO) == NVLegacyCollectionMergeAdd,
            @"a distinct UUID adds the incoming note"
        );
        AssertTrue(
            NVLegacyCollectionMergeActionForMatch(YES, YES, YES, YES) == NVLegacyCollectionMergeSkipIdentical,
            @"an identical UUID match is omitted"
        );
        AssertTrue(
            NVLegacyCollectionMergeActionForMatch(YES, YES, YES, NO) == NVLegacyCollectionMergePreserveDivergent,
            @"a divergent UUID match is preserved"
        );
        AssertTrue(
            NVLegacyCollectionMergeActionForMatch(YES, NO, YES, YES) == NVLegacyCollectionMergePreserveDivergent,
            @"a renamed UUID match is preserved"
        );
        AssertEqualObjects(
            NVLegacyMergedCopyTitle(@"Plan", @[@"Plan"]),
            @"Plan (Merged Copy)",
            @"the first divergent version receives the established title"
        );
        AssertEqualObjects(
            NVLegacyMergedCopyTitle(
                @"Plan",
                @[@"Plan", @"plan (merged copy)", @"Plan (Merged Copy) 2"]
            ),
            @"Plan (Merged Copy) 3",
            @"merged-copy title collisions are case-insensitive and monotonic"
        );
    }

    if (failureCount > 0) {
        NSLog(@"%lu legacy note policy test(s) failed", (unsigned long)failureCount);
        return 1;
    }
    NSLog(@"All legacy note policy tests passed");
    return 0;
}
