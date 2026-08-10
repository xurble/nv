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

#import <AppKit/AppKit.h>

#import "URLDetection.h"

static NSUInteger failureCount = 0;

static void AssertEqualObjects(id actual, id expected, NSString *message)
{
    if (actual != expected && ![actual isEqual:expected]) {
        NSLog(@"FAIL: %@ (expected '%@', got '%@')", message, expected, actual);
        failureCount++;
    }
}

static void AssertDetectedURL(NSString *sample, NSString *linkText, NSString *expectedURL)
{
    NSMutableAttributedString *attributedString = [[[NSMutableAttributedString alloc] initWithString:sample] autorelease];
    NVAddURLLinkAttributes(attributedString, NSMakeRange(0, [attributedString length]));

    NSRange linkRange = [sample rangeOfString:linkText];
    NSURL *URL = [attributedString attribute:NSLinkAttributeName atIndex:linkRange.location effectiveRange:NULL];
    AssertEqualObjects([URL absoluteString], expectedURL, [NSString stringWithFormat:@"'%@' should be detected", linkText]);

    if (NSMaxRange(linkRange) < [attributedString length]) {
        id trailingAttribute = [attributedString attribute:NSLinkAttributeName atIndex:NSMaxRange(linkRange) effectiveRange:NULL];
        AssertEqualObjects(trailingAttribute, nil, @"Punctuation or text following a URL should not be linked");
    }
}

static void AssertNoDetectedURL(NSString *sample, NSString *message)
{
    NSMutableAttributedString *attributedString = [[[NSMutableAttributedString alloc] initWithString:sample] autorelease];
    NVAddURLLinkAttributes(attributedString, NSMakeRange(0, [attributedString length]));
    id link = [attributedString attribute:NSLinkAttributeName atIndex:0 longestEffectiveRange:NULL inRange:NSMakeRange(0, [attributedString length])];
    AssertEqualObjects(link, nil, message);
}

int main(void)
{
    @autoreleasepool {
        AssertDetectedURL(@"Visit http://example.com/path?q=1#part now", @"http://example.com/path?q=1#part", @"http://example.com/path?q=1#part");
        AssertDetectedURL(@"Visit https://example.com.", @"https://example.com", @"https://example.com");
        AssertDetectedURL(@"See www.example.com/test afterwards", @"www.example.com/test", @"http://www.example.com/test");
        AssertDetectedURL(@"Email person@example.com when ready", @"person@example.com", @"mailto:person@example.com");
        AssertDetectedURL(@"Use mailto:person@example.com now", @"mailto:person@example.com", @"mailto:person@example.com");
        AssertDetectedURL(@"Fetch ftp://ftp.example.com/file next", @"ftp://ftp.example.com/file", @"ftp://ftp.example.com/file");
        AssertDetectedURL(@"Open file:///tmp/example.txt next", @"file:///tmp/example.txt", @"file:///tmp/example.txt");
        AssertDetectedURL(@"Bracket (https://example.com/path).", @"https://example.com/path", @"https://example.com/path");
        AssertNoDetectedURL(@"file:///tmp/.file/id=123", @"Private file-reference URLs should remain unlinked");

        NSString *rangeSample = @"https://outside.example and https://inside.example";
        NSRange insideRange = [rangeSample rangeOfString:@"https://inside.example"];
        NSMutableAttributedString *rangeString = [[[NSMutableAttributedString alloc] initWithString:rangeSample] autorelease];
        NVAddURLLinkAttributes(rangeString, insideRange);
        AssertEqualObjects([rangeString attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL], nil,
                           @"Detection should not modify text outside the requested edit range");
        NSURL *insideURL = [rangeString attribute:NSLinkAttributeName atIndex:insideRange.location effectiveRange:NULL];
        AssertEqualObjects([insideURL absoluteString], @"https://inside.example",
                           @"Detection should preserve offsets for a partial edit range");
    }

    if (failureCount > 0) {
        NSLog(@"%lu URL-detection test(s) failed", (unsigned long)failureCount);
        return 1;
    }

    NSLog(@"All URL-detection tests passed");
    return 0;
}
