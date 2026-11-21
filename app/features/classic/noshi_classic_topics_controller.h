#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* the topics of a forum in the classic style: the system table with a row each, pinned first */
@interface NoshiClassicTopicsController : UITableViewController

- (id)initWithSession:(NoshiSession *)session forum:(NoshiDialog *)forum avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);

/* whether this screen is the topics of that forum, so a profile opened from it can go back instead of stacking another */
- (BOOL)showsForum:(NoshiDialog *)forum;

@end
