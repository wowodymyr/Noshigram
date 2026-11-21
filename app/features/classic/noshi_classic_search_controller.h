#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* the search of the chat list in the classic style: the system's search field in the navigation bar, a scrolling
   strip of the ten kinds of results, system rows, and the duck when a query finds nothing */
@interface NoshiClassicSearchController : UIViewController

/* dialogs is the loaded chat list, newest first */
- (id)initWithSession:(NoshiSession *)session dialogs:(NSArray *)dialogs avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

@end
