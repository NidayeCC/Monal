//
//  ParseMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "ParseMessage.h"

@implementation ParseMessage


#pragma mark NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    
    //ignore error message
	if(([elementName isEqualToString:@"message"])  && ([[attributeDict objectForKey:@"type"] isEqualToString:kMessageErrorType]))
	{
		debug_NSLog(@" message error");
		
		return;
	}
	
	
	
	if(([elementName isEqualToString:@"message"])  && ([[attributeDict objectForKey:@"type"] isEqualToString:kMessageGroupChatType]))
	{
		State=@"Message";
		NSArray*  parts=[[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/"];
		
//		if([parts count]>1)
//		{
//            debug_NSLog(@"group chat message");
//            messageUser=[parts objectAtIndex:0];
//			mucUser=[parts objectAtIndex:1]; //stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"_%@", domain]
//            //					   withString:[NSString stringWithFormat:@"@%@", domain]] ;
//            
//            
//			
//		}
//        else
//            
//        {
//            debug_NSLog(@"group chat message from room ");
//            messageUser=[attributeDict objectForKey:@"from"];
//            mucUser=    [attributeDict objectForKey:@"from"];
//		}
//        
//        
//		;
//		return;
	}
	else
        if([elementName isEqualToString:@"message"]) //&& ([[attributeDict objectForKey:@"type"] isEqualToString:@"chat"]))
        {
            _from=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
            debug_NSLog(@"message from %@", _from);
            return;
        }

	//multi user chat
	//message->user:X
	if(([State isEqualToString:@"Message"]) && ( ([elementName isEqualToString: @"user:invite"]) || ([elementName isEqualToString: @"invite"]))
       // && (([[attributeDict objectForKey:@"xmlns:user"] isEqualToString:@"http://jabber.org/protocol/muc#user"]) ||
       //  ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"http://jabber.org/protocol/muc#user"])
       //   )
	   )
	{
		State=@"MucUser";
		
        // [self joinMuc:messageUser:@""]; // since we dont have a pw, leave it blank
        
//        NSString* askmsg=[NSString stringWithFormat:@"%@: You have been invited to this group chat. Join? ", _from];
//        //ask for authorization
//        
//        dispatch_async(dispatch_get_main_queue(), ^{
//            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Invite"
//                                                            message:askmsg
//                                                           delegate:self cancelButtonTitle:@"Yes"
//                                                  otherButtonTitles:@"No", nil];
//            alert.tag=2;
//            
//            [alert show];
//        });
		return;
	}
	
	if(([State isEqualToString:@"MucUser"]) && (([elementName isEqualToString: @"user:invite"]) || ([elementName isEqualToString: @"invite"])))
	{
        //	messageUser=[attributeDict objectForKey:@"from"] ;
    
		return; 
	}
	
	if((([State isEqualToString:@"MucUser"]) && (([elementName isEqualToString: @"user:reason"]))) || ([elementName isEqualToString: @"reason"]))
	{
		debug_NSLog(@"user reason set"); 
		State=@"MucUserReason";

		return;
	}
	
    
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if([elementName isEqualToString:@"body"])
    {
        _messageText=_messageBuffer;
        debug_NSLog(@"got message %@", _messageText);
    }
    
    if([elementName isEqualToString:@"message"])
    {
        // this is the end of parse
        if(!_actualFrom) _actualFrom=_from; 
    }
    
}

@end