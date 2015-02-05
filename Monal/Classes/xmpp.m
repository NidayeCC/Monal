//
//  xmpp.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <CommonCrypto/CommonCrypto.h>
#import <CFNetwork/CFSocketStream.h>
#import "xmpp.h"
#import "DataLayer.h"
#import "EncodingTools.h"
#import "MLXMPPManager.h"

//objects
#import "XMPPIQ.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"

//parsers
#import "ParseFeatures.h"
#import "ParseIq.h"
#import "ParsePresence.h"
#import "ParseMessage.h"
#import "ParseChallenge.h"
#import "ParseFailure.h"
#import "ParseEnabled.h"
#import "ParseA.h"
#import "ParseResumed.h"
#import "ParseSuccess.h"
#import "ParseProceed.h"

#import "MLImageManager.h"
#import "UIAlertView+Blocks.h"

#define kConnectTimeout 20ull //seconds

NSString *const kMessageId=@"MessageID";
NSString *const kSendTimer=@"SendTimer";

NSString *const kStanzaID=@"stanzaID";
NSString *const kStanza=@"stanza";

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@interface xmpp()
{
    BOOL _loginStarted;
    BOOL _reconnectScheduled;
}

@property (nonatomic, strong) NSXMLParser *parser;
@property (nonatomic, strong) XMPPParser *xmppParser;

@property (nonatomic, strong) NSString *pingID;
@property (nonatomic, strong) NSOperationQueue *readQueue;
@property (nonatomic, strong) NSOperationQueue *writeQueue;

//stream resumption
@property (nonatomic, assign) BOOL supportsSM2;
@property (nonatomic, assign) BOOL supportsSM3;

@property (nonatomic, assign) BOOL supportsResume;
@property (nonatomic, strong) NSString *streamID;

//carbons
@property (nonatomic, assign) BOOL usingCarbons2;

//server details
@property (nonatomic, strong) NSSet *serverFeatures;

/**
 h to go out in r stanza
 */
@property (nonatomic, strong) NSNumber *lastHandledInboundStanza;

/**
 h from a stanza
 */
@property (nonatomic, strong) NSNumber *lastHandledOutboundStanza;

/**
 internal counter that should match lastHandledOutboundStanza
 */
@property (nonatomic, strong) NSNumber *lastOutboundStanza;

/**
 Array of NSdic with stanzas that have not been acked.
 NSDic {stanzaID, stanza}
 */
@property (nonatomic, strong) NSMutableArray *unAckedStanzas;

@property (nonatomic, strong) NSArray* stanzaTypes;


@end



@implementation xmpp

-(id) init
{
    self=[super init];
    _accountState = kStateLoggedOut;
    
    _discoveredServerList=[[NSMutableArray alloc] init];
  
    _outputQueue=[[NSMutableArray alloc] init];
    _port=5552;
    _SSL=YES;
    _oldStyleSSL=NO;
    int r =  arc4random();
    _resource=[NSString stringWithFormat:@"Monal%d",r];
    
    self.readQueue =[[NSOperationQueue alloc] init];
    self.writeQueue =[[NSOperationQueue alloc] init];
    self.readQueue.maxConcurrentOperationCount=1;
    self.writeQueue.maxConcurrentOperationCount=1;
    
    //more frequent on top to end iteration quickly
    self.stanzaTypes=[NSArray arrayWithObjects:
                      @"iq",
                      @"r",
                      @"a",
                      @"message",
                      @"presence",
                      @"error",
                      @"stream",
                      @"features",
                      @"proceed",
                      @"failure",
                      @"challenge",
                      @"response",
                      @"success",
                      @"enabled",
                      @"resumed",
                      @"failed",
                      nil];
    
    _versionHash=[self getVersionString];
    return self;
}

-(void)dealloc
{
    
}

-(void) setRunLoop
{
    dispatch_async(dispatch_get_current_queue(), ^{
        [_oStream setDelegate:self];
        [_oStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [[NSRunLoop currentRunLoop]run];
    });
}

-(void) createStreams
{
    
    NSDictionary* info=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                         kinfoTypeKey:@"connect", kinfoStatusKey:@"Opening Connection"};
    [self.contactsVC showConnecting:info];
    
    CFReadStreamRef readRef= NULL;
    CFWriteStreamRef writeRef= NULL;
    
    DDLogInfo(@"stream  creating to  server: %@ port: %d", _server, _port);
    
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)_server, _port, &readRef, &writeRef);
    
    _iStream= (__bridge NSInputStream*)readRef;
    _oStream= (__bridge NSOutputStream*) writeRef;
    
    if((_iStream==nil) || (_oStream==nil))
    {
        DDLogError(@"Connection failed");
        return;
    }
    else
        DDLogInfo(@"streams created ok");
    
    if((CFReadStreamSetProperty((__bridge CFReadStreamRef)_iStream,
                                kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP))
       //       &&
       //       (CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_oStream,
       //                                 kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP))
       )
    {
        DDLogInfo(@"Set VOIP properties on streams.");
    }
    else
    {
        DDLogInfo(@"could not set VOIP properties on streams.");
    }
    
    if((_SSL==YES)  && (_oldStyleSSL==YES))
    {
        // do ssl stuff here
        DDLogInfo(@"securing connection.. for old style");
        
        NSMutableDictionary *settings = [ [NSMutableDictionary alloc ]
                                         initWithObjectsAndKeys:
                                         [NSNull null],kCFStreamSSLPeerName,
                                         kCFStreamSocketSecurityLevelNegotiatedSSL,
                                         kCFStreamSSLLevel,
                                         nil ];
        
        if(self.selfSigned)
        {
            NSDictionary* secureOFF= [ [NSDictionary alloc ]
                                      initWithObjectsAndKeys:
                                      [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
                                      [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
                                      [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
                                      [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain, nil];
            
            [settings addEntriesFromDictionary:secureOFF];
            
            
            
        }
        
        
        CFReadStreamSetProperty((__bridge CFReadStreamRef)_iStream,
                                kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings);
        CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_oStream,
                                 kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings);
        
        DDLogInfo(@"connection secured");
    }
    

    
    XMLNode* xmlOpening = [[XMLNode alloc] initWithElement:@"xml"];
    [self send:xmlOpening];
    [self startStream];
    [self setRunLoop];
  
    
    
    
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t streamTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,q_background
                                                           );
    
    dispatch_source_set_timer(streamTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_SEC),
                              1ull * NSEC_PER_SEC
                              , 1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(streamTimer, ^{
        DDLogError(@"stream connection timed out");
        dispatch_source_cancel(streamTimer);
        [self disconnect];
    });
    
    dispatch_source_set_cancel_handler(streamTimer, ^{
        DDLogError(@"stream timer cancelled");
    });
    
    dispatch_resume(streamTimer);
    
    
    [_iStream open];
    [_oStream open];
    
    NSDictionary* info2=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                          kinfoTypeKey:@"connect", kinfoStatusKey:@"Logging in"};
    [self.contactsVC updateConnecting:info2];
    
    dispatch_source_cancel(streamTimer);
    
    
}

-(void) connectionTask
{
    if(_xmppQueue==NULL) {
        _xmppQueue=dispatch_get_current_queue();
    }
    if([_domain length]>0) {
        _fulluser=[NSString stringWithFormat:@"%@@%@", _username, _domain];
    }
    else {
        _fulluser=_username;
    }
    
    if(_oldStyleSSL==NO) {
        // do DNS discovery if it hasn't already been set
        if([_discoveredServerList count]==0) {
            [self dnsDiscover];
        }
    }
    
    if([_discoveredServerList count]>0) {
        //sort by priority
        NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"priority"  ascending:YES];
        NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
        [_discoveredServerList sortUsingDescriptors:sortArray];
        
        // take the top one
        _server=[[_discoveredServerList objectAtIndex:0] objectForKey:@"server"];
        _port=[[[_discoveredServerList objectAtIndex:0] objectForKey:@"port"] integerValue];
    }
    
    [self createStreams];
}


-(void) connect
{
    [self.readQueue cancelAllOperations];
    [self.writeQueue cancelAllOperations];
    if(self.explicitLogout) return;
    if(self.accountState==kStateLoggedIn )
    {
        DDLogError(@"assymetrical call to login without a teardown loggedin");
        return;
    }
    
    self.pingID=nil;
    
    DDLogInfo(@"XMPP connnect  start");
    [self connectionTask];
    
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t loginCancelOperation = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                                    q_background);
    
    dispatch_source_set_timer(loginCancelOperation,
                              dispatch_time(DISPATCH_TIME_NOW, kConnectTimeout* NSEC_PER_SEC),
                              kConnectTimeout* NSEC_PER_SEC,
                              1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(loginCancelOperation, ^{
        DDLogInfo(@"login cancel op");
        dispatch_async(_xmppQueue, ^{
            //hide connecting message
            if(_fulluser && _accountNo) {
                NSDictionary* info=@{kaccountNameKey:_fulluser, kaccountNoKey:self.accountNo,
                                     kinfoTypeKey:@"connect", kinfoStatusKey:@""};
                [self.contactsVC hideConnecting:info];
            }
            _loginStarted=NO;
            // try again
            if((self.accountState<kStateHasStream) && (_loggedInOnce))
            {
                DDLogInfo(@"trying to login again");
                //make sure we are enabled still.
                if([[DataLayer sharedInstance] isAccountEnabled:[NSString stringWithFormat:@"%@",self.accountNo]]) {
                    
                    //temp background task while a new one is created
                    __block UIBackgroundTaskIdentifier tempTask= [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
                        [[UIApplication sharedApplication] endBackgroundTask:tempTask];
                        tempTask=UIBackgroundTaskInvalid;
                    }];
                    [self reconnect];
                    
                    [[UIApplication sharedApplication] endBackgroundTask:tempTask];
                    tempTask=UIBackgroundTaskInvalid;
                    
                }
            }
            else if (self.accountState==kStateLoggedIn ) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kMLHasConnectedNotice object:nil];
            }
            else {
                DDLogInfo(@"failed to login and not retrying");
            }
            
        });
        
        dispatch_source_cancel(loginCancelOperation);
        
    });
    
    dispatch_source_set_cancel_handler(loginCancelOperation, ^{
        DDLogInfo(@"login timer cancelled");
        if(self.accountState<kStateHasStream)
        {
            if(!_reconnectScheduled)
            {
                _loginStarted=NO;
                DDLogInfo(@"login client does not have stream");
                _accountState=kStateReconnecting;
                [self reconnect];
            }
        }
    });
    
    dispatch_resume(loginCancelOperation);
    
}

