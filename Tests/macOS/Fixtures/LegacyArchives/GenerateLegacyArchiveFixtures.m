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

#import <AppKit/AppKit.h>
#import "NSData_transformations.h"
#import "WALController.h"

@interface NoteObject : NSObject <NSCoding, SynchronizedNote> {
    CFUUIDBytes identifier;
    unsigned int sequenceNumber;
    NSString *title;
    NSString *labels;
    NSMutableAttributedString *content;
    NSString *filename;
    NSDictionary *metadata;
    CFAbsoluteTime createdAt;
    CFAbsoluteTime modifiedAt;
    NSStringEncoding encoding;
}
- (id)initWithUUID:(NSUUID *)uuid
             title:(NSString *)noteTitle
              text:(NSString *)text
            labels:(NSString *)noteLabels
          filename:(NSString *)noteFilename
          metadata:(NSDictionary *)syncMetadata
           created:(CFAbsoluteTime)created
          modified:(CFAbsoluteTime)modified
          encoding:(NSStringEncoding)noteEncoding
               lsn:(unsigned int)lsn
              bold:(BOOL)bold;
@end

@implementation NoteObject
- (id)initWithCoder:(NSCoder *)coder { (void)coder; return [self init]; }
- (id)initWithUUID:(NSUUID *)uuid
             title:(NSString *)noteTitle
              text:(NSString *)text
            labels:(NSString *)noteLabels
          filename:(NSString *)noteFilename
          metadata:(NSDictionary *)syncMetadata
           created:(CFAbsoluteTime)created
          modified:(CFAbsoluteTime)modified
          encoding:(NSStringEncoding)noteEncoding
               lsn:(unsigned int)lsn
              bold:(BOOL)bold {
    if ((self = [super init])) {
        [uuid getUUIDBytes:(unsigned char *)&identifier];
        title = [noteTitle copy];
        labels = [noteLabels copy];
        content = [[NSMutableAttributedString alloc] initWithString:text];
        if (bold && [content length] > 0) {
            [content addAttribute:NSFontAttributeName
                            value:[NSFont boldSystemFontOfSize:13]
                            range:NSMakeRange(0, MIN((NSUInteger)4, [content length]))];
        }
        filename = [noteFilename copy];
        metadata = [syncMetadata copy];
        createdAt = created;
        modifiedAt = modified;
        encoding = noteEncoding;
        sequenceNumber = lsn;
    }
    return self;
}
- (void)dealloc {
    [title release]; [labels release]; [content release]; [filename release]; [metadata release];
    [super dealloc];
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeDouble:modifiedAt forKey:@"modifiedDate"];
    [coder encodeDouble:createdAt forKey:@"createdDate"];
    [coder encodeInt32:0 forKey:@"selectionRangeLocation"];
    [coder encodeInt32:0 forKey:@"selectionRangeLength"];
    [coder encodeBool:[content.string canBeConvertedToEncoding:NSASCIIStringEncoding]
                 forKey:@"contentsWere7Bit"];
    [coder encodeInt32:sequenceNumber forKey:@"logSequenceNumber"];
    [coder encodeInt32:0 forKey:@"currentFormatID"];
    [coder encodeInt32:0 forKey:@"logicalSize"];
    [coder encodeInt64:0 forKey:@"fileModifiedDate"];
    [coder encodeInt32:(int32_t)encoding forKey:@"fileEncoding"];
    [coder encodeBytes:(const uint8_t *)&identifier length:sizeof(identifier) forKey:@"uniqueNoteIDBytes"];
    [coder encodeObject:metadata forKey:@"syncServicesMD"];
    [coder encodeObject:title forKey:@"titleString"];
    [coder encodeObject:labels forKey:@"labelString"];
    [coder encodeObject:content forKey:@"contentString"];
    [coder encodeObject:filename forKey:@"filename"];
}
- (CFUUIDBytes *)uniqueNoteIDBytes { return &identifier; }
- (NSDictionary *)syncServicesMD { return metadata; }
- (unsigned int)logSequenceNumber { return sequenceNumber; }
- (void)incrementLSN { sequenceNumber++; }
- (BOOL)youngerThanLogObject:(id<SynchronizedNote>)object { return sequenceNumber < [object logSequenceNumber]; }
- (void)setSyncObjectAndKeyMD:(NSDictionary *)dictionary forService:(NSString *)serviceName { (void)dictionary; (void)serviceName; }
- (void)removeAllSyncMDForService:(NSString *)serviceName { (void)serviceName; }
@end

