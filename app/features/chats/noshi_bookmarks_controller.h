#import "noshi_gift_screen.h"
#import "noshi_sticker_library.h"

/* the messages the person bookmarked, newest first, from every chat: a tap opens the chat at the message, a swipe takes the bookmark away */
@interface NoshiBookmarksController : NoshiGiftScreen <UITableViewDataSource, UITableViewDelegate>

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

@end
