#import <UIKit/UIKit.h>

#import "noshi_country_book.h"
#import "noshi_country_controller.h"

@class NoshiPhoneController;

@protocol NoshiPhoneControllerDelegate <NSObject>
/* number is the full international form, a plus and digits only */
- (void)phoneController:(NoshiPhoneController *)controller didSubmitNumber:(NSString *)number;
/* the link under the card: the person wants to log in with a QR code instead */
- (void)phoneControllerDidRequestQr:(NoshiPhoneController *)controller;
@end

@interface NoshiPhoneController : UIViewController <UITextFieldDelegate, NoshiCountryControllerDelegate>

- (id)initWithCountryBook:(NoshiCountryBook *)book;

@property (nonatomic, assign) id<NoshiPhoneControllerDelegate> delegate;
/* the code request is out: Next and the fields stop answering until the result arrives */
@property (nonatomic, assign) BOOL busy;

@end