@interface NotationPrefs : NSObject <NSCoding>
@property(nonatomic, assign) BOOL encrypted;
@property(nonatomic, assign) NSUInteger iterations;
@property(nonatomic, retain) NSData *masterSalt;
@property(nonatomic, retain) NSData *sessionSalt;
@property(nonatomic, retain) NSData *verifier;
@property(nonatomic, copy) NSString *keychainIdentifier;
@end

@implementation NotationPrefs
@synthesize encrypted, iterations, masterSalt, sessionSalt, verifier, keychainIdentifier;
- (id)initWithCoder:(NSCoder *)coder { (void)coder; return [self init]; }
- (void)dealloc {
    [masterSalt release]; [sessionSalt release]; [verifier release]; [keychainIdentifier release];
    [super dealloc];
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt32:4 forKey:@"epochIteration"];
    [coder encodeInt:0 forKey:@"notesStorageFormat"];
    [coder encodeBool:encrypted forKey:@"doesEncryption"];
    [coder encodeBool:NO forKey:@"storesPasswordInKeychain"];
    [coder encodeBool:NO forKey:@"secureTextEntry"];
    [coder encodeInt:(int)iterations forKey:@"hashIterationCount"];
    [coder encodeInt:256 forKey:@"keyLengthInBits"];
    [coder encodeBool:YES forKey:@"confirmFileDeletion"];
    [coder encodeBool:YES forKey:@"appendFileExtensionToNewNotes"];
    [coder encodeObject:[NSFont systemFontOfSize:13] forKey:@"baseBodyFont"];
    [coder encodeObject:[NSColor textColor] forKey:@"foregroundColor"];
    NSArray *extensions = @[
        [NSMutableArray array],
        [NSMutableArray arrayWithObjects:@"txt", @"text", @"utf8", @"taskpaper", @"md", @"markdown", nil],
        [NSMutableArray arrayWithObject:@"rtf"],
        [NSMutableArray arrayWithObjects:@"html", @"htm", nil]
    ];
    for (NSUInteger index = 0; index < 4; index++) {
        [coder encodeObject:[NSMutableArray array]
                     forKey:[NSString stringWithFormat:@"typeStrings.%lu", (unsigned long)index]];
        [coder encodeObject:[extensions objectAtIndex:index]
                     forKey:[NSString stringWithFormat:@"pathExtensions.%lu", (unsigned long)index]];
        [coder encodeInt:0 forKey:[NSString stringWithFormat:@"chosenExtIndices.%lu", (unsigned long)index]];
    }
    [coder encodeObject:@{} forKey:@"syncServiceAccounts"];
    [coder encodeObject:keychainIdentifier forKey:@"keychainDatabaseIdentifier"];
    [coder encodeObject:@[] forKey:@"seenDiskUUIDEntries"];
    [coder encodeObject:masterSalt forKey:@"masterSalt"];
    [coder encodeObject:sessionSalt forKey:@"dataSessionSalt"];
    [coder encodeObject:verifier forKey:@"verifierKey"];
}
@end

@interface FrozenNotation : NSObject <NSCoding>
@property(nonatomic, retain) NotationPrefs *prefs;
@property(nonatomic, retain) NSData *notesData;
@end

@implementation FrozenNotation
@synthesize prefs, notesData;
- (id)initWithCoder:(NSCoder *)coder { (void)coder; return [self init]; }
- (void)dealloc { [prefs release]; [notesData release]; [super dealloc]; }
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:prefs forKey:@"prefs"];
    [coder encodeObject:notesData forKey:@"notesData"];
    [coder encodeObject:[NSSet set] forKey:@"deletedNoteSet"];
}
@end

static NSData *ArchiveObject(id object, NSString *key)
{
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:data] autorelease];
    [archiver encodeObject:object forKey:key];
    [archiver finishEncoding];
    return data;
}

static NSData *FixedData(uint8_t seed, NSUInteger count)
{
    NSMutableData *data = [NSMutableData dataWithLength:count];
    uint8_t *bytes = [data mutableBytes];
    for (NSUInteger index = 0; index < count; index++) bytes[index] = seed + (uint8_t)index;
    return data;
}

static NotationPrefs *FixturePreferences(BOOL encrypted, NSUInteger iterations, NSString *passphrase)
{
    NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
    prefs.encrypted = encrypted;
    prefs.iterations = iterations;
    prefs.keychainIdentifier = encrypted ? @"sanitized-fixture-keychain-id" : nil;
    if (encrypted) {
        prefs.masterSalt = FixedData(0x10, 256);
        prefs.sessionSalt = FixedData(0x40, 256);
        NSData *passphraseData = [passphrase dataUsingEncoding:NSUTF8StringEncoding];
        NSData *masterKey = [passphraseData derivedKeyOfLength:32 salt:prefs.masterSalt iterations:(int)iterations];
        NSData *verifySalt = [NSData dataWithBytesNoCopy:VERIFY_SALT length:sizeof(VERIFY_SALT) freeWhenDone:NO];
        prefs.verifier = [masterKey derivedKeyOfLength:32 salt:verifySalt iterations:1];
    }
    return prefs;
}

