#import "noshi_settings_kit.h"

@class NoshiSession;

/* the Change Chat Background screen of the chat settings */
@interface NoshiWallpaperController : NoshiSettingsPageController

/* the wallpaper of every chat, from the chat settings */
- (id)init;
/* the wallpaper of one chat alone, from the menu of that chat: what is picked stays in this chat, and the app and its other chats keep theirs */
- (id)initWithPeerKind:(int32_t)peerKind peerId:(long long)peerId;

/* the account the page is opened from */
@property (nonatomic, retain) NoshiSession *session;

@end
