#import "noshi_gift_screen.h"
#import "noshi_sticker_library.h"

/* the profile of a channel, or of a group built on one */
@interface NoshiChannelProfileController : NoshiGiftScreen

/* dialog is a chat with a channel (peer kind 3); stickers is for the chat of the discussion group */
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers;

@end
