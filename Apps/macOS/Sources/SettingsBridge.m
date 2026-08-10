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

#import "SettingsBridge.h"
#import "LegacyCompatibility/NVLegacyCompatibility.h"
#import "Spiral-Swift.h"

#import "AppController.h"
#import "ExternalEditorListController.h"
#import "FrozenNotation.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstrict-prototypes"
#import "GlobalPrefs.h"
#import "LinkingEditor.h"
#pragma clang diagnostic pop
#import "NSData_transformations.h"
#import "NotationPrefs.h"
#import "NotationPrefsViewController.h"
#import "NotationFileManager.h"
#import "NoteObject.h"
#import "PTHotKeys/PTKeyCombo.h"
#import "PTHotKeys/PTKeyComboPanel.h"

NSNotificationName const NVSettingsBridgeDidChangeNotification = @"NVSettingsBridgeDidChangeNotification";

static NSString * const NVLegacyCollectionImportErrorDomain = @"farm.poplar.spiral.legacy-import";

typedef NS_ENUM(NSInteger, NVLegacyCollectionImportError) {
    NVLegacyCollectionImportErrorUnreadableFolder = 1,
    NVLegacyCollectionImportErrorUnrecognizedFormat,
    NVLegacyCollectionImportErrorOpenFailed,
    NVLegacyCollectionImportErrorNoNotes,
    NVLegacyCollectionImportErrorConversionFailed,
    NVLegacyCollectionImportErrorWrongPassphrase,
    NVLegacyCollectionImportErrorDamagedArchive
};

@interface NVLegacyCollectionPreparation ()
@property(nonatomic, readwrite) NSInteger storageFormat;
@property(nonatomic, readwrite) NSUInteger noteCount;
@property(nonatomic, readwrite) BOOL detectedSignificantFormatting;
@property(nonatomic, readwrite) BOOL sourceWasEncrypted;
@property(nonatomic, readwrite) BOOL recoveredWAL;
@property(nonatomic, readwrite, copy) NSString *sourceApplication;
@property(nonatomic, readwrite, copy, nullable) NSString *sourceVersion;
@property(nonatomic, readwrite, copy) NSArray<NSDictionary<NSString *, id> *> *noteSnapshots;
@property(nonatomic, readwrite, copy) NSDictionary<NSString *, NSData *> *collectionMetadata;
@end

@implementation NVLegacyCollectionPreparation

- (void)dealloc {
    [_sourceApplication release];
    [_sourceVersion release];
    [_noteSnapshots release];
    [_collectionMetadata release];
    [super dealloc];
}

@end

@implementation NVLegacyCollectionImporter

