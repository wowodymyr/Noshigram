#import "noshi_list_controller.h"
#import "noshi_media_cache.h"
#import "noshi_sticker_library.h"

/* a community: a switch that folds it into one entry of the chat list, then the chats it groups, the ones the
   person is in and the ones they can only look at */
@interface NoshiCommunityController : NoshiListController

/* known are the dialogs of the chat list, whose last messages the chats of the community take over */
- (id)initWithSession:(NoshiSession *)session community:(NoshiDialog *)community known:(NSArray *)known avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
