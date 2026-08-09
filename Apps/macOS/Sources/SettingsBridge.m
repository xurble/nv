#import "SettingsBridge.h"
#import "LegacyCompatibility/NVLegacyCompatibility.h"
#import "Spiral-Swift.h"

#import "AppController.h"
#import "ExternalEditorListController.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstrict-prototypes"
#import "GlobalPrefs.h"
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
    NVLegacyCollectionImportErrorConversionFailed
};

@interface NVLegacyCollectionPreparation ()
@property(nonatomic, readwrite) NSInteger storageFormat;
@property(nonatomic, readwrite) NSUInteger noteCount;
@property(nonatomic, readwrite) BOOL detectedSignificantFormatting;
@property(nonatomic, readwrite) BOOL sourceWasEncrypted;
@end

@implementation NVLegacyCollectionPreparation
@end

@implementation NVLegacyCollectionImporter

+ (NSError *)errorWithCode:(NVLegacyCollectionImportError)code description:(NSString *)description {
    return [NSError errorWithDomain:NVLegacyCollectionImportErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (int)inferredSeparateFileFormatAtURL:(NSURL *)folderURL error:(NSError **)error {
    NSSet *plainExtensions = [NSSet setWithObjects:@"txt", @"text", @"utf8", @"taskpaper", nil];
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
    if ([formats count] != 1) {
        if (error) {
            *error = [self errorWithCode:NVLegacyCollectionImportErrorUnrecognizedFormat
                             description:[formats count] == 0
                                ? @"The selected folder does not contain recognizable Notational Velocity or nvAlt note files."
                                : @"The selected folder contains a mixture of note file formats and cannot be imported safely as one legacy collection."];
        }
        return -1;
    }
    return [[formats anyObject] intValue];
}

+ (NVLegacyCollectionPreparation *)prepareWorkingCopyAtURL:(NSURL *)workingCopyURL
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
        error:&openError];
    if (!controller) {
        if (error) {
            NSString *description = openError == kPassCanceledErr
                ? @"The encrypted notes import was cancelled."
                : [NSString stringWithFormat:@"The legacy notes collection could not be opened (%d).", (int)openError];
            *error = [self errorWithCode:NVLegacyCollectionImportErrorOpenFailed description:description];
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

    BOOL sourceWasEncrypted = [prefs doesEncryption];
    if (sourceWasEncrypted) {
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
    NSString *extension = [[prefs chosenPathExtensionForFormat:targetFormat] copy];
    NSArray *exportedFilenames = [[controller noteFileNamesForMigration] copy];
    NSUInteger noteCount = [contents count];
    [controller closeAllResources];
    [controller release];

    BOOL verifiedEveryNote = [exportedFilenames count] == noteCount;
    for (NSString *filename in exportedFilenames) {
        NSURL *exportedURL = [workingCopyURL URLByAppendingPathComponent:filename];
        NSNumber *isRegularFile = nil;
        if (![[[filename pathExtension] lowercaseString] isEqualToString:[extension lowercaseString]] ||
            ![exportedURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil] ||
            ![isRegularFile boolValue]) {
            verifiedEveryNote = NO;
            break;
        }
    }
    [exportedFilenames release];
    [extension release];
    if (!verifiedEveryNote) {
        if (error)
            *error = [self errorWithCode:NVLegacyCollectionImportErrorConversionFailed
                             description:@"Spiral could not verify that every legacy note was converted to a clean file."];
        return nil;
    }

    NVLegacyCollectionPreparation *result = [[[NVLegacyCollectionPreparation alloc] init] autorelease];
    result.storageFormat = targetFormat;
    result.noteCount = noteCount;
    result.detectedSignificantFormatting = significantFormatting;
    result.sourceWasEncrypted = sourceWasEncrypted;
    return result;
}

@end

@interface NVSettingsBridge ()
@property(nonatomic, retain) GlobalPrefs *globalPrefs;
@property(nonatomic, retain) NotationPrefsViewController *workflowController;
@end

@implementation NVSettingsBridge

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
- (NSString *)notesFolderPath { return [self.globalPrefs humanViewablePathForDefaultDirectory] ?: NSLocalizedString(@"Default notes folder", nil); }
- (NSURL *)notesFolderURL {
    NSData *aliasData = [self.globalPrefs aliasDataForDefaultDirectory];
    NSString *path = [[NSFileManager defaultManager] pathCopiedFromAliasData:aliasData];
    if (path.length > 0)
        return [NSURL fileURLWithPath:path isDirectory:YES];

    FSRef defaultRef;
    if ([NotationController getDefaultNotesDirectoryRef:&defaultRef] != noErr)
        return nil;
    return [(NSURL *)CFURLCreateFromFSRef(kCFAllocatorDefault, &defaultRef) autorelease];
}
- (BOOL)notesFolderIsInICloud {
    NSURL *url = [self notesFolderURL];
    return url ? [SpiralStorageLocationController isURLInICloud:url] : NO;
}

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

- (void)chooseNotesFolderForWindow:(NSWindow *)window {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canCreateDirectories = YES;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.resolvesAliases = YES;
    panel.allowsMultipleSelection = NO;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.title = NSLocalizedString(@"Select a folder", nil);
    panel.prompt = NSLocalizedString(@"Select", nil);
    panel.message = NSLocalizedString(@"Select the folder Spiral should use for reading and storing notes.", nil);

    panel.directoryURL = [self notesFolderURL];

    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil)
            return;

        NSURL *currentURL = [self notesFolderURL];
        NSURL *resolvedCurrentURL = [[currentURL URLByResolvingSymlinksInPath] standardizedURL];
        NSURL *resolvedSelectedURL = [[panel.URL URLByResolvingSymlinksInPath] standardizedURL];
        if (resolvedCurrentURL && [resolvedCurrentURL isEqual:resolvedSelectedURL])
            return;

        SpiralFolderChangeDecision decision = [SpiralStorageLocationController decisionForTargetFolderAtURL:panel.URL];
        if (decision != SpiralFolderChangeDecisionUseEmptyFolder &&
            decision != SpiralFolderChangeDecisionMergeCollection)
            return;

        AppController *appController = (AppController *)[NSApp delegate];
        if ([appController switchToNotesDirectoryURL:panel.URL mergeCurrentNotes:YES])
            [self changed];
    }];
}

