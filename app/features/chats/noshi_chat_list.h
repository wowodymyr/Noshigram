#import <Foundation/Foundation.h>

#import "noshi_dialog.h"

/* what the main chat list shares with the rest of the app: the unread total, the last rows it loaded, and what a swipe on a row does */

/* the unread messages of the main list, those of muted chats left out: the count a chat shows by its way back; posted on the main thread when it changes */
extern NSString *const NoshiUnreadTotalDidChangeNotification;
NSInteger NoshiUnreadTotal(void);
void NoshiSetUnreadTotal(NSInteger total);
/* the rows of the main chat list as the screen last loaded it, nil before the first load; what the icon badge is counted from when the server cannot be asked */
NSArray *NoshiMainDialogsSnapshot(void);
void NoshiSetMainDialogsSnapshot(NSArray *dialogs);

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

/* what a swipe to the left does on a chat of the main list or of the archive, by the choice of the chat settings:
   the archive until another is chosen */
NoshiDialogAction NoshiDialogSwipeAction(NoshiDialog *dialog, NSInteger folderId);
/* the word on the button of an action */
NSString *NoshiDialogActionText(NoshiDialogAction action);
