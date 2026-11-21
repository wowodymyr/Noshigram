#import <UIKit/UIKit.h>

#import "noshi_attach_options.h"

typedef enum { NoshiAttachGallery, NoshiAttachFile, NoshiAttachLocation, NoshiAttachGift, NoshiAttachContact, NoshiAttachCamera } NoshiAttachChoice;

@class NoshiAttachSheet;

@protocol NoshiAttachSheetDelegate <NSObject>
- (void)attachSheet:(NoshiAttachSheet *)sheet didChoose:(NoshiAttachChoice)choice;
/* the pictures picked, with the words and the choices of the sheet's menu */
- (void)attachSheet:(NoshiAttachSheet *)sheet didChooseAssets:(NSArray *)urls options:(NoshiAttachOptions *)options;
@end

@interface NoshiAttachSheet : UIView
@property (nonatomic, assign) id<NoshiAttachSheetDelegate> delegate;
@property (nonatomic, assign) BOOL offersGift;
/* the sheet that picks a photo or a video for the profile and nothing else: the grid under its own title, one tap on a picture hands it over, and none of the buttons for files, places, gifts and
   contacts, nor the words and the menu of a message; set before the sheet is shown */
@property (nonatomic, assign) BOOL profilePicker;
- (void)showInView:(UIView *)host;
- (void)dismiss;
@end
