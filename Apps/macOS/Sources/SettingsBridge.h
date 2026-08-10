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
#import "LegacyCompatibility/NVLegacyCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const NVSettingsBridgeDidChangeNotification;

@interface NVSettingsBridge : NSObject <NSFontChanging>

+ (NSTextView *)newPhase3Editor;

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
@property(nonatomic, readonly) NSInteger storageFormat;
@property(nonatomic, readonly) BOOL confirmFileDeletion;
@property(nonatomic, readonly) BOOL appendFileExtensionToNewNotes;
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
- (void)requestStorageFormat:(NSInteger)format;
- (void)setConfirmFileDeletion:(BOOL)value;
- (void)setAppendFileExtensionToNewNotes:(BOOL)value;
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
