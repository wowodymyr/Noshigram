#import <UIKit/UIKit.h>


@class NoshiWelcomeController;

@protocol NoshiWelcomeControllerDelegate <NSObject>
- (void)welcomeControllerDidTapStart:(NoshiWelcomeController *)controller;
/* the faint link under the button: log in with a QR code, without typing a number */
- (void)welcomeControllerDidRequestQr:(NoshiWelcomeController *)controller;
@end

@interface NoshiWelcomeController : UIViewController <UIScrollViewDelegate>

@property (nonatomic, assign) id<NoshiWelcomeControllerDelegate> delegate;

@end
