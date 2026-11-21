#import "noshi_gift_screen.h"

/* the gifts for sale as tiles; a tap opens the screen that writes the note and pays */
@interface NoshiGiftCatalogController : NoshiGiftScreen

/* the user the gift goes to, as a chat with them */
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

/* runs on the main thread once a gift was paid for, so the screen below can refresh */
@property (nonatomic, copy) void (^sentHandler)(void);

@end
