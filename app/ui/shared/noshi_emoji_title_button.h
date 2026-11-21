#import <UIKit/UIKit.h>

#import "noshi_emoji_label.h"

/* a button whose title is somebody else's text, such as a bot's key */
@interface NoshiEmojiTitleButton : UIButton {
    NoshiEmojiLabel *_face;
}

- (void)setFaceText:(NSString *)text font:(UIFont *)font color:(UIColor *)color;
/* hides the face while something else, such as a spinner, takes its place */
- (void)setFaceHidden:(BOOL)hidden;

@end
