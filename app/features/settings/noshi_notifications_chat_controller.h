#import "noshi_media_cache.h"
#import "noshi_notify_ui.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* ProfileNotificationsActivity, as far as it means something on this phone; whether the chat notifies and until
   when, the text of the message in the banner, the stories of a person, the tone, and the way back to the settings
   of its kind */
@interface NoshiNotificationsChatController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media peerKind:(int32_t)peerKind peerId:(long long)peerId peerHash:(long long)peerHash
              channel:(BOOL)broadcast topic:(int32_t)topic title:(NSString *)title;

@end
