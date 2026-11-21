#import <UIKit/UIKit.h>

@interface NoshiPhotoEditor : UIViewController
- (id)initWithImage:(UIImage *)image completion:(void (^)(UIImage *image))completion;
@end
