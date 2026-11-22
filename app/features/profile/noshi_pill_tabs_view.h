#import <UIKit/UIKit.h>

/* the segments of the system on a white strip, as the shared media of telegram for ios 4 had them; they share the width while the titles fit, and scroll otherwise */
@interface NoshiPillTabsView : UIView

- (id)initWithTitles:(NSArray *)titles;

@property (nonatomic, assign) NSUInteger selectedIndex;
/* runs on the main thread when the person taps another tab */
@property (nonatomic, copy) void (^changeHandler)(NSUInteger index);

@end
