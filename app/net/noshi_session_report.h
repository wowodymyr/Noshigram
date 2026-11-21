#import <Foundation/Foundation.h>

#include "noshi_report.h"

#import "noshi_dialog.h"
#import "noshi_session.h"

@interface NoshiSession (Report)

/* tells Telegram that the user, group or channel breaks its rules. comment may be nil, and the reason other needs
   one; the completion gets nil once the server took the report, and an error name otherwise (NOT_REPORTED when it
   answered false) */
- (void)reportDialog:(NoshiDialog *)dialog reason:(noshi_report_reason)reason comment:(NSString *)comment completion:(void (^)(NSString *errorName))completion;

@end

/* one step of the dialogue of messages.report: the server either took the report, or lists what to choose from, or wants words */
typedef enum {
    NoshiMessageReportDone = 1,
    NoshiMessageReportChoose,
    NoshiMessageReportComment
} NoshiMessageReportKind;

@interface NoshiMessageReportStep : NSObject {
    NoshiMessageReportKind _kind;
    NSString *_title;
    NSArray *_options;
    NSArray *_tokens;
    NSData *_token;
    BOOL _commentOptional;
}
@property (nonatomic, readonly) NoshiMessageReportKind kind;
@property (nonatomic, readonly, copy) NSString *title;
/* the words of each choice, and the token each one is sent back with, in the same order */
@property (nonatomic, readonly, retain) NSArray *options;
@property (nonatomic, readonly, retain) NSArray *tokens;
/* for the comment step: the token the words are sent with */
@property (nonatomic, readonly, retain) NSData *token;
@property (nonatomic, readonly) BOOL commentOptional;
+ (NoshiMessageReportStep *)stepWithAnswer:(const noshi_message_report_answer *)answer;
@end

@interface NoshiSession (MessageReport)

/* the first call has a nil token; the step comes back on the main thread, or an error name when the request failed
   or the answer was not one the dialogue knows */
- (void)reportMessageIds:(NSArray *)ids ofDialog:(NoshiDialog *)dialog token:(NSData *)token comment:(NSString *)comment
              completion:(void (^)(NoshiMessageReportStep *step, NSString *errorName))completion;

@end
