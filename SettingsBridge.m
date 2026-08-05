#import "SettingsBridge.h"

#import "AppController.h"
#import "ExternalEditorListController.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstrict-prototypes"
#import "GlobalPrefs.h"
#pragma clang diagnostic pop
#import "NSData_transformations.h"
#import "NotationPrefs.h"
#import "NotationPrefsViewController.h"
#import "PTHotKeys/PTKeyCombo.h"
#import "PTHotKeys/PTKeyComboPanel.h"

NSNotificationName const NVSettingsBridgeDidChangeNotification = @"NVSettingsBridgeDidChangeNotification";

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

    NSString *currentPath = [self.globalPrefs humanViewablePathForDefaultDirectory];
    if (currentPath.length > 0)
        panel.directoryURL = [NSURL fileURLWithPath:currentPath isDirectory:YES];

    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil)
            return;

        /* Alias data is an existing public persistence format. Keep conversion
           at this single compatibility boundary while using the URL-based panel. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        FSRef selectedRef = {{0}};
        if (!CFURLGetFSRef((CFURLRef)panel.URL, &selectedRef))
            return;
#pragma clang diagnostic pop

        NSData *aliasData = [NSData aliasDataForFSRef:&selectedRef];
        if (!aliasData)
            return;

        [self.globalPrefs setAliasDataForDefaultDirectory:aliasData sender:self];
        [self changed];
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
