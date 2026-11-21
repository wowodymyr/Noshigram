#import <UIKit/UIKit.h>

#import "noshi_bot_markup.h"

/* the keyboard a bot puts in place of the system one: rows of keys that fill the width, scrolling when there are more rows than fit */
@interface NoshiBotKeyboardView : UIView {
    NoshiMarkup *_markup;
    UIScrollView *_scroll;
    NSMutableArray *_keys;
    void (^_pressHandler)(NoshiMarkupButton *button);
}

@property (nonatomic, copy) void (^pressHandler)(NoshiMarkupButton *button);
@property (nonatomic, readonly, retain) NoshiMarkup *markup;

- (void)setMarkup:(NoshiMarkup *)markup;
/* the height the keys want for a width, no taller than maxHeight; a keyboard that is not asked to resize fills maxHeight */
- (CGFloat)preferredHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight;

@end
