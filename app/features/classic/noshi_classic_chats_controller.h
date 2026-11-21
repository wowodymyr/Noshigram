#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* the chat list built from the system's own table, search bar, toolbar, segmented control and edit button */
@interface NoshiClassicChatsController : UITableViewController

/* 0 lists the chats, 1 the archive */
- (id)initWithSession:(NoshiSession *)session folderId:(int32_t)folderId avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

/* the unread messages of the chats that are not muted, for the badge on the tab */
@property (nonatomic, copy) void (^unreadHandler)(NSInteger total);

/* a second tap on the chats tab brings the list back to its top, search bar included, as the modern bar does */
- (void)scrollToTopAnimated;

@end
