#import <UIKit/UIKit.h>

#import "noshi_custom_emoji_picker.h"
#import "noshi_emoji_picker.h"
#import "noshi_gif_picker.h"
#import "noshi_sticker_picker.h"

@class NoshiInputPanel;

@protocol NoshiInputPanelDelegate <NSObject>
- (void)inputPanel:(NoshiInputPanel *)panel didPickEmoji:(NSString *)emoji;
- (void)inputPanelDidTapBackspace:(NoshiInputPanel *)panel;
/* the word question of the emoji search is gone; the field lost its focus to it, so the owner shows the panel again */
- (void)inputPanelDidCloseEmojiSearch:(NoshiInputPanel *)panel;
- (void)inputPanel:(NoshiInputPanel *)panel didPickSticker:(NoshiSticker *)sticker;
- (void)inputPanel:(NoshiInputPanel *)panel didPickCustomEmoji:(NoshiCustomEmojiDocument *)emoji;
- (void)inputPanel:(NoshiInputPanel *)panel didPickGif:(NoshiMedia *)gif;
- (void)inputPanel:(NoshiInputPanel *)panel didPickInlineResult:(NoshiInlineResult *)result queryId:(long long)queryId;
/* the tile "Create" of the sticker grid */
- (void)inputPanelDidTapCreateSticker:(NoshiInputPanel *)panel;
@end

/* what stands in for the keyboard: the emoji grid, the animations and the sticker list, and for Premium the custom
   emoji grid */
@interface NoshiInputPanel : UIView <NoshiEmojiPickerDelegate, NoshiStickerPickerDelegate, NoshiCustomEmojiPickerDelegate, NoshiGifPickerDelegate> {
    id<NoshiInputPanelDelegate> _delegate;
}
@property (nonatomic, assign) id<NoshiInputPanelDelegate> delegate;

- (id)initWithMedia:(NoshiMediaCache *)media library:(NoshiStickerLibrary *)library;
/* the account the search of the emoji grid asks its keywords from */
- (void)enableEmojiSearchWithSession:(NoshiSession *)session;
/* adds the tab of custom emoji, for an account with Telegram Premium; asking twice is the same as once */
- (void)enableCustomEmojiWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media;
/* the tab of animations; dialog is the chat they are sent to, which the search needs */
- (void)enableGifsWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media library:(NoshiStickerLibrary *)library dialog:(NoshiDialog *)dialog;

@end
