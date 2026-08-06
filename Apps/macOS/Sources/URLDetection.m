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
