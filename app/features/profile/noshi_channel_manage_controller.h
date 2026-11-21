#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session_channels.h"
#import "noshi_settings_kit.h"

/* the management screen of a channel or group for its creator and admins */
@interface NoshiChannelManageController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

/* runs on the main thread after the channel changed, with the full channel as the server now has it, so the profile behind can show it */
@property (nonatomic, copy) void (^changedHandler)(NoshiFullChannel *channel);

@end
