#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"
#import "noshi_sticker_library.h"

/* the Settings tab, which is the profile too, as in telegram for ios 4: the photo and the name of the signed in person at the top, a tap on the name or on the
   first row opens the full profile, then the groups of rows */
@interface NoshiSettingsController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

/* handed to the full profile, which opens the gifts and the stickers of the account */
@property (nonatomic, retain) NoshiStickerLibrary *stickerLibrary;
/* signs the account out of this device; the completion gets nil on success and the name of the error otherwise */
@property (nonatomic, copy) void (^signOutHandler)(void (^completion)(NSString *errorName));

@end
