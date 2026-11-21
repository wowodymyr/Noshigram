#import "noshi_session.h"
#import "noshi_settings_kit.h"
#import "noshi_media_cache.h"

void NoshiLoadQuickReactionPicture(NoshiSession *session, NoshiMediaCache *media, void (^picture)(void));

@interface NoshiQuickReactionController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session;
@end
