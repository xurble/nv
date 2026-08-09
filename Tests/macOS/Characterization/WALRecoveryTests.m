#import <Foundation/Foundation.h>
#include <unistd.h>

#import "WALController.h"

@interface NSString (WALTestUUID)
+ (NSString *)uuidStringWithBytes:(CFUUIDBytes)bytes;
@end

@implementation NSString (WALTestUUID)
+ (NSString *)uuidStringWithBytes:(CFUUIDBytes)bytes
{
    CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, bytes);
    return [(NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease];
}
@end

@interface WALFixtureNote : NSObject <SynchronizedNote> {
    CFUUIDBytes identifier;
    NSMutableDictionary *metadata;
    unsigned int sequenceNumber;
    NSString *body;
}
- (id)initWithIdentifier:(CFUUIDBytes)bytes sequenceNumber:(unsigned int)lsn body:(NSString *)text;
- (NSString *)body;
@end

@implementation WALFixtureNote
- (id)initWithIdentifier:(CFUUIDBytes)bytes sequenceNumber:(unsigned int)lsn body:(NSString *)text
{
    if ((self = [super init])) {
        identifier = bytes;
        sequenceNumber = lsn;
        body = [text copy];
        metadata = [[NSMutableDictionary alloc] initWithDictionary:
            @{@"LegacySync": @{@"remote-id": @"historic-42"}}];
    }
    return self;
}
- (id)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        NSUInteger length = 0;
        const uint8_t *bytes = [coder decodeBytesForKey:@"identifier" returnedLength:&length];
        if (bytes) memcpy(&identifier, bytes, MIN(length, sizeof(identifier)));
        sequenceNumber = [coder decodeInt32ForKey:@"sequenceNumber"];
        metadata = [[coder decodeObjectForKey:@"metadata"] mutableCopy];
        body = [[coder decodeObjectForKey:@"body"] copy];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeBytes:(const uint8_t *)&identifier length:sizeof(identifier) forKey:@"identifier"];
    [coder encodeInt32:sequenceNumber forKey:@"sequenceNumber"];
    [coder encodeObject:metadata forKey:@"metadata"];
    [coder encodeObject:body forKey:@"body"];
}
- (void)dealloc { [metadata release]; [body release]; [super dealloc]; }
- (CFUUIDBytes *)uniqueNoteIDBytes { return &identifier; }
- (NSDictionary *)syncServicesMD { return metadata; }
- (unsigned int)logSequenceNumber { return sequenceNumber; }
- (void)incrementLSN { sequenceNumber++; }
- (BOOL)youngerThanLogObject:(id<SynchronizedNote>)object
{
    return sequenceNumber < [object logSequenceNumber];
}
- (void)setSyncObjectAndKeyMD:(NSDictionary *)dictionary forService:(NSString *)serviceName
{
    [metadata setObject:dictionary forKey:serviceName];
}
- (void)removeAllSyncMDForService:(NSString *)serviceName { [metadata removeObjectForKey:serviceName]; }
- (NSString *)body { return body; }
@end

static NSUInteger failureCount = 0;

static void AssertTrue(BOOL condition, NSString *message)
{
    if (!condition) { NSLog(@"FAIL: %@", message); failureCount++; }
}

static NSData *SessionKey(void)
{
    unsigned char bytes[32];
    for (NSUInteger index = 0; index < sizeof(bytes); index++) bytes[index] = (unsigned char)index;
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

static CFUUIDBytes FixtureIdentifier(void)
{
    return (CFUUIDBytes){0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x46, 0x77,
                         0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff};
}

static NSString *MakeTemporaryDirectory(void)
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"SpiralWALTests-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:&error];
    AssertTrue(error == nil, @"the disposable WAL directory should be created");
    return path;
}

static void RemoveTemporaryDirectory(NSString *path)
{
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    AssertTrue(error == nil, @"the disposable WAL directory should be removed");
}

int main(void)
{
    @autoreleasepool {
        NSString *directory = MakeTemporaryDirectory();
        NSData *key = SessionKey();
        WALStorageController *writer = [[WALStorageController alloc]
            initWithParentFSRep:[directory fileSystemRepresentation] encryptionKey:key];
        WALFixtureNote *oldNote = [[[WALFixtureNote alloc] initWithIdentifier:FixtureIdentifier()
            sequenceNumber:1 body:@"before crash"] autorelease];
        WALFixtureNote *newNote = [[[WALFixtureNote alloc] initWithIdentifier:FixtureIdentifier()
            sequenceNumber:2 body:@"after crash"] autorelease];

        AssertTrue([writer writeNoteObject:oldNote], @"the first WAL record should be written");
        AssertTrue([writer writeNoteObject:newNote], @"the replacement WAL record should be written");
        AssertTrue([writer synchronize], @"the WAL should synchronize before simulated crash recovery");

        WALRecoveryController *reader = [[WALRecoveryController alloc]
            initWithParentFSRep:[directory fileSystemRepresentation] encryptionKey:key];
        NSDictionary *recovered = [reader recoveredNotes];
        WALFixtureNote *latest = [[recovered allValues] lastObject];
        AssertTrue([recovered count] == 1, @"replay should coalesce records with the same stable identifier");
        AssertTrue([[latest body] isEqual:@"after crash"], @"replay should retain the greatest log sequence number");
        AssertTrue([[[latest syncServicesMD] objectForKey:@"LegacySync"] isEqual:@{@"remote-id": @"historic-42"}],
                   @"WAL replay should preserve historical synchronization metadata");
        [reader release];
        [writer release];
        RemoveTemporaryDirectory(directory);

        directory = MakeTemporaryDirectory();
        writer = [[WALStorageController alloc]
            initWithParentFSRep:[directory fileSystemRepresentation] encryptionKey:key];
        AssertTrue([writer writeNoteObject:oldNote], @"a complete WAL record should be written");
        AssertTrue([writer writeNoteObject:newNote], @"a record to truncate should be written");
        AssertTrue([writer synchronize], @"the WAL should synchronize before truncation");
        NSString *journal = [directory stringByAppendingPathComponent:@"Interim Note-Changes"];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:journal error:NULL];
        off_t truncatedLength = [[attributes objectForKey:NSFileSize] longLongValue] - 8;
        AssertTrue(truncate([journal fileSystemRepresentation], truncatedLength) == 0,
                   @"the final WAL record should be truncated to simulate an interrupted write");

        reader = [[WALRecoveryController alloc]
            initWithParentFSRep:[directory fileSystemRepresentation] encryptionKey:key];
        recovered = [reader recoveredNotes];
        WALFixtureNote *survivor = [[recovered allValues] lastObject];
        AssertTrue([recovered count] == 1, @"a complete record before a torn write should remain recoverable");
        AssertTrue([[survivor body] isEqual:@"before crash"], @"the torn trailing record must not replace valid state");
        [reader release];

        NSMutableData *wrongKey = [NSMutableData dataWithData:key];
        ((unsigned char *)[wrongKey mutableBytes])[0] ^= 0xff;
        reader = [[WALRecoveryController alloc]
            initWithParentFSRep:[directory fileSystemRepresentation] encryptionKey:wrongKey];
        AssertTrue([[reader recoveredNotes] count] == 0, @"a WAL encrypted with another session key must not replay");
        [reader release];
        [writer release];
        RemoveTemporaryDirectory(directory);
    }

    if (failureCount > 0) {
        NSLog(@"%lu WAL recovery test(s) failed", (unsigned long)failureCount);
        return 1;
    }
    NSLog(@"All WAL recovery tests passed");
    return 0;
}
