#import <UIKit/UIKit.h>
#import "noshi_session.h"
#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"

typedef enum {
    NoshiChatPeekOpen,
    NoshiChatPeekPin,
    NoshiChatPeekMute,
    NoshiChatPeekArchive,
    NoshiChatPeekSelect,
    NoshiChatPeekMarkRead
} NoshiChatPeekAction;

void NoshiShowChatPeek(UIView *host, CGRect source, NoshiDialog *dialog, NoshiSession *session,
                         NoshiAvatarCache *avatars, NoshiMediaCache *media, BOOL canSelect,
                         void (^handler)(NoshiChatPeekAction action));