-(void) disconnect
{
    if(self.explicitLogout)
    {
        XMLNode* stream = [[XMLNode alloc] init];
        stream.element=@"/stream:stream"; //hack to close stream
        [self send:stream];
        self.streamID=nil;
        self.unAckedStanzas=nil;
    }
    
    if(kStateDisconnected) return;
    [self.readQueue cancelAllOperations];
    [self.writeQueue cancelAllOperations];
    
    self.pingID=nil;
    DDLogInfo(@"removing streams");
    
    //prevent any new read or write
    [_iStream setDelegate:nil];
    [_oStream setDelegate:nil];
    
    [_oStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                        forMode:NSDefaultRunLoopMode];
    
    [_iStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                        forMode:NSDefaultRunLoopMode];
    DDLogInfo(@"removed streams");
    
    
    [self.readQueue addOperation:
     [NSBlockOperation blockOperationWithBlock:^{
        
        @try
        {
            [_iStream close];
           
        }
        @catch(id theException)
        {
            DDLogError(@"Exception in istream close");
        }
    }]];
    
    [self.writeQueue addOperation:
     [NSBlockOperation blockOperationWithBlock:^{
        
       	@try
        {
            [_oStream close];
            _outputQueue=[[NSMutableArray alloc] init];
        }
        @catch(id theException)
        {
            DDLogError(@"Exception in ostream close");
        }
        
    }]];
    
    
    [_contactsVC clearContactsForAccount:_accountNo];
    [[DataLayer sharedInstance] resetContactsForAccount:_accountNo];
    
    DDLogInfo(@"Connections closed");
    
    _startTLSComplete=NO;
    _streamHasSpace=NO;
    _loginStarted=NO;
    _loginError=NO;
    _accountState=kStateDisconnected;
    
    DDLogInfo(@"All closed and cleaned up");
    
    
    
    //for good measure
    NSString* user=_fulluser;
    if(!_fulluser) {
        user=@"";
    }
    NSDictionary* info=@{kaccountNameKey:user, kaccountNoKey:_accountNo,
                         kinfoTypeKey:@"connect", kinfoStatusKey:@""};
    [self.contactsVC hideConnecting:info];
    
    NSDictionary* info2=@{kaccountNameKey:user, kaccountNoKey:_accountNo,
                          kinfoTypeKey:@"connect", kinfoStatusKey:@"Disconnected"};
    
    
    if(!_loggedInOnce)
    {
        info2=@{kaccountNameKey:user, kaccountNoKey:_accountNo,
                kinfoTypeKey:@"connect", kinfoStatusKey:@"Could not login."};
    }
    
    [self.contactsVC showConnecting:info2];
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3ull * NSEC_PER_SEC), q_background,  ^{
        [self.contactsVC hideConnecting:info2];
    });
    
    
    [[DataLayer sharedInstance]  resetContactsForAccount:_accountNo];
    _reconnectScheduled =NO;
}
-(void) reconnect
{
    [self reconnect:5.0];
}

-(void) reconnect:(NSInteger) scheduleWait
{
    DDLogVerbose(@"reconnecting ");
    //can be called multiple times
    
    if(_loginStarted) {
        DDLogVerbose(@"reconnect called while one already in progress. Stopping.");
        return;
    }
    _loginStarted=YES;
    
    __block UIBackgroundTaskIdentifier reconnectBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
        
        if((([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
            || ([UIApplication sharedApplication].applicationState==UIApplicationStateInactive )) && _accountState<kStateHasStream)
        {
            //present notification
            
            NSDate* theDate=[NSDate dateWithTimeIntervalSinceNow:0]; //immediate fire
            
            UIApplication* app = [UIApplication sharedApplication];
            
            // Create a new notification
            UILocalNotification* alarm = [[UILocalNotification alloc] init];
            if (alarm)
            {
                if(!_hasShownAlert) {
                    _hasShownAlert=YES;
                    //scehdule info
                    alarm.fireDate = theDate;
                    alarm.timeZone = [NSTimeZone defaultTimeZone];
                    alarm.repeatInterval = 0;
                    alarm.alertBody =  @"Lost connection for too long and could not reliably reconnect. Please reopen and make sure you are connected";
                    
                    [app scheduleLocalNotification:alarm];
                    
                    DDLogVerbose(@"Scheduled local disconnect alert ");
                    [self disconnect];
                }
                
            }
        }
        
        DDLogVerbose(@"Reconnect bgtask took too long. closing");
        [[UIApplication sharedApplication] endBackgroundTask:reconnectBackgroundTask];
        reconnectBackgroundTask=UIBackgroundTaskInvalid;
        
    }];
    
    if (reconnectBackgroundTask != UIBackgroundTaskInvalid) {
        if(_accountState>=kStateReconnecting) {
            DDLogInfo(@" account sate >=reconencting, disconnecting first" );
            [self disconnect];
            _loginStarted=YES;
        }
        
        NSTimeInterval wait=scheduleWait;
        if(!_loggedInOnce) {
            wait=0;
        }
        
        if(!_reconnectScheduled)
        {
            _reconnectScheduled=YES;
            DDLogInfo(@"Trying to connect again in %f seconds. ", wait);
            dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, wait * NSEC_PER_SEC), q_background,  ^{
                //there may be another login operation freom reachability or another timer
                if(self.accountState<kStateReconnecting) {
                    [self connect];
                    [[UIApplication sharedApplication] endBackgroundTask:reconnectBackgroundTask];
                    reconnectBackgroundTask=UIBackgroundTaskInvalid;
                }
            });
        } else  {
            DDLogInfo(@"reconnect scheduled already" );
        }
    }
    
}

#pragma mark XMPP

-(void) startStream
{
    [self.readQueue addOperation:
     [NSBlockOperation blockOperationWithBlock:^{
        //flush input to restart
        self.parser =[[NSXMLParser alloc] initWithStream:_iStream];
        [self.parser setShouldProcessNamespaces:YES];
        [self.parser setShouldReportNamespacePrefixes:YES];
        [self.parser setShouldResolveExternalEntities:NO];

        self.parser.delegate=self;
        
        dispatch_async(_xmppQueue, ^{
            [self.parser parse];
        });
       
    
        XMLNode* stream = [[XMLNode alloc] init];
        stream.element=@"stream:stream";
        [stream.attributes setObject:@"jabber:client" forKey:@"xmlns"];
        [stream.attributes setObject:@"http://etherx.jabber.org/streams" forKey:@"xmlns:stream"];
        [stream.attributes setObject:@"1.0" forKey:@"version"];
        if(_domain)
            [stream.attributes setObject:_domain forKey:@"to"];
        [self send:stream];
    }]];
}


-(void) sendPing
{
    if(self.accountState<kStateReconnecting  && !_reconnectScheduled)
    {
        DDLogInfo(@" ping calling reconnect");
        _accountState=kStateReconnecting;
        [self reconnect:0];
        return;
    }
    
    if(self.accountState<kStateLoggedIn)
    {
        DDLogInfo(@"ping attempt before logged in. returning.");
        return;
    }
    
    if(self.supportsSM3 && self.unAckedStanzas)
    {
        XMLNode* rNode =[[XMLNode alloc] initWithElement:@"r"];
        NSDictionary *dic=@{@"xmlns":@"urn:xmpp:sm:3"};
        rNode.attributes =[dic mutableCopy];
        [self send:rNode];
    }
    else  {
        //get random number
        self.pingID=[NSString stringWithFormat:@"Monal%d",arc4random()%100000];
        
        dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_source_t pingTimeOut = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                               q_background);
        
        dispatch_source_set_timer(pingTimeOut,
                                  dispatch_time(DISPATCH_TIME_NOW, kConnectTimeout* NSEC_PER_SEC),
                                  kConnectTimeout* NSEC_PER_SEC,
                                  1ull * NSEC_PER_SEC);
        
        dispatch_source_set_event_handler(pingTimeOut, ^{
            
            if(self.pingID)
            {
                DDLogVerbose(@"ping timed out without a reply to %@",self.pingID);
                _accountState=kStateReconnecting;
                [self reconnect];
            }
            else
            {
                DDLogVerbose(@"ping reply was seen");
                
            }
            
            dispatch_source_cancel(pingTimeOut);
            
        });
        
        dispatch_source_set_cancel_handler(pingTimeOut, ^{
            DDLogInfo(@"ping timer cancelled");
        });
        
        dispatch_resume(pingTimeOut);
        
        
        XMPPIQ* ping =[[XMPPIQ alloc] initWithId:self.pingID andType:kiqGetType];
        [ping setiqTo:_domain];
        [ping setPing];
        [self send:ping];
    }
    
    
}

