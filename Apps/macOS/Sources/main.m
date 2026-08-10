//
//  main.m
//  Notation
//
//  Created by Zachary Schneirov on 12/19/05.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
    This file is part of Notational Velocity.

    Notational Velocity is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Notational Velocity is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */

#import <Cocoa/Cocoa.h>
#import "Spiral-Swift.h"

static int SpiralRunDisposableLaunchProbe(NSString *directoryPath)
{
    NSString *temporaryRoot = [NSTemporaryDirectory() stringByStandardizingPath];
    NSString *directory = [directoryPath stringByStandardizingPath];
    NSString *requiredPrefix = [temporaryRoot hasSuffix:@"/"] ? temporaryRoot : [temporaryRoot stringByAppendingString:@"/"];
    if (![directory hasPrefix:requiredPrefix]) {
        NSLog(@"Refusing launch probe outside the temporary directory: %@", directory);
        return 64;
    }

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        NSLog(@"Launch probe directory does not exist: %@", directory);
        return 66;
    }

    NSString *markerPath = [directory stringByAppendingPathComponent:@".spiral-launch-ok"];
    NSError *error = nil;
    if (![@"Spiral launched without opening user data\n" writeToFile:markerPath
                                                      atomically:YES
                                                        encoding:NSUTF8StringEncoding
                                                           error:&error]) {
        NSLog(@"Unable to write launch probe marker: %@", error);
        return 74;
    }
    return 0;
}

static BOOL SpiralPathIsInsideTemporaryDirectory(NSString *path)
{
    NSString *temporaryRoot = [NSTemporaryDirectory() stringByStandardizingPath];
    NSString *standardizedPath = [path stringByStandardizingPath];
    NSString *requiredPrefix = [temporaryRoot hasSuffix:@"/"] ? temporaryRoot : [temporaryRoot stringByAppendingString:@"/"];
    return [standardizedPath hasPrefix:requiredPrefix];
}

static int SpiralRunLegacyMigrationProbe(NSDictionary<NSString *, NSString *> *environment)
{
    NSString *sourcePath = [environment objectForKey:@"SPIRAL_LEGACY_MIGRATION_PROBE_SOURCE"];
    NSString *destinationPath = [environment objectForKey:@"SPIRAL_LEGACY_MIGRATION_PROBE_DESTINATION"];
    NSString *reportPath = [environment objectForKey:@"SPIRAL_LEGACY_MIGRATION_PROBE_REPORT"];
    if (![sourcePath length] || ![destinationPath length] || ![reportPath length] ||
        !SpiralPathIsInsideTemporaryDirectory(sourcePath) ||
        !SpiralPathIsInsideTemporaryDirectory(destinationPath) ||
        !SpiralPathIsInsideTemporaryDirectory(reportPath)) {
        NSLog(@"Legacy migration probes require source, destination, and report paths inside the temporary directory.");
        return 64;
    }

    BOOL encrypted = [[environment objectForKey:@"SPIRAL_LEGACY_MIGRATION_PROBE_ENCRYPTED"] isEqualToString:@"1"];
    NSData *passphraseData = [[environment objectForKey:@"SPIRAL_LEGACY_MIGRATION_PROBE_PASSPHRASE"]
        dataUsingEncoding:NSUTF8StringEncoding];
    NSString *failureCount = [environment objectForKey:@"SPIRAL_LEGACY_MIGRATION_PROBE_FAIL_AFTER"];
    NSNumber *failureAfter = [failureCount length] ? @([failureCount integerValue]) : nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block int32_t status = 1;
    __block NSString *message = nil;
    [SpiralLegacyMigrationProbe runWithSourceURL:[NSURL fileURLWithPath:sourcePath isDirectory:YES]
                              destinationRootURL:[NSURL fileURLWithPath:destinationPath isDirectory:YES]
                                       reportURL:[NSURL fileURLWithPath:reportPath]
                                       encrypted:encrypted
                                  passphraseData:passphraseData
                   failureAfterImportedNoteCount:failureAfter
                                      completion:^(int32_t result, NSString *errorMessage) {
        status = result;
        message = [errorMessage copy];
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
    if (status != 0)
        NSLog(@"Legacy migration probe failed: %@", message);
    [message release];
    return status;
}

int main(int argc, char *argv[])
{
    NSDictionary<NSString *, NSString *> *environment = [[NSProcessInfo processInfo] environment];
    NSString *legacyMigrationProbeSource = [environment
        objectForKey:@"SPIRAL_LEGACY_MIGRATION_PROBE_SOURCE"];
    if ([legacyMigrationProbeSource length] > 0)
        return SpiralRunLegacyMigrationProbe(environment);

    NSString *launchProbeDirectory = [environment
        objectForKey:@"SPIRAL_DISPOSABLE_LAUNCH_DIRECTORY"];
    if ([launchProbeDirectory length] > 0) {
        return SpiralRunDisposableLaunchProbe(launchProbeDirectory);
    }

    if (![[[[NSProcessInfo processInfo] environment] objectForKey:@"SPIRAL_PHASE3_UI_TEST_MODE"] isEqualToString:@"1"])
        [SpiralPreferencesMigrationController migrateBeforeApplicationLaunch];
    return NSApplicationMain(argc,  (const char **) argv);
}
