#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* the Calls tab in the classic style: the system table of the calls of the account, newest first */
@interface NoshiClassicCallsController : UITableViewController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

@end
