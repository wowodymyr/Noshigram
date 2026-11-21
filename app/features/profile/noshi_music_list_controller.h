#import "noshi_gift_screen.h"

/* the songs saved on a profile, a page at a time, with the player under them */
@interface NoshiMusicListController : NoshiGiftScreen

/* dialog is the chat with the person whose profile it is, or the chat with oneself for one's own; first is the song the profile
   showed, listed at once while the first page loads */
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog first:(NoshiMedia *)first avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media;

@end
