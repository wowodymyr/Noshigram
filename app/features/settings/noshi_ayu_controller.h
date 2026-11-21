#import "noshi_settings_kit.h"

@class NoshiSession;

/* AyuMoments it: the ghost mode, the filters of messages by a regular expression, and the keeping of what the
   other side deletes or changes */
@interface NoshiAyuController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session;
@end

/* the three switches of the ghost mode */
@interface NoshiGhostController : NoshiSettingsPageController
@end

/* the list of the filters of the person, with the way to add one and to change or remove it */
@interface NoshiRegexFiltersController : NoshiSettingsPageController
@end
