#import "noshi_media_cache.h"
#import "noshi_notify_ui.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* NotificationsSoundActivity: the tone of a kind of chat or of one chat */
@interface NoshiNotificationsSoundController : NoshiSettingsPageController

/* current is an NSValue of the noshi_notify_sound that stands now, nil for the default one. apply gets every tone the person picks, on the main thread */
- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media title:(NSString *)title current:(NSValue *)current
                apply:(void (^)(noshi_notify_sound sound))apply;

@end
