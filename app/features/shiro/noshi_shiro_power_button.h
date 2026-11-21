#import <UIKit/UIKit.h>

typedef enum {
    NoshiShiroPowerOff = 0,
    /* the shape cycles through the others while the tunnel is made */
    NoshiShiroPowerWorking,
    NoshiShiroPowerOn,
    NoshiShiroPowerFailed
} NoshiShiroPowerState;

/* the power control as a Material shape: a scallop in a quiet tone when the tunnel is off, the same scallop lit
   and turning slowly over a counter-turning bloom when it carries traffic */
@interface NoshiShiroPowerButton : UIControl

@property (nonatomic, assign) NoshiShiroPowerState powerState;
/* repaints in the colors of the current theme */
- (void)applyTheme;

@end
