#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* a community in the classic style: a grouped table with the switch that folds it into one entry of the chat list,
   and the chats it groups in two sections */
@interface NoshiClassicCommunityController : UITableViewController

- (id)initWithSession:(NoshiSession *)session community:(NoshiDialog *)community known:(NSArray *)known avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
