#import <UIKit/UIKit.h>

#import "noshi_session.h"

@class NoshiMainController;
@class NoshiDetailHost;

@protocol NoshiMainControllerDelegate <NSObject>
- (void)mainController:(NoshiMainController *)controller requestsSignOut:(void (^)(NSString *errorName))completion;
@end

/* the signed in app: the screens of the system tab bar */
@interface NoshiMainController : UIViewController <UITabBarControllerDelegate, UINavigationControllerDelegate> {
    id<NoshiMainControllerDelegate> _delegate;
    NoshiDetailHost *_detailHost;
}

@property (nonatomic, assign) id<NoshiMainControllerDelegate> delegate;
/* set on a tablet, where this screen is the left pane and what it opens goes to the right one; nil on a phone */
@property (nonatomic, assign) NoshiDetailHost *detailHost;

- (id)initWithSession:(NoshiSession *)session;

@end
