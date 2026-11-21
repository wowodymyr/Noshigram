#import "noshi_session_invites.h"
#import "noshi_session_internal.h"

#import "noshi_rpc.h"

#include "noshi_tl_ids.h"

static NSString *NoshiInviteUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation NoshiInvite

@synthesize link = _link;
@synthesize title = _title;
@synthesize revoked = _revoked;
@synthesize permanent = _permanent;
@synthesize requestNeeded = _requestNeeded;
@synthesize date = _date;
@synthesize expireDate = _expireDate;
@synthesize usageLimit = _usageLimit;
@synthesize usage = _usage;
@synthesize requested = _requested;

- (id)initWithRow:(const noshi_invite *)row {
    self = [super init];
    if (!self) return nil;
    _link = [NoshiInviteUtf8(row->link) copy];
    _title = [NoshiInviteUtf8(row->title) copy];
    _revoked = row->revoked;
    _permanent = row->permanent;
    _requestNeeded = row->request_needed;
    _date = row->date;
    _startDate = row->start_date;
    _expireDate = row->expire_date;
    _usageLimit = row->usage_limit;
    _usage = row->usage;
    _requested = row->requested;
    return self;
}

- (void)dealloc {
    [_link release];
    [_title release];
    [super dealloc];
}

- (BOOL)expired {
    if (_revoked) return NO;
    if (_expireDate > 0 && _expireDate <= (int32_t)time(NULL)) return YES;
    return _usageLimit > 0 && _usage >= _usageLimit;
}

@end

static noshi_invite_spec NoshiInviteSpec(int32_t expireDate, int32_t usageLimit, BOOL requestNeeded, NSString *title) {
    noshi_invite_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.expire_date = expireDate;
    spec.usage_limit = usageLimit;
    spec.request_needed = requestNeeded ? 1 : 0;
    snprintf(spec.title, sizeof(spec.title), "%s", title.length ? title.UTF8String : "");
    return spec;
}

@implementation NoshiSession (Invites)

- (void)loadInvitesOfDialog:(NoshiDialog *)dialog revoked:(BOOL)revoked afterInvite:(NoshiInvite *)last
                 completion:(void (^)(NSArray *, NSInteger, NSString *))completion {
    void (^done)(NSArray *, NSInteger, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *offsetLink = [[last.link copy] autorelease];
    int32_t offsetDate = last.date;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_invite_list_request(arena, &peer, revoked ? 1 : 0, offsetDate, offsetLink.length ? offsetLink.UTF8String : NULL, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *invites = nil;
        NSInteger total = 0;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_invite *rows = calloc(NOSHI_INVITES_MAX, sizeof(*rows));
            size_t count = 0;
            int32_t all = 0;
            noshi_status status = rows ? noshi_invite_list_parse(result->value, rows, NOSHI_INVITES_MAX, &count, &all) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                invites = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [invites addObject:[[[NoshiInvite alloc] initWithRow:&rows[i]] autorelease]];
                total = all;
            } else {
                NSLog(@"noshigram: messages.getExportedChatInvites answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(invites, total, delivered); [done release]; }];
    }];
}

/* the answer of a creation or an edit is the link as the server has it now */
- (void)runInviteRequest:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build completion:(void (^)(NoshiInvite *, NoshiInvite *, NSString *))completion {
    void (^done)(NoshiInvite *, NoshiInvite *, NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NoshiInvite *invite = nil, *replacement = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_invite row, other;
            int replaced = 0;
            noshi_status status = noshi_invite_answer_parse(result->value, &row, &other, &replaced);
            if (status == NOSHI_OK) {
                invite = [[[NoshiInvite alloc] initWithRow:&row] autorelease];
                if (replaced) replacement = [[[NoshiInvite alloc] initWithRow:&other] autorelease];
            } else {
                NSLog(@"noshigram: the answer about an invite link was rejected: %s", noshi_status_name(status));
                error = @"MALFORMED";
            }
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(invite, replacement, delivered); [done release]; }];
    }];
}

- (void)createInviteInDialog:(NoshiDialog *)dialog expireDate:(int32_t)expireDate usageLimit:(int32_t)usageLimit requestNeeded:(BOOL)requestNeeded
                       title:(NSString *)title completion:(void (^)(NoshiInvite *, NSString *))completion {
    void (^done)(NoshiInvite *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    noshi_invite_spec spec = NoshiInviteSpec(expireDate, usageLimit, requestNeeded, title);
    [self runInviteRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_invite_create_request(arena, &peer, &spec, request);
    } completion:^(NoshiInvite *invite, NoshiInvite *replacement, NSString *errorName) {
        (void)replacement;
        done(invite, errorName);
        [done release];
    }];
}

- (void)editInvite:(NoshiInvite *)invite inDialog:(NoshiDialog *)dialog expireDate:(int32_t)expireDate usageLimit:(int32_t)usageLimit
     requestNeeded:(BOOL)requestNeeded title:(NSString *)title completion:(void (^)(NoshiInvite *, NSString *))completion {
    void (^done)(NoshiInvite *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    noshi_invite_spec spec = NoshiInviteSpec(expireDate, usageLimit, requestNeeded, title);
    NSString *link = [[invite.link copy] autorelease];
    [self runInviteRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_invite_edit_request(arena, &peer, link.UTF8String, &spec, request);
    } completion:^(NoshiInvite *edited, NoshiInvite *replacement, NSString *errorName) {
        (void)replacement;
        done(edited, errorName);
        [done release];
    }];
}

- (void)revokeInvite:(NoshiInvite *)invite inDialog:(NoshiDialog *)dialog
          completion:(void (^)(NoshiInvite *, NoshiInvite *, NSString *))completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *link = [[invite.link copy] autorelease];
    [self runInviteRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_invite_revoke_request(arena, &peer, link.UTF8String, request);
    } completion:completion];
}

/* the two deletes answer with a Bool */
- (void)runInviteDelete:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (!noshi_tl_is(result->value, NOSHI_TL_ID_boolTrue)) error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)deleteInvite:(NoshiInvite *)invite inDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *link = [[invite.link copy] autorelease];
    [self runInviteDelete:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_invite_delete_request(arena, &peer, link.UTF8String, request);
    } completion:completion];
}

- (void)deleteRevokedInvitesInDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self runInviteDelete:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_invite_delete_revoked_request(arena, &peer, request);
    } completion:completion];
}

@end
