#import "noshi_session_namecolor.h"

#import "noshi_session_internal.h"

#include "noshi_name_color.h"

#import "noshi_peer_colors.h"
#import "noshi_rpc.h"

@implementation NoshiSession (NameColor)

- (void)loadNameColors:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_name_colors_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *colors = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_name_color_option *rows = calloc(NOSHI_NAME_COLORS_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_name_colors_parse(result->value, rows, NOSHI_NAME_COLORS_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                colors = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    [colors addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:rows[i].id], @"id", [NSNumber numberWithUnsignedInt:rows[i].light], @"light",
                                       [NSNumber numberWithUnsignedInt:rows[i].dark], @"dark", [NSNumber numberWithBool:rows[i].hidden != 0], @"hidden", nil]];
                }
            } else {
                NSLog(@"noshigram: help.getPeerColors answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{
            /* a list that has not changed is an empty one, and what is stored stays */
            if (colors.count) NoshiStoreServerNameColors(colors);
            done(colors.count ? colors : NoshiServerNameColors(), deliveredError);
            [done release];
        }];
    }];
}

- (void)setNameColorId:(NSInteger)colorId completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_name_color_set_request(arena, (int32_t)colorId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status parsed = noshi_name_color_set_parse(result->value);
            if (parsed == NOSHI_E_STATE) error = @"NOT_MODIFIED";
            else if (parsed != NOSHI_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

@end
