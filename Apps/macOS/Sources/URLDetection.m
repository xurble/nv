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

#import "URLDetection.h"

static NSDataDetector *NVURLDetector(void)
{
    static NSDataDetector *detector = nil;
    static BOOL attemptedCreation = NO;

    if (!attemptedCreation) {
        @synchronized([NSDataDetector class]) {
            if (!attemptedCreation) {
                NSError *error = nil;
                detector = [[NSDataDetector alloc] initWithTypes:NSTextCheckingTypeLink error:&error];
                attemptedCreation = YES;
                if (!detector)
                    NSLog(@"Could not create URL detector: %@", error);
            }
        }
    }

    return detector;
}

void NVAddURLLinkAttributes(NSMutableAttributedString *attributedString, NSRange range)
{
    NSUInteger stringLength = [attributedString length];
    if (!range.length || range.location > stringLength || range.length > stringLength - range.location)
        return;

    NSDataDetector *detector = NVURLDetector();
    if (!detector)
        return;

    NSArray<NSTextCheckingResult *> *matches = [detector matchesInString:[attributedString string]
                                                                  options:0
                                                                    range:range];
    for (NSTextCheckingResult *match in matches) {
        NSURL *url = [match URL];
        if (!url || ([url isFileURL] && [[url absoluteString]
                                        rangeOfString:@"/.file/" options:NSLiteralSearch].location != NSNotFound))
            continue;

        [attributedString addAttribute:NSLinkAttributeName value:url range:[match range]];
    }
}
