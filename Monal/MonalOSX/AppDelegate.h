//
//  AppDelegate.h
//  MonalOSX
//
//  Created by Anurodh Pokharel on 2/7/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <UIKit/UIKitView.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>


@property (nonatomic ,weak) IBOutlet UIKitView *chameleonRightView;
@property (nonatomic ,weak) IBOutlet UIKitView *chameleonLeftView;
@property (nonatomic, weak) IBOutlet NSWindow *window;

-(IBAction) showContacts:(id) sender;
-(IBAction) showChats:(id) sender;
-(IBAction) showSettings:(id) sender;
-(IBAction) showAccounts:(id) sender;
-(IBAction) showAbout:(id) sender;

@end


