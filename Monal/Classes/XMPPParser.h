//
//  XMPPParser.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import <Foundation/Foundation.h>
#import "DDLog.h"



@interface XMPPParser : NSObject  <NSXMLParserDelegate>
{
    NSString* State;
    NSMutableString* _messageBuffer;
    
    NSString* _type;
    NSString* _from;
    NSString* _user;
    NSString* _resource;
    NSString* _idval;
    
}

/*
 xmpp stanza type contined here iq, presence, message etc.
 */
@property (nonatomic, strong, readonly) NSString* stanzaType;

@property (nonatomic, strong, readonly) NSString* type;
/**
 full name as sent from server
 */
@property (nonatomic, strong, readonly) NSString* from;

/**
 username part of from
 */
@property (nonatomic, strong, readonly) NSString* user;

/**
 resource part of from
 */
@property (nonatomic, strong, readonly) NSString* resource;
@property (nonatomic, strong, readonly) NSString* idval;

@end
