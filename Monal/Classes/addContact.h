//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface addContact : UIViewController<UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate>
{

    UITextField* _currentTextField;
    UIPickerView* _accountPicker;
    UIView* _accountPickerView; 
    NSInteger _selectedRow;
    
     UIBarButtonItem* _closeButton;

}

@property (nonatomic, weak) IBOutlet UITextField* buddyName;
@property (nonatomic, weak) IBOutlet UITextField* accountName;
@property (nonatomic, weak) IBOutlet UIButton* addButton;
@property (nonatomic, weak) IBOutlet UIToolbar* keyboardToolbar;
@property (nonatomic, weak) IBOutlet UILabel* contactLabel;
@property (nonatomic, weak) IBOutlet UILabel* accountLabel;

-(IBAction) addPress;
-(void) closeView;


- (IBAction)toolbarDone:(id)sender;
- (IBAction)toolbarPrevious:(id)sender;
- (IBAction)toolbarNext:(id)sender;

@end
