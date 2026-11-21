#import "noshi_list_controller.h"
#import "noshi_media_cache.h"
#import "noshi_sticker_library.h"

/* the Calls tab: the calls of the account, newest first, each with the person, how it went and when */
@interface NoshiCallsController : NoshiListController

@property (nonatomic, retain) NoshiMediaCache *media;
@property (nonatomic, retain) NoshiStickerLibrary *stickerLibrary;

@end
