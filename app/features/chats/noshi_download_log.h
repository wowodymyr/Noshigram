#import <Foundation/Foundation.h>

#import "noshi_dialog.h"
#import "noshi_message.h"
#import "noshi_session.h"

/* the files a person asked for in a chat and that came, kept for each account, newest first; the list of downloads of the search shows them, and a tap opens the chat at the
   message. A file the cache has dropped since comes again from that message */
#define NOSHI_DOWNLOAD_LOG_MAX 300

void NoshiDownloadLogAdd(NoshiSession *session, NoshiDialog *dialog, NoshiMessage *message);
/* the downloads as rows that stand for their messages: the file name, then the chat and the size; query narrows them by name or chat, case and accents aside */
NSArray *NoshiDownloadLogDialogs(NoshiSession *session, NSString *query);
