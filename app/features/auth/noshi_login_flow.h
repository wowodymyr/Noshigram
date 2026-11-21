#import <UIKit/UIKit.h>

#import "noshi_country_book.h"
#import "noshi_form_controller.h"
#import "noshi_phone_controller.h"
#import "noshi_qr_controller.h"
#import "noshi_session.h"

@class NoshiLoginFlow;

@protocol NoshiLoginFlowDelegate <NSObject>
- (void)loginFlow:(NoshiLoginFlow *)flow didAuthorizeUser:(long long)userId;
@end

/* walks the navigation stack through the phone, code, password and name screens as the login state
   machine asks for them; the welcome screen below the phone screen is not its business */
@interface NoshiLoginFlow : NSObject <NoshiPhoneControllerDelegate, NoshiQrControllerDelegate, NoshiFormControllerDelegate, NoshiSessionDelegate> {
    id<NoshiLoginFlowDelegate> _delegate;
}

@property (nonatomic, assign) id<NoshiLoginFlowDelegate> delegate;

- (id)initWithNavigation:(UINavigationController *)navigation session:(NoshiSession *)session
            countryBook:(NoshiCountryBook *)book;
/* pushes the phone screen and takes over as the session delegate */
- (void)begin;
/* the same, but the first screen is the QR code, with the phone screen kept for the way to the number */
- (void)beginWithQr;

@end
