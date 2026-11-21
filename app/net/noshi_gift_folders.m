#import "noshi_gift_folders.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

#include "noshi_gifts.h"

@implementation NoshiGiftFolder

@synthesize folderId = _folderId;
@synthesize count = _count;
@synthesize title = _title;

- (id)initWithRow:(const noshi_gift_collection *)row {
    self = [super init];
    if (!self) return nil;
    _folderId = row->id;
    _count = row->count;
    _title = [[NSString stringWithUTF8String:row->title] copy];
    return self;
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}

@end

/* the ids of the messages of these gifts, at most one batch; the rest of a longer list is the caller's next call */
static NSData *NoshiGiftMessageIds(NSArray *gifts) {
    NSMutableData *data = [NSMutableData data];
    for (NoshiSavedGift *gift in gifts) {
        if (gift.messageId <= 0 || data.length / sizeof(int32_t) >= NOSHI_GIFT_COLLECTION_BATCH_MAX) continue;
        int32_t identifier = gift.messageId;
        [data appendBytes:&identifier length:sizeof(identifier)];
    }
    return data;
}

@implementation NoshiSession (GiftFolders)

- (void)loadGiftFoldersOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_collections_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *folders = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_gift_collection *rows = calloc(NOSHI_GIFT_COLLECTIONS_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_gift_collections_parse(result->value, rows, NOSHI_GIFT_COLLECTIONS_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                folders = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [folders addObject:[[[NoshiGiftFolder alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: payments.getStarGiftCollections answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredFolders = [[folders copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredFolders, deliveredError); [done release]; }];
    }];
}

- (void)loadSavedGiftsOfDialog:(NoshiDialog *)dialog folder:(int32_t)folderId offset:(NSString *)offset completion:(NoshiSavedGiftsCompletion)completion {
    if (folderId <= 0) {
        [self loadSavedGiftsOfDialog:dialog offset:offset completion:completion];
        return;
    }
    NoshiSavedGiftsCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *start = offset ? [offset copy] : [@"" copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_saved_gifts_in_collection_request(arena, &peer, folderId, start.UTF8String, 30, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *gifts = nil;
        NSString *next = nil;
        NSString *error = nil;
        NSInteger total = 0;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_saved_gift *rows = calloc(NOSHI_SAVED_GIFTS_MAX, sizeof(*rows));
            noshi_saved_gift_page page;
            size_t count = 0;
            noshi_status status = rows ? noshi_saved_gifts_parse(result->value, rows, NOSHI_SAVED_GIFTS_MAX, &count, &page) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                gifts = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [gifts addObject:[NoshiSavedGift savedGiftWithRow:&rows[i]]];
                total = page.total;
                if (page.next_offset[0]) next = [NSString stringWithUTF8String:page.next_offset];
            } else {
                NSLog(@"noshigram: payments.getSavedStarGifts of a folder answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredGifts = [[gifts copy] autorelease];
        NSString *deliveredNext = [[next copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredGifts, total, deliveredNext, deliveredError); [done release]; }];
    }];
    [start release];
}

/* a request whose answer is a folder or true, of which only the error matters */
- (void)runFolderRequest:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ if (done) done(delivered); [done release]; }];
    }];
}

- (void)createGiftFolderTitled:(NSString *)title withGifts:(NSArray *)gifts dialog:(NoshiDialog *)dialog
                    completion:(void (^)(NoshiGiftFolder *, NSString *))completion {
    void (^done)(NoshiGiftFolder *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *name = [title copy];
    NSData *ids = [NoshiGiftMessageIds(gifts) retain];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_collection_create_request(arena, &peer, name.UTF8String, ids.bytes, ids.length / sizeof(int32_t), request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiGiftFolder *folder = nil;
        NSString *error = nil;
        noshi_gift_collection row;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_gift_collection_read(result->value, &row) != NOSHI_OK) error = @"INTERNAL";
        else folder = [[[NoshiGiftFolder alloc] initWithRow:&row] autorelease];
        [self noteRpcError:error];
        NoshiGiftFolder *deliveredFolder = [folder retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredFolder, deliveredError); [deliveredFolder release]; [done release]; }];
    }];
    [name release];
    [ids release];
}

- (void)renameGiftFolder:(NoshiGiftFolder *)folder to:(NSString *)title dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    int32_t identifier = folder.folderId;
    NSString *name = [[title copy] autorelease];
    [self runFolderRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_collection_update_request(arena, &peer, identifier, name.UTF8String, NULL, 0, NULL, 0, request);
    } completion:completion];
}

- (void)addGifts:(NSArray *)gifts toFolder:(NoshiGiftFolder *)folder dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    int32_t identifier = folder.folderId;
    NSData *ids = [NoshiGiftMessageIds(gifts) retain];
    [self runFolderRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_collection_update_request(arena, &peer, identifier, NULL, ids.bytes, ids.length / sizeof(int32_t), NULL, 0, request);
    } completion:^(NSString *error) {
        [ids release];
        if (completion) completion(error);
    }];
}

- (void)removeGifts:(NSArray *)gifts fromFolder:(NoshiGiftFolder *)folder dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    int32_t identifier = folder.folderId;
    NSData *ids = [NoshiGiftMessageIds(gifts) retain];
    [self runFolderRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_collection_update_request(arena, &peer, identifier, NULL, NULL, 0, ids.bytes, ids.length / sizeof(int32_t), request);
    } completion:^(NSString *error) {
        [ids release];
        if (completion) completion(error);
    }];
}

- (void)deleteGiftFolder:(NoshiGiftFolder *)folder dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    int32_t identifier = folder.folderId;
    [self runFolderRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_collection_delete_request(arena, &peer, identifier, request);
    } completion:completion];
}

@end
