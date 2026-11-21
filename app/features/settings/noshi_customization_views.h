#import <UIKit/UIKit.h>

/* the shapes of the pictures as a grid of cells, the chosen one in a pressed well of the accent. the first cell is the rounded square */
@interface NoshiShapeGridView : UIView
@property (nonatomic, assign) NSInteger selectedShape;
/* runs on the main thread when the person taps a shape */
@property (nonatomic, copy) void (^chooseHandler)(NSInteger shape);
+ (CGFloat)heightForWidth:(CGFloat)width;
@end

/* what the choices of the customization look like together: a bar of the chosen material and gloss, a strip of the chat with its texture, a glossy button and a picture, and two rows with the chosen lines between */
@interface NoshiClassicPreviewView : UIView
- (void)refresh;
- (void)setPicture:(UIImage *)picture;
+ (CGFloat)height;
@end
