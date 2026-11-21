#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_sticker_library.h"

@class NoshiStickerPicker;

@protocol NoshiStickerPickerDelegate <NSObject>
- (void)stickerPicker:(NoshiStickerPicker *)picker didPickSticker:(NoshiSticker *)sticker;
@optional
/* the tile "Create" among the recent stickers: the screen starts the making of a sticker */
- (void)stickerPickerDidTapCreate:(NoshiStickerPicker *)picker;
@end

/* the stickers of the account as one list of sections them */
@interface NoshiStickerPicker : UIView <UITableViewDataSource, UITableViewDelegate> {
    id<NoshiStickerPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<NoshiStickerPickerDelegate> delegate;
/* the height at the bottom that the floating tabs of the panel cover, which the list leaves free to scroll past */
@property (nonatomic, assign) CGFloat bottomInset;

- (id)initWithMedia:(NoshiMediaCache *)media library:(NoshiStickerLibrary *)library;
/* called each time the picker comes on screen, to fetch what is missing and to refresh the favorites and the recent ones */
- (void)prepare;

@end
