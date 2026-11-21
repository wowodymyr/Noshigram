#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* the screen a forum opens into, in the style the app runs in; closeHandler runs once the person leaves it for the list */
UIViewController *NoshiTopicsScreen(NoshiSession *session, NoshiDialog *forum, NoshiAvatarCache *avatars, NoshiMediaCache *media,
                                      NoshiStickerLibrary *stickers, void (^closeHandler)(void));

/* the same for a list of chats that is on screen, which a phone shows beside the topics as a column of pictures; archiveHandler opens the archive from its first button, and
   nil leaves the button out */
UIViewController *NoshiTopicsScreenWithChats(NoshiSession *session, NoshiDialog *forum, NSArray *dialogs, NoshiAvatarCache *avatars, NoshiMediaCache *media,
                                               NoshiStickerLibrary *stickers, void (^archiveHandler)(void), void (^closeHandler)(void));
