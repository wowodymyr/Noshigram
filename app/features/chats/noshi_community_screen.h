#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* the screen a community opens into, in the style the app runs in; known are the dialogs of the chat list, closeHandler runs once the
   person leaves it for the list */
UIViewController *NoshiCommunityScreen(NoshiSession *session, NoshiDialog *community, NSArray *known, NoshiAvatarCache *avatars,
                                         NoshiMediaCache *media, NoshiStickerLibrary *stickers, void (^closeHandler)(void));
