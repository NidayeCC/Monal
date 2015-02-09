//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MonalAppDelegate.h"

#import "MLPortraitNavController.h"
#import "CallViewController.h"

// tab bar
#import "ContactsViewController.h"
#import "ActiveChatsViewController.h"
#import "SettingsViewController.h"
#import "AccountsViewController.h"
#import "ChatLogsViewController.h"
#import "GroupChatViewController.h"
#import "SearchUsersViewController.h"
#import "LogViewController.h"
#import "HelpViewController.h"
#import "AboutViewController.h"
#import "MLNotificationManager.h"

#if TARGET_OS_MAC

#elif TARGET_OS_IPHONE
#import <Crashlytics/Crashlytics.h>
#endif

//xmpp
#import "MLXMPPManager.h"

@interface MonalAppDelegate ()

@property (nonatomic, strong)  UITabBarItem* activeTab;

@property (nonatomic, strong)  UINavigationController *settingsNav;
@property (nonatomic, strong)  UINavigationController *activeChatNav;
@property (nonatomic, strong)  UINavigationController *accountsNav;
@property (nonatomic, strong)  UINavigationController *contactsNav;
@property (nonatomic, strong)  UINavigationController *aboutNav;



@end;

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@implementation MonalAppDelegate

-(void) createRootInterface
{
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showCallScreen:) name:kMonalCallStartedNotice object:nil];
    
//    self.window.screen=[UIScreen mainScreen];
    
    
//    UIButton *sillyButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
//    [sillyButton setTitle:@"Click Me!" forState:UIControlStateNormal];
//    [sillyButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
//    [sillyButton addTarget:self action:@selector(moveTheApple:) forControlEvents:UIControlEventTouchUpInside];
//    sillyButton.frame = CGRectMake(22,300,200,50);
//    [self.window addSubview:sillyButton];
//    
//    
//    [self.window makeKeyAndVisible];
//    return;
    
    _tabBarController=[[MLTabBarController alloc] init];
    ContactsViewController* contactsVC = [[ContactsViewController alloc] init];
    [MLXMPPManager sharedInstance].contactVC=contactsVC;
    contactsVC.presentationTabBarController=_tabBarController; 
    
    UIBarStyle barColor=UIBarStyleBlackOpaque;
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
         barColor=UIBarStyleDefault;
    }
    
    ActiveChatsViewController * activeChatsVC = [[ActiveChatsViewController alloc] init];
    self.activeChatNav=[[UINavigationController alloc] initWithRootViewController:activeChatsVC];
    self.activeChatNav.navigationBar.barStyle=barColor;
    self.activeChatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Active Chats",@"") image:[UIImage imageNamed:@"906-chat-3"] tag:0];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:UIApplicationWillEnterForegroundNotification object:nil];
    _activeTab=self.activeChatNav.tabBarItem;
    
    
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    self.settingsNav=[[UINavigationController alloc] initWithRootViewController:settingsVC];
    self.settingsNav.navigationBar.barStyle=barColor;
     self.settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Settings",@"") image:[UIImage imageNamed:@"740-gear"] tag:0];
    
    AccountsViewController *accountsVC = [[AccountsViewController alloc] init];
    self.accountsNav=[[UINavigationController alloc] initWithRootViewController:accountsVC];
     self.accountsNav.navigationBar.barStyle=barColor;
     self.accountsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Accounts",@"") image:[UIImage imageNamed:@"1049-at-sign"] tag:0];
    
    ChatLogsViewController* chatLogVC = [[ChatLogsViewController alloc] init];
    UINavigationController* chatLogNav=[[UINavigationController alloc] initWithRootViewController:chatLogVC];
    chatLogNav.navigationBar.barStyle=barColor;
    chatLogNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Chat Logs",@"") image:[UIImage imageNamed:@"1065-rewind-time-1"] tag:0];
    
