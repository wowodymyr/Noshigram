#import "noshi_avatar_cache.h"
#import "noshi_dialog.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

#import "noshi_dialog.h"

/* the channels the person manages, each with its picture, to choose the one for the profile from; the first row takes the channel off */
@interface NoshiChannelPickerController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
@property (nonatomic, copy) NSString *screenTitle;
/* the channel on the profile now, which is marked */
@property (nonatomic, assign) long long currentChannelId;
/* runs on the main thread with the chosen channel, or nil for none */
@property (nonatomic, copy) void (^pickHandler)(NoshiDialog *channel);

@end