static NSData *DatabaseData(NSArray *notes, NotationPrefs *prefs, NSString *passphrase)
{
    NSMutableData *notesData = [NSMutableData dataWithData:
        ArchiveObject([NSMutableArray arrayWithArray:notes], @"notes")];
    notesData = [notesData compressedData];
    if (prefs.encrypted) {
        NSData *masterKey = [[passphrase dataUsingEncoding:NSUTF8StringEncoding]
            derivedKeyOfLength:32 salt:prefs.masterSalt iterations:(int)prefs.iterations];
        NSData *sessionKey = [masterKey derivedKeyOfLength:32 salt:prefs.sessionSalt iterations:1];
        NSCAssert([notesData encryptAESDataWithKey:sessionKey
                                               iv:[prefs.sessionSalt subdataWithRange:NSMakeRange(0, 16)]],
                  @"fixture encryption failed");
    }
    FrozenNotation *frozen = [[[FrozenNotation alloc] init] autorelease];
    frozen.prefs = prefs;
    frozen.notesData = notesData;
    return ArchiveObject(frozen, NSKeyedArchiveRootObjectKey);
}

static NoteObject *FixtureNote(NSString *uuid, NSString *title, NSString *text, NSString *labels,
                               NSString *filename, NSDictionary *metadata, CFAbsoluteTime created,
                               CFAbsoluteTime modified, NSStringEncoding encoding, unsigned int lsn, BOOL bold)
{
    return [[[NoteObject alloc] initWithUUID:[[[NSUUID alloc] initWithUUIDString:uuid] autorelease]
                                      title:title text:text labels:labels filename:filename metadata:metadata
                                    created:created modified:modified encoding:encoding lsn:lsn bold:bold] autorelease];
}

static void WriteManifest(NSString *directory, NSString *application, NSString *version,
                          NSArray *expectedNotes, BOOL encrypted, BOOL recoveredWAL, NSUInteger iterations)
{
    NSDictionary *manifest = @{
        @"sourceApplication": application,
        @"sourceVersion": version,
        @"encrypted": @(encrypted),
        @"recoveredWAL": @(recoveredWAL),
        @"hashIterationCount": @(iterations),
        @"expectedNotes": expectedNotes
    };
    [manifest writeToFile:[directory stringByAppendingPathComponent:@"LegacyFixtureManifest.plist"] atomically:YES];
}

