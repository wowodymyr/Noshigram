#import "noshi_avatar_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* the screen behind the Noshigram row of the settings; the pictures of the people are the ones bundled until the
   current profile photo of each @name has been fetched */
@interface NoshiAboutController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars;
@end