//    SearchUsersViewController* searchUsersVC = [[SearchUsersViewController alloc] init];
//    UINavigationController* searchUsersNav=[[UINavigationController alloc] initWithRootViewController:searchUsersVC];
//    searchUsersNav.navigationBar.barStyle=barColor;
//    searchUsersNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Search Users",@"") image:[UIImage imageNamed:@"708-search"] tag:0];
//    
    GroupChatViewController* groupChatVC = [[GroupChatViewController alloc] init];
    UINavigationController* groupChatNav=[[UINavigationController alloc] initWithRootViewController:groupChatVC];
    groupChatNav.navigationBar.barStyle=barColor;
    groupChatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Group Chat",@"") image:[UIImage imageNamed:@"974-users"] tag:0];
    
    HelpViewController* helpVC = [[HelpViewController alloc] init];
    UINavigationController* helpNav=[[UINavigationController alloc] initWithRootViewController:helpVC];
    helpNav.navigationBar.barStyle=barColor;
    helpNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Help",@"") image:[UIImage imageNamed:@"739-question"] tag:0];
    
    AboutViewController *aboutVC = [[AboutViewController alloc] init];
    self.aboutNav=[[UINavigationController alloc] initWithRootViewController:aboutVC];
    self.aboutNav.navigationBar.barStyle=barColor;
    self.aboutNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"About",@"") image:[UIImage imageNamed:@"724-info"] tag:0];
    
#ifdef DEBUG
    LogViewController* logVC = [[LogViewController alloc] init];
    UINavigationController* logNav=[[UINavigationController alloc] initWithRootViewController:logVC];
    logNav.navigationBar.barStyle=barColor;
    logNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Log",@"") image:nil tag:0];
#endif
    
    
#ifdef TARGET_OS_MAC
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomDesktop  )
    {
        
       self.contactsNav=[[UINavigationController alloc] initWithRootViewController:contactsVC];
       self.contactsNav.navigationBar.barStyle=barColor;
       
       _chatNav=self.contactsNav;
       contactsVC.currentNavController=_chatNav;
    
      self.window.rootViewController=self.contactsNav;
    }
#else
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone  )
    {
        
        _chatNav=[[UINavigationController alloc] initWithRootViewController:self.contactsVC];
        _chatNav.navigationBar.barStyle=barColor;
        contactsVC.currentNavController=_chatNav;
        _chatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Contacts",@"") image:[UIImage imageNamed:@"973-user"] tag:0];
        
    
        _tabBarController.viewControllers=[NSArray arrayWithObjects:_chatNav,activeChatNav, settingsNav,  accountsNav, chatLogNav, groupChatNav, //searchUsersNav,
                                           helpNav, aboutNav,
#ifdef DEBUG
                                           logNav,
#endif
                                           nil];
        
        self.window.rootViewController=_tabBarController;
        
    }
    else
    {
        
        //this is a dummy nav controller not really used for anything
        UINavigationController* navigationControllerContacts=[[UINavigationController alloc] initWithRootViewController:contactsVC];
        navigationControllerContacts.navigationBar.barStyle=barColor;
        
        _chatNav=activeChatNav;
        contactsVC.currentNavController=_chatNav;
        _splitViewController=[[UISplitViewController alloc] init];
        self.window.rootViewController=_splitViewController;
        
        _tabBarController.viewControllers=[NSArray arrayWithObjects: activeChatNav,  settingsNav, accountsNav, chatLogNav, groupChatNav,
                                        //   searchU∫sersNav,
                                           helpNav, aboutNav,
#ifdef DEBUG
                                           logNav,
#endif
                                           nil];
        
        _splitViewController.viewControllers=[NSArray arrayWithObjects:navigationControllerContacts, _tabBarController,nil];
        _splitViewController.delegate=self;
    }
    
    _chatNav.navigationBar.barStyle=barColor;
     _tabBarController.moreNavigationController.navigationBar.barStyle=barColor;
    
#endif
    
    [self.window makeKeyAndVisible];
}


#pragma mark notification actions
-(void) showCallScreen:(NSNotification*) userInfo
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       NSDictionary* contact=userInfo.object;
                       CallViewController *callScreen= [[CallViewController alloc] initWithContact:contact];
                       MLPortraitNavController* callNav = [[MLPortraitNavController alloc] initWithRootViewController:callScreen];
                       callNav.navigationBar.hidden=YES;
                       
                       if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
                       {
                           callNav.modalPresentationStyle=UIModalPresentationFormSheet;
                       }
                       
                       [self.tabBarController presentModalViewController:callNav animated:YES];
                   });
}

