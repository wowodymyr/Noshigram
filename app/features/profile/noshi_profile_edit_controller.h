#import "noshi_gift_screen.h"
#import "noshi_session_profile.h"

/* the profile in cards: the name, the bio with its counter, the phone, the username and the birthday, the personal
   channel and the way out */
@interface NoshiProfileEditController : NoshiGiftScreen

- (id)initWithSession:(NoshiSession *)session person:(NoshiPerson *)person fullUser:(NoshiFullUser *)full avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media;

/* runs on the main thread after anything was saved, so the profile below loads again */
@property (nonatomic, copy) void (^changedHandler)(void);
/* the row at the bottom: runs when the person taps it, which is the screen below's to confirm */
@property (nonatomic, copy) void (^logoutHandler)(void);

@end
