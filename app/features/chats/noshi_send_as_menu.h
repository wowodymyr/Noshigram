#import <UIKit/UIKit.h>
#import "noshi_avatar_cache.h"

@interface NoshiSendAsMenu : UIView
- (id)initWithOptions:(NSArray *)options selected:(NSUInteger)selected avatars:(NoshiAvatarCache *)avatars handler:(void (^)(NSUInteger))handler;
- (void)showInView:(UIView *)host anchor:(CGRect)anchor;
@end
