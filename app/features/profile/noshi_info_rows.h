#import <UIKit/UIKit.h>

/* the grouped rows of the info screens of telegram for ios 4: white groups with a hairline along their edges on the grey ground, rows of 44 points in them with a line
   between them that starts at their words */

#define NOSHI_INFO_ROW_HEIGHT 44.0
/* the grey between two groups */
#define NOSHI_INFO_SECTION_GAP 24.0

/* the hairline of the groups and of the lines between their rows */
UIColor *NoshiInfoLineColor(void);

/* an empty white group, owned by the caller; its rows are added as its subviews */
UIView *NoshiNewInfoGroup(void);

/* sets the frames of the rows one under another in the group, places the group at y across the width and returns its height; a row left out of the array is not shown */
CGFloat NoshiLayoutInfoGroup(UIView *group, NSArray *rows, CGFloat y, CGFloat width);

/* places the hairlines of a group that holds something other than rows, such as the head of a profile */
void NoshiFitInfoGroupLines(UIView *group, BOOL top);

/* a row owned by the caller: words in the accent for an action, or plain words with a grey value at the right and, with a chevron, an arrow for a screen behind it */
@interface NoshiInfoRow : UIControl

- (id)initWithTitle:(NSString *)title accent:(BOOL)accent chevron:(BOOL)chevron target:(id)target action:(SEL)action;

@property (nonatomic, copy) NSString *title;
/* the grey words at the right end, nil for none */
@property (nonatomic, copy) NSString *value;

@end
