#import <Foundation/Foundation.h>

#import "noshi_draft.h"
#import "noshi_session.h"

/* the drafts: what the person types and has not sent is kept by the account, so it follows them to every phone */
@interface NoshiSession (Drafts)

/* the draft of a chat or topic is now this (an empty text and no reply clear it). The board has it at once, and the account within a moment; main thread */
- (void)saveDraftText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo noWebpage:(BOOL)noWebpage forDialog:(NoshiDialog *)dialog;

/* worker only: the drafts a chat list answer carries go to the board; complete is NO for the answer the last run kept */
- (void)noteDraftsOfDialogsAnswer:(const noshi_tl_value *)answer complete:(BOOL)complete;
- (void)noteDraftsOfDialogsAnswer:(const noshi_tl_value *)answer complete:(BOOL)complete since:(NSUInteger)revision;
/* worker only: the same for the topics of a forum */
- (void)noteDraftsOfTopicsAnswer:(const noshi_tl_value *)answer forum:(NoshiDialog *)forum since:(NSUInteger)revision;
/* worker only: an updateDraftMessage of the account */
- (void)noteDraftUpdate:(const noshi_tl_value *)update;
/* worker only: asks for every draft of the account once per run; they come back as updates */
- (void)requestAllDraftsOnce;

@end
