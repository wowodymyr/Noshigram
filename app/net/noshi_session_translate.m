#import "noshi_session_translate.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

#include "noshi_translate.h"

@implementation NoshiSession (Translate)

- (void)translateText:(NSString *)text to:(NSString *)language completion:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    NSString *body = [[text copy] autorelease];
    NSString *code = [[language copy] autorelease];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_translate_request(arena, body.UTF8String, code.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *translated = nil, *error = nil;
        if (result->status == NOSHI_E_ARG) {
            error = @"ARG";
        } else if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            char *buffer = malloc(NOSHI_TRANSLATE_TEXT_MAX + 1);
            if (buffer && noshi_translate_parse(result->value, buffer, NOSHI_TRANSLATE_TEXT_MAX + 1) == NOSHI_OK) translated = [NSString stringWithUTF8String:buffer];
            if (!translated) error = @"MALFORMED";
            free(buffer);
        }
        [self noteRpcError:error];
        NSString *delivered = [[translated copy] autorelease];
        NSString *failure = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, failure); [done release]; }];
    }];
}

@end
