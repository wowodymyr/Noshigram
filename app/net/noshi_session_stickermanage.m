#import "noshi_session_stickermanage.h"

#import "noshi_session_internal.h"

#include "noshi_sticker_manage.h"
#include "noshi_messages.h"

#import "noshi_rpc.h"

NSString *const NoshiStickerSetsDidChangeNotification = @"NoshiStickerSetsDidChange";

@implementation NoshiSession (StickerManage)

/* the answer of both calls: a Bool, true when the server did what was asked */
- (void)finishManage:(const noshi_mt_rpc_result *)result completion:(void (^)(NSString *))done {
    NSString *error = nil;
    if (result->status != NOSHI_OK) {
        error = NoshiRpcErrorName(result);
    } else {
        noshi_status parsed = noshi_sticker_manage_parse(result->value);
        if (parsed == NOSHI_E_STATE) error = @"NOT_MODIFIED";
        else if (parsed != NOSHI_OK) error = @"MALFORMED";
    }
    [self noteRpcError:error];
    NSString *delivered = [[error copy] autorelease];
    [self deliverMain:^{
        if (!delivered) [[NSNotificationCenter defaultCenter] postNotificationName:NoshiStickerSetsDidChangeNotification object:nil];
        done(delivered);
        [done release];
    }];
}

- (void)uninstallStickerSet:(NoshiStickerSet *)set completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    int64_t setId = set.row.id, hash = set.row.access_hash;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_uninstall_request(arena, setId, hash, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishManage:result completion:done];
    }];
}

- (void)installStickerSet:(NoshiStickerSet *)set completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    int64_t setId = set.row.id, hash = set.row.access_hash;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_install_request(arena, setId, hash, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_sticker_install_parse(result->value) != NOSHI_OK) error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            if (!delivered) [[NSNotificationCenter defaultCenter] postNotificationName:NoshiStickerSetsDidChangeNotification object:nil];
            done(delivered);
            [done release];
        }];
    }];
}

- (void)loadStickerPackWithId:(long long)setId accessHash:(long long)accessHash
                   completion:(void (^)(NoshiStickerSet *, NSArray *, NSString *))completion {
    void (^done)(NoshiStickerSet *, NSArray *, NSString *) = [completion copy];
    noshi_sticker_set_row wanted;
    memset(&wanted, 0, sizeof(wanted));
    wanted.id = setId;
    wanted.access_hash = accessHash;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_set_request(arena, &wanted, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiStickerSet *set = nil;
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_row *rows = calloc(NOSHI_STICKERS_MAX, sizeof(*rows));
            noshi_sticker_set_row header;
            size_t count = 0;
            if (rows && noshi_sticker_set_parse(result->value, &header, rows, NOSHI_STICKERS_MAX, &count) == NOSHI_OK) {
                set = [NoshiStickerSet setWithRow:&header];
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[NoshiSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getStickerSet answer for a pack was rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NoshiStickerSet *deliveredSet = [set retain];
        NSArray *deliveredStickers = [stickers retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{
            done(deliveredSet, deliveredStickers, deliveredError);
            [deliveredSet release];
            [deliveredStickers release];
            [done release];
        }];
    }];
}

- (void)loadFeaturedStickerSets:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_featured_stickers_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *sets = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_set_row *rows = calloc(NOSHI_STICKER_SETS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_featured_stickers_parse(result->value, rows, NOSHI_STICKER_SETS_MAX, &count) == NOSHI_OK) {
                sets = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sets addObject:[NoshiStickerSet setWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getFeaturedStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:sets error:error completion:done];
        [done release];
    }];
}

- (void)loadArchivedStickerSetsLimit:(int32_t)limit completion:(void (^)(NSArray *, int32_t, NSString *))completion {
    void (^done)(NSArray *, int32_t, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_archived_stickers_request(arena, 0, limit, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *sets = nil;
        NSString *error = nil;
        int32_t total = 0;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_set_row *rows = calloc(NOSHI_STICKER_SETS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_archived_stickers_parse(result->value, rows, NOSHI_STICKER_SETS_MAX, &count, &total) == NOSHI_OK) {
                sets = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sets addObject:[NoshiStickerSet setWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getArchivedStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredSets = [sets retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{
            done(deliveredSets, total, deliveredError);
            [deliveredSets release];
            [done release];
        }];
    }];
}

- (void)moveStickerSetToTop:(NoshiStickerSet *)set among:(NSArray *)sets completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSUInteger count = MIN(sets.count, (NSUInteger)NOSHI_STICKER_ORDER_MAX);
    int64_t *ids = calloc(count ? count : 1, sizeof(*ids));
    size_t used = 0;
    if (ids) {
        ids[used++] = set.row.id;
        for (NoshiStickerSet *other in sets) {
            if (other.row.id != set.row.id && used < count) ids[used++] = other.row.id;
        }
    }
    NSData *order = ids ? [NSData dataWithBytes:ids length:used * sizeof(*ids)] : nil;
    free(ids);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        if (!order.length) return NOSHI_E_ARG;
        return noshi_sticker_reorder_request(arena, (const int64_t *)order.bytes, order.length / sizeof(int64_t), request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishManage:result completion:done];
    }];
}

@end
