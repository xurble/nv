#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const NVSettingsBridgeDidChangeNotification;

@interface NVSettingsBridge : NSObject <NSFontChanging>

@property(nonatomic, readonly) BOOL autoCompleteSearches;
@property(nonatomic, readonly) BOOL confirmNoteDeletion;
@property(nonatomic, readonly) BOOL quitWhenClosingWindow;
@property(nonatomic, readonly) BOOL tabKeyIndents;
@property(nonatomic, readonly) BOOL checkSpellingAsYouType;
@property(nonatomic, readonly) BOOL pastePreservesStyle;
@property(nonatomic, readonly) BOOL linksAutoSuggested;
@property(nonatomic, readonly) BOOL softTabs;
@property(nonatomic, readonly) BOOL URLsAreClickable;
@property(nonatomic, readonly) BOOL highlightSearchTerms;
@property(nonatomic, readonly) CGFloat tableFontSize;
@property(nonatomic, readonly, copy) NSString *noteBodyFontDescription;
@property(nonatomic, readonly, retain) NSColor *foregroundTextColor;
@property(nonatomic, readonly, retain) NSColor *backgroundTextColor;
@property(nonatomic, readonly, retain) NSColor *searchHighlightColor;
@property(nonatomic, readonly, copy) NSString *appShortcutDescription;
@property(nonatomic, readonly, copy) NSString *notesFolderPath;

@property(nonatomic, readonly) NSInteger storageFormat;
@property(nonatomic, readonly) BOOL confirmFileDeletion;
@property(nonatomic, readonly) BOOL encryptionEnabled;
@property(nonatomic, readonly) BOOL storesPasswordInKeychain;
@property(nonatomic, readonly) BOOL secureTextEntry;
@property(nonatomic, readonly) NSUInteger encryptionKeyLength;
@property(nonatomic, readonly) BOOL hasKeychainItem;
@property(nonatomic, readonly, copy) NSArray<NSString *> *allowedExtensions;
@property(nonatomic, readonly, copy) NSArray<NSString *> *allowedTypes;
@property(nonatomic, readonly) NSUInteger defaultExtensionIndex;

@property(nonatomic, readonly, retain) NSView *legacyWorkflowView;
@property(nonatomic, readonly, retain) NSMenu *externalEditorMenu;

- (void)setAutoCompleteSearches:(BOOL)value;
- (void)setConfirmNoteDeletion:(BOOL)value;
- (void)setQuitWhenClosingWindow:(BOOL)value;
- (void)setTabKeyIndents:(BOOL)value;
- (void)setCheckSpellingAsYouType:(BOOL)value;
- (void)setPastePreservesStyle:(BOOL)value;
- (void)setLinksAutoSuggested:(BOOL)value;
- (void)setSoftTabs:(BOOL)value;
- (void)setURLsAreClickable:(BOOL)value;
- (void)setHighlightSearchTerms:(BOOL)value;
- (void)setTableFontSize:(CGFloat)value;
- (void)setForegroundTextColor:(NSColor *)value;
- (void)setBackgroundTextColor:(NSColor *)value;
- (void)setSearchHighlightColor:(NSColor *)value;

- (void)chooseApplicationShortcutForWindow:(NSWindow *)window;
- (void)chooseNoteBodyFont;
- (void)chooseNotesFolderForWindow:(NSWindow *)window;

- (void)requestStorageFormat:(NSInteger)format;
- (void)setConfirmFileDeletion:(BOOL)value;
- (void)requestEncryptionToggle;
- (void)requestPassphraseChange;
- (void)setStoresPasswordInKeychain:(BOOL)value;
- (void)setSecureTextEntry:(BOOL)value;
- (void)removeKeychainItem;

- (BOOL)replaceAllowedExtensionAtIndex:(NSUInteger)index withValue:(NSString *)value;
- (BOOL)replaceAllowedTypeAtIndex:(NSUInteger)index withValue:(NSString *)value;
- (void)addAllowedExtension;
- (void)addAllowedType;
- (BOOL)removeAllowedExtensionAtIndex:(NSUInteger)index;
- (void)removeAllowedTypeAtIndex:(NSUInteger)index;
- (BOOL)makeDefaultExtensionAtIndex:(NSUInteger)index;

- (void)synchronize;

@end

NS_ASSUME_NONNULL_END
