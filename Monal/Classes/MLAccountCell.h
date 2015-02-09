//
//  MLAccountCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/8/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MLAccountCell : UITableViewCell

@property (nonatomic, assign) BOOL switchEnabled;
@property (nonatomic, assign) BOOL textEnabled;

/**
 UIswitch
 */
#ifdef TARGET_OS_MAC
@property (nonatomic, strong) UIButton* toggleSwitch;
#elif TARGET_OS_IPHONE
@property (nonatomic, strong) UISwitch* toggleSwitch;
#endif

/**
 Textinput field
 */
@property (nonatomic, strong) UITextField* textInputField;

@end
