#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_message.h"

/* what a hold on a reaction of a private chat shows, as in Telegram: the reaction large, and under it a card for each person who put it with the time they did. a tap anywhere takes it away.
   entries are dictionaries with "person" (NoshiPerson) and "date" (an NSNumber of unix seconds) */
@interface NoshiReactionTimePopup : UIView
+ (void)presentReaction:(NoshiReaction *)reaction entries:(NSArray *)entries avatars:(NoshiAvatarCache *)avatars inView:(UIView *)host;
@end
