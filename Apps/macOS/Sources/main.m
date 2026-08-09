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

int main(int argc, char *argv[])
{
    NSString *launchProbeDirectory = [[[NSProcessInfo processInfo] environment]
        objectForKey:@"SPIRAL_DISPOSABLE_LAUNCH_DIRECTORY"];
    if ([launchProbeDirectory length] > 0) {
        return SpiralRunDisposableLaunchProbe(launchProbeDirectory);
    }

    [SpiralPreferencesMigrationController migrateBeforeApplicationLaunch];
    return NSApplicationMain(argc,  (const char **) argv);
}
