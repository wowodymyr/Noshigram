#import "noshi_gift_screen.h"
#import "noshi_person.h"
#import "noshi_session_channels.h"

/* the QR code of a t.me link with the picture of its owner in its middle, and the ways to copy or share the link */
@interface NoshiProfileQrController : NoshiGiftScreen

- (id)initWithSession:(NoshiSession *)session person:(NoshiPerson *)person avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
/* a channel or group; a channel with no link the account can see shows a line that says so in place of the code */
- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

@end
