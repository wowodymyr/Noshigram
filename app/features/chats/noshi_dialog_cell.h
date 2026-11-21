#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_dialog.h"
#import "noshi_media_cache.h"
#import "noshi_story.h"

/* what the swipe from the right edge of a row does; None disables the swipe */
typedef enum {
    NoshiDialogActionNone,
    NoshiDialogActionArchive,
    NoshiDialogActionUnarchive,
    NoshiDialogActionHide,
    /* the archive entry's "pin on top", which brings the hidden archive back to the top of the list */
    NoshiDialogActionPin,
    /* the swipes the chat settings offer for an ordinary chat, besides the archive */
    NoshiDialogActionPinChat,
    NoshiDialogActionUnpinChat,
    NoshiDialogActionMarkRead,
    NoshiDialogActionMarkUnread,
    NoshiDialogActionMute,
    NoshiDialogActionUnmute,
    NoshiDialogActionDeleteChat
} NoshiDialogAction;

@class NoshiDialogCell;

/* what a swipe to the left does on a chat of the main list or of the archive, by the choice of the chat settings:
   the archive until another is chosen */
NoshiDialogAction NoshiDialogSwipeAction(NoshiDialog *dialog, NSInteger folderId);
/* the word on the button of an action */
NSString *NoshiDialogActionText(NoshiDialogAction action);

@protocol NoshiDialogCellDelegate <NSObject>
/* a swipe started, so the row that was open can close */
- (void)dialogCellDidBeginSwipe:(NoshiDialogCell *)cell;
/* the swipe went all the way or the opened button was tapped; the cell stays slid out until it is reconfigured */
- (void)dialogCell:(NoshiDialogCell *)cell didTriggerAction:(NoshiDialogAction)action;
@end

/* one row of the chat list; the height is fixed so the table never measures */
@class NoshiDraft;

@interface NoshiDialogCell : UITableViewCell

@property (nonatomic, assign) id<NoshiDialogCellDelegate> swipeDelegate;
@property (nonatomic, readonly) BOOL swipeOpen;
/* where the picture of a photo or video preview comes from; without it the row shows the text alone */
@property (nonatomic, assign) NoshiMediaCache *media;
/* runs when the arrow on the avatar of a chat that belongs to a community is tapped; set after configureWithDialog, cleared by the next configure */
@property (nonatomic, copy) void (^communityHandler)(void);

/* the stories of the user the row is with: a ring round the avatar, coloured while one is unseen; nil takes it away. Set after configureWithDialog, which clears it */
- (void)setStoryPeer:(NoshiStoryPeer *)peer;

+ (CGFloat)rowHeight;
/* the height of the row of this chat: a forum that names its topics stands taller than the rest */
+ (CGFloat)rowHeightForDialog:(NoshiDialog *)dialog;
- (void)configureWithDialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars action:(NoshiDialogAction)action;
/* replaces the preview with what the chat is doing right now, in the accent color; nil puts the last message back */
- (void)showTypingText:(NSString *)text;
/* the unsent message of the chat stands in the place of the last one, after a red "Draft:" and with the time of the draft. Set after configureWithDialog,
   which puts the last message back; nil leaves it */
- (void)showDraft:(NoshiDraft *)draft;
- (void)closeSwipeAnimated:(BOOL)animated;
/* changes what the swipe does, for a row that stays on screen after its action ran */
- (void)setSwipeAction:(NoshiDialogAction)action;
- (void)yieldSwipeToRecognizers:(NSArray *)recognizers;

@end
