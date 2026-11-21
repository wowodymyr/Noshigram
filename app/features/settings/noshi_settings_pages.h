#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_settings_kit.h"

/* the Appearance page of the Noshigram settings, as far as the app has something behind each row */
@interface NoshiAppearanceSettingsController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session;
@end
