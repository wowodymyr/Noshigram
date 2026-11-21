#import "noshi_gift_screen.h"
#import "noshi_star_gift.h"

/* one gift for one person: the note, whether to hide the name, and the payment in stars */
@interface NoshiGiftComposeController : NoshiGiftScreen

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog gift:(NoshiStarGift *)gift
              avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

/* runs on the main thread after the payment went through */
@property (nonatomic, copy) void (^sentHandler)(void);

@end
