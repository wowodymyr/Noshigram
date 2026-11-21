#import <UIKit/UIKit.h>

#import "noshi_login_flow.h"
#import "noshi_main_controller.h"
#import "noshi_phone_controller.h"
#import "noshi_session.h"
#import "noshi_welcome_controller.h"

@interface NoshiAppDelegate : UIResponder <UIApplicationDelegate, NoshiWelcomeControllerDelegate,
                                              NoshiLoginFlowDelegate, NoshiMainControllerDelegate,
                                              NoshiSessionDelegate, NoshiCallDelegate, UINavigationControllerDelegate>
@property (nonatomic, retain) UIWindow *window;
@end
