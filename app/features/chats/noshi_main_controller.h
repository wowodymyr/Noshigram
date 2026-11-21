#import <UIKit/UIKit.h>

#import "noshi_chats_controller.h"
#import "noshi_session.h"
#import "noshi_profile_controller.h"
#import "noshi_tab_bar.h"

@class NoshiMainController;
@class NoshiDetailHost;

@protocol NoshiMainControllerDelegate <NSObject>
- (void)mainController:(NoshiMainController *)controller requestsSignOut:(void (^)(NSString *errorName))completion;
@end

/* the signed in app: one screen at a time over a tab bar */
@interface NoshiMainController : UIViewController <NoshiTabBarDelegate, NoshiChatsControllerDelegate,
                                                     NoshiProfileControllerDelegate> {
    id<NoshiMainControllerDelegate> _delegate;
    NoshiDetailHost *_detailHost;
}

@property (nonatomic, assign) id<NoshiMainControllerDelegate> delegate;
/* set on a tablet, where this screen is the left pane and what it opens goes to the right one; nil on a phone */
@property (nonatomic, assign) NoshiDetailHost *detailHost;

- (id)initWithSession:(NoshiSession *)session;

@end