-(void) sendWhiteSpacePing
{
    if(self.accountState<kStateReconnecting  )
    {
        DDLogInfo(@" whitespace ping calling reconnect");
        _accountState=kStateReconnecting;
        [self reconnect:0];
        return;
    }
    
    XMLNode* ping =[[XMLNode alloc] initWithElement:@"whitePing"]; // no such element. Node has logic to  print white space
    [self send:ping];
}





#pragma mark message ACK
-(void) sendUnAckedMessages
{
    for (NSDictionary *dic in self.unAckedStanzas)
    {
        [self send:(XMLNode*)[dic objectForKey:kStanza]];
    }
}

-(void) removeUnAckedMessagesLessThan:(NSNumber*) hvalue
{
    NSMutableArray *discard =[[NSMutableArray alloc] initWithCapacity:[self.unAckedStanzas count]];
    for (NSDictionary *dic in self.unAckedStanzas)
    {
        NSNumber *stanzaNumber = [dic objectForKey:kStanzaID];
        if([stanzaNumber integerValue]<[hvalue integerValue])
        {
            [discard addObject:dic];
        }
    }
    
    [self.unAckedStanzas removeObjectsInArray:discard];
}


#pragma mark NSXMLParser delegate
- (void)parserDidStartDocument:(NSXMLParser *)parser{
    DDLogVerbose(@"parsing start");
    
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    DDLogVerbose(@"began element %@ with attributes %@",elementName, attributeDict );
    for (NSString *stanza in self.stanzaTypes){
    //determine element
        if([stanza isEqualToString:elementName]){
            //create correct xmpp parser
            NSString *parserName = [NSString stringWithFormat:@"Parse%@",[stanza capitalizedString]];
            self.xmppParser=[[NSClassFromString(parserName) alloc] init];
            if(!self.xmppParser) self.xmppParser =[[XMPPParser alloc] init]; // for unimplemented 
            //call delegate functions on that
            [self.xmppParser parser:parser didStartElement:elementName namespaceURI:namespaceURI qualifiedName:qName attributes:attributeDict];
            break;
        }
    }
}

