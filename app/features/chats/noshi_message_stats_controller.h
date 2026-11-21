#import "noshi_settings_kit.h"
#import "noshi_session.h"

@class NoshiAvatarCache;
@class NoshiMessage;

/* the statistics of one post of a channel the account administers: the counts, the graph of views and shares, the graph of reactions by
   emotion, and the public channels that forwarded the post */
@interface NoshiMessageStatsController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog message:(NoshiMessage *)message avatars:(NoshiAvatarCache *)avatars;
@end
