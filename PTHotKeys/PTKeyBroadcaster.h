//
//  PTKeyBroadcaster.h
//  Protein
//
//  Created by Quentin Carnicelli on Sun Aug 03 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//

#import <AppKit/AppKit.h>


@interface PTKeyBroadcaster : NSButton
{
}

+ (long)cocoaModifiersAsCarbonModifiers: (long)cocoaModifiers;

@end

FOUNDATION_EXPORT NSString * const PTKeyBroadcasterKeyEvent; //keys: keyCombo as PTKeyCombo
