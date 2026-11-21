#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* the account page of the settings: the name, the surname and the bio, who sees the bio, the personal channel and
   the way out */
@interface NoshiAccountController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
/* runs on the main thread after the name or the channel changed, so the screen under this one reads the person again */
@property (nonatomic, copy) void (^changedHandler)(void);
/* the row at the bottom: the screen below confirms and signs out */
@property (nonatomic, copy) void (^logoutHandler)(void);
@end
