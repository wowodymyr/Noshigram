#import "noshi_session_channels.h"
#import "noshi_session_invites.h"
#import "noshi_settings_kit.h"

/* the form of one invite link: its name, how long it lives, how many people it takes in and whether an admin has to accept them. invite is nil for a new link;
   saved runs on the main thread with the link as the server made it, and the screen goes back */
@interface NoshiChannelInviteEditController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel invite:(NoshiInvite *)invite saved:(void (^)(NoshiInvite *saved))saved;

@end
