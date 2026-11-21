#import <UIKit/UIKit.h>

@protocol NoshiDismissPanGuard <NSObject>
- (BOOL)noshiCanDismissByPan;
@end

/* a downward pull closes a card; scrolling content may start a pull only at its top */
void NoshiAddDismissPan(UIView *card, id target, SEL action);