- (void)switchToICloudForWindow:(NSWindow *)window {
    NSURL *currentURL = [self notesFolderURL];
    if (!currentURL)
        return;

    [SpiralFirstRunMigrationController prepareICloudSwitchFromURL:currentURL
                                                        forWindow:window
                                                        completion:^(SpiralPreparedNotesDirectory *prepared) {
        if ([[[prepared directoryURL] standardizedURL] isEqual:[currentURL standardizedURL]])
            return;

        AppController *appController = (AppController *)[NSApp delegate];
        BOOL switched = [appController switchToNotesDirectoryURL:[prepared directoryURL]
                                                mergeCurrentNotes:[prepared requiresMerge]];
        if (switched) {
            [SpiralFirstRunMigrationController finalizePreparedNotesDirectory:prepared];
            [self changed];
        } else {
            [SpiralFirstRunMigrationController cancelPreparedNotesDirectory:prepared];
        }
    }];
}

- (NSInteger)storageFormat { return [[self notationPrefs] notesStorageFormat]; }
- (BOOL)confirmFileDeletion { return [[self notationPrefs] confirmFileDeletion]; }
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

- (void)requestStorageFormat:(NSInteger)format { [self.workflowController requestStorageFormatFromModernSettings:format]; [self changed]; }
- (void)setConfirmFileDeletion:(BOOL)value { [[self notationPrefs] setConfirmsFileDeletion:value]; [self changed]; }
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
