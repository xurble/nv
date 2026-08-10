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

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        AssertTrue(argc == 2, @"the golden encryption fixture path is required");
        NSData *fixtureData = argc == 2 ? [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]] : nil;
        NSDictionary *fixture = fixtureData ? [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:NULL] : nil;
        AssertTrue(fixture != nil, @"the golden encryption fixture should load");

        NSData *key = DataFromHexString([fixture objectForKey:@"keyHex"]);
        NSData *iv = DataFromHexString([fixture objectForKey:@"ivHex"]);
        NSData *expectedCiphertext = DataFromHexString([fixture objectForKey:@"ciphertextHex"]);
        NSData *plaintext = [[fixture objectForKey:@"plaintextUTF8"] dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableData *payload = [NSMutableData dataWithData:plaintext];

        AssertTrue([payload encryptAESDataWithKey:key iv:iv], @"AES-256-CBC encryption should succeed");
        AssertEqualObjects(payload, expectedCiphertext, @"AES-256-CBC output must remain byte-compatible with legacy databases");
        AssertTrue([payload decryptAESDataWithKey:key iv:iv], @"AES-256-CBC decryption should succeed");
        AssertEqualObjects(payload, plaintext,
                           @"AES-256-CBC should recover the original payload");

        NSData *passphrase = [[fixture objectForKey:@"passphraseUTF8"] dataUsingEncoding:NSUTF8StringEncoding];
        NSData *masterSalt = DataFromHexString([fixture objectForKey:@"masterSaltHex"]);
        NSData *expectedMasterKey = DataFromHexString([fixture objectForKey:@"expectedMasterKeyHex"]);
        NSData *masterKey = [passphrase derivedKeyOfLength:32
                                                     salt:masterSalt
                                               iterations:[[fixture objectForKey:@"hashIterations"] intValue]];
        AssertEqualObjects(masterKey, expectedMasterKey,
                           @"legacy database passphrase derivation must remain byte-compatible");

        NSData *dataSessionSalt = DataFromHexString([fixture objectForKey:@"dataSessionSaltHex"]);
        NSData *expectedDataSessionKey = DataFromHexString([fixture objectForKey:@"expectedDataSessionKeyHex"]);
        NSData *dataSessionKey = [masterKey derivedKeyOfLength:32 salt:dataSessionSalt iterations:1];
        AssertEqualObjects(dataSessionKey, expectedDataSessionKey,
                           @"legacy per-database session-key derivation must remain byte-compatible");

        NSMutableData *databasePayload = [NSMutableData dataWithData:
            DataFromHexString([fixture objectForKey:@"encryptedDatabasePayloadHex"])];
        AssertTrue([databasePayload decryptAESDataWithKey:dataSessionKey
                                                       iv:[dataSessionSalt subdataWithRange:NSMakeRange(0, 16)]],
                   @"an old encrypted database payload should decrypt");
        NSData *uncompressedDatabasePayload = [databasePayload uncompressedData];
        NSData *expectedDatabasePayload = [[fixture objectForKey:@"databasePayloadUTF8"]
            dataUsingEncoding:NSUTF8StringEncoding];
        AssertEqualObjects(uncompressedDatabasePayload, expectedDatabasePayload,
                           @"the decrypted database payload should retain the legacy compression envelope");

        NSData *wrongPassphrase = [@"wrong-passphrase" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *wrongMasterKey = [wrongPassphrase derivedKeyOfLength:32
                                                               salt:masterSalt
                                                         iterations:[[fixture objectForKey:@"hashIterations"] intValue]];
        NSData *wrongSessionKey = [wrongMasterKey derivedKeyOfLength:32 salt:dataSessionSalt iterations:1];
        NSMutableData *wrongPayload = [NSMutableData dataWithData:
            DataFromHexString([fixture objectForKey:@"encryptedDatabasePayloadHex"])];
        BOOL wrongPayloadDecrypted = [wrongPayload decryptAESDataWithKey:wrongSessionKey
                                                                       iv:[dataSessionSalt subdataWithRange:NSMakeRange(0, 16)]];
        NSData *wrongUncompressedPayload = wrongPayloadDecrypted && [wrongPayload isCompressedFormat]
            ? [wrongPayload uncompressedData]
            : nil;
        AssertTrue(![wrongUncompressedPayload isEqualToData:expectedDatabasePayload],
                   @"an old encrypted database payload should reject the wrong passphrase");

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
