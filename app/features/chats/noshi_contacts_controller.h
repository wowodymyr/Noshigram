#import "noshi_list_controller.h"
#import "noshi_media_cache.h"
#import "noshi_sticker_library.h"

/* the contact list, alphabetical, with the last seen line under each name */
@interface NoshiContactsController : NoshiListController

/* what a chat opened from a contact needs for its pictures and its sticker panel */
@property (nonatomic, retain) NoshiMediaCache *media;
@property (nonatomic, retain) NoshiStickerLibrary *stickerLibrary;

@end
