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

@end

/// Permanent macOS adapter around the legacy archive, passphrase, encryption,
/// WAL, encoding, and clean-file export implementation. New shared code must
/// consume its exported values/files and must not import the legacy object graph.
@interface NVLegacyCollectionImporter : NSObject

+ (nullable NVLegacyCollectionPreparation *)prepareWorkingCopyAtURL:(NSURL *)workingCopyURL
                                                              error:(NSError **)error;

@end


NS_ASSUME_NONNULL_END
