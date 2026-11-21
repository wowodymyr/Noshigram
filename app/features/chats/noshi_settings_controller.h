#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* the Settings tab: the profile of the signed in person at the top with a camera to change the photo, then the
   cards of sections, each an icon in a tinted circle with a title and a line under it */
@interface NoshiSettingsController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

/* signs the account out of this device; the completion gets nil on success and the name of the error otherwise */
@property (nonatomic, copy) void (^signOutHandler)(void (^completion)(NSString *errorName));

@end
