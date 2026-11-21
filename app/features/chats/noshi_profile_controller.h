#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

@class NoshiProfileController;

@protocol NoshiProfileControllerDelegate <NSObject>
/* the user confirmed; the answer arrives once the server has ended the session */
- (void)profileController:(NoshiProfileController *)controller requestsSignOut:(void (^)(NSString *errorName))completion;
/* the settings button: the app shows its settings tab */
- (void)profileControllerRequestsSettings:(NoshiProfileController *)controller;
@end

/* who is signed in: photo, name and status, the buttons for a photo, the profile and the settings, the phone, the
   bio and the username, and under them our stories */
@interface NoshiProfileController : UIViewController {
    id<NoshiProfileControllerDelegate> _delegate;
}

@property (nonatomic, assign) id<NoshiProfileControllerDelegate> delegate;
@property (nonatomic, assign) CGFloat bottomInset;
@property (nonatomic, retain) NoshiAvatarCache *avatars;
/* the pictures of stories and gifts load from here */
@property (nonatomic, retain) NoshiMediaCache *media;
/* a chat opened from the profile, such as the personal channel, needs this for its sticker panel */
@property (nonatomic, retain) NoshiStickerLibrary *stickerLibrary;

- (id)initWithSession:(NoshiSession *)session;

@end
