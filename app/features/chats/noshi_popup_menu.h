#import <UIKit/UIKit.h>

#import "noshi_symbol.h"

/* the menu of the dots of a screen, shown as telegram for ios 4 showed it: the system sheet of buttons from the bottom with a Cancel under them, as the dots of the settings
   already were. a view only so that the screens keep their way of making and showing it */
@interface NoshiPopupMenu : UIView

/* kept for the screens that set it; the sheet of the system minds the keyboard by itself */
@property (nonatomic, assign) CGFloat bottomInset;
/* the button drawn in red, as the system draws a deletion; -1, the default, for none */
@property (nonatomic, assign) NSInteger destructiveIndex;

/* each button has a title; the glyphs are not drawn on the sheet of the system. the handler runs with the button's index, and not at all on Cancel */
- (id)initWithTitles:(NSArray *)titles symbols:(const NoshiSymbol *)symbols handler:(void (^)(NSUInteger index))handler;
/* the sheet comes up from host; anchor is where a popover of an ipad points */
- (void)showInView:(UIView *)host anchor:(CGPoint)anchor;
- (void)dismiss;

@end
