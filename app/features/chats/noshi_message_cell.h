#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_chat_item.h"
#import "noshi_bot_markup.h"
#import "noshi_media_cache.h"

@class NoshiMessageCell;
@class NoshiStickerLibrary;

@protocol NoshiMessageCellDelegate <NSObject>
/* the address of a link in the text was tapped */
- (void)messageCell:(NoshiMessageCell *)cell didTapLink:(NSString *)url;
/* the red mark of a message that did not go out was tapped */
- (void)messageCellDidLongPress:(NoshiMessageCell *)cell;
- (void)messageCell:(NoshiMessageCell *)cell didTapReaction:(NoshiReaction *)reaction;
@optional
/* whether a hold on a reaction chip shows when it was put (a private chat); where it does not, a hold on the chip is a hold on the message as before */
- (BOOL)messageCellShowsReactionTime:(NoshiMessageCell *)cell;
- (void)messageCell:(NoshiMessageCell *)cell didHoldReaction:(NoshiReaction *)reaction;
@required
- (void)messageCellDidTapFailed:(NoshiMessageCell *)cell;
@optional
/* the part of the words the person selected in the bubble is to be quoted by an answer; offset counts UTF-16 units of the text */
- (void)messageCell:(NoshiMessageCell *)cell didQuoteText:(NSString *)quote offset:(int32_t)offset;
@required
/* the preview of the message this one answers */
- (void)messageCellDidTapReply:(NoshiMessageCell *)cell;
/* the card of a gift service message was tapped */
- (void)messageCellDidTapGift:(NoshiMessageCell *)cell;
/* the play button or title of a song in a bubble was tapped */
- (void)messageCellDidTapAudio:(NoshiMessageCell *)cell;
/* the file button of a document that has come was tapped: the file is at path, and name is what it was called */
- (void)messageCell:(NoshiMessageCell *)cell didOpenFileAtPath:(NSString *)path name:(NSString *)name;
/* the comments row under a channel post, and the round button beside it */
- (void)messageCellDidTapComments:(NoshiMessageCell *)cell;
- (void)messageCellDidTapShare:(NoshiMessageCell *)cell;
/* the name or picture of the sender of a group message was tapped */
- (void)messageCellDidTapSender:(NoshiMessageCell *)cell;
/* a service line (somebody joined, left, was added, renamed the chat) was tapped; the delegate opens the profile of who it is about */
@optional
- (void)messageCellDidTapService:(NoshiMessageCell *)cell;
@required
@optional
- (void)messageCell:(NoshiMessageCell *)cell answerSharingRequest:(BOOL)accept;
/* the card of a one-time photo, video, voice note or round video was tapped */
- (void)messageCellDidTapViewOnce:(NoshiMessageCell *)cell;
/* the cross on the picture or file of a message that is still going up was tapped */
- (void)messageCellDidCancelSending:(NoshiMessageCell *)cell;
/* the line "forwarded from" of a bubble was tapped */
- (void)messageCellDidTapForward:(NoshiMessageCell *)cell;
@required
/* the photo, video or animation of a message was tapped */
- (void)messageCellDidTapMedia:(NoshiMessageCell *)cell;
/* a tap on a message whose paid media is still locked */
- (void)messageCellDidTapPaid:(NoshiMessageCell *)cell;
/* a button under a bot's message was pressed */
- (void)messageCell:(NoshiMessageCell *)cell didPressButton:(NoshiMarkupButton *)button;
/* a swipe to the left over the message answers it: asked before the swipe may start, and told when it went far enough */
- (BOOL)messageCellCanSwipeReply:(NoshiMessageCell *)cell;
- (void)messageCellDidSwipeReply:(NoshiMessageCell *)cell;
@optional
- (void)messageCell:(NoshiMessageCell *)cell didTapCode:(NoshiTextEntity *)entity;
/* a tap on a collapsed quote that is longer than its fold; quote is the offset where its entity starts, and the chat folds or opens it */
- (void)messageCell:(NoshiMessageCell *)cell didToggleQuote:(NSUInteger)quote;
/* a file, a song, a voice note or a video the person asked for has come whole; the chat keeps it in the list of downloads */
- (void)messageCell:(NoshiMessageCell *)cell didDownloadMedia:(NoshiMessage *)message;
- (void)messageCellDidRevealSpoiler:(NoshiMessageCell *)cell;
/* a tap on a sticker that belongs to a pack: the screen shows the pack */
- (void)messageCellDidTapSticker:(NoshiMessageCell *)cell;
/* a tap on the message that no link, picture, button or player of it took */
- (void)messageCellDidTapBody:(NoshiMessageCell *)cell;
/* an answer of a poll was tapped, or the button under the answers when the index is -1 */
- (void)messageCell:(NoshiMessageCell *)cell didTapPollAnswer:(NSInteger)index;
/* two taps on the message, when the setting for its direction gives them an action */
- (void)messageCellDidDoubleTap:(NoshiMessageCell *)cell;
/* a tap on a row of a chat in which messages are being selected: the message goes in or out of the selection */
- (void)messageCellDidToggleSelection:(NoshiMessageCell *)cell;
@end

