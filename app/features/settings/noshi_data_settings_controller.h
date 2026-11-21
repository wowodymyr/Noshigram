#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* the Data and Memory screen, as far as the app has something behind each row: the memory the app takes and how
   long files stay, the network the app used, and the drafts the account keeps on the server */
@interface NoshiDataSettingsController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

@end
