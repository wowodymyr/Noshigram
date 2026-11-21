#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* the Stickers and Emoji screen of the settings */
@interface NoshiStickersSettingsController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media;

@end
