#import "noshi_session_saved.h"

#import "noshi_chat_settings.h"
#import "noshi_session_internal.h"

#include "noshi_messages.h"
#include "noshi_updates.h"

uint32_t NoshiSavingMask(void) {
    uint32_t mask = 0;
    if (NoshiChatFlagGet(NoshiChatFlagAyuSaveDeleted)) {
        mask |= NOSHI_KEEP_DELETED;
        if (NoshiChatFlagGet(NoshiChatFlagAyuDeletedPrivate)) mask |= NOSHI_KEEP_PRIVATE;
        if (NoshiChatFlagGet(NoshiChatFlagAyuDeletedGroups)) mask |= NOSHI_KEEP_GROUPS;
        if (NoshiChatFlagGet(NoshiChatFlagAyuDeletedChannels)) mask |= NOSHI_KEEP_CHANNELS;
        if (NoshiChatFlagGet(NoshiChatFlagAyuDeletedBots)) mask |= NOSHI_KEEP_BOTS;
    }
    if (NoshiChatFlagGet(NoshiChatFlagAyuSaveEdits)) mask |= NOSHI_KEEP_EDITS;
    return mask;
}

typedef struct {
    NSMutableArray *messages;
    BOOL deleted;
    int32_t low, high;
    int64_t divisor;        /* the id of a version is the id of its message times this plus a number */
    int32_t only;           /* a message whose versions are wanted, or zero */
} NoshiSavedRead;

static noshi_status NoshiCollectSaved(void *ctx, int64_t id, const noshi_tl_value *value) {
    NoshiSavedRead *read = ctx;
    int64_t messageId = id / read->divisor;
    if (read->only ? messageId != read->only : (messageId < read->low || messageId > read->high)) return NOSHI_OK;
    noshi_message_row *row = calloc(1, sizeof(*row));
    if (!row) return NOSHI_E_NOMEM;
    if (noshi_message_read(value, row) == NOSHI_OK) {
        NoshiMessage *message = [NoshiMessage messageWithRow:row];
        message.deletedLocally = read->deleted;
        if (message) [read->messages addObject:message];
    }
    free(row);
    return NOSHI_OK;
}

@implementation NoshiSession (Saved)

- (void)setSavingSettingsFromDefaults {
    uint32_t mask = NoshiSavingMask();
    [self post:^{
        if ([self workerStore]) [self setKeepMask:mask];
    }];
}

- (void)countSavedMessages:(void (^)(NSInteger, NSString *))completion {
    void (^done)(NSInteger, NSString *) = [completion copy];
    [self post:^{
        noshi_store *store = [self workerStore];
        int64_t deleted = 0, versions = 0;
        noshi_status status = store ? noshi_store_count(store, NOSHI_RECORD_DELETED_MESSAGE, &deleted) : NOSHI_E_STATE;
        if (status == NOSHI_OK) status = noshi_store_count(store, NOSHI_RECORD_MESSAGE_EDIT, &versions);
        NSInteger total = (NSInteger)(deleted + versions);
        NSString *error = status == NOSHI_OK ? nil : @"STORAGE";
        [self deliverMain:^{ done(total, error); [done release]; }];
    }];
}

- (void)deleteSavedMessage:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer peer = {dialog.peerKind, dialog.peerId};
    [self post:^{
        noshi_store *store = [self workerStore];
        noshi_status status = store && messageId > 0 ? noshi_store_delete(store, NOSHI_RECORD_DELETED_MESSAGE, peer, messageId) : NOSHI_E_ARG;
        if (status == NOSHI_OK) [self storeChanged];
        NSString *error = status == NOSHI_OK ? nil : @"STORAGE";
        [self deliverMain:^{ if (done) done(error); [done release]; }];
    }];
}

- (void)clearSavedMessages:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self post:^{
        noshi_store *store = [self workerStore];
        noshi_status status = store ? noshi_store_clear(store, NOSHI_RECORD_DELETED_MESSAGE) : NOSHI_E_STATE;
        if (status == NOSHI_OK) status = noshi_store_clear(store, NOSHI_RECORD_MESSAGE_EDIT);
        if (status == NOSHI_OK) [self storeChanged];
        NSString *error = status == NOSHI_OK ? nil : @"STORAGE";
        [self deliverMain:^{ done(error); [done release]; }];
    }];
}

- (void)clearSavedDeletedOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer peer = {dialog.peerKind, dialog.peerId};
    [self post:^{
        noshi_store *store = [self workerStore];
        noshi_status status = store ? NOSHI_OK : NOSHI_E_STATE;
        /* a page holds at most two hundred of them, newest first, so the pages are taken until none is left */
        while (status == NOSHI_OK) {
            NSArray *page = NoshiSavedDeletedOfPeer(store, peer, 0, INT32_MAX);
            if (!page.count) break;
            for (NoshiMessage *message in page) {
                status = noshi_store_delete(store, NOSHI_RECORD_DELETED_MESSAGE, peer, message.messageId);
                if (status != NOSHI_OK) break;
            }
        }
        [self storeChanged];
        NSString *error = status == NOSHI_OK ? nil : @"STORAGE";
        [self deliverMain:^{ if (done) done(error); [done release]; }];
    }];
}

NSMutableArray *NoshiSavedDeletedOfPeer(noshi_store *store, noshi_peer peer, int32_t low, int32_t high) {
    NSMutableArray *found = [NSMutableArray array];
    NoshiSavedRead read = {found, YES, low, high, 1, 0};
    if (store && noshi_store_page(store, NOSHI_RECORD_DELETED_MESSAGE, peer, (int64_t)high + 1, 200, NoshiCollectSaved, &read) != NOSHI_OK) [found removeAllObjects];
    return found;
}

- (void)loadSavedDeletedOfDialog:(NoshiDialog *)dialog from:(int32_t)low to:(int32_t)high completion:(void (^)(NSArray *))completion {
    void (^done)(NSArray *) = [completion copy];
    noshi_peer peer = {dialog.peerKind, dialog.peerId};
    [self post:^{
        NSArray *delivered = [[NoshiSavedDeletedOfPeer([self workerStore], peer, low, high) copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)loadEditVersionsOfMessage:(int32_t)messageId dialog:(NoshiDialog *)dialog completion:(void (^)(NSArray *))completion {
    void (^done)(NSArray *) = [completion copy];
    noshi_peer peer = {dialog.peerKind, dialog.peerId};
    [self post:^{
        noshi_store *store = [self workerStore];
        NSMutableArray *found = [NSMutableArray array];
        NoshiSavedRead read = {found, NO, 0, 0, NOSHI_EDIT_VERSIONS, messageId};
        int64_t before = ((int64_t)messageId + 1) * NOSHI_EDIT_VERSIONS;
        if (store && noshi_store_page(store, NOSHI_RECORD_MESSAGE_EDIT, peer, before, 100, NoshiCollectSaved, &read) != NOSHI_OK) [found removeAllObjects];
        /* the page runs from the newest version to the oldest */
        NSArray *delivered = [[[found reverseObjectEnumerator] allObjects] copy];
        [self deliverMain:^{ done([delivered autorelease]); [done release]; }];
    }];
}

@end