-(void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    [self.xmppParser parser:parser didEndElement:elementName namespaceURI:namespaceURI qualifiedName:qName];
    // if it is a trcked stanza call process
    for (NSString *stanza in self.stanzaTypes){
        if([stanza isEqualToString:elementName]){
            //call process stanza
            XMPPParser *toProcess=self.xmppParser;
            dispatch_async(_xmppQueue, ^{
                [self processInput:toProcess];
            });
            self.xmppParser=nil;
            break;
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    [self.xmppParser parser:parser foundCharacters:string];
}

- (void)parser:(NSXMLParser *)parser foundIgnorableWhitespace:(NSString *)whitespaceString
{
    [self.xmppParser parser:parser foundIgnorableWhitespace:whitespaceString];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    DDLogVerbose(@"Error: line: %d , col: %d desc: %@ ",[parser lineNumber],
                 [parser columnNumber], [parseError localizedDescription]);
    
}

#pragma mark stanza handling
-(void) processInput:(XMPPParser *)toProcess
{
    //prevent reconnect attempt
    if(_accountState<kStateHasStream) _accountState=kStateHasStream;
    
    self.lastHandledInboundStanza=[NSNumber numberWithInteger: [self.lastHandledInboundStanza integerValue]+1];
  
    if([toProcess.stanzaType isEqualToString:@"iq"])
    {
        ParseIq* iqNode=  (ParseIq*) toProcess;
        if ([iqNode.type isEqualToString:kiqErrorType])
        {
            return;
        }
        
        if(iqNode.features && iqNode.discoInfo) {
            self.serverFeatures=[iqNode.features copy];
            
            if([self.serverFeatures containsObject:@"urn:xmpp:carbons:2"])
            {
                XMPPIQ* carbons =[[XMPPIQ alloc] initWithId:@"enableCarbons" andType:kiqSetType];
                XMLNode *enable =[[XMLNode alloc] initWithElement:@"enable"];
                [enable setXMLNS:@"urn:xmpp:carbons:2"];
                [carbons.children addObject:enable];
                [self send:carbons];
            }
        }
        
        if(iqNode.legacyAuth)
        {
            XMPPIQ* auth =[[XMPPIQ alloc] initWithId:@"auth2" andType:kiqSetType];
            [auth setAuthWithUserName:self.username resource:self.resource andPassword:self.password];
            [self send:auth];
        }
        
        if(iqNode.shouldSetBind)
        {
            _jid=iqNode.jid;
            DDLogVerbose(@"Set jid %@", _jid);
            
            XMPPIQ* sessionQuery= [[XMPPIQ alloc] initWithId:_sessionKey andType:kiqSetType];
            XMLNode* session = [[XMLNode alloc] initWithElement:@"session"];
            [session setXMLNS:@"urn:ietf:params:xml:ns:xmpp-session"];
            [sessionQuery.children addObject:session];
            [self send:sessionQuery];
            
            XMPPIQ* discoItems =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
            [discoItems setiqTo:_domain];
            XMLNode* items = [[XMLNode alloc] initWithElement:@"query"];
            [items setXMLNS:@"http://jabber.org/protocol/disco#items"];
            [discoItems.children addObject:items];
            [self send:discoItems];
            
            XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
            [discoInfo setiqTo:_domain];
            [discoInfo setDiscoInfoNode];
            [self send:discoInfo];
            
            
            //no need to pull roster on every call if disconenct
            if(!_rosterList)
            {
                XMPPIQ* roster =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
                [roster setRosterRequest];
                [self send:roster];
            }
            
            self.priority= [[[NSUserDefaults standardUserDefaults] stringForKey:@"XMPPPriority"] integerValue];
            self.statusMessage=[[NSUserDefaults standardUserDefaults] stringForKey:@"StatusMessage"];
            self.awayState=[[NSUserDefaults standardUserDefaults] boolForKey:@"Away"];
            self.visibleState=[[NSUserDefaults standardUserDefaults] boolForKey:@"Visible"];
            
            XMPPPresence* presence =[[XMPPPresence alloc] initWithHash:_versionHash];
            [presence setPriority:self.priority];
            if(self.statusMessage) [presence setStatus:self.statusMessage];
            if(self.awayState) [presence setAway];
            if(!self.visibleState) [presence setInvisible];
            
            [self send:presence];
            
        }
        
        if((iqNode.discoInfo) && [iqNode.type isEqualToString:kiqGetType])
        {
            XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
            [discoInfo setiqTo:iqNode.from];
            [discoInfo setDiscoInfoWithFeaturesAndNode:iqNode.queryNode];
            [self send:discoInfo];
            
        }
        
        if(iqNode.vCard)
        {
            NSString* fullname=iqNode.fullName;
            if(iqNode.fullName)
            {
                [[DataLayer sharedInstance] setFullName:iqNode.fullName forBuddy:iqNode.user andAccount:_accountNo];
            }
            
            if(iqNode.photoBinValue)
            {
                [[MLImageManager sharedInstance] setIconForContact:iqNode.user andAccount:_accountNo WithData:iqNode.photoBinValue ];
            }
            
            if(!fullname) fullname=iqNode.user;
            
            NSDictionary* userDic=@{kusernameKey: iqNode.user,
                                    kfullNameKey: fullname,
                                    kaccountNoKey:_accountNo
                                    };
            
            dispatch_async(_xmppQueue, ^{
                [self.contactsVC addOnlineUser:userDic];
            });
            
        }
        
        if(iqNode.ping)
        {
            XMPPIQ* pong =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
            [pong setiqTo:_domain];
            [self send:pong];
        }
        
        if([iqNode.idval isEqualToString:self.pingID])
        {
            //response to my ping
            self.pingID=nil;
        }
        
        if (iqNode.version)
        {
            XMPPIQ* versioniq =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
            [versioniq setiqTo:iqNode.from];
            [versioniq setVersion];
            [self send:versioniq];
        }
        
        if (iqNode.last)
        {
            XMPPIQ* lastiq =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
            [lastiq setiqTo:iqNode.from];
            [lastiq setLast];
            [self send:lastiq];
        }
        
        if (iqNode.time)
        {
            XMPPIQ* timeiq =[[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
            [timeiq setiqTo:iqNode.from];
            //[lastiq setLast];
            [self send:timeiq];
        }
        
        
        if ([iqNode.type isEqualToString:kiqResultType])
        {
            if([iqNode.idval isEqualToString:@"enableCarbons"])
            {
                self.usingCarbons2=YES;
            }
            
            if(iqNode.discoItems==YES)
            {
                if([iqNode.from isEqualToString:self.server] || [iqNode.from isEqualToString:self.domain])
                {
                    for (NSDictionary* item in iqNode.items)
                    {
                        if(!_discoveredServices) _discoveredServices=[[NSMutableArray alloc] init];
                        [_discoveredServices addObject:item];
                    }
                }
                else
                {
                    
                }
            }
            else if (iqNode.roster==YES)
            {
                self.rosterList=iqNode.items;
                
                for(NSDictionary* contact in self.rosterList)
                {
                    
                    if([[contact objectForKey:@"subscription"] isEqualToString:@"both"])
                    {
                        if(![[DataLayer sharedInstance] isBuddyInList:[contact objectForKey:@"jid"] forAccount:_accountNo])
                        {
                            [[DataLayer sharedInstance] addBuddy:[contact objectForKey:@"jid"]?[contact objectForKey:@"jid"]:@"" forAccount:_accountNo fullname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@"" nickname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""];
                        }
                        else
                        {
                            // update info if needed
                            
                            [[DataLayer sharedInstance] setFullName:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@"" forBuddy:[contact objectForKey:@"jid"]?[contact objectForKey:@"jid"]:@"" andAccount:_accountNo ] ;
                            
                        }
                    }
                    else
                    {
                        
                    }
                }
                
            }
            
            //confirmation of set call after we accepted
            if([iqNode.idval isEqualToString:self.jingle.idval])
            {
                NSArray* nameParts= [iqNode.from componentsSeparatedByString:@"/"];
                NSString* from;
                if([nameParts count]>1) {
                    from=[nameParts objectAtIndex:0];
                } else from = iqNode.from;
                
                NSString* fullName;
                fullName=[[DataLayer sharedInstance] fullName:from forAccount:_accountNo];
                if(!fullName) fullName=from;
                
                NSDictionary* userDic=@{@"buddy_name":from,
                                        @"full_name":fullName,
                                        @"account_id":_accountNo
                                        };
                
                [[NSNotificationCenter defaultCenter]
                 postNotificationName: kMonalCallStartedNotice object: userDic];
                
                
                [self.jingle rtpConnect];
                return;
            }
            
        }
        
        
        if ([iqNode.type isEqualToString:kiqSetType]) {
            if(iqNode.jingleSession) {
                
                //accpetance of our call
                if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-accept"] &&
                   [[iqNode.jingleSession objectForKey:@"sid"] isEqualToString:self.jingle.thesid])
                {
                    
                    NSDictionary* transport1;
                    NSDictionary* transport2;
                    for(NSDictionary* candidate in iqNode.jingleTransportCandidates) {
                        if([[candidate objectForKey:@"component"] isEqualToString:@"1"]) {
                            transport1=candidate;
                        }
                        if([[candidate objectForKey:@"component"] isEqualToString:@"2"]) {
                            transport2=candidate;
                        }
                    }
                    
                    NSDictionary* pcmaPayload;
                    for(NSDictionary* payload in iqNode.jinglePayloadTypes) {
                        if([[payload objectForKey:@"name"] isEqualToString:@"PCMA"]) {
                            pcmaPayload=payload;
                            break;
                        }
                    }
                    
                    if (pcmaPayload && transport1) {
                        self.jingle.recipientIP=[transport1 objectForKey:@"ip"];
                        self.jingle.destinationPort= [transport1 objectForKey:@"port"];
                        
                        XMPPIQ* node = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                        [node setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user,iqNode.resource]];
                        [self send:node];
                        
                        [self.jingle rtpConnect];
                    }
                    return;
                }
                
                if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-terminate"] &&  [[iqNode.jingleSession objectForKey:@"sid"] isEqualToString:self.jingle.thesid]) {
                    XMPPIQ* node = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                    [node setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user,iqNode.resource]];
                    [self send:node];
                    [self.jingle rtpDisconnect];
                }
                
                if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-initiate"]) {
                    NSDictionary* pcmaPayload;
                    for(NSDictionary* payload in iqNode.jinglePayloadTypes) {
                        if([[payload objectForKey:@"name"] isEqualToString:@"PCMA"]) {
                            pcmaPayload=payload;
                            break;
                        }
                    }
                    
                    NSDictionary* transport1;
                    NSDictionary* transport2;
                    for(NSDictionary* candidate in iqNode.jingleTransportCandidates) {
                        if([[candidate objectForKey:@"component"] isEqualToString:@"1"]) {
                            transport1=candidate;
                        }
                        if([[candidate objectForKey:@"component"] isEqualToString:@"2"]) {
                            transport2=candidate;
                        }
                    }
                    
                    if (pcmaPayload && transport1) {
                        self.jingle = [[jingleCall alloc] init];
                        self.jingle.initiator= [iqNode.jingleSession objectForKey:@"initiator"];
                        self.jingle.responder= [iqNode.jingleSession objectForKey:@"responder"];
                        self.jingle.thesid= [iqNode.jingleSession objectForKey:@"sid"];
                        self.jingle.destinationPort= [transport1 objectForKey:@"port"];
                        self.jingle.idval=iqNode.idval;
                        if(transport2) {
                            self.jingle.destinationPort2= [transport2 objectForKey:@"port"];
                        }
                        else {
                            self.jingle.destinationPort2=[transport1 objectForKey:@"port"]; // if nothing is provided just reuse..
                        }
                        self.jingle.recipientIP=[transport1 objectForKey:@"ip"];
                        
                        
                        if(iqNode.user && iqNode.resource) {
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                
                                NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"Incoming Call From %@?", nil), iqNode.from ];
                                RIButtonItem* cancelButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Decline", nil) action:^{
                                    XMPPIQ* node =[self.jingle rejectJingleTo:iqNode.user withId:iqNode.idval andResource:iqNode.resource];
                                    [self send:node];
                                    self.jingle=nil;
                                }];
                                
                                RIButtonItem* yesButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Accept Call", nil) action:^{
                                    
                                    XMPPIQ* node =[self.jingle acceptJingleTo:iqNode.user withId:iqNode.idval andResource:iqNode.resource];
                                    [self send:node];
                                }];
                                
                                UIAlertView* alert =[[UIAlertView alloc] initWithTitle:@"Audio Call" message:messageString cancelButtonItem:cancelButton otherButtonItems:yesButton, nil];
                                [alert show];
                            } );
                            
                            
                        }
                    }
                    else {
                        //does not support the same formats
                    }
                    
                }
            }
        }
        
        //*** MUC related
        if(iqNode.conferenceServer)
        {
            _conferenceServer=iqNode.conferenceServer;
        }
        
        if([iqNode.from isEqualToString:_conferenceServer] && iqNode.discoItems)
        {
            _roomList=iqNode.items;
            [[NSNotificationCenter defaultCenter]
             postNotificationName: kMLHasRoomsNotice object: self];
        }
        
        
    }
    else  if([toProcess.stanzaType  isEqualToString:@"message"])
    {
        ParseMessage* messageNode= (ParseMessage*) toProcess;
        if([messageNode.type isEqualToString:kMessageErrorType])
        {
            //TODO: mark message as error
            return;
        }
        
        
        if(messageNode.mucInvite)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"You have been invited to a conversation %@?", nil), messageNode.from ];
                RIButtonItem* cancelButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Cancel", nil) action:^{
                    
                }];
                
                RIButtonItem* yesButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Join", nil) action:^{
                    
                    [self joinRoom:messageNode.from withPassword:nil];
                }];
                
                UIAlertView* alert =[[UIAlertView alloc] initWithTitle:@"Chat Invite" message:messageString cancelButtonItem:cancelButton otherButtonItems:yesButton, nil];
                [alert show];
            });
            
        }
        
        if(messageNode.hasBody)
        {
            if ([messageNode.type isEqualToString:kMessageGroupChatType]
                && [messageNode.actualFrom isEqualToString:_username])
            {
                //this is just a muc echo
            }
            else
            {
                [[DataLayer sharedInstance] addMessageFrom:messageNode.from to:_fulluser
                                                forAccount:_accountNo withBody:messageNode.messageText
                                              actuallyfrom:messageNode.actualFrom delivered:YES];
                
                [[DataLayer sharedInstance] addActiveBuddies:messageNode.from forAccount:_accountNo];
                
                
                if(messageNode.from) {
                    NSString* actuallyFrom= messageNode.actualFrom;
                    if(!actuallyFrom) actuallyFrom=messageNode.from;
                    
                    NSString* messageText=messageNode.messageText;
                    if(!messageText) messageText=@"";
                    
                    NSDictionary* userDic=@{@"from":messageNode.from,
                                            @"actuallyfrom":actuallyFrom,
                                            @"messageText":messageText,
                                            @"to":_fulluser,
                                            @"accountNo":_accountNo
                                            };
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalNewMessageNotice object:self userInfo:userDic];
                }
            }
        }
        
        if(messageNode.avatarData)
        {
            [[MLImageManager sharedInstance] setIconForContact:messageNode.actualFrom andAccount:_accountNo WithData:messageNode.avatarData];
            
        }
        
    }
    else  if([toProcess.stanzaType  isEqualToString:@"presence"])
    {
        ParsePresence* presenceNode= (ParsePresence*) toProcess;
        if([presenceNode.user isEqualToString:_fulluser]) {
            return; //ignore self
        }
        
        if([presenceNode.type isEqualToString:kpresencesSubscribe])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"Do you wish to allow %@ to add you to their contacts?", nil), presenceNode.from ];
                RIButtonItem* cancelButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"No", nil) action:^{
                    [self rejectFromRoster:presenceNode.from];
                    
                }];
                
                RIButtonItem* yesButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Yes", nil) action:^{
                    [self approveToRoster:presenceNode.from];
                    [self addToRoster:presenceNode.from];
                    
                }];
                
                UIAlertView* alert =[[UIAlertView alloc] initWithTitle:@"Approve Contact" message:messageString cancelButtonItem:cancelButton otherButtonItems:yesButton, nil];
                [alert show];
            });
            
        }
        
        if(presenceNode.MUC)
        {
            for (NSString* code in presenceNode.statusCodes) {
                if([code isEqualToString:@"201"]) {
                    //201- created and needs configuration
                    //make instant room
                    XMPPIQ *configNode = [[XMPPIQ alloc] initWithId:_sessionKey andType:kiqSetType];
                    [configNode setiqTo:presenceNode.from];
                    [configNode setInstantRoom];
                    [self send:configNode];
                }
            }
            
            //mark buddy as MUC
        }
        
        if(presenceNode.type ==nil)
        {
            DDLogVerbose(@"presence priority notice from %@", presenceNode.user);
            
            if((presenceNode.user!=nil) && ([[presenceNode.user stringByTrimmingCharactersInSet:
                                              [NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0))
            {
                if(![[DataLayer sharedInstance] isBuddyInList:presenceNode.user forAccount:_accountNo])
                {
                    DDLogVerbose(@"Buddy not already in list");
                    [[DataLayer sharedInstance] addBuddy:presenceNode.user forAccount:_accountNo fullname:@"" nickname:@"" ];
                }
                else
                {
                    DDLogVerbose(@"Buddy already in list");
                }
                
                DDLogVerbose(@" showing as online now");
                
                [[DataLayer sharedInstance] setOnlineBuddy:presenceNode forAccount:_accountNo];
                [[DataLayer sharedInstance] setBuddyState:presenceNode forAccount:_accountNo];
                [[DataLayer sharedInstance] setBuddyStatus:presenceNode forAccount:_accountNo];
                
                NSString* state=presenceNode.show;
                if(!state) state=@"";
                NSString* status=presenceNode.status;
                if(!status) status=@"";
                NSDictionary* userDic=@{kusernameKey: presenceNode.user,
                                        kaccountNoKey:_accountNo,
                                        kstateKey:state,
                                        kstatusKey:status
                                        };
                dispatch_async(_xmppQueue, ^{
                    [self.contactsVC addOnlineUser:userDic];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactOnlineNotice object:self userInfo:userDic];
                });
                
                if(!presenceNode.MUC) {
                    // do not do this in the background
                    if([UIApplication sharedApplication].applicationState!=UIApplicationStateBackground)
                    {
                        //check for vcard change
                        if(presenceNode.photoHash) {
                            if([presenceNode.photoHash isEqualToString:[[DataLayer sharedInstance]  buddyHash:presenceNode.user forAccount:_accountNo]])
                            {
                                DDLogVerbose(@"photo hash is the  same");
                            }
                            else
                            {
                                [[DataLayer sharedInstance]  setBuddyHash:presenceNode forAccount:_accountNo];
                                XMPPIQ* iqVCard= [[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
                                [iqVCard getVcardTo:presenceNode.user];
                                [self send:iqVCard];
                            }
                        }
                    }
                    else
                    {
                        // just set and request when in foreground if needed
                        [[DataLayer sharedInstance]  setBuddyHash:presenceNode forAccount:_accountNo];
                    }
                }
                else {
                    
                }
                
            }
            else
            {
                DDLogError(@"ERROR: presence priority notice but no user name.");
                
            }
        }
        else if([presenceNode.type isEqualToString:kpresenceUnavailable])
        {
            if ([[DataLayer sharedInstance] setOfflineBuddy:presenceNode forAccount:_accountNo] ) {
                NSDictionary* userDic=@{kusernameKey: presenceNode.user,
                                        kaccountNoKey:_accountNo};
                dispatch_async(_xmppQueue, ^{
                    [self.contactsVC removeOnlineUser:userDic];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactOfflineNotice object:self userInfo:userDic];
                });
            }
            
        }
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"error"])
    {
        [self disconnect];
    }
    else  if([toProcess.stanzaType isEqualToString:@"stream:stream"])
    {
        //  ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:nextStanzaPos];
    }
    else  if([toProcess.stanzaType isEqualToString:@"stream"])
    {
        ParseFeatures* streamNode= ( ParseFeatures*) toProcess;
        
        //perform logic to handle stream
        if(streamNode.error)
        {
            return;
            
        }
        
        if(self.accountState!=kStateLoggedIn )
        {
            
            if(streamNode.callStartTLS &&  _SSL)
            {
                XMLNode* startTLS= [[XMLNode alloc] init];
                startTLS.element=@"starttls";
                [startTLS.attributes setObject:@"urn:ietf:params:xml:ns:xmpp-tls" forKey:@"xmlns"];
                [self send:startTLS];
                
            }
            
            if ((_SSL && _startTLSComplete) || (!_SSL && !_startTLSComplete) || (_SSL && _oldStyleSSL))
            {
                //look at menchanisms presented
                
                if(streamNode.SASLPlain)
                {
                    NSString* saslplain=[EncodingTools encodeBase64WithString: [NSString stringWithFormat:@"\0%@\0%@",  _username, _password ]];
                    
                    XMLNode* saslXML= [[XMLNode alloc]init];
                    saslXML.element=@"auth";
                    [saslXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:@"xmlns"];
                    [saslXML.attributes setObject: @"PLAIN"forKey: @"mechanism"];
                    
                    //google only uses sasl plain
                    [saslXML.attributes setObject:@"http://www.google.com/talk/protocol/auth" forKey: @"xmlns:ga"];
                    [saslXML.attributes setObject:@"true" forKey: @"ga:client-uses-full-bind-result"];
                    
                    saslXML.data=saslplain;
                    [self send:saslXML];
                    
                }
                else
                    if(streamNode.SASLDIGEST_MD5)
                    {
                        XMLNode* saslXML= [[XMLNode alloc]init];
                        saslXML.element=@"auth";
                        [saslXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:@"xmlns"];
                        [saslXML.attributes setObject: @"DIGEST-MD5"forKey: @"mechanism"];
                        
                        [self send:saslXML];
                    }
                    else
                    {
                        
                        //no supported auth mechanism try legacy
                        //[self disconnect];
                        DDLogInfo(@"no auth mechanism. will try legacy auth");
                        XMPPIQ* iqNode =[[XMPPIQ alloc] initWithElement:@"iq"];
                        [iqNode getAuthwithUserName:self.username ];
                        
                        [self send:iqNode];
                        
                        
                    }
            }
            
            
        }
        else
        {
            
            if(self.streamID) {
                XMLNode *resumeNode =[[XMLNode alloc] initWithElement:@"resume"];
                NSDictionary *dic=@{@"xmlns":@"urn:xmpp:sm:3",@"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza], @"previd":self.streamID };
                resumeNode.attributes =[dic mutableCopy];
                [self send:resumeNode];
            }
            else {
                XMPPIQ* iqNode =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqSetType];
                [iqNode setBindWithResource:_resource];
                
                [self send:iqNode];
                
                if(streamNode.supportsSM3)
                {
                    self.supportsSM3=YES;
                    
                    XMLNode *enableNode =[[XMLNode alloc] initWithElement:@"enable"];
                    NSDictionary *dic=@{@"xmlns":@"urn:xmpp:sm:3",@"resume":@"true" };
                    enableNode.attributes =[dic mutableCopy];
                    [self send:enableNode];
                    
                    
                }
            }
            
        }
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"enabled"])
    {
        ParseEnabled* enabledNode= (ParseEnabled*) toProcess;
        self.supportsResume=enabledNode.resume;
        self.streamID=enabledNode.streamID;
        //initilize values
        self.lastHandledInboundStanza=[NSNumber numberWithInteger:0];
        self.lastHandledOutboundStanza=[NSNumber numberWithInteger:0];
        self.lastOutboundStanza=[NSNumber numberWithInteger:0];
        self.unAckedStanzas =[[NSMutableArray alloc] init];
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"r"])
    {
        XMLNode *aNode =[[XMLNode alloc] initWithElement:@"a"];
        NSDictionary *dic=@{@"xmlns":@"urn:xmpp:sm:3",@"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza] };
        aNode.attributes =[dic mutableCopy];
        [self send:aNode];
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"a"])
    {
        ParseA* aNode= (ParseA*) toProcess;
        self.lastHandledOutboundStanza=aNode.h;
        
        //remove acked messages
        [self removeUnAckedMessagesLessThan:aNode.h];
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"resumed"])
    {
        ParseResumed* resumeNode= (ParseResumed*) toProcess;
        //h would be compared to outbound value
        if([resumeNode.h integerValue]==[self.lastHandledOutboundStanza integerValue])
        {
            [self.unAckedStanzas removeAllObjects];
        }
        else {
            [self removeUnAckedMessagesLessThan:resumeNode.h];
            //send unacked stanzas
            [self sendUnAckedMessages];
        }
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"failed"])
    {
        // if resume failed. bind like normal
        XMPPIQ* iqNode =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqSetType];
        [iqNode setBindWithResource:_resource];
        
        [self send:iqNode];
        
    }
    
    else  if([toProcess.stanzaType isEqualToString:@"features"])
    {
        ParseFeatures* streamNode= (ParseFeatures*) toProcess;
    }
    else  if([toProcess.stanzaType isEqualToString:@"proceed"])
    {
        ParseProceed* proceedNode= (ParseProceed*) toProcess;
        
        if(proceedNode.startTLSProceed)
        {
            NSMutableDictionary *settings = [ [NSMutableDictionary alloc ]
                                             initWithObjectsAndKeys:
                                             [NSNull null],kCFStreamSSLPeerName,
                                             nil ];
            
            if(_brokenServerSSL)
            {
                DDLogInfo(@"recovering from broken SSL implemtation limit to ss3-tl1");
                [settings addEntriesFromDictionary:@{@"kCFStreamSSLLevel":@"kCFStreamSocketSecurityLevelTLSv1_0SSLv3"}];
            }
            else
            {
                [settings addEntriesFromDictionary:@{@"kCFStreamSSLLevel":@"kCFStreamSocketSecurityLevelTLSv1"}];
            }
            
            if(self.selfSigned)
            {
                NSDictionary* secureOFF= [ [NSDictionary alloc ]
                                          initWithObjectsAndKeys:
                                          [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
                                          [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
                                          [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
                                          [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain, nil];
                
                [settings addEntriesFromDictionary:secureOFF];
                
                
                
            }
            
            if ( 	CFReadStreamSetProperty((__bridge CFReadStreamRef)_iStream,
                                            kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings) &&
                CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_oStream,
                                         kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings)	 )
                
            {
                DDLogInfo(@"Set TLS properties on streams. Security level %@", [_iStream propertyForKey:NSStreamSocketSecurityLevelKey]);
                
                NSDictionary* info2=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                                      kinfoTypeKey:@"connect", kinfoStatusKey:@"Securing Connection"};
                [self.contactsVC updateConnecting:info2];
            }
            else
            {
                DDLogError(@"not sure.. Could not confirm Set TLS properties on streams.");
                DDLogInfo(@"Set TLS properties on streams.security level %@", [_iStream propertyForKey:NSStreamSocketSecurityLevelKey]);
                
                
                
                //                        NSDictionary* info2=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                //                                              kinfoTypeKey:@"connect", kinfoStatusKey:@"Could not secure connection"};
                //                        [self.contactsVC updateConnecting:info2];
                
            }
            
            [self startStream];
            
            _startTLSComplete=YES;
        }
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"failure"])
    {
        ParseFailure* failure = (ParseFailure*) toProcess;
        if(failure.saslError || failure.notAuthorized)
        {
            _loginError=YES;
            [self disconnect];
        }
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"challenge"])
    {
        ParseChallenge* challengeNode= (ParseChallenge*) toProcess;
        if(challengeNode.saslChallenge)
        {
            XMLNode* responseXML= [[XMLNode alloc]init];
            responseXML.element=@"response";
            [responseXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:@"xmlns"];
            
            
            NSString* decoded=[[NSString alloc]  initWithData: (NSData*)[EncodingTools dataWithBase64EncodedString:challengeNode.challengeText] encoding:NSASCIIStringEncoding];
            DDLogVerbose(@"decoded challenge to %@", decoded);
            NSArray* parts =[decoded componentsSeparatedByString:@","];
            
            if([parts count]<2)
            {
                //this is a success message  from challenge
                
                NSArray* rspparts= [[parts objectAtIndex:0] componentsSeparatedByString:@"="];
                if([[rspparts objectAtIndex:0] isEqualToString:@"rspauth"])
                {
                    DDLogVerbose(@"digest-md5 success");
                    
                }
                
            }
            else{
                
                NSString* realm;
                NSString* nonce;
                
                for(NSString* part in parts)
                {
                    NSArray* split = [part componentsSeparatedByString:@"="];
                    if([split count]>1)
                    {
                        if([split[0] isEqualToString:@"realm"]) {
                            realm=[split[1]  substringWithRange:NSMakeRange(1, [split[1]  length]-2)] ;
                        }
                        
                        if([split[0] isEqualToString:@"nonce"]) {
                            nonce=[split[1]  substringWithRange:NSMakeRange(1, [split[1]  length]-2)] ;
                        }
                        
                    }
                }
                
                if(!realm) realm=@"";
                
                NSData* cnonce_Data=[EncodingTools MD5: [NSString stringWithFormat:@"%d",arc4random()%100000]];
                NSString* cnonce =[EncodingTools hexadecimalString:cnonce_Data];
                
                
                //                if([password length]==0)
                //                {
                //                    if(theTempPass!=NULL)
                //                        password=theTempPass;
                //
                //                }
                
                //  nonce=@"580F35C1AE408E7DA57DE4DEDC5B9CA7";
                //    cnonce=@"B9E01AE3-29E5-4FE5-9AA0-72F99742428A";
                
                
                // ****** digest stuff going on here...
                NSString* X= [NSString stringWithFormat:@"%@:%@:%@", self.username, realm, self.password ];
                DDLogVerbose(@"X: %@", X);
                
                NSData* Y = [EncodingTools MD5:X];
                
                // above is correct
                
                /*
                 NSString* A1= [NSString stringWithFormat:@"%@:%@:%@:%@@%@/%@",
                 Y,[nonce substringWithRange:NSMakeRange(1, [nonce length]-2)],cononce,account,domain,resource];
                 */
                
                //  if you have the authzid  here you need it below too but it wont work on som servers
                // so best not include it
                
                NSString* A1Str=[NSString stringWithFormat:@":%@:%@",
                                 nonce,cnonce];
                NSData* A1= [A1Str
                             dataUsingEncoding:NSUTF8StringEncoding];
                
                NSMutableData *HA1data = [NSMutableData dataWithCapacity:([Y length] + [A1 length])];
                [HA1data appendData:Y];
                [HA1data appendData:A1];
                DDLogVerbose(@" HA1data : %@",HA1data  );
                
                
                //this hash is wrong..
                NSData* HA1=[EncodingTools DataMD5:HA1data];
                
                //below is correct
                
                NSString* A2=[NSString stringWithFormat:@"AUTHENTICATE:xmpp/%@", realm];
                DDLogVerbose(@"%@", A2);
                NSData* HA2=[EncodingTools MD5:A2];
                
                NSString* KD=[NSString stringWithFormat:@"%@:%@:00000001:%@:auth:%@",
                              [EncodingTools hexadecimalString:HA1], nonce,
                              cnonce,
                              [EncodingTools hexadecimalString:HA2]];
                
                // DDLogVerbose(@" ha1: %@", [self hexadecimalString:HA1] );
                //DDLogVerbose(@" ha2: %@", [self hexadecimalString:HA2] );
                
                DDLogVerbose(@" KD: %@", KD );
                NSData* responseData=[EncodingTools MD5:KD];
                // above this is ok
                NSString* response=[NSString stringWithFormat:@"username=\"%@\",realm=\"%@\",nonce=\"%@\",cnonce=\"%@\",nc=00000001,qop=auth,digest-uri=\"xmpp/%@\",response=%@,charset=utf-8",
                                    self.username,realm, nonce, cnonce, realm, [EncodingTools hexadecimalString:responseData]];
                //,authzid=\"%@@%@/%@\"  ,account,domain, resource
                
                DDLogVerbose(@"  response :  %@", response);
                NSString* encoded=[EncodingTools encodeBase64WithString:response];
                
                //                NSString* xmppcmd = [NSString stringWithFormat:@"<response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>%@</response>", encoded]
                //                [self talk:xmppcmd];
                
                responseXML.data=encoded;
            }
            
            [self send:responseXML];
            return;
            
        }
    }
    else  if([toProcess.stanzaType isEqualToString:@"response"])
    {
        
    }
    else  if([toProcess.stanzaType isEqualToString:@"success"])
    {
        ParseSuccess* successNode= (ParseSuccess*) toProcess;
        if(successNode.SASLSuccess)
        {
            DDLogInfo(@"Got SASL Success");
            
            srand([[NSDate date] timeIntervalSince1970]);
            // make up a random session key (id)
            _sessionKey=[NSString stringWithFormat:@"monal%ld",random()%100000];
            DDLogVerbose(@"session key: %@", _sessionKey);
            
            [self startStream];
            _accountState=kStateLoggedIn;
            _loggedInOnce=YES;
            _loginStarted=NO;
            
            
            NSDictionary* info=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                                 kinfoTypeKey:@"connect", kinfoStatusKey:@""};
            dispatch_async(_xmppQueue, ^{
                [self.contactsVC hideConnecting:info];
            });
            
        }
        
    }
}



