//
//  ParseSuccess.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/4/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "ParseSuccess.h"

@implementation ParseSuccess

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    //***** sasl success...
    if(([elementName isEqualToString:@"success"]) &&  ([namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
       )
        
    {
        _SASLSuccess=YES;
    }
}

@end
