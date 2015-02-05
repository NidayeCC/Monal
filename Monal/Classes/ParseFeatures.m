//
//  ParseStream.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import "ParseFeatures.h"
#import "DDLog.h"

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@implementation ParseFeatures

#pragma mark NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict{
    DDLogVerbose(@"began this element: %@", elementName);
     _messageBuffer=nil;
    
    if(([elementName isEqualToString:@"auth"]))
	{
        DDLogVerbose(@"Supports legacy auth");
        _supportsLegacyAuth=true;
        
		return;
    }
    
    if(([elementName isEqualToString:@"register"]))
	{
        DDLogVerbose(@"Supports user registration");
        _supportsUserReg=YES;
        
		return;
    }
    
	if(([elementName isEqualToString:@"starttls"]))
	{
        DDLogVerbose(@"Using startTLS");
        _callStartTLS=YES;
		return; 
	}
    

    
	if( ([elementName isEqualToString:@"bind"]))
	{
        _bind=YES;
		return;
    }
	
    /** stream management **/
    if( ([elementName isEqualToString:@"sm"]))
    {
        if([namespaceURI isEqualToString:@"urn:xmpp:sm:2"])
        {
        _supportsSM2=YES;
        }
        if([namespaceURI isEqualToString:@"urn:xmpp:sm:3"])
        {
        _supportsSM3=YES;
        }
        return;
    }
    

	if( [elementName isEqualToString:@"mechanisms"] )
	{
	
		DDLogVerbose(@"mechanisms xmlns:%@ ", namespaceURI);
		if([namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
		{
			DDLogVerbose(@"SASL supported");
			_supportsSASL=YES;
		}
		State=@"Mechanisms";
		return;
	}

	if(([State isEqualToString:@"Mechanisms"]) && [elementName isEqualToString:@"mechanism"])
	{
		DDLogVerbose(@"Reading mechanism"); 
		State=@"Mechanism";
		return;
	}
	
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if( ([elementName isEqualToString:@"mechanism"]) && ([State isEqualToString:@"Mechanism"]))
	{
		
		State=@"Mechanisms";
		
		DDLogVerbose(@"got login mechanism: %@", _messageBuffer);
		if([_messageBuffer isEqualToString:@"PLAIN"])
		{
			DDLogVerbose(@"SASL PLAIN is supported");
			_SASLPlain=YES;
		}
		
		if([_messageBuffer isEqualToString:@"CRAM-MD5"])
		{
			DDLogVerbose(@"SASL CRAM-MD5 is supported");
			_SASLCRAM_MD5=YES;
		}
		
		if([_messageBuffer isEqualToString:@"DIGEST-MD5"])
		{
			DDLogVerbose(@"SASL DIGEST-MD5 is supported");
			_SASLDIGEST_MD5=YES;
		}
        
        _messageBuffer=nil; 
		return;
		
	}
}




@end