-(void) send:(XMLNode*) stanza
{
    if(!stanza) return;
    
    if(self.supportsSM3 && self.unAckedStanzas)
    {
        NSDictionary *dic =@{kStanzaID:[NSNumber numberWithInteger: [self.lastOutboundStanza integerValue]], kStanza:stanza};
        [self.unAckedStanzas addObject:dic];
        self.lastOutboundStanza=[NSNumber numberWithInteger:[self.lastOutboundStanza integerValue]+1];
    }
    
    [self.writeQueue addOperation:
     [NSBlockOperation blockOperationWithBlock:^{
        [_outputQueue addObject:stanza];
        [self writeFromQueue];  // try to send if there is space
        
    }]];
}


#pragma mark messaging

-(void) sendMessage:(NSString*) message toContact:(NSString*) contact isMUC:(BOOL) isMUC andMessageId:(NSString *) messageId
{
    XMPPMessage* messageNode =[[XMPPMessage alloc] init];
    [messageNode.attributes setObject:contact forKey:@"to"];
    [messageNode setBody:message];
    [messageNode setXmppId:messageId ];
    
    if(isMUC)
    {
        [messageNode.attributes setObject:kMessageGroupChatType forKey:@"type"];
    } else  {
        [messageNode.attributes setObject:kMessageChatType forKey:@"type"];
    }
    
    [self send:messageNode];
}


