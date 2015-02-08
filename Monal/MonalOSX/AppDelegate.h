//
//  AppDelegate.h
//  MonalOSX
//
//  Created by Anurodh Pokharel on 2/7/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MonalAppDelegate.h"
#import <UIKit/UIKitView.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property  (nonatomic ,strong) IBOutlet MonalAppDelegate *MonalApp;
@property  (nonatomic ,weak) IBOutlet UIKitView *chameleonNSView;
@end

