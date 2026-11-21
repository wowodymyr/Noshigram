#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* who is signed in and the way out, as a grouped system table with the person on top */
@interface NoshiClassicProfileController : UITableViewController <UIActionSheetDelegate>

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars;

/* the person confirmed; the handler asks the server to end the session and calls back with nil or the rpc error name */
@property (nonatomic, retain) NoshiMediaCache *media;
@property (nonatomic, retain) NoshiStickerLibrary *stickerLibrary;
@property (nonatomic, copy) void (^signOutHandler)(void (^completion)(NSString *errorName));

@end
