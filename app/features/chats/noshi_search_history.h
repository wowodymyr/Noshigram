#import <Foundation/Foundation.h>

#import "noshi_dialog.h"
#import "noshi_session.h"

/* the chats a person opened from the search, newest first, kept for each account: a chat that the account's own list does not hold (a public channel or a person found
   through the server) is kept with its address and name, since the access hash that opens it belongs to the account */
#define NOSHI_SEARCH_HISTORY_MAX 12

/* the remembered chats as dialogs: the live one from dialogs where the list has it, the kept address and name where it does not */
NSArray *NoshiSearchHistoryDialogs(NoshiSession *session, NSArray *dialogs);
/* dialogs is the list of the account, which the first start of this version reads the chats of the old keys from */
void NoshiSearchHistoryRemember(NoshiSession *session, NoshiDialog *dialog, NSArray *dialogs);
void NoshiSearchHistoryClear(NoshiSession *session);
