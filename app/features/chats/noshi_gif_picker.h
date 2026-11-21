#import <UIKit/UIKit.h>

#import "noshi_bot.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

@class NoshiGifPicker;

@protocol NoshiGifPickerDelegate <NSObject>
/* an animation of the account's own list, or one the search found that Telegram already keeps */
- (void)gifPicker:(NoshiGifPicker *)picker didPickGif:(NoshiMedia *)gif;
/* a search result that is a link a bot hosts, which the bot sends in the person's name */
- (void)gifPicker:(NoshiGifPicker *)picker didPickInlineResult:(NoshiInlineResult *)result queryId:(long long)queryId;
@end

/* the animations of the account as a grid of pictures, with a search over them and the quick words the panel
   offers in its search bar */
@interface NoshiGifPicker : UIView <UITableViewDataSource, UITableViewDelegate> {
    id<NoshiGifPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<NoshiGifPickerDelegate> delegate;
/* the chat the animation goes to, which the inline search is asked in */
@property (nonatomic, retain) NoshiDialog *dialog;
@property (nonatomic, assign) CGFloat bottomInset;

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media library:(NoshiStickerLibrary *)library;
/* called each time the picker comes on screen: the saved animations are asked for again */
- (void)prepare;

@end
