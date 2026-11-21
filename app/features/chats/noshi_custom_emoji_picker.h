#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_symbol.h"

@class NoshiCustomEmojiPicker;

@protocol NoshiCustomEmojiPickerDelegate <NSObject>
- (void)customEmojiPicker:(NoshiCustomEmojiPicker *)picker didPickEmoji:(NoshiCustomEmojiDocument *)emoji;
@optional
/* the tab put first by leadingSymbol was chosen; the picker shows no grid then, and the owner shows its own content under the strip */
- (void)customEmojiPickerDidSelectLeading:(NoshiCustomEmojiPicker *)picker;
/* a set was chosen, or the first load of the sets finished: the owner takes its own content away */
- (void)customEmojiPickerDidSelectSet:(NoshiCustomEmojiPicker *)picker;
@end

/* the custom emoji sets of a Premium account as a strip of set names over a grid of the emoji of the chosen one */
@interface NoshiCustomEmojiPicker : UIView {
    id<NoshiCustomEmojiPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<NoshiCustomEmojiPickerDelegate> delegate;
/* a glyph tab before the sets, for an owner that has content of its own to offer first; it is the chosen tab until a set is tapped */
@property (nonatomic, assign) BOOL hasLeading;
@property (nonatomic, assign) NoshiSymbol leadingSymbol;
@property (nonatomic, copy) NSString *leadingLabel;
/* a set of the strip draws a lock, for an account that may look at custom emoji and not use them */
@property (nonatomic, assign) BOOL showsLocks;
/* the height of the strip, which an owner with a leading tab starts its own content under */
+ (CGFloat)stripHeight;

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media;
/* called each time the picker comes on screen, to fetch what is missing */
- (void)prepare;

@end
