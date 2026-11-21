#import <UIKit/UIKit.h>

/* a screen on top of the stack that adopts this can keep the swipe from taking it away while it is not safe to leave */
@protocol NoshiBackSwipeBlocking <NSObject>
- (BOOL)blocksBackSwipe;
@end

/* the swipe back from the left edge of the screen */
@interface NoshiBackSwipe : NSObject
- (id)initWithNavigationController:(UINavigationController *)navigation;
@end
