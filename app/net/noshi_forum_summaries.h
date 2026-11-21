#import <Foundation/Foundation.h>

#include "noshi_dialogs.h"

@class NoshiDialog;

/* what the topics of each forum said of it the last time they were read, kept for the chat list; the worker fills it and the main thread reads it */
@interface NoshiForumSummaries : NSObject

/* gives every forum of the list the summary kept for it */
- (void)applyToDialogs:(NSArray *)dialogs;
/* keeps the summary read for a forum whose last message was topMessage */
- (void)setSummary:(const noshi_forum_summary *)summary forForum:(int64_t)peerId topMessage:(int32_t)topMessage;
/* a forum is read again when its last message moved on or the kept summary is old, and not while a read of it is running; asking marks the read as started */
- (BOOL)beginReadingForum:(int64_t)peerId topMessage:(int32_t)topMessage;
- (void)endReadingForum:(int64_t)peerId;

@end
