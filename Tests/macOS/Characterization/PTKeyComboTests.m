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

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

#import "PTKeyBroadcaster.h"
#import "PTKeyCombo.h"

static NSUInteger failureCount = 0;

static void AssertCondition(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        failureCount++;
    }
}

int main(void)
{
    @autoreleasepool {
        PTKeyCombo *defaultCombo = [PTKeyCombo defaultHotKeyCombo];
        PTKeyCombo *commandSpace = [PTKeyCombo keyComboWithKeyCode:49 modifiers:cmdKey];
        PTKeyCombo *commandShiftSpace = [PTKeyCombo keyComboWithKeyCode:49 modifiers:(cmdKey | shiftKey)];
        PTKeyCombo *bareSpace = [PTKeyCombo keyComboWithKeyCode:49 modifiers:0];
        PTKeyCombo *functionSpace = [PTKeyCombo keyComboWithKeyCode:49 modifiers:rightControlKey];
        PTKeyCombo *commandFunctionSpace = [PTKeyCombo keyComboWithKeyCode:49 modifiers:(cmdKey | rightControlKey)];

        AssertCondition([defaultCombo keyCode] == kVK_Space, @"The first-run hot key should use Space");
        AssertCondition([defaultCombo modifiers] == optionKey, @"The first-run hot key should use Option");
        AssertCondition([defaultCombo isValidHotKeyCombo], @"The first-run hot key must be registrable");
        AssertCondition([commandSpace isValidHotKeyCombo], @"Command-Space should be a valid Carbon hot key combination");
        AssertCondition([commandShiftSpace isValidHotKeyCombo], @"Command-Shift-Space should be a valid Carbon hot key combination");
        AssertCondition(![bareSpace isValidHotKeyCombo], @"Bare Space must not be registered as a global hot key");
        AssertCondition(![functionSpace isValidHotKeyCombo], @"Fn-Space must not degrade to bare Space");
        AssertCondition(![commandFunctionSpace isValidHotKeyCombo], @"Combinations containing unsupported modifiers must be rejected");

        long functionModifier = [PTKeyBroadcaster cocoaModifiersAsCarbonModifiers:NSEventModifierFlagFunction];
        long standardModifiers = [PTKeyBroadcaster cocoaModifiersAsCarbonModifiers:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];

        AssertCondition(functionModifier == 0, @"The Cocoa Fn modifier must not be represented as Carbon right-Control");
        AssertCondition(standardModifiers == (cmdKey | optionKey), @"Supported Cocoa modifiers should retain their Carbon equivalents");
    }

    if (failureCount > 0) {
        NSLog(@"%lu hot-key test(s) failed", (unsigned long)failureCount);
        return 1;
    }

    NSLog(@"All hot-key tests passed");
    return 0;
}
