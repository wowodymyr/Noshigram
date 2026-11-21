#import <UIKit/UIKit.h>

#import "noshi_dialog.h"
#import "noshi_session.h"

@class NoshiAvatarCache, NoshiMediaCache, NoshiStickerLibrary;

/* the message button of a profile: the chat the profile was opened from when it is the one right below, so the way
   back does not pile a second copy of the same chat on the stack */
void NoshiProfileShowChat(UIViewController *profile, NoshiSession *session, NoshiDialog *dialog, NoshiAvatarCache *avatars,
                            NoshiMediaCache *media, NoshiStickerLibrary *stickers);
