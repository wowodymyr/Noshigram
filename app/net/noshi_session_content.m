#import "noshi_session_content.h"

#import "noshi_session_internal.h"

#include "noshi_content.h"

#import "noshi_rpc.h"

@implementation NoshiSession (Content)

- (void)loadContentSettings:(void (^)(BOOL, BOOL, NSString *))completion {
    void (^done)(BOOL, BOOL, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_content_settings_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        noshi_content_settings settings;
        NSString *error = nil;
        memset(&settings, 0, sizeof(settings));
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_content_settings_parse(result->value, &settings) != NOSHI_OK) error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        BOOL enabled = settings.sensitive_enabled != 0, canChange = settings.sensitive_can_change != 0;
        [self deliverMain:^{ done(enabled, canChange, delivered); [done release]; }];
    }];
}

- (void)setSensitiveContent:(BOOL)enabled completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_content_set_request(arena, enabled ? 1 : 0, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status parsed = noshi_content_set_parse(result->value);
            if (parsed == NOSHI_E_STATE) error = @"NOT_MODIFIED";
            else if (parsed != NOSHI_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

@end
