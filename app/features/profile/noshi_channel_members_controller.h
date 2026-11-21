#import "noshi_gift_screen.h"
#import "noshi_session_channels.h"

/* one of the three lists an admin keeps: the subscribers, the administrators and the blacklist */
@interface NoshiChannelMembersController : NoshiGiftScreen <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel list:(NoshiChannelList)list avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media;

/* set before the screen is shown: the person tapped is passed here and the screen goes back */
@property (nonatomic, copy) void (^pickHandler)(NoshiChannelMember *member);
/* runs on the main thread after a change that moves the counts of the channel (an admin appointed or taken away, a person banned or let back) */
@property (nonatomic, copy) void (^changedHandler)(void);

@end
