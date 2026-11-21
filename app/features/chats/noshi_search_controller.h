#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* the search screen of the chat list: a field with the keyboard up, ten kinds of results to pick from */
@interface NoshiSearchController : UIViewController

/* dialogs is the loaded chat list, newest first, which the local kinds search and the people on top come from */
- (id)initWithSession:(NoshiSession *)session dialogs:(NSArray *)dialogs avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

@end
