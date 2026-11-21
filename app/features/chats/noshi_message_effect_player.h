#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_session.h"

/* the animation of a message effect over the chat, once: the lottie of the effect, or its sticker when it has none, as large as the width of the screen and centered. one plays at a time,
   a new one ends the one before, and nothing plays with reduced motion */
@interface NoshiMessageEffectPlayer : NSObject
+ (void)playEffect:(NoshiMessageEffect *)effect inView:(UIView *)host media:(NoshiMediaCache *)media;
+ (void)dismiss;
@end
