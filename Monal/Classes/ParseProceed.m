//
//  ParseProceed.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/4/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "ParseProceed.h"

@implementation ParseProceed

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
 
    if(([elementName isEqualToString:@"proceed"]) && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-tls"]) )
    {
        //trying to switch to TLS
        _startTLSProceed=YES;
    }
    
}

@end
