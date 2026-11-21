#import "noshi_session_internal.h"

#import "noshi_rpc.h"
#import "noshi_session_report.h"

@implementation NoshiSession (Report)

- (void)reportDialog:(NoshiDialog *)dialog reason:(noshi_report_reason)reason comment:(NSString *)comment completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *text = [[comment copy] autorelease];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_report_request(arena, &peer, reason, text.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status parsed = noshi_report_parse(result->value);
            if (parsed == NOSHI_E_STATE) error = @"NOT_REPORTED";
            else if (parsed != NOSHI_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

@end

@implementation NoshiMessageReportStep
@synthesize kind = _kind;
@synthesize title = _title;
@synthesize options = _options;
@synthesize tokens = _tokens;
@synthesize token = _token;
@synthesize commentOptional = _commentOptional;

+ (NoshiMessageReportStep *)stepWithAnswer:(const noshi_message_report_answer *)answer {
    NoshiMessageReportStep *step = [[[NoshiMessageReportStep alloc] init] autorelease];
    step->_kind = (NoshiMessageReportKind)answer->step;
    step->_title = [[NSString stringWithUTF8String:answer->title] copy];
    NSMutableArray *options = [NSMutableArray array], *tokens = [NSMutableArray array];
    for (size_t i = 0; i < answer->option_count; ++i) {
        NSString *text = [NSString stringWithUTF8String:answer->options[i].text];
        [options addObject:text ? text : @""];
        [tokens addObject:[NSData dataWithBytes:answer->options[i].token length:answer->options[i].token_len]];
    }
    step->_options = [options retain];
    step->_tokens = [tokens retain];
    step->_token = [[NSData dataWithBytes:answer->token length:answer->token_len] retain];
    step->_commentOptional = answer->comment_optional != 0;
    return step;
}

- (void)dealloc {
    [_title release];
    [_options release];
    [_tokens release];
    [_token release];
    [super dealloc];
}
@end

@implementation NoshiSession (MessageReport)

- (void)reportMessageIds:(NSArray *)ids ofDialog:(NoshiDialog *)dialog token:(NSData *)token comment:(NSString *)comment
              completion:(void (^)(NoshiMessageReportStep *, NSString *))completion {
    void (^done)(NoshiMessageReportStep *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSMutableData *packed = [[NSMutableData alloc] init];
    for (NSNumber *identifier in ids) {
        int32_t value = identifier.intValue;
        [packed appendBytes:&value length:sizeof(value)];
    }
    size_t count = MIN(packed.length / sizeof(int32_t), (size_t)NOSHI_REPORT_IDS_MAX);
    NSData *chosen = [token copy];
    NSString *text = [comment copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_message_report_request(arena, &peer, packed.bytes, count, chosen.bytes, chosen.length, text.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        NoshiMessageReportStep *step = nil;
        noshi_message_report_answer *answer = calloc(1, sizeof(*answer));
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else if (!answer || noshi_message_report_parse(result->value, answer) != NOSHI_OK) {
            error = @"MALFORMED";
        } else {
            step = [NoshiMessageReportStep stepWithAnswer:answer];
        }
        free(answer);
        [packed release];
        [chosen release];
        [text release];
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(step, deliveredError); [done release]; }];
    }];
}

@end
