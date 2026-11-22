#import <UIKit/UIKit.h>

/* what the choices of the customization look like together: a bar, a strip of the chat with a key and a picture, and two rows with the chosen lines between */
@interface NoshiClassicPreviewView : UIView
- (void)refresh;
- (void)setPicture:(UIImage *)picture;
+ (CGFloat)height;
@end
