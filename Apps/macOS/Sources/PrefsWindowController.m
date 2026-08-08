/* Copyright (c) 2010, Zachary Schneirov. All rights reserved. */

#import "PrefsWindowController.h"
#import "Spiral-Swift.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstrict-prototypes"
#import "GlobalPrefs.h"
#pragma clang diagnostic pop
#import "NSData_transformations.h"
#import "NSFileManager_NV.h"

@implementation PrefsWindowController

- (id)init {
    self = [super init];
    if (self) {
        modernSettingsController = [[ModernSettingsWindowController alloc] init];
    }
    return self;
}

- (void)dealloc {
    [modernSettingsController release];
    [super dealloc];
}

- (void)showWindow:(id)sender {
    [modernSettingsController showWindow:sender];
}

- (BOOL)getNewNotesRefFromOpenPanel:(FSRef *)notesDirectoryRef
                       returnedPath:(NSString **)path
            mergeExistingCollection:(BOOL *)mergeExistingCollection {
    if (!notesDirectoryRef)
        return NO;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canCreateDirectories = YES;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.resolvesAliases = YES;
    panel.allowsMultipleSelection = NO;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.title = NSLocalizedString(@"Select a folder", nil);
    panel.prompt = NSLocalizedString(@"Select", nil);
    panel.message = NSLocalizedString(@"Select the folder that Spiral should use for reading and storing notes.", nil);

    NSData *currentAlias = [[GlobalPrefs defaultPrefs] aliasDataForDefaultDirectory];
    NSString *currentPath = [[NSFileManager defaultManager] pathCopiedFromAliasData:currentAlias];
    if (currentPath.length > 0)
        panel.directoryURL = [NSURL fileURLWithPath:currentPath isDirectory:YES];

    while (YES) {
        if ([panel runModal] != NSModalResponseOK || panel.URL == nil)
            return NO;

        NSURL *currentURL = currentPath.length > 0 ? [NSURL fileURLWithPath:currentPath isDirectory:YES] : nil;
        NSURL *resolvedCurrentURL = [[currentURL URLByResolvingSymlinksInPath] standardizedURL];
        NSURL *resolvedSelectedURL = [[panel.URL URLByResolvingSymlinksInPath] standardizedURL];
        if (resolvedCurrentURL && [resolvedCurrentURL isEqual:resolvedSelectedURL]) {
            if (mergeExistingCollection)
                *mergeExistingCollection = NO;
            break;
        }

        SpiralFolderChangeDecision decision = [SpiralStorageLocationController decisionForTargetFolderAtURL:panel.URL];
        if (decision == SpiralFolderChangeDecisionRefusedRegularFolder)
            continue;
        if (decision == SpiralFolderChangeDecisionCancel)
            return NO;
        if (mergeExistingCollection)
            *mergeExistingCollection = YES;
        break;
    }

    if (path)
        *path = [[panel.URL.path copy] autorelease];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return CFURLGetFSRef((CFURLRef)panel.URL, notesDirectoryRef);
#pragma clang diagnostic pop
}

@end
