#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* NotificationsSettingsActivity: the kinds of chat (private chats, groups, channels, stories, reactions) with
   their exceptions, the vibration of a call, the number on the icon */
@interface NoshiNotificationsSettingsController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

@end
