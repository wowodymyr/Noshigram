#import <UIKit/UIKit.h>

#import "noshi_shiro.h"

/* shiro for the classic style, after the home screen of shiro 1.0.0 */
@interface NoshiClassicShiroController : UIViewController

/* host is any controller on the main screen; the screen goes on the main controller above it, or on the top one when there is none */
+ (void)presentWithShiro:(NoshiShiro *)shiro from:(UIViewController *)host;

@end