#pragma mark set connection attributes
-(void) setStatusMessageText:(NSString*) message
{
    if([message length]>0)
        self.statusMessage=message;
    else
        message=nil;
    
    XMPPPresence* node =[[XMPPPresence alloc] initWithHash:self.versionHash];
    if(message)[node setStatus:message];
    
    if(self.awayState) [node setAway];
    
    [self send:node];
}

-(void) setAway:(BOOL) away
{
    self.awayState=away;
    XMPPPresence* node =[[XMPPPresence alloc] initWithHash:self.versionHash];
    if(away)
        [node setAway];
    else
        [node setAvailable];
    
    if(self.statusMessage) [node setStatus:self.statusMessage];
    [self send:node];
}

-(void) setVisible:(BOOL) visible
{
    self.visibleState=visible;
    XMPPPresence* node =[[XMPPPresence alloc] initWithHash:self.versionHash];
    if(!visible)
        [node setInvisible];
    else
    {
        if(self.statusMessage) [node setStatus:self.statusMessage];
        if(self.awayState) [node setAway];
    }
    
    [self send:node];
}

-(void) updatePriority:(NSInteger) priority
{
    self.priority=priority;
    
    XMPPPresence* node =[[XMPPPresence alloc] initWithHash:self.versionHash];
    [node setPriority:priority];
    [self send:node];
    
}



