#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session_channels.h"
#import "noshi_settings_kit.h"

/* the rights of one administrator as switches, the way edits them; the ones of a channel or those of a group, an
   admin can hand out only what it holds itself (the creator all of them), a title shown next to the name, and for
   an existing admin a way to take the post away */
@interface NoshiChannelRightsController : NoshiSettingsPageController

/* rights and rank are what the person has now; zero and nil for a subscriber who is being made an admin, who starts with the usual set */
- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel person:(NoshiPerson *)person rights:(uint32_t)rights
                 rank:(NSString *)rank isAdmin:(BOOL)isAdmin avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

/* runs on the main thread after the rights were saved or taken away, so the list behind this screen can load again */
@property (nonatomic, copy) void (^changedHandler)(void);

@end
