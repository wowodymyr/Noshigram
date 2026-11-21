#import "noshi_settings_kit.h"
#import "noshi_session.h"
#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"

/* the people who looked at one of our stories, newest first, with when; opened from the count of views under the story */
@interface NoshiStoryViewersController : NoshiSettingsPageController
/* a tap on a row opens the profile of the person; their reaction stands at the right end of it. views and reactions are the counts the story carried, which the first page corrects */
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog storyId:(int32_t)storyId views:(int32_t)views reactions:(int32_t)reactions
              avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
/* the page in a navigation controller of its own, ready to be presented over the story; the classic theme gets a Close button in its bar */
- (UINavigationController *)presentableNavigation;
@end
