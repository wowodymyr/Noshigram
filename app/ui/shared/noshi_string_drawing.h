#import <UIKit/UIKit.h>

/* how a line that does not fit ends; the numbers are the ones UILineBreakMode and NSLineBreakMode share */
typedef enum {
    NoshiStringWrap = 0,
    NoshiStringClip = 2,
    NoshiStringTailTruncate = 3,
    NoshiStringMiddleTruncate = 5
} NoshiStringBreak;

/* plain string measuring and drawing. ios 5 and 6 have only the UIKit methods that ios 7 deprecated, and the
   attribute based ones that replaced them do not exist there */
CGSize NoshiStringSize(NSString *string, UIFont *font);
CGSize NoshiStringSizeIn(NSString *string, UIFont *font, CGSize constraint);
void NoshiDrawStringAt(NSString *string, UIFont *font, CGPoint point);
/* the color is the one already set on the context; alignment is one of the NoshiTextAlignment values */
void NoshiDrawStringIn(NSString *string, UIFont *font, CGRect rect, NoshiStringBreak mode, NSInteger alignment);

/* a one line label whose room is fixed (a date, a time, a last seen line) shrinks its letters, down to minimum points, before it would end in three dots */
void NoshiLabelFitToWidth(UILabel *label, CGFloat minimum);
