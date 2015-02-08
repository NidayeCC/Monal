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

@end
