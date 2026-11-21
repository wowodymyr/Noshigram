#import <UIKit/UIKit.h>
#import "noshi_session_profile.h"

@interface NoshiRatingBadge : UIControl
@property (nonatomic, assign) int32_t level;
@end

void NoshiShowRating(UIView *host, NoshiFullUser *user);
