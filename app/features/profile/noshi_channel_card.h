#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_session_profile.h"

/* the personal channel of a profile as a card: "Channel" with its follower count, the picture, the name, the
   newest line and its time */
@interface NoshiChannelCard : UIControl

- (void)configureWithChannel:(NoshiPersonalChannel *)channel avatars:(NoshiAvatarCache *)avatars;
+ (CGFloat)height;

@end
