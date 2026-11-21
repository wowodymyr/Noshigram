#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session_channels.h"
#import "noshi_session_invites.h"
#import "noshi_settings_kit.h"

/* the invite links the account made for a channel or a group: the live ones, the revoked ones, and what to do with each (copy, share, change the term and the
   number of joins, revoke, delete) */
@interface NoshiChannelInvitesController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

@end