/* one row of the chat */
@interface NoshiMessageCell : UITableViewCell {
    id<NoshiMessageCellDelegate> _delegate;
}

@property (nonatomic, assign) id<NoshiMessageCellDelegate> delegate;
@property (nonatomic, readonly) NoshiChatItem *item;
/* where the chip of a reaction stands in view's coordinates, CGRectZero when the row has no such chip */
- (CGRect)chipFrameOfReaction:(NoshiReaction *)reaction inView:(UIView *)view;
/* the message whose picture the last tap hit: a picture of an album, or the message of the row; set before the delegate hears of the tap */
@property (nonatomic, readonly) NoshiMessage *tappedMediaMessage;
/* an emoji, sticker or gif eligible for the visible animation budget, including files still loading */
@property (nonatomic, readonly) BOOL animatedSticker;
/* gives a single emoji its animation, nil leaves the emoji picture */
@property (nonatomic, retain) NoshiStickerLibrary *stickerLibrary;

/* a moving list holds new sticker renderers and inline players until it settles */
@property (nonatomic, assign) BOOL activationDeferred;

/* the ring on the cross of a message that is going up follows the message's uploadProgress */
- (void)showUploadProgress;
/* a band of the accent color fades in over the row and out again: the message a reply, a search or a bookmark led to */
- (void)flashHighlight;
/* the card of a one-time file burns away; completion runs when the animation is over */
- (void)playBurnWithCompletion:(void (^)(void))completion;

/* readies the picture of a row that is not on screen yet; a row without a picture does nothing */
+ (void)prepareItem:(NoshiChatItem *)item media:(NoshiMediaCache *)media;

/* the item must already be laid out for the width of the table */
- (void)configureWithItem:(NoshiChatItem *)item media:(NoshiMediaCache *)media avatars:(NoshiAvatarCache *)avatars;
/* a chat that is selecting shows a circle on every message that can be picked and takes every tap on it for a pick; the incoming ones step
   aside to make room for it. selected fills the circle */
- (void)setSelecting:(BOOL)selecting selected:(BOOL)selected animated:(BOOL)animated;
/* a picture of the row as it is drawn now, for the menu that keeps the message lit while the rest of the chat is dimmed */
- (UIImage *)contentSnapshot;
/* selects the word the last long press touched, with handles and a menu to copy or quote it */
- (void)beginTextSelection;
- (void)clearTextSelection;
- (BOOL)hasTextSelection;
/* a spinner on one button of the keyboard under the message while its press is answered; nil takes it away */
- (void)setBusyMarkupButton:(NoshiMarkupButton *)button;
/* starts the round message of this cell if it is not already playing */
- (void)startRound;
/* the lottie sticker plays or rests on its first frame; any other cell ignores it */
- (void)setAnimating:(BOOL)animating;
- (BOOL)replySwipeActive;
/* the height of the bubble as it is drawn now; the table reads it before a row is configured again and passes it to growBodyFromHeight: after, so a bubble that gains a
   reaction row grows instead of jumping */
- (CGFloat)bodyHeight;
- (void)growBodyFromHeight:(CGFloat)from;

@end
