//
//  MLAccountCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/8/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLAccountCell.h"

@implementation MLAccountCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
        
        self.selectionStyle=UITableViewCellSelectionStyleNone;
        
        _textInputField=[[UITextField alloc] initWithFrame:CGRectZero];
#ifdef TARGET_OS_MAC
        _toggleSwitch =[UIButton buttonWithType:UIButtonTypeRoundedRect];
        [_toggleSwitch  setTitle:@"OFF" forState:UIControlStateNormal];
        _toggleSwitch.backgroundColor=[UIColor whiteColor];
#elif TARGET_OS_IPHONE
        _toggleSwitch=[[UISwitch alloc] initWithFrame:CGRectZero];
#endif
    }
    return self;
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
    CGRect textLabelFrame = self.textLabel.frame;
   
    //this is to account for padding in the grouped tableview cell
    int padding =30;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        padding=80;
    }

    int width=200;
    
    if(self.switchEnabled)
    {
#ifdef TARGET_OS_MAC
        CGRect frame=CGRectMake(self.frame.size.width-width-padding,
                                textLabelFrame.origin.y+9,width,
                                textLabelFrame.size.height*2/3);
        
#elif TARGET_OS_IPHONE
        CGRect frame=CGRectMake(self.frame.size.width-_toggleSwitch.frame.size.width-padding,
                                textLabelFrame.origin.y+7,_toggleSwitch.frame.size.width,
                                textLabelFrame.size.height);
#endif
        _toggleSwitch.frame=frame;
      [self.contentView addSubview: _toggleSwitch ];
        
    }
    
    if(self.textEnabled)
    {
        
        CGRect frame=CGRectMake(self.frame.size.width-width-padding,
                                textLabelFrame.origin.y+9,width,
                                textLabelFrame.size.height*2/3);

        _textInputField.frame=frame;
        _textInputField.returnKeyType=UIReturnKeyDone;
        [self.contentView addSubview: _textInputField ];
#ifdef TARGET_OS_MAC
        _textInputField.backgroundColor=[UIColor whiteColor];
#elif TARGET_OS_IPHONE
#endif
    }
    
}

@end
