#import <Foundation/Foundation.h>

#include "noshi_bookmarks.h"

#import "noshi_dialog.h"
#import "noshi_session.h"

/* posted on the main thread after a bookmark was added or removed */
extern NSString *const NoshiBookmarksDidChangeNotification;

/* one bookmarked message, as the list shows it */
@interface NoshiBookmark : NSObject {
    noshi_bookmark _row;
}
- (id)initWithRow:(const noshi_bookmark *)row;
@property (nonatomic, readonly) int32_t messageId;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly) int32_t added;
/* the name of the chat, and the start of the message or the word for its media */
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *text;
/* the chat the message is in, built from what was kept, with no picture */
- (NoshiDialog *)dialog;
@end

/* the messages the person marked, kept in a file of the account's directory, newest first; a file of another
   account is not read, so signing in as somebody else starts an empty list */
@interface NoshiBookmarks : NSObject

/* one list per account directory, loaded when first asked for */
+ (NoshiBookmarks *)bookmarksForSession:(NoshiSession *)session;

@property (nonatomic, readonly) NSArray *entries;
- (BOOL)containsMessageId:(int32_t)messageId inDialog:(NoshiDialog *)dialog;
/* text is the line to recognise the message by */
- (BOOL)addMessageId:(int32_t)messageId date:(int32_t)date text:(NSString *)text inDialog:(NoshiDialog *)dialog;
- (BOOL)removeMessageId:(int32_t)messageId inDialog:(NoshiDialog *)dialog;
- (BOOL)removeEntry:(NoshiBookmark *)entry;

@end
