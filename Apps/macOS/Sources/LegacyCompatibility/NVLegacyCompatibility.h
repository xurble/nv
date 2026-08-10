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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// AppKit-era compatibility result. The implementation is intentionally
/// quarantined behind this header and may only operate on a disposable,
/// byte-verified copy of a selected Notational Velocity or nvAlt collection.
@interface NVLegacyCollectionPreparation : NSObject

@property(nonatomic, readonly) NSInteger storageFormat;
@property(nonatomic, readonly) NSUInteger noteCount;
@property(nonatomic, readonly) BOOL detectedSignificantFormatting;
@property(nonatomic, readonly) BOOL sourceWasEncrypted;
@property(nonatomic, readonly) BOOL recoveredWAL;
@property(nonatomic, readonly, copy) NSString *sourceApplication;
@property(nonatomic, readonly, copy, nullable) NSString *sourceVersion;
@property(nonatomic, readonly, copy) NSArray<NSDictionary<NSString *, id> *> *noteSnapshots;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSData *> *collectionMetadata;

@end

/// Permanent macOS adapter around the legacy archive, passphrase, encryption,
/// WAL, encoding, and clean-file export implementation. New shared code must
/// consume its exported values/files and must not import the legacy object graph.
@interface NVLegacyCollectionImporter : NSObject

+ (nullable NVLegacyCollectionPreparation *)prepareWorkingCopyAtURL:(NSURL *)workingCopyURL
                                                              error:(NSError **)error;

/// Noninteractive variant for a caller that has already obtained the legacy
/// passphrase. Passing nil retains the established Keychain/prompt behavior.
+ (nullable NVLegacyCollectionPreparation *)prepareWorkingCopyAtURL:(NSURL *)workingCopyURL
                                                      passphraseData:(nullable NSData *)passphraseData
                                                               error:(NSError **)error;

@end


NS_ASSUME_NONNULL_END
