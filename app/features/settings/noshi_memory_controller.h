#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_settings_kit.h"

/* what the app keeps on the phone: the size of the photos of people and of the files of messages, how long the
   files stay, and the way to empty both */
@interface NoshiMemoryController : NoshiSettingsPageController

- (id)initWithAvatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

@end
