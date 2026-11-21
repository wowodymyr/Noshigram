#import "noshi_gift_screen.h"
#import "noshi_profile_feed.h"

/* our pinned or archived stories as tiles; a tap plays them in the story viewer */
@interface NoshiStoryFeedController : NoshiGiftScreen

/* kind is NoshiFeedPinnedStories or NoshiFeedArchivedStories; owner is the chat with oneself */
- (id)initWithSession:(NoshiSession *)session kind:(NoshiProfileFeedKind)kind owner:(NoshiDialog *)owner avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media;

@end
