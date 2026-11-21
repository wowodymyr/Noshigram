#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_dialog.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* one chat: the messages over the wallpaper, a bar with the person or group on top, the field below */
@class NoshiPerson;

@interface NoshiChatController : UIViewController {
    void (^_closeHandler)(void);
    NoshiDialog *(^_nextChatProvider)(NoshiDialog *);
}

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);
/* the channel with unread posts that comes after this chat, asked for when the list is pulled up past its end */
@property (nonatomic, copy) NoshiDialog *(^nextChatProvider)(NoshiDialog *current);
/* the screen shows only the pinned messages of the chat, under a title that counts them, with no field below; set before the view loads */
@property (nonatomic, assign) BOOL pinnedList;
/* with pinnedList: the list holds the messages of the chat that contain this text, and a tap on one goes back to the chat at that message; set before
   the view loads */
@property (nonatomic, copy) NSString *searchQuery;
/* with pinnedList: the list holds what this person wrote in the chat (the "history" of the menu of a message in a group); set before the view loads */
@property (nonatomic, retain) NoshiPerson *historyPerson;
/* the message to scroll to once the newest page is in, such as the one a bookmark names; set before the view loads */
@property (nonatomic, assign) int32_t startMessageId;
/* text for the field when the screen opens, such as a bot's name and a query from a link or an app */
@property (nonatomic, copy) NSString *draftText;
/* the chat is with a bot and the link that led here carries a start parameter: the first press of Start sends it */
@property (nonatomic, copy) NSString *startParam;

/* whether this chat is with that peer */
- (BOOL)showsDialog:(NoshiDialog *)dialog;

/* puts text in the field and opens the keyboard */
- (void)applyDraft:(NSString *)text;
- (void)jumpToMessageId:(int32_t)messageId;

@end