-(void) updateUnread
{
    //make sure unread badge matches application badge
    
    int unread= [[DataLayer sharedInstance] countUnreadMessages];
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if(unread>0)
        {
            _activeTab.badgeValue=[NSString stringWithFormat:@"%d",unread];
            [UIApplication sharedApplication].applicationIconBadgeNumber =unread;
        }
        else
        {
            _activeTab.badgeValue=nil;
             [UIApplication sharedApplication].applicationIconBadgeNumber =0;
        }
    });
}

#pragma mark app life cycle



- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    
#ifdef  DEBUG
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    self.fileLogger.maximumFileSize=1024 * 500;
    [DDLog addLogger:self.fileLogger];
#endif
    //ios8 register for local notifications and badges
#ifdef TARGET_OS_MAC
    
#elif TARGET_OS_IPHONE
    if([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)])
    {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound|UIUserNotificationTypeBadge categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    }
#endif
    
    [self createRootInterface];

    //rating
    [Appirater setAppId:@"317711500"];
    [Appirater setDaysUntilPrompt:5];
    [Appirater setUsesUntilPrompt:10];
    [Appirater setSignificantEventsUntilPrompt:5];
    [Appirater setTimeBeforeReminding:2];
    //[Appirater setDebug:YES];
    [Appirater appLaunched:YES];
    
    [MLNotificationManager sharedInstance].window=self.window;
    
     // should any accounts connect?
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
#ifdef TARGET_OS_MAC
    
#elif TARGET_OS_IPHONE
    [Crashlytics startWithAPIKey:@"6e807cf86986312a050437809e762656b44b197c"];
#endif
  //  [Crashlytics sharedInstance].debugMode = YES;
  // [[Crashlytics sharedInstance] crash];
    
    
    //update logs if needed
    if(! [[NSUserDefaults standardUserDefaults] boolForKey:@"Logging"])
    {
        [[DataLayer sharedInstance] messageHistoryCleanAll];
    }
    return YES;
}

-(void) applicationDidBecomeActive:(UIApplication *)application
{
  //  [UIApplication sharedApplication].applicationIconBadgeNumber=0;
}

#pragma mark notifiction 
#ifdef TARGET_OS_MAC

#elif TARGET_OS_IPHONE
-(void) application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    DDLogVerbose(@"did register for local notifications");
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
  DDLogVerbose(@"entering app with %@", notification);
    
    //iphone
    //make sure tab 0
    if([notification.userInfo objectForKey:@"from"]) {
    [self.tabBarController setSelectedIndex:0];
    [[MLXMPPManager sharedInstance].contactVC presentChatWithName:[notification.userInfo objectForKey:@"from"] account:[notification.userInfo objectForKey:@"accountNo"] ];
    }
}
#endif 

#pragma mark memory
-(void) applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    [[MLImageManager sharedInstance] purgeCache];
}

#pragma mark backgrounding
- (void)applicationWillEnterForeground:(UIApplication *)application
{
      DDLogVerbose(@"Entering FG");
    [[MLXMPPManager sharedInstance] clearKeepAlive];
    [[MLXMPPManager sharedInstance] resetForeground];
}

-(void) applicationDidEnterBackground:(UIApplication *)application
{
    UIApplicationState state = [application applicationState];
    if (state == UIApplicationStateInactive) {
        DDLogVerbose(@"Screen lock");
    } else if (state == UIApplicationStateBackground) {
        DDLogVerbose(@"Entering BG");
    }
    
    [[MLXMPPManager sharedInstance] setKeepAlivetimer];
}

-(void)applicationWillTerminate:(UIApplication *)application
{
    
       [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark splitview controller delegate
- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return NO;
}

#pragma mark OSX hooks
-(IBAction) showContacts:(id) sender
{
     self.window.rootViewController=self.contactsNav;
}

-(IBAction) showChats:(id) sender
{
     self.window.rootViewController=self.activeChatNav;
}

-(IBAction) showSettings:(id) sender{
     self.window.rootViewController=self.settingsNav;
}

-(IBAction) showAccounts:(id) sender
{
     self.window.rootViewController=self.accountsNav;
}

-(IBAction) showAbout:(id) sender
{
     self.window.rootViewController=self.aboutNav;
}

@end

