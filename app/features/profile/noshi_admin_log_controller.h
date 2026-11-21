#import "noshi_gift_screen.h"
#import "noshi_session_channels.h"

/* the recent actions of a group or channel: what its admins did lately, newest first, searchable by text; only an admin may open it */
@interface NoshiAdminLogController : NoshiGiftScreen <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

@end
