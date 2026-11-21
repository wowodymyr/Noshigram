#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_star_gift.h"
#import "noshi_text_layout.h"

/* the geometry of a gift card in a chat for one width: the picture on top, a title, a line under it, the note or (unique
   gifts without a note) the model, backdrop and symbol, and the button */
@interface NoshiGiftCardLayout : NSObject {
    NoshiStarGift *_gift;
    CGSize _size;
    CGRect _stickerFrame;
    CGRect _buttonFrame;
    NoshiTextLayout *_title;
    NoshiTextLayout *_subtitle;
    NoshiTextLayout *_note;
    NoshiTextLayout *_button;
    CGPoint _titleOrigin;
    CGPoint _subtitleOrigin;
    CGPoint _noteOrigin;
    CGPoint _buttonTextOrigin;
    NSArray *_rowNames;
    NSArray *_rowValues;
    NSArray *_rowNameOrigins;
    NSArray *_rowValueOrigins;
}
/* subtitle is the line under the title, note the words that came with the gift (may be empty) */
+ (NoshiGiftCardLayout *)layoutForGift:(NoshiStarGift *)gift title:(NSString *)title subtitle:(NSString *)subtitle note:(NSString *)note
                                    width:(CGFloat)width;
@property (nonatomic, readonly, retain) NoshiStarGift *gift;
@property (nonatomic, readonly) CGSize size;
@property (nonatomic, readonly) CGRect stickerFrame;
@property (nonatomic, readonly) CGRect buttonFrame;
@property (nonatomic, readonly, retain) NoshiTextLayout *title;
@property (nonatomic, readonly, retain) NoshiTextLayout *subtitle;
@property (nonatomic, readonly, retain) NoshiTextLayout *note;
@property (nonatomic, readonly, retain) NoshiTextLayout *button;
@property (nonatomic, readonly) CGPoint titleOrigin;
@property (nonatomic, readonly) CGPoint subtitleOrigin;
@property (nonatomic, readonly) CGPoint noteOrigin;
@property (nonatomic, readonly) CGPoint buttonTextOrigin;
@property (nonatomic, readonly, retain) NSArray *rowNames;
@property (nonatomic, readonly, retain) NSArray *rowValues;
@property (nonatomic, readonly, retain) NSArray *rowNameOrigins;
@property (nonatomic, readonly, retain) NSArray *rowValueOrigins;
@end

/* the card itself: a unique gift sits on its backdrop with the pattern, a regular one on a dark plate; the animation of the
   gift plays once when the card comes into view and the button sparkles while it is on screen */
@interface NoshiGiftCardView : UIView
- (void)configureWithLayout:(NoshiGiftCardLayout *)layout media:(NoshiMediaCache *)media;
- (void)setActive:(BOOL)active;
/* drops the animation and the pending loads; the next configure starts over */
- (void)discard;
@end
