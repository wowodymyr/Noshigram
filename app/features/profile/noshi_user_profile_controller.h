#import "noshi_gift_screen.h"
#import "noshi_sticker_library.h"

/* the profile of another person: photo and name, whether they are on line, the buttons for a gift and for their
   stories, their phone, bio, username and birthday when they share them */
@interface NoshiUserProfileController : NoshiGiftScreen

/* dialog is a chat with a user; stickers is for the chat of their personal channel */
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers;

@end