+ (NSError *)errorWithCode:(NVLegacyCollectionImportError)code description:(NSString *)description {
    return [NSError errorWithDomain:NVLegacyCollectionImportErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (int)inferredSeparateFileFormatAtURL:(NSURL *)folderURL error:(NSError **)error {
    NSSet *plainExtensions = [NSSet setWithObjects:@"txt", @"text", @"utf8", @"taskpaper", @"md", @"markdown", nil];
    NSSet *rtfExtensions = [NSSet setWithObject:@"rtf"];
    NSSet *htmlExtensions = [NSSet setWithObjects:@"html", @"htm", nil];
    NSMutableSet *formats = [NSMutableSet set];

    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
        enumeratorAtURL:folderURL
        includingPropertiesForKeys:@[NSURLIsRegularFileKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles
        errorHandler:^BOOL(NSURL *url, NSError *enumerationError) {
            if (error && !*error)
                *error = enumerationError;
            return NO;
        }];

    for (NSURL *itemURL in enumerator) {
        NSNumber *isRegularFile = nil;
        if (![itemURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:error])
            return -1;
        if (![isRegularFile boolValue])
            continue;

        NSString *name = [itemURL lastPathComponent];
        if ([name isEqualToString:NotesDatabaseFileName] || [name isEqualToString:@"Interim Note-Changes"])
            continue;

        NSString *extension = [[itemURL pathExtension] lowercaseString];
        if ([plainExtensions containsObject:extension])
            [formats addObject:@(PlainTextFormat)];
        else if ([rtfExtensions containsObject:extension])
            [formats addObject:@(RTFTextFormat)];
        else if ([htmlExtensions containsObject:extension])
            [formats addObject:@(HTMLFormat)];
    }

    if (error && *error)
        return -1;
    if ([formats count] == 0) {
        if (error) {
            *error = [self errorWithCode:NVLegacyCollectionImportErrorUnrecognizedFormat
                             description:@"The selected folder does not contain recognizable Notational Velocity or nvAlt note files."];
        }
        return -1;
    }
    //This is the default for newly created notes, not a restriction on the
    //existing files in the collection.
    if ([formats containsObject:@(PlainTextFormat)])
        return PlainTextFormat;
    if ([formats containsObject:@(RTFTextFormat)])
        return RTFTextFormat;
    return HTMLFormat;
}

+ (NVLegacyCollectionPreparation *)prepareWorkingCopyAtURL:(NSURL *)workingCopyURL
                                                      error:(NSError **)error {
    return [self prepareWorkingCopyAtURL:workingCopyURL passphraseData:nil error:error];
}

+ (NSData *)propertyListData:(id)value {
    if (!value)
        return nil;
    return [NSPropertyListSerialization dataWithPropertyList:value
                                                      format:NSPropertyListBinaryFormat_v1_0
                                                     options:0
                                                       error:nil];
}

+ (NVLegacyCollectionPreparation *)prepareWorkingCopyAtURL:(NSURL *)workingCopyURL
                                            passphraseData:(NSData *)passphraseData
                                                     error:(NSError **)error {
    NSNumber *isDirectory = nil;
    if (![workingCopyURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:error] ||
        ![isDirectory boolValue]) {
        if (error && !*error)
            *error = [self errorWithCode:NVLegacyCollectionImportErrorUnreadableFolder
                             description:@"The selected notes location is not a readable folder."];
        return nil;
    }

    BOOL hadDatabase = [[NSFileManager defaultManager]
        fileExistsAtPath:[[workingCopyURL URLByAppendingPathComponent:NotesDatabaseFileName] path]];
    BOOL hadWAL = [[NSFileManager defaultManager]
        fileExistsAtPath:[[workingCopyURL URLByAppendingPathComponent:@"Interim Note-Changes"] path]];
    if (hadDatabase) {
        NSData *archiveData = [NSData dataWithContentsOfURL:
            [workingCopyURL URLByAppendingPathComponent:NotesDatabaseFileName]
                                               options:NSDataReadingMappedIfSafe
                                                 error:error];
        id archiveRoot = nil;
        if (archiveData) {
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                archiveRoot = [NSKeyedUnarchiver unarchiveObjectWithData:archiveData];
#pragma clang diagnostic pop
            } @catch (NSException *exception) {
                (void)exception;
            }
        }
        if (![archiveRoot isKindOfClass:[FrozenNotation class]]) {
            if (error) {
                *error = [self errorWithCode:NVLegacyCollectionImportErrorDamagedArchive
                                 description:@"The legacy notes archive is damaged or unreadable."];
            }
            return nil;
        }
    }
    int inferredFileFormat = SingleDatabaseFormat;
    if (!hadDatabase) {
        inferredFileFormat = [self inferredSeparateFileFormatAtURL:workingCopyURL error:error];
        if (inferredFileFormat < 0)
            return nil;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    FSRef workingCopyRef;
    BOOL resolvedWorkingCopy = CFURLGetFSRef((CFURLRef)workingCopyURL, &workingCopyRef);
#pragma clang diagnostic pop
    if (!resolvedWorkingCopy) {
        if (error)
            *error = [self errorWithCode:NVLegacyCollectionImportErrorUnreadableFolder
                             description:@"The selected notes folder could not be opened."];
        return nil;
    }

    OSStatus openError = noErr;
    NotationController *controller = [[NotationController alloc]
        initLegacyMigrationWithDirectoryRef:&workingCopyRef
        error:&openError
        passphraseData:passphraseData];
    if (!controller) {
        if (error) {
            NVLegacyCollectionImportError code = NVLegacyCollectionImportErrorOpenFailed;
            NSString *description = nil;
            if (openError == kPassCanceledErr) {
                description = @"The encrypted notes import was cancelled.";
            } else if (openError == kNoAuthErr) {
                code = NVLegacyCollectionImportErrorWrongPassphrase;
                description = @"The passphrase did not unlock the legacy notes collection.";
            } else if (openError == kCoderErr || openError == kCompressionErr) {
                code = NVLegacyCollectionImportErrorDamagedArchive;
                description = @"The legacy notes archive is damaged or unreadable.";
            } else {
                description = [NSString stringWithFormat:@"The legacy notes collection could not be opened (%d).", (int)openError];
            }
            *error = [self errorWithCode:code description:description];
        }
        return nil;
    }

    NotationPrefs *prefs = [controller notationPrefs];
    if (!hadDatabase && [prefs notesStorageFormat] != inferredFileFormat)
        [prefs setNotesStorageFormat:inferredFileFormat];

    NSArray *contents = [controller noteContentsForMigration];
    if ([contents count] == 0) {
        [controller closeAllResources];
        [controller release];
        if (error)
            *error = [self errorWithCode:NVLegacyCollectionImportErrorNoNotes
                             description:@"No notes were found in the selected folder."];
        return nil;
    }

    int sourceFormat = hadDatabase ? [controller currentNoteStorageFormat] : inferredFileFormat;
    int targetFormat = sourceFormat;
    BOOL significantFormatting = NO;
    if (sourceFormat == SingleDatabaseFormat) {
        NSMutableDictionary *baseAttributes = [NSMutableDictionary dictionary];
        if ([prefs baseBodyFont])
            [baseAttributes setObject:[prefs baseBodyFont] forKey:NSFontAttributeName];
        if ([prefs foregroundColor])
            [baseAttributes setObject:[prefs foregroundColor] forKey:NSForegroundColorAttributeName];
        significantFormatting = [SpiralLegacyNoteFormattingDetector
            containsSignificantFormattingInContents:contents
            baseAttributes:baseAttributes];
        targetFormat = significantFormatting ? RTFTextFormat : PlainTextFormat;
    }

    if (targetFormat != PlainTextFormat && targetFormat != RTFTextFormat && targetFormat != HTMLFormat) {
        [controller closeAllResources];
        [controller release];
        if (error)
            *error = [self errorWithCode:NVLegacyCollectionImportErrorUnrecognizedFormat
                             description:@"This legacy notes storage format is not supported by the clean-file importer."];
        return nil;
    }

    NSArray *noteSnapshots = [[controller noteValueSnapshotsForMigrationUsingFormat:targetFormat] copy];
    if ([noteSnapshots count] != [contents count]) {
        [noteSnapshots release];
        [controller closeAllResources];
        [controller release];
        if (error)
            *error = [self errorWithCode:NVLegacyCollectionImportErrorConversionFailed
                             description:@"Spiral could not extract every legacy note and its metadata."];
        return nil;
    }

    BOOL sourceWasEncrypted = [prefs doesEncryption];
    NSUInteger hashIterationCount = [prefs hashIterationCount];
    NSString *keychainDatabaseIdentifier = [[prefs valueForKey:@"keychainDatabaseIdentifier"] copy];
    if (sourceWasEncrypted && !passphraseData) {
        NSAlert *plaintextWarning = [[[NSAlert alloc] init] autorelease];
        [plaintextWarning setAlertStyle:NSAlertStyleWarning];
        [plaintextWarning setMessageText:@"The imported notes will no longer use legacy encryption"];
        [plaintextWarning setInformativeText:
            @"Spiral will create ordinary unencrypted TXT, RTF, or HTML files. "
             "The original encrypted Notational Velocity or nvAlt folder and its Keychain item will be kept until you deliberately remove them."];
        [plaintextWarning addButtonWithTitle:@"Import Unencrypted Files"];
        [plaintextWarning addButtonWithTitle:@"Cancel"];
        if ([plaintextWarning runModal] != NSAlertFirstButtonReturn) {
            [controller closeAllResources];
            [controller release];
            if (error)
                *error = [self errorWithCode:NVLegacyCollectionImportErrorOpenFailed
                                 description:@"The encrypted notes import was cancelled before unencrypted files were created."];
            return nil;
        }
        [prefs disableEncryptionForMigrationWithoutRemovingLegacyKeychainItem];
    }
    if (sourceFormat == SingleDatabaseFormat)
        [prefs useDefaultPathExtensionForFormatForMigration:targetFormat];
    if ([prefs notesStorageFormat] != targetFormat)
        [prefs setNotesStorageFormat:targetFormat];
    [controller flushEverything];
    BOOL convertedSingleDatabase = sourceFormat == SingleDatabaseFormat;
    NSString *extension = [[prefs chosenPathExtensionForFormat:targetFormat] copy];
    NSArray *exportedFilenames = [[controller noteFileNamesForMigration] copy];
    NSUInteger noteCount = [contents count];
    [controller closeAllResources];
    [controller release];

    BOOL verifiedEveryNote = [exportedFilenames count] == noteCount;
    NSString *verificationFailure = nil;
    NSSet *cleanExtensions = [NSSet setWithObjects:
        @"txt", @"text", @"utf8", @"taskpaper", @"md", @"markdown", @"rtf", @"html", @"htm", nil];
    for (NSString *filename in exportedFilenames) {
        // Carbon's HFS path representation uses '/' for the character that
        // appears as ':' in a POSIX filename. Convert before URL-based checks.
        NSString *fileSystemName = [filename stringByReplacingOccurrencesOfString:@"/" withString:@":"];
        NSURL *exportedURL = [workingCopyURL URLByAppendingPathComponent:fileSystemName];
        NSNumber *isRegularFile = nil;
        NSString *pathExtension = [[filename pathExtension] lowercaseString];
        BOOL hasExpectedExtension = convertedSingleDatabase
            ? [pathExtension isEqualToString:[extension lowercaseString]]
            : [cleanExtensions containsObject:pathExtension];
        if (!hasExpectedExtension ||
            ![exportedURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil] ||
            ![isRegularFile boolValue]) {
            verifiedEveryNote = NO;
            verificationFailure = [NSString stringWithFormat:@"%@ (expected extension %@; regular file %@)",
                filename, extension, isRegularFile];
            break;
        }
    }
    [exportedFilenames release];
    [extension release];
    if (!verifiedEveryNote) {
        [noteSnapshots release];
        if (error)
            *error = [self errorWithCode:NVLegacyCollectionImportErrorConversionFailed
                             description:[NSString stringWithFormat:
                                 @"Spiral could not verify that every legacy note was converted to a clean file%@.",
                                 verificationFailure ? [@": " stringByAppendingString:verificationFailure] : @""]];
        return nil;
    }

    NVLegacyCollectionPreparation *result = [[[NVLegacyCollectionPreparation alloc] init] autorelease];
    result.storageFormat = targetFormat;
    result.noteCount = noteCount;
    result.detectedSignificantFormatting = significantFormatting;
    result.sourceWasEncrypted = sourceWasEncrypted;
    result.recoveredWAL = hadWAL;
    NSData *fixtureManifestData = [NSData dataWithContentsOfURL:
        [workingCopyURL URLByAppendingPathComponent:@"LegacyFixtureManifest.plist"]];
    NSDictionary *fixtureManifest = fixtureManifestData
        ? [NSPropertyListSerialization propertyListWithData:fixtureManifestData
                                                    options:NSPropertyListImmutable
                                                     format:NULL
                                                      error:NULL]
        : nil;
    result.sourceApplication = [fixtureManifest objectForKey:@"sourceApplication"]
        ?: @"Notational Velocity/nvAlt";
    result.sourceVersion = [fixtureManifest objectForKey:@"sourceVersion"];
    result.noteSnapshots = noteSnapshots;
    NSMutableDictionary *collectionMetadata = [NSMutableDictionary dictionary];
    NSData *storageFormatData = [self propertyListData:@(sourceFormat)];
    NSData *iterationData = [self propertyListData:@(hashIterationCount)];
    if (storageFormatData)
        [collectionMetadata setObject:storageFormatData forKey:@"legacy.storageFormat"];
    if (iterationData)
        [collectionMetadata setObject:iterationData forKey:@"legacy.hashIterationCount"];
    NSData *keychainIdentifierData = [self propertyListData:keychainDatabaseIdentifier];
    if (keychainIdentifierData)
        [collectionMetadata setObject:keychainIdentifierData forKey:@"legacy.keychainDatabaseIdentifier"];
    result.collectionMetadata = collectionMetadata;
    [keychainDatabaseIdentifier release];
    [noteSnapshots release];
    return result;
}

@end

@interface NVSettingsBridge ()
@property(nonatomic, retain) GlobalPrefs *globalPrefs;
@property(nonatomic, retain) NotationPrefsViewController *workflowController;
@end

@implementation NVSettingsBridge

+ (NSTextView *)newPhase3Editor {
    LinkingEditor *editor = [[[LinkingEditor alloc] initWithFrame:NSZeroRect] autorelease];
    [editor awakeFromNib];
    return editor;
}

- (id)init {
    self = [super init];
    if (self) {
        self.globalPrefs = [GlobalPrefs defaultPrefs];
        self.workflowController = [[[NotationPrefsViewController alloc] init] autorelease];
    }
    return self;
}

- (void)dealloc {
    [_globalPrefs release];
    [_workflowController release];
    [super dealloc];
}

- (NotationPrefs *)notationPrefs { return [self.globalPrefs notationPrefs]; }
- (void)changed { [[NSNotificationCenter defaultCenter] postNotificationName:NVSettingsBridgeDidChangeNotification object:self]; }

- (BOOL)autoCompleteSearches { return [self.globalPrefs autoCompleteSearches]; }
- (BOOL)confirmNoteDeletion { return [self.globalPrefs confirmNoteDeletion]; }
- (BOOL)quitWhenClosingWindow { return [self.globalPrefs quitWhenClosingWindow]; }
- (BOOL)tabKeyIndents { return [self.globalPrefs tabKeyIndents]; }
- (BOOL)checkSpellingAsYouType { return [self.globalPrefs checkSpellingAsYouType]; }
- (BOOL)pastePreservesStyle { return [self.globalPrefs pastePreservesStyle]; }
- (BOOL)linksAutoSuggested { return [self.globalPrefs linksAutoSuggested]; }
- (BOOL)softTabs { return [self.globalPrefs softTabs]; }
- (BOOL)URLsAreClickable { return [self.globalPrefs URLsAreClickable]; }
- (BOOL)highlightSearchTerms { return [self.globalPrefs highlightSearchTerms]; }
- (CGFloat)tableFontSize { return [self.globalPrefs tableFontSize]; }
- (NSString *)noteBodyFontDescription {
    NSFont *font = [self.globalPrefs noteBodyFont];
    return font ? [NSString stringWithFormat:@"%@, %g pt", [font displayName], [font pointSize]] : NSLocalizedString(@"System font", nil);
}
- (NSColor *)foregroundTextColor { return [self.globalPrefs foregroundTextColor]; }
- (NSColor *)backgroundTextColor { return [self.globalPrefs backgroundTextColor]; }
- (NSColor *)searchHighlightColor { return [self.globalPrefs searchTermHighlightColorRaw:YES]; }
- (NSString *)appShortcutDescription { return [[self.globalPrefs appActivationKeyCombo] description] ?: @""; }
- (void)setAutoCompleteSearches:(BOOL)value { [self.globalPrefs setAutoCompleteSearches:value sender:self]; [self changed]; }
- (void)setConfirmNoteDeletion:(BOOL)value { [self.globalPrefs setConfirmNoteDeletion:value sender:self]; [self changed]; }
- (void)setQuitWhenClosingWindow:(BOOL)value { [self.globalPrefs setQuitWhenClosingWindow:value sender:self]; [self changed]; }
- (void)setTabKeyIndents:(BOOL)value { [self.globalPrefs setTabIndenting:value sender:self]; [self changed]; }
- (void)setCheckSpellingAsYouType:(BOOL)value { [self.globalPrefs setCheckSpellingAsYouType:value sender:self]; [self changed]; }
- (void)setPastePreservesStyle:(BOOL)value { [self.globalPrefs setPastePreservesStyle:value sender:self]; [self changed]; }
- (void)setLinksAutoSuggested:(BOOL)value { [self.globalPrefs setLinksAutoSuggested:value sender:self]; [self changed]; }
- (void)setSoftTabs:(BOOL)value { [self.globalPrefs setSoftTabs:value sender:self]; [self changed]; }
- (void)setURLsAreClickable:(BOOL)value { [self.globalPrefs setMakeURLsClickable:value sender:self]; [self changed]; }
- (void)setHighlightSearchTerms:(BOOL)value { [self.globalPrefs setShouldHighlightSearchTerms:value sender:self]; [self changed]; }
- (void)setTableFontSize:(CGFloat)value { [self.globalPrefs setTableFontSize:value sender:self]; [self changed]; }
- (void)setForegroundTextColor:(NSColor *)value { [self.globalPrefs setForegroundTextColor:value sender:self]; [self changed]; }
- (void)setBackgroundTextColor:(NSColor *)value { [self.globalPrefs setBackgroundTextColor:value sender:self]; [self changed]; }
- (void)setSearchHighlightColor:(NSColor *)value { [self.globalPrefs setSearchTermHighlightColor:value sender:self]; [self changed]; }

- (void)chooseApplicationShortcutForWindow:(NSWindow *)window {
    [[PTKeyComboPanel sharedPanel] showSheetForHotkey:[self.globalPrefs appActivationHotKey]
                                           forWindow:window
                                       modalDelegate:self];
}

- (void)keyComboPanelEnded:(PTKeyComboPanel *)panel {
    PTKeyCombo *oldCombo = [[self.globalPrefs appActivationKeyCombo] retain];
    [self.globalPrefs setAppActivationKeyCombo:[panel keyCombo] sender:self];
    if (![self.globalPrefs registerAppActivationKeystrokeWithTarget:[NSApp delegate] selector:@selector(toggleNVActivation:)]) {
        [self.globalPrefs setAppActivationKeyCombo:oldCombo sender:self];
        NSBeep();
    }
    [oldCombo release];
    [self changed];
}

- (void)chooseNoteBodyFont {
    NSFontManager *manager = [NSFontManager sharedFontManager];
    [manager setTarget:self];
    [manager setAction:@selector(changeFont:)];
    [manager setSelectedFont:[self.globalPrefs noteBodyFont] isMultiple:NO];
    [manager orderFrontFontPanel:self];
}

- (void)changeFont:(id)sender {
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *font = [manager convertFont:[manager selectedFont]];
    NSFontTraitMask disallowedTraits = NSItalicFontMask | NSBoldFontMask;
    if (([manager traitsOfFont:font] & disallowedTraits) != 0) {
        NSBeep();
        return;
    }
    [self.globalPrefs setNoteBodyFont:font sender:self];
    [self changed];
}

- (NSInteger)storageFormat { return [[self notationPrefs] notesStorageFormat]; }
- (BOOL)confirmFileDeletion { return [[self notationPrefs] confirmFileDeletion]; }
- (BOOL)appendFileExtensionToNewNotes { return [[self notationPrefs] appendFileExtensionToNewNotes]; }
- (BOOL)encryptionEnabled { return [[self notationPrefs] doesEncryption]; }
- (BOOL)storesPasswordInKeychain { return [[self notationPrefs] storesPasswordInKeychain]; }
- (BOOL)secureTextEntry { return [[self notationPrefs] secureTextEntry]; }
- (NSUInteger)encryptionKeyLength { return [[self notationPrefs] keyLengthInBits]; }
- (BOOL)hasKeychainItem {
    SecKeychainItemRef item = [[self notationPrefs] currentKeychainItem];
    if (item) CFRelease(item);
    return item != NULL;
}
- (NSArray<NSString *> *)allowedExtensions {
    NSMutableArray *values = [NSMutableArray array];
    for (NSInteger index = 0; index < [[self notationPrefs] pathExtensionsCount]; index++)
        [values addObject:[[self notationPrefs] pathExtensionAtIndex:(int)index]];
    return values;
}
- (NSArray<NSString *> *)allowedTypes {
    NSMutableArray *values = [NSMutableArray array];
    for (NSInteger index = 0; index < [[self notationPrefs] typeStringsCount]; index++)
        [values addObject:[[self notationPrefs] typeStringAtIndex:(int)index]];
    return values;
}
- (NSUInteger)defaultExtensionIndex { return [[self notationPrefs] indexOfChosenPathExtension]; }
- (NSView *)legacyWorkflowView { return [self.workflowController view]; }

- (void)requestStorageFormat:(NSInteger)format {
    if (format < PlainTextFormat || format > HTMLFormat)
        return;
    [self.workflowController requestStorageFormatFromModernSettings:format];
    [self changed];
}
- (void)setConfirmFileDeletion:(BOOL)value { [[self notationPrefs] setConfirmsFileDeletion:value]; [self changed]; }
- (void)setAppendFileExtensionToNewNotes:(BOOL)value { [[self notationPrefs] setAppendFileExtensionToNewNotes:value]; [self changed]; }
- (void)requestEncryptionToggle { [self.workflowController requestEncryptionToggleFromModernSettings]; [self changed]; }
- (void)requestPassphraseChange { [self.workflowController requestPassphraseChangeFromModernSettings]; }
- (void)setStoresPasswordInKeychain:(BOOL)value { [[self notationPrefs] setStoresPasswordInKeychain:value]; [self changed]; }
- (void)setSecureTextEntry:(BOOL)value { [[self notationPrefs] setSecureTextEntry:value]; [self changed]; }
- (void)removeKeychainItem { [[self notationPrefs] removeKeychainData]; [self changed]; }

- (BOOL)replaceAllowedExtensionAtIndex:(NSUInteger)index withValue:(NSString *)value { BOOL result = [[self notationPrefs] setExtension:value atIndex:(unsigned int)index]; [self changed]; return result; }
- (BOOL)replaceAllowedTypeAtIndex:(NSUInteger)index withValue:(NSString *)value { BOOL result = [[self notationPrefs] setType:value atIndex:(unsigned int)index]; [self changed]; return result; }
- (void)addAllowedExtension { [[self notationPrefs] addAllowedPathExtension:@""]; [self changed]; }
- (void)addAllowedType { [[self notationPrefs] addAllowedType:@""]; [self changed]; }
- (BOOL)removeAllowedExtensionAtIndex:(NSUInteger)index { BOOL result = [[self notationPrefs] removeAllowedPathExtensionAtIndex:(unsigned int)index]; [self changed]; return result; }
- (void)removeAllowedTypeAtIndex:(NSUInteger)index { [[self notationPrefs] removeAllowedTypeAtIndex:(unsigned int)index]; [self changed]; }
- (BOOL)makeDefaultExtensionAtIndex:(NSUInteger)index { BOOL result = [[self notationPrefs] setChosenPathExtensionAtIndex:(unsigned int)index]; [self changed]; return result; }

- (NSMenu *)externalEditorMenu { return [[ExternalEditorListController sharedInstance] addEditorPrefsMenu]; }
- (void)synchronize { [self.globalPrefs synchronize]; }

@end
