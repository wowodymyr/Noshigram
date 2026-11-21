#import <UIKit/UIKit.h>
#import "noshi_avatar_cache.h"
#import "noshi_message.h"

/* the same bounded chip layout supplies row heights and the touch controls */
CGFloat NoshiReactionsHeight(NSArray *reactions, CGFloat width, BOOL counts);
/* the same layout for a row that shares its bubble with the time: the height, the width the widest row takes, and the width of the last row, which is
   what the time has to fit beside */
CGFloat NoshiReactionsMetrics(NSArray *reactions, CGFloat width, BOOL counts, CGFloat *used, CGFloat *lastRow);

@interface NoshiReactionsView : UIView {
    NSArray *_reactions;
    NSArray *_buttons;
    BOOL _counts;
    BOOL _alignRight;
    BOOL _inBubble;
    BOOL _outgoing;
    void (^_pickHandler)(NoshiReaction *reaction);
    void (^_holdHandler)(NoshiReaction *reaction);
    NoshiAvatarCache *_avatars;
}
@property (nonatomic, assign) BOOL alignRight;
/* the chips sit in the bubble of a message; translucent over the bubble color, since the card color of the free
   standing chips would vanish on the bubble of our own messages. outgoing tells which bubble it is */
@property (nonatomic, assign) BOOL inBubble;
@property (nonatomic, assign) BOOL outgoing;
/* where the pictures of the faces on the chips come from; without it a chip with faces shows the colors and initials */
@property (nonatomic, assign) NoshiAvatarCache *avatars;
@property (nonatomic, copy) void (^pickHandler)(NoshiReaction *reaction);
/* a hold on a chip; the chat decides what it shows (the time of a reaction in a private chat) */
@property (nonatomic, copy) void (^holdHandler)(NoshiReaction *reaction);
/* whether a point of this view is on a chip, so a hold there is not a hold on the bubble under it */
- (BOOL)chipContainsPoint:(CGPoint)point;
- (void)setReactions:(NSArray *)reactions counts:(BOOL)counts;
/* animated: a chip that is new, or whose count changed since the last call, pops in with an overshoot */
- (void)setReactions:(NSArray *)reactions counts:(BOOL)counts animated:(BOOL)animated;
/* where the chip of a reaction stands in view's coordinates, CGRectZero when it has none */
- (CGRect)frameOfReaction:(NoshiReaction *)reaction inView:(UIView *)view;
/* a chip of a reaction that was taken away is still shrinking out of view */
- (BOOL)animatingOut;

@end
