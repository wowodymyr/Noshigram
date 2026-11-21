#import <UIKit/UIKit.h>

/* what the choices of the customization look like together: a bar of the chosen material and gloss, a strip of the chat with its texture, a glossy button and a picture, and two rows with the chosen lines between */
@interface NoshiClassicPreviewView : UIView
- (void)refresh;
- (void)setPicture:(UIImage *)picture;
+ (CGFloat)height;
@end
