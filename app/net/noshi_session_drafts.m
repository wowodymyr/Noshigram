#import "noshi_session_drafts.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"
#include "noshi_tl_ids.h"

/* worker only: collects what the core walk reports as board entries; a draft that cannot be read is left out, so it neither shows nor erases one */
static noshi_status NoshiCollectDraft(void *ctx, int32_t kind, int64_t peer, int32_t top, const noshi_tl_value *body) {
    NSMutableArray *entries = ctx;
    id draft = [NSNull null];
    if (body) {
        noshi_draft *row = malloc(sizeof(*row));
        if (!row) return NOSHI_E_NOMEM;
        noshi_status status = noshi_draft_read(body, top, row);
        if (status == NOSHI_OK) {
            NoshiDraft *read = [NoshiDraft draftWithRow:row];
            if (read) draft = read;
        }
        free(row);
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: a draft of chat %lld was not read: %s", (long long)peer, noshi_status_name(status));
            return NOSHI_OK;
        }
    }
    [entries addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:kind], [NSNumber numberWithLongLong:peer], [NSNumber numberWithInt:top], draft, nil]];
    return NOSHI_OK;
}

@implementation NoshiSession (Drafts)

- (void)saveDraftText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo noWebpage:(BOOL)noWebpage forDialog:(NoshiDialog *)dialog {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    int32_t kind = dialog.peerKind, top = dialog.topicId;
    long long chat = dialog.peerId;
    NSString *body = [text copy];
    NoshiDraft *draft = [[[NoshiDraft alloc] initWithText:body entities:entities replyTo:replyTo noWebpage:noWebpage
                                                          date:(int32_t)[[NSDate date] timeIntervalSince1970]] autorelease];
    [self.drafts setLocalDraft:draft kind:kind peer:chat top:top];
    NSUInteger revision = self.drafts.revision;
    NSMutableData *strings = nil;
    size_t count = 0;
    NSMutableData *packed = NoshiPackSendEntities(entities, &strings, &count);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        (void)strings;
        return noshi_draft_save_request(arena, &peer, body.UTF8String, packed.bytes, count, replyTo, noWebpage, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? (noshi_tl_is(result->value, NOSHI_TL_ID_boolTrue) ? nil : @"REFUSED") : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            if (delivered) NSLog(@"noshigram: saving the draft of chat %lld failed: %@", chat, delivered);
            [self.drafts noteSavedKind:kind peer:chat top:top revision:revision success:delivered == nil];
        }];
    }];
    [body release];
}

- (void)noteDraftsOfDialogsAnswer:(const noshi_tl_value *)answer complete:(BOOL)complete {
    [self noteDraftsOfDialogsAnswer:answer complete:complete since:NSUIntegerMax];
}

- (void)noteDraftsOfDialogsAnswer:(const noshi_tl_value *)answer complete:(BOOL)complete since:(NSUInteger)revision {
    NSMutableArray *entries = [NSMutableArray array];
    noshi_status status = noshi_draft_dialogs_visit(answer, NoshiCollectDraft, entries);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: the drafts of the chat list were not read: %s", noshi_status_name(status));
        return;
    }
    [self deliverMain:^{ [self.drafts noteListed:entries complete:complete since:revision]; }];
}

- (void)noteDraftsOfTopicsAnswer:(const noshi_tl_value *)answer forum:(NoshiDialog *)forum since:(NSUInteger)revision {
    NSMutableArray *entries = [NSMutableArray array];
    noshi_status status = noshi_draft_topics_visit(answer, forum.peerKind, forum.peerId, NoshiCollectDraft, entries);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: the drafts of the topics were not read: %s", noshi_status_name(status));
        return;
    }
    [self deliverMain:^{ [self.drafts noteListed:entries complete:YES since:revision]; }];
}

- (void)noteDraftUpdate:(const noshi_tl_value *)update {
    int32_t kind = 0, top = 0;
    int64_t peer = 0;
    const noshi_tl_value *body = NULL;
    noshi_status status = noshi_draft_update_read(update, &kind, &peer, &top, &body);
    if (status == NOSHI_E_UNSUPPORTED) return;
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: a draft update was rejected: %s", noshi_status_name(status));
        return;
    }
    noshi_draft *row = malloc(sizeof(*row));
    if (!row) return;
    status = noshi_draft_read(body, top, row);
    NoshiDraft *draft = status == NOSHI_OK ? [NoshiDraft draftWithRow:row] : nil;
    free(row);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: the draft of chat %lld was not read: %s", (long long)peer, noshi_status_name(status));
        return;
    }
    [self deliverMain:^{ [self.drafts noteAccountDraft:draft kind:kind peer:peer top:top]; }];
}

- (void)requestAllDraftsOnce {
    if (_draftsRequested) return;
    _draftsRequested = YES;
    [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "messages.getAllDrafts");
        return *request ? NOSHI_OK : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        /* the drafts arrive as the updates of the answer, which the client delivers to noteDraftUpdate */
        if (result->status == NOSHI_OK) return;
        NSString *error = NoshiRpcErrorName(result);
        [self noteRpcError:error];
        _draftsRequested = NO;
        NSLog(@"noshigram: asking for the drafts failed: %@", error);
    }];
}

@end
