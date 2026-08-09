#import <Foundation/Foundation.h>

#import "NSData_transformations.h"

static NSUInteger failureCount = 0;

static NSData *DataFromHexString(NSString *hexString)
{
    NSMutableData *data = [NSMutableData dataWithCapacity:[hexString length] / 2];
    unsigned int byte = 0;

    for (NSUInteger index = 0; index + 1 < [hexString length]; index += 2) {
        NSString *pair = [hexString substringWithRange:NSMakeRange(index, 2)];
        NSScanner *scanner = [NSScanner scannerWithString:pair];
        if (![scanner scanHexInt:&byte]) {
            return nil;
        }
        unsigned char value = (unsigned char)byte;
        [data appendBytes:&value length:1];
    }

    return data;
}

static void AssertEqualObjects(id actual, id expected, NSString *message)
{
    if (![actual isEqual:expected]) {
        NSLog(@"FAIL: %@ (expected %@, got %@)", message, expected, actual);
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
        NSData *key = DataFromHexString(@"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f");
        NSData *iv = DataFromHexString(@"101112131415161718191a1b1c1d1e1f");
        NSData *expectedCiphertext = DataFromHexString(@"c3108feb0a61f6bc6e7403b5480b42dab20775b7d66411527c7c9b1af6e3ee6b");
        NSMutableData *payload = [NSMutableData dataWithData:[@"Legacy note payload" dataUsingEncoding:NSUTF8StringEncoding]];

        AssertTrue([payload encryptAESDataWithKey:key iv:iv], @"AES-256-CBC encryption should succeed");
        AssertEqualObjects(payload, expectedCiphertext, @"AES-256-CBC output must remain byte-compatible with legacy databases");
        AssertTrue([payload decryptAESDataWithKey:key iv:iv], @"AES-256-CBC decryption should succeed");
        AssertEqualObjects(payload,
                           [@"Legacy note payload" dataUsingEncoding:NSUTF8StringEncoding],
                           @"AES-256-CBC should recover the original payload");

        NSData *identifier = DataFromHexString(@"00112233445566778899aabbccddeeff");
        NSString *encodedIdentifier = [identifier encodeBase64WithNewlines:NO];
        AssertEqualObjects(encodedIdentifier, @"ABEiM0RVZneImaq7zN3u/w==", @"Note identifiers must keep their Base64 representation");
        AssertEqualObjects([[@"abc" dataUsingEncoding:NSUTF8StringEncoding] encodeBase64],
                           @"YWJj\n",
                           @"Legacy line-wrapped Base64 should retain its terminating newline");
        NSData *digestInput = [@"legacy-volume-id" dataUsingEncoding:NSUTF8StringEncoding];
        AssertEqualObjects([digestInput MD5Digest],
                           DataFromHexString(@"dd1a02e757928398575ad54f573cb8f4"),
                           @"Legacy MD5 digests must remain byte-compatible");
    }

    if (failureCount > 0) {
        NSLog(@"%lu legacy-crypto compatibility test(s) failed", (unsigned long)failureCount);
        return 1;
    }

    NSLog(@"All legacy-crypto compatibility tests passed");
    return 0;
}
