#import <UIKit/UIKit.h>

/* the wide call to action button: a flat rounded plate of the accent color, darker while it is pressed; the label is a real subview so it stays sharp and accessible */
@interface NoshiFlatButton : UIControl

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat titleSize;

@end
