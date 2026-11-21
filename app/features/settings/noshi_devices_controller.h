#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* the Devices screen, in the modern theme */
@interface NoshiDevicesController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media;

@end
