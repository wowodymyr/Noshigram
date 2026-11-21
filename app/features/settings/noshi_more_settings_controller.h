#import "noshi_settings_kit.h"

@class NoshiSession;

/* the More page of the Noshigram settings: the proxy, the local Premium and the other switches of the client */
@interface NoshiMoreSettingsController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session;
@end
