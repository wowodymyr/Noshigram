#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_notify_ui.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* NotificationsCustomSettingsActivity: one kind of chat; the kind NoshiNotifyKindAllExceptions lists the
   exceptions of every kind and nothing else */
@interface NoshiNotificationsKindController : NoshiSettingsPageController

/* exceptions is what the main page already loaded, nil to ask the server */
- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media kind:(NoshiNotifyKind)kind exceptions:(NSArray *)exceptions;

@end
