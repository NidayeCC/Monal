//
//  AppDelegate.m
//  MonalOSX
//
//  Created by Anurodh Pokharel on 2/7/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "AppDelegate.h"
#import "MonalAppDelegate.h"

@interface AppDelegate ()

@property  (nonatomic ,strong)  MonalAppDelegate *MonalApp;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    self.MonalApp = [[MonalAppDelegate alloc] init];
    [self.chameleonLeftView launchApplicationWithDelegate:self.MonalApp afterDelay:0];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

-(IBAction) showContacts:(id) sender
{
    [self.MonalApp showContacts:sender];
}

-(IBAction) showChats:(id) sender
{
    [self.MonalApp showChats:sender];
}

-(IBAction) showSettings:(id) sender{
    [self.MonalApp showSettings:sender];
    
}

-(IBAction) showAccounts:(id) sender
{
    [self.MonalApp showAccounts:sender];
}

-(IBAction) showAbout:(id) sender
{
     [self.MonalApp showAbout:sender];
}

@end
