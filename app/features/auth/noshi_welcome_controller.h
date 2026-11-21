#import <UIKit/UIKit.h>

#import "noshi_shiro.h"

@class NoshiWelcomeController;

@protocol NoshiWelcomeControllerDelegate <NSObject>
- (void)welcomeControllerDidTapStart:(NoshiWelcomeController *)controller;
/* the faint link under the button: log in with a QR code, without typing a number */
- (void)welcomeControllerDidRequestQr:(NoshiWelcomeController *)controller;
@end

@interface NoshiWelcomeController : UIViewController <UIScrollViewDelegate>

@property (nonatomic, assign) id<NoshiWelcomeControllerDelegate> delegate;
/* the VPN, whose button stands at the top right: a phone that cannot reach Telegram has to be able to turn it on
   before it signs in */
@property (nonatomic, assign) NoshiShiro *shiro;

@end