#pragma mark query info

-(NSString*)getVersionString
{
    // We may need this later
    //    NSString* unhashed=[NSString stringWithFormat:@"client/pc//Monal %@<http://jabber.org/protocol/disco#info<http://jabber.org/protocol/disco#items<http://jabber.org/protocol/muc#user<jabber:iq:version<urn:xmpp:jingle:1<urn:xmpp:jingle:apps:rtp:1<urn:xmpp:jingle:apps:rtp:audio<urn:xmpp:jingle:transports:raw-udp:0<urn:xmpp:jingle:transports:raw-udp:1<", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    //
    NSString* unhashed=[NSString stringWithFormat:@"client/phone//Monal %@<http://jabber.org/protocol/caps<http://jabber.org/protocol/disco#info<http://jabber.org/protocol/disco#items<http://jabber.org/protocol/muc<", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    NSData* hashed;
    //<http://jabber.org/protocol/offline<
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    NSData *stringBytes = [unhashed dataUsingEncoding: NSUTF8StringEncoding]; /* or some other encoding */
    if (CC_SHA1([stringBytes bytes], [stringBytes length], digest)) {
        hashed =[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
    }
    
    NSString* hashedBase64= [EncodingTools encodeBase64WithData:hashed];
    
    
    return hashedBase64;
    
}


-(void) getServiceDetails
{
    if(_hasRequestedServerInfo)
        return;  // no need to call again on disconnect
    
    if(!_discoveredServices)
    {
        DDLogInfo(@"no discovered services");
        return;
    }
    
    for (NSDictionary *item in _discoveredServices)
    {
        XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
        NSString* jid =[item objectForKey:@"jid"];
        if(jid)
        {
            [discoInfo setiqTo:jid];
            [discoInfo setDiscoInfoNode];
            [self send:discoInfo];
            
            _hasRequestedServerInfo=YES;
        } else
        {
            DDLogError(@"no jid on info");
        }
    }
    
    
}

#pragma mark  MUC

-(void) getConferenceRooms
{
    if(_conferenceServer && !_roomList)
    {
        XMPPIQ* discoItem =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
        [discoItem setiqTo:_conferenceServer];
        [discoItem setDiscoItemNode];
        [self send:discoItem];
    }
    else
    {
        if(!_conferenceServer) DDLogInfo(@"no conference server discovered");
        if(_roomList){
            [[NSNotificationCenter defaultCenter] postNotificationName: kMLHasRoomsNotice object: self];
        }
    }
}


-(void) joinRoom:(NSString*) room withPassword:(NSString *)password
{
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    NSArray* parts =[room componentsSeparatedByString:@"@"];
    if([parts count]>1)
    {
        [presence joinRoom:[parts objectAtIndex:0] withPassword:password onServer:[parts objectAtIndex:1] withName:_username];
        //allow nick name in the future
        
    }
    else{
        [presence joinRoom:room withPassword:password onServer:_conferenceServer withName:_username]; //allow nick name in the future
        
    }
    [self send:presence];
}

-(void) leaveRoom:(NSString*) room
{
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    [presence leaveRoom:room onServer:_conferenceServer withName:_username];
    [self send:presence];
}


#pragma mark XMPP add and remove contact
-(void) removeFromRoster:(NSString*) contact
{
    XMPPIQ* iq = [[XMPPIQ alloc] initWithId:_sessionKey andType:kiqSetType];
    [iq setRemoveFromRoster:contact];
    [self send:iq];
    
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    [presence unsubscribeContact:contact];
    [self send:presence];
    
    
    XMPPPresence* presence2 =[[XMPPPresence alloc] init];
    [presence2 unsubscribedContact:contact];
    [self send:presence2];
    
}

-(void) rejectFromRoster:(NSString*) contact
{
    XMPPPresence* presence2 =[[XMPPPresence alloc] init];
    [presence2 unsubscribedContact:contact];
    [self send:presence2];
}


-(void) addToRoster:(NSString*) contact
{
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    [presence subscribeContact:contact];
    [self send:presence];
    
    
}

-(void) approveToRoster:(NSString*) contact
{
    
    XMPPPresence* presence2 =[[XMPPPresence alloc] init];
    [presence2 subscribedContact:contact];
    [self send:presence2];
}

#pragma mark Jingle calls
-(void)call:(NSDictionary*) contact
{
    if(self.jingle) return;
    self.jingle=[[jingleCall alloc] init];
    self.jingle.me=self.jid;
    
    NSArray* resources= [[DataLayer sharedInstance] resourcesForContact:[contact objectForKey:@"buddy_name"]];
    if([resources count]>0)
    {
        //TODO selct resource action sheet?
        XMPPIQ* jingleiq =[self.jingle initiateJingleTo:[contact objectForKey:@"buddy_name" ] withId:_sessionKey andResource:[[resources objectAtIndex:0] objectForKey:@"resource"]];
        [self send:jingleiq];
    }
}

-(void)hangup:(NSDictionary*) contact
{
    XMPPIQ* jingleiq =[self.jingle terminateJinglewithId:_sessionKey];
    [self send:jingleiq];
    [self.jingle rtpDisconnect];
    self.jingle=nil;
}


#pragma mark nsstream delegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    DDLogVerbose(@"Stream has event");
    switch(eventCode)
    {
        case NSStreamEventOpenCompleted:
        {
            DDLogVerbose(@"Stream open completed");
            //            if(stream ==_iStream) {
            //                CFDataRef socketData = CFReadStreamCopyProperty((__bridge CFReadStreamRef)(stream), kCFStreamPropertySocketNativeHandle);
            //                CFSocketNativeHandle socket;
            //                CFDataGetBytes(socketData, CFRangeMake(0, sizeof(CFSocketNativeHandle)), (UInt8 *)&socket);
            //                CFRelease(socketData);
            //
            //                int on = 1;
            //                if (setsockopt(socket, SOL_SOCKET, SO_KEEPALIVE, &on, sizeof(on)) == -1) {
            //                    DDLogVerbose(@"setsockopt failed: %s", strerror(errno));
            //                }
            //            }
        }
            //for writing
        case NSStreamEventHasSpaceAvailable:
        {
            [self.writeQueue addOperation:
             [NSBlockOperation blockOperationWithBlock:^{
                _streamHasSpace=YES;
                
                DDLogVerbose(@"Stream has space to write");
                [self writeFromQueue];
            }]];
            break;
        }
            
            //for reading
        case  NSStreamEventHasBytesAvailable:
        {
            DDLogVerbose(@"Stream has bytes to read");
         
            break;
        }
            
        case NSStreamEventErrorOccurred:
        {
            NSError* st_error= [stream streamError];
            DDLogError(@"Stream error code=%d domain=%@   local desc:%@ ",st_error.code,st_error.domain,  st_error.localizedDescription);
            
            
            if(st_error.code==2)// operation couldnt be completed
            {
                [self disconnect];
                return;
            }
            
            
            if(st_error.code==2)// socket not connected
            {
                [self disconnect];
                return;
            }
            
            if(st_error.code==61)// Connection refused
            {
                [self disconnect];
                return;
            }
            
            
            if(st_error.code==64)// Host is down
            {
                [self disconnect];
                return;
            }
            
            if(st_error.code==-9807)// Could not complete operation. SSL probably
            {
                [self disconnect];
                return;
            }
            
            if(st_error.code==-9820)// Could not complete operation. SSL broken on server
            {
                DDLogInfo(@"setting broke ssl. retrying");
                _brokenServerSSL=YES;
                _loginStarted=NO;
                _accountState=kStateReconnecting;
                [self reconnect:0];
                
                return;
            }
            
            
            if(_loggedInOnce)
            {
                DDLogInfo(@" stream error calling reconnect");
                // login process has its own reconnect mechanism
                if(self.accountState>=kStateHasStream) {
                    _accountState=kStateReconnecting;
                    _loginStarted=NO;
                    [self reconnect];
                }
            }
            
            else
            {
                // maybe account never worked and should be disabled and reachability should be removed
                //                [[DataLayer sharedInstance] disableEnabledAccount:_accountNo];
                //                [[MLXMPPManager sharedInstance] disconnectAccount:_accountNo];
                
            }
            break;
            
        }
        case NSStreamEventNone:
        {
            DDLogVerbose(@"Stream event none");
            break;
            
        }
            
            
        case NSStreamEventEndEncountered:
        {
            DDLogInfo(@"%@ Stream end encoutered", [stream class] );
            _accountState=kStateReconnecting;
            _loginStarted=NO;
            [self reconnect];
            break;
        }
            
    }
    
}

#pragma mark network I/O
-(void) writeFromQueue
{
    if(!_streamHasSpace)
    {
        DDLogVerbose(@"no space to write. returning. ");
        return;
    }
    
    for(XMLNode* node in _outputQueue)
    {
        BOOL success=[self writeToStream:node.XMLString];
        if(success) {
            if([node isKindOfClass:[XMPPMessage class]])
            {
                XMPPMessage *messageNode = (XMPPMessage *) node;
                NSDictionary *dic =@{kMessageId:messageNode.xmppId};
                [[NSNotificationCenter defaultCenter] postNotificationName: kMonalSentMessageNotice object:self userInfo:dic];
                
            }
        }
    }
    
    [_outputQueue removeAllObjects];
    
}

-(BOOL) writeToStream:(NSString*) messageOut
{
    if(!messageOut) {
        DDLogVerbose(@" tried to send empty message. returning");
        return NO;
    }
    _streamHasSpace=NO; // triggers more has space messages
    
    //we probably want to break these into chunks
    DDLogVerbose(@"sending: %@ ", messageOut);
    const uint8_t * rawstring = (const uint8_t *)[messageOut UTF8String];
    int len= strlen((char*)rawstring);
    DDLogVerbose(@"size : %d",len);
    if([_oStream write:rawstring maxLength:len]!=-1)
    {
        DDLogVerbose(@"done writing ");
        return YES;
    }
    else
    {
        NSError* error= [_oStream streamError];
        DDLogVerbose(@"sending: failed with error %d domain %@ message %@",error.code, error.domain, error.userInfo);
    }
    
    return NO;
}


#pragma mark DNS

-(void) dnsDiscover
{
    DNSServiceRef sdRef;
    DNSServiceErrorType res;
    
    NSString* serviceDiscoveryString=[NSString stringWithFormat:@"_xmpp-client._tcp.%@", _domain];
    
    res=DNSServiceQueryRecord(
                              &sdRef, 0, 0,
                              [serviceDiscoveryString UTF8String],
                              kDNSServiceType_SRV,
                              kDNSServiceClass_IN,
                              query_cb,
                              ( __bridge void *)(self)
                              );
    if(res==kDNSServiceErr_NoError)
    {
        int sock=DNSServiceRefSockFD(sdRef);
        
        fd_set set;
        struct timeval timeout;
        
        /* Initialize the file descriptor set. */
        FD_ZERO (&set);
        FD_SET (sock, &set);
        
        /* Initialize the timeout data structure. */
        timeout.tv_sec = 2ul;
        timeout.tv_usec = 0;
        
        /* select returns 0 if timeout, 1 if input available, -1 if error. */
        int ready= select (FD_SETSIZE,&set, NULL, NULL,
                           &timeout) ;
        
        if(ready>0)
        {
            
            DNSServiceProcessResult(sdRef);
            DNSServiceRefDeallocate(sdRef);
        }
        else
        {
            DDLogVerbose(@"dns call timed out");
        }
        
    }
}






char *ConvertDomainLabelToCString_withescape(const domainlabel *const label, char *ptr, char esc)
{
    const u_char *      src = label->c;                         // Domain label we're reading
    const u_char        len = *src++;                           // Read length of this (non-null) label
    const u_char *const end = src + len;                        // Work out where the label ends
    if (len > MAX_DOMAIN_LABEL) return(NULL);           // If illegal label, abort
    while (src < end)                                           // While we have characters in the label
    {
        u_char c = *src++;
        if (esc)
        {
            if (c == '.')                                       // If character is a dot,
                *ptr++ = esc;                                   // Output escape character
            else if (c <= ' ')                                  // If non-printing ascii,
            {                                                   // Output decimal escape sequence
                *ptr++ = esc;
                *ptr++ = (char)  ('0' + (c / 100)     );
                *ptr++ = (char)  ('0' + (c /  10) % 10);
                c      = (u_char)('0' + (c      ) % 10);
            }
        }
        *ptr++ = (char)c;                                       // Copy the character
    }
    *ptr = 0;                                                   // Null-terminate the string
    return(ptr);                                                // and return
}

char *ConvertDomainNameToCString_withescape(const domainname *const name, char *ptr, char esc)
{
    const u_char *src         = name->c;                        // Domain name we're reading
    const u_char *const max   = name->c + MAX_DOMAIN_NAME;      // Maximum that's valid
    
    if (*src == 0) *ptr++ = '.';                                // Special case: For root, just write a dot
    
    while (*src)                                                                                                        // While more characters in the domain name
    {
        if (src + 1 + *src >= max) return(NULL);
        ptr = ConvertDomainLabelToCString_withescape((const domainlabel *)src, ptr, esc);
        if (!ptr) return(NULL);
        src += 1 + *src;
        *ptr++ = '.';                                           // Write the dot after the label
    }
    
    *ptr++ = 0;                                                 // Null-terminate the string
    return(ptr);                                                // and return
}

// print arbitrary rdata in a readable manned
void print_rdata(int type, int len, const u_char *rdata, void* context)
{
    int i;
    srv_rdata *srv;
    char targetstr[MAX_CSTRING];
    struct in_addr in;
    
    switch (type)
    {
        case T_TXT:
        {
            // print all the alphanumeric and punctuation characters
            for (i = 0; i < len; i++)
                if (rdata[i] >= 32 && rdata[i] <= 127) printf("%c", rdata[i]);
            printf("\n");
            ;
            return;
        }
        case T_SRV:
        {
            srv = (srv_rdata *)rdata;
            ConvertDomainNameToCString_withescape(&srv->target, targetstr, 0);
            //  DDLogVerbose(@"pri=%d, w=%d, port=%d, target=%s\n", ntohs(srv->priority), ntohs(srv->weight), ntohs(srv->port), targetstr);
            
            xmpp* client=(__bridge xmpp*) context;
            int portval=ntohs(srv->port);
            NSString* theserver=[NSString stringWithUTF8String:targetstr];
            NSNumber* num=[NSNumber numberWithInt:ntohs(srv->priority)];
            NSNumber* theport=[NSNumber numberWithInt:portval];
            if(theserver && num && theport) {
                NSDictionary* row=[NSDictionary dictionaryWithObjectsAndKeys:num,@"priority", theserver, @"server", theport, @"port",nil];
                [client.discoveredServerList addObject:row];
            }
            //	DDLogVerbose(@"DISCOVERY: server  %@", theserver);
            
            return;
        }
        case T_A:
        {
            assert(len == 4);
            memcpy(&in, rdata, sizeof(in));
            //   DDLogVerbose(@"%s\n", inet_ntoa(in));
            
            return;
        }
        case T_PTR:
        {
            ConvertDomainNameToCString_withescape((domainname *)rdata, targetstr, 0);
            //  DDLogVerbose(@"%s\n", targetstr);
            
            return;
        }
        default:
        {
            //   DDLogVerbose(@"ERROR: I dont know how to print RData of type %d\n", type);
            
            return;
        }
    }
}

void query_cb(const DNSServiceRef DNSServiceRef, const DNSServiceFlags flags, const u_int32_t interfaceIndex, const DNSServiceErrorType errorCode, const char *name, const u_int16_t rrtype, const u_int16_t rrclass, const u_int16_t rdlen, const void *rdata, const u_int32_t ttl, void *context)
{
    (void)DNSServiceRef;
    (void)flags;
    (void)interfaceIndex;
    (void)rrclass;
    (void)ttl;
    (void)context;
    
    if (errorCode)
    {
        // DDLogVerbose(@"query callback: error==%d\n", errorCode);
        return;
    }
    // DDLogVerbose(@"query callback - name = %s, rdata=\n", name);
    print_rdata(rrtype, rdlen, rdata, context);
}


/*
 // this is useful later for ichat bonjour
 
 #pragma mark DNS service discovery
 - (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)netServiceBrowser
 {
 DDLogVerbose(@"began service search of domain %@", domain);
 }
 
 
 - (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didNotSearch:(NSDictionary *)errorInfo
 {
 DDLogVerbose(@"did not  service search");
 }
 
 - (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
 {
 [netService retain];
 DDLogVerbose(@"Add service %@. %@ %@\n", [netService name], [netService type], [netService domain]);
 }
 
 - (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)netServiceBrowser
 {
 DDLogVerbose(@"stopped service search");
 }
 */



@end
