#import "noshi_avatar_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* About, the last row of the settings: the version, the links, the authors and the credits; the pictures of the people are the ones bundled until the
   current profile photo of each @name has been fetched */
@interface NoshiAboutController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars;
@end
