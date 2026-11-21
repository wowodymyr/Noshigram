#import "noshi_session_data.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

#include "noshi_sticker_manage.h"

@implementation NoshiSession (Data)

- (void)clearAllDraftsWithCompletion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "messages.clearAllDrafts");
        return *request ? NOSHI_OK : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            /* the Bool the server answers with: true when it did what was asked */
            noshi_status parsed = noshi_sticker_manage_parse(result->value);
            if (parsed == NOSHI_E_STATE) error = @"NOT_MODIFIED";
            else if (parsed != NOSHI_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            done(delivered);
            [done release];
        }];
    }];
}

- (void)sendOfflineStatus {
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "account.updateStatus");
        return *request ? noshi_tl_set(*request, "offline", noshi_tl_new_obj(arena, "boolTrue")) : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) NSLog(@"noshigram: account.updateStatus failed: %@", NoshiRpcErrorName(result));
    }];
}

- (void)deleteAccountWithReason:(NSString *)reason completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSString *text = [reason copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "account.deleteAccount");
        return *request ? noshi_tl_set_str(arena, *request, "reason", text.UTF8String ? text.UTF8String : "") : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status parsed = noshi_sticker_manage_parse(result->value);
            if (parsed != NOSHI_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            done(delivered);
            [done release];
        }];
    }];
    [text release];
}

@end
