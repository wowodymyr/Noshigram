#import <UIKit/UIKit.h>

#import "noshi_dialog.h"
#import "noshi_session.h"

/* posted on the main thread when files reached the app from the share sheet or "open in"; userInfo has "urls", an array of file urls */
extern NSString *const NoshiShareFilesNotification;

/* looks in the folder of the app group for what the share extension left, and posts NoshiShareFilesNotification for the newest share, with "urls", "text" (may be absent)
   and "directory", the folder to delete once it is sent. Older shares and leftovers more than a day old are deleted. Safe to call at any time: a share is claimed once. */
void NoshiShareCollectPending(void);

/* the folder and what it held are gone */
void NoshiShareDiscard(NSString *directory);

/* sends the files one after another to the chat: a picture as a photo, a gif as an animation, anything else as a document. Each file is deleted after its send,
   since the system leaves the copy it made in the inbox of the app. a text goes first, as one message. done gets the first error, or nil when all went out. */
void NoshiShareSendFiles(NSArray *urls, NSString *text, NoshiDialog *dialog, NoshiSession *session, void (^done)(NSString *errorName));
