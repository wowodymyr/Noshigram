#import <UIKit/UIKit.h>

#import "noshi_bot_markup.h"

/* the buttons a bot puts under a message: rows of equal buttons laid out by the core, each a touch target of its own */
@interface NoshiMarkupView : UIView {
    NoshiMarkup *_markup;
    NSMutableArray *_buttons;
    NSData *_frames;
    NSInteger _busy;
    void (^_pressHandler)(NoshiMarkupButton *button);
}

/* runs on a press of an enabled button */
@property (nonatomic, copy) void (^pressHandler)(NoshiMarkupButton *button);
@property (nonatomic, readonly, retain) NoshiMarkup *markup;

/* shows the buttons at the frames the item worked out; the frames are relative to this view */
- (void)setMarkup:(NoshiMarkup *)markup frames:(NSData *)frames;
/* a spinner on the button while its press is being answered; the button of a markup, or nil for none */
- (void)setBusyButton:(NoshiMarkupButton *)button;

@end
