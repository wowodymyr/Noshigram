#import "noshi_session_sendas.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

#include "noshi_send_as.h"
#include "noshi_tl_ids.h"

/* a chat is told apart by its kind and id; the topic of a forum does not change who writes */
static NSString *NoshiSendAsKey(const noshi_peer_ref *chat) {
    return [NSString stringWithFormat:@"%d:%lld", (int)chat->kind, (long long)chat->id];
}

/* the stars the person agreed to pay for each message to a chat that charges for them; the server refuses a message without the amount (ALLOW_PAYMENT_REQUIRED_n) and
   takes a smaller one than its price just as badly, so the amount it named is what is sent. the sends run on a worker, hence the lock */
static NSMutableDictionary *sPaidApprovals;

static NSString *NoshiPaidKey(NoshiSession *session, const noshi_peer_ref *chat) {
    return [NSString stringWithFormat:@"%p:%d:%lld", session, (int)chat->kind, (long long)chat->id];
}

void NoshiApprovePaidMessages(NoshiSession *session, const noshi_peer_ref *chat, long long stars) {
    @synchronized([NoshiSession class]) {
        if (!sPaidApprovals) sPaidApprovals = [[NSMutableDictionary alloc] init];
        if (stars > 0) [sPaidApprovals setObject:[NSNumber numberWithLongLong:stars] forKey:NoshiPaidKey(session, chat)];
        else [sPaidApprovals removeObjectForKey:NoshiPaidKey(session, chat)];
    }
}

static long long NoshiApprovedPaidStars(NoshiSession *session, const noshi_peer_ref *chat) {
    @synchronized([NoshiSession class]) {
        return [[sPaidApprovals objectForKey:NoshiPaidKey(session, chat)] longLongValue];
    }
}

noshi_status NoshiApplySendAs(NoshiSession *session, const noshi_peer_ref *chat, noshi_arena *arena, noshi_tl_value *request) {
    NoshiDialog *identity = [session storedSendAsForChat:chat];
    if (identity) {
        noshi_peer_ref who = NoshiPeerRefOfDialog(identity);
        noshi_status status = noshi_set_send_as(arena, request, &who);
        if (status != NOSHI_OK) return status;
    }
    long long paid = NoshiApprovedPaidStars(session, chat);
    if (paid > 0 && (noshi_tl_is(request, NOSHI_TL_ID_messages_sendMessage) || noshi_tl_is(request, NOSHI_TL_ID_messages_sendMedia) ||
                     noshi_tl_is(request, NOSHI_TL_ID_messages_sendMultiMedia) || noshi_tl_is(request, NOSHI_TL_ID_messages_forwardMessages)))
        return noshi_tl_set_i64(arena, request, "allow_paid_stars", paid);
    return NOSHI_OK;
}

@implementation NoshiSendAsOption
@synthesize identity = _identity;
@synthesize premiumRequired = _premiumRequired;

- (id)initWithRow:(const noshi_dialog_row *)row premiumRequired:(BOOL)premium {
    self = [super init];
    if (!self) return nil;
    _identity = [[NoshiDialog alloc] initWithRow:row];
    _premiumRequired = premium;
    return self;
}

- (BOOL)isAccount { return _identity.saved; }

- (void)dealloc {
    [_identity release];
    [super dealloc];
}
@end

@implementation NoshiSession (SendAs)

- (void)approvePaidMessages:(long long)stars ofDialog:(NoshiDialog *)dialog {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NoshiApprovePaidMessages(self, &peer, stars);
}

- (void)loadSendAsOptionsOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    int64_t self_id = [NoshiSession accountIdInDirectory:self.directory];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_send_as_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *options = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_dialog_row *rows = calloc(NOSHI_SEND_AS_MAX, sizeof(*rows));
            uint8_t premium[NOSHI_SEND_AS_MAX];
            size_t count = 0;
            noshi_status status = rows ? noshi_send_as_parse(result->value, self_id, rows, premium, NOSHI_SEND_AS_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                options = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [options addObject:[[[NoshiSendAsOption alloc] initWithRow:&rows[i] premiumRequired:premium[i] != 0] autorelease]];
            } else {
                NSLog(@"noshigram: channels.getSendAs answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(options, deliveredError); [done release]; }];
    }];
}

- (NoshiDialog *)storedSendAsForChat:(const noshi_peer_ref *)chat {
    NoshiDialog *identity;
    @synchronized(self) {
        identity = [[[_sendAsChoices objectForKey:NoshiSendAsKey(chat)] retain] autorelease];
    }
    return identity;
}

- (void)storeSendAs:(NoshiDialog *)identity forChat:(const noshi_peer_ref *)chat {
    @synchronized(self) {
        if (!_sendAsChoices) _sendAsChoices = [[NSMutableDictionary alloc] init];
        if (identity) [_sendAsChoices setObject:identity forKey:NoshiSendAsKey(chat)];
        else [_sendAsChoices removeObjectForKey:NoshiSendAsKey(chat)];
    }
}

- (NoshiDialog *)sendAsIdentityOfDialog:(NoshiDialog *)dialog {
    noshi_peer_ref chat = NoshiPeerRefOfDialog(dialog);
    return [self storedSendAsForChat:&chat];
}

- (void)adoptSendAsIdentity:(NoshiDialog *)identity ofDialog:(NoshiDialog *)dialog {
    noshi_peer_ref chat = NoshiPeerRefOfDialog(dialog);
    [self storeSendAs:identity.saved ? nil : identity forChat:&chat];
}

- (void)chooseSendAsIdentity:(NoshiDialog *)identity ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref chat = NoshiPeerRefOfDialog(dialog);
    NoshiDialog *before = [[self storedSendAsForChat:&chat] retain];
    BOOL account = !identity || identity.saved;
    noshi_peer_ref who;
    memset(&who, 0, sizeof(who));
    if (account) {
        who.kind = 1;
        who.self = 1;
    } else {
        who = NoshiPeerRefOfDialog(identity);
    }
    /* later messages carry the choice at once; a refusal puts the old one back */
    [self storeSendAs:account ? nil : identity forChat:&chat];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_save_default_send_as_request(arena, &chat, &who, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        [self noteRpcError:error];
        if (error) [self storeSendAs:before forChat:&chat];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
        [before release];
    }];
}

@end
