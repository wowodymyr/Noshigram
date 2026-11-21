#import <Foundation/Foundation.h>

#import "noshi_dialog.h"
#import "noshi_session.h"

/* what the person does to messages that are already in a chat; every completion runs on the main thread, with nil
   once the server took the request and an error name otherwise */
@interface NoshiSession (Actions)

- (void)setSharingRestricted:(BOOL)restricted ofDialog:(NoshiDialog *)dialog requestId:(int32_t)requestId completion:(void (^)(NSString *errorName))completion;
/* delivers the cached lifetime and clock offset first, then the refreshed values or an error on the main thread */
- (void)loadSharingPeriod:(void (^)(int32_t seconds, int64_t offsetMilliseconds, NSString *errorName))completion;

/* revoke takes the messages from the other side too; a channel ignores it */
- (void)deleteMessageIds:(NSArray *)ids ofDialog:(NoshiDialog *)dialog revoke:(BOOL)revoke completion:(void (^)(NSString *errorName))completion;
- (void)pinMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog unpin:(BOOL)unpin completion:(void (^)(NSString *errorName))completion;
/* the new text without any entities, so only a message that had none is edited this way */
- (void)editMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog text:(NSString *)text completion:(void (^)(NSString *errorName))completion;
/* the caption of a message that carries media: the media stays, and the text may be empty to take the caption away */
- (void)editCaptionOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog text:(NSString *)text completion:(void (^)(NSString *errorName))completion;
/* hideAuthor sends the copies as written by the forwarder, without the line about where they came from */
- (void)forwardMessageIds:(NSArray *)ids fromDialog:(NoshiDialog *)from toDialog:(NoshiDialog *)to hideAuthor:(BOOL)hideAuthor completion:(void (^)(NSString *errorName))completion;

/* a text that the server sends at the given time (unix seconds, in the future); the chat is usually the favorites,
   where it works as a reminder */
- (void)scheduleText:(NSString *)text atDate:(int32_t)date toDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* with the formatting runs of the text, as an answer to replyTo (zero for none) */
- (void)scheduleText:(NSString *)text entities:(NSArray *)entities atDate:(int32_t)date toDialog:(NoshiDialog *)dialog replyTo:(int32_t)replyTo completion:(void (^)(NSString *errorName))completion;
/* the link that opens a message of a channel or supergroup, public or private; the completion gets it, or nil and the rpc error name */
- (void)exportLinkOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *link, NSString *errorName))completion;
/* votes in the poll of a message: options are NSData tokens of the answers (see NoshiPollAnswer), none takes the
   vote back */
- (void)sendVoteOptions:(NSArray *)options forMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* the current copies of these messages (at most a hundred) as the server holds them, such as polls that were voted
   in since; messages that are gone are left out */
- (void)loadMessagesWithIds:(NSArray *)ids ofDialog:(NoshiDialog *)dialog completion:(NoshiListCompletion)completion;

/* the same messages with their authors, needed when a reply points outside the loaded history */
- (void)loadMessagesWithIds:(NSArray *)ids ofDialog:(NoshiDialog *)dialog withPeople:(NoshiHistoryCompletion)completion;

/* the words of a voice message from the server. pending means it is still listening and the text is not final: ask again a moment later */
- (void)transcribeMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *text, BOOL pending, NSString *errorName))completion;

/* when the other side of a private chat read a message of ours, unix seconds; an error name when they did not yet or keep it private */
- (void)loadReadDateOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(int32_t date, NSString *errorName))completion;
- (void)loadGroupReadDatesOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSArray *readers, NSString *errorName))completion;

/* one page of reactors, their reactions and server dates; next is nil at the end */
- (void)loadReactorsOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog offset:(NSString *)offset
                    completion:(void (^)(NSArray *reactors, NSDictionary *people, NSString *next, NSString *errorName))completion;

@end