static NSString *CreateCase(NSString *root, NSString *name)
{
    NSString *directory = [root stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    return directory;
}

static void WriteDatabase(NSString *directory, NSArray *notes, NotationPrefs *prefs, NSString *passphrase)
{
    [DatabaseData(notes, prefs, passphrase) writeToFile:[directory stringByAppendingPathComponent:@"Notes & Settings"] atomically:YES];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) return 64;
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        NSString *passphrase = @"fixture-passphrase";
        NSDictionary *syncMetadata = @{ @"Simplenote": @{ @"key": @"historic-42", @"version": @7 } };
        NoteObject *plainOne = FixtureNote(@"11111111-2222-4333-8444-555555555555", @"Café / filename",
            @"Legacy MacRoman café body", @"archive legacy", @"Café - filename.txt", syncMetadata,
            100, 200, NSMacOSRomanStringEncoding, 1, NO);
        NoteObject *plainTwo = FixtureNote(@"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", @"Historical sync",
            @"Metadata survives migration", @"sync", @"Historical sync.txt", syncMetadata,
            300, 400, NSUTF8StringEncoding, 2, NO);

        NSString *directory = CreateCase(root, @"notational-velocity-plaintext");
        WriteDatabase(directory, @[plainOne, plainTwo], FixturePreferences(NO, 8000, passphrase), passphrase);
        WriteManifest(directory, @"Notational Velocity", @"2.0b5", @[
            @{ @"title": @"Café / filename", @"text": @"Legacy MacRoman café body", @"format": @"txt", @"tags": @[@"archive", @"legacy"] },
            @{ @"title": @"Historical sync", @"text": @"Metadata survives migration", @"format": @"txt", @"tags": @[@"sync"] }
        ], NO, NO, 8000);

        NoteObject *rich = FixtureNote(@"22222222-3333-4444-8555-666666666666", @"Rich nvAlt note",
            @"Bold survives around edits", @"nvAlt markdown", @"Rich nvAlt note.rtf", syncMetadata,
            500, 600, NSUTF8StringEncoding, 1, YES);
        directory = CreateCase(root, @"nvalt-rich");
        WriteDatabase(directory, @[rich], FixturePreferences(NO, 8000, passphrase), passphrase);
        WriteManifest(directory, @"nvAlt", @"2.2", @[
            @{ @"title": @"Rich nvAlt note", @"text": @"Bold survives around edits", @"format": @"rtf", @"tags": @[@"nvAlt", @"markdown"] }
        ], NO, NO, 8000);

        NoteObject *secret = FixtureNote(@"33333333-4444-4555-8666-777777777777", @"Encrypted note",
            @"Decrypted only in a verified copy", @"private", @"Encrypted note.txt", syncMetadata,
            700, 800, NSUTF8StringEncoding, 1, NO);
        directory = CreateCase(root, @"encrypted-default-kdf");
        WriteDatabase(directory, @[secret], FixturePreferences(YES, 8000, passphrase), passphrase);
        WriteManifest(directory, @"Notational Velocity", @"2.0b5 encrypted", @[
            @{ @"title": @"Encrypted note", @"text": @"Decrypted only in a verified copy", @"format": @"txt", @"tags": @[@"private"] }
        ], YES, NO, 8000);

        directory = CreateCase(root, @"encrypted-alternate-kdf");
        WriteDatabase(directory, @[secret], FixturePreferences(YES, 20000, passphrase), passphrase);
        WriteManifest(directory, @"nvAlt", @"2.2 alternate KDF", @[
            @{ @"title": @"Encrypted note", @"text": @"Decrypted only in a verified copy", @"format": @"txt", @"tags": @[@"private"] }
        ], YES, NO, 20000);

        NoteObject *before = FixtureNote(@"44444444-5555-4666-8777-888888888888", @"WAL note",
            @"before crash", @"journal", @"WAL note.txt", syncMetadata, 900, 901, NSUTF8StringEncoding, 1, NO);
        NoteObject *after = FixtureNote(@"44444444-5555-4666-8777-888888888888", @"WAL note",
            @"after crash", @"journal", @"WAL note.txt", syncMetadata, 900, 902, NSUTF8StringEncoding, 2, NO);
        NSData *plainWALKey = [NSData dataWithBytesNoCopy:"This is a 32 byte temporary key"
                                                    length:sizeof("This is a 32 byte temporary key")
                                              freeWhenDone:NO];
        directory = CreateCase(root, @"wal-intact");
        WriteDatabase(directory, @[before], FixturePreferences(NO, 8000, passphrase), passphrase);
        WALStorageController *writer = [[WALStorageController alloc]
            initWithParentFSRep:[directory fileSystemRepresentation] encryptionKey:plainWALKey];
        [writer writeNoteObject:after]; [writer synchronize]; [writer release];
        WriteManifest(directory, @"Notational Velocity", @"2.0b5 WAL", @[
            @{ @"title": @"WAL note", @"text": @"after crash", @"format": @"txt", @"tags": @[@"journal"] }
        ], NO, YES, 8000);

        directory = CreateCase(root, @"wal-interrupted");
        WriteDatabase(directory, @[before], FixturePreferences(NO, 8000, passphrase), passphrase);
        writer = [[WALStorageController alloc]
            initWithParentFSRep:[directory fileSystemRepresentation] encryptionKey:plainWALKey];
        [writer writeNoteObject:after];
        NoteObject *torn = FixtureNote(@"55555555-6666-4777-8888-999999999999", @"Torn note",
            @"must not appear", @"journal", @"Torn note.txt", @{}, 903, 904, NSUTF8StringEncoding, 1, NO);
        [writer writeNoteObject:torn]; [writer synchronize]; [writer release];
        NSString *journal = [directory stringByAppendingPathComponent:@"Interim Note-Changes"];
        off_t length = [[[[NSFileManager defaultManager] attributesOfItemAtPath:journal error:NULL]
            objectForKey:NSFileSize] longLongValue];
        truncate([journal fileSystemRepresentation], length - 8);
        WriteManifest(directory, @"nvAlt", @"2.2 interrupted WAL", @[
            @{ @"title": @"WAL note", @"text": @"after crash", @"format": @"txt", @"tags": @[@"journal"] }
        ], NO, YES, 8000);

        directory = CreateCase(root, @"damaged-archive");
        [@"not a keyed archive" writeToFile:[directory stringByAppendingPathComponent:@"Notes & Settings"]
                                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        WriteManifest(directory, @"Notational Velocity", @"damaged", @[], NO, NO, 8000);
    }
    return 0;
}
