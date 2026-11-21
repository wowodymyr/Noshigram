#import "noshi_session_admin_log.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *NoshiLogUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation NoshiAdminEvent

@synthesize eventId = _eventId;
@synthesize date = _date;
@synthesize kind = _kind;
@synthesize flag = _flag;
@synthesize hasMedia = _hasMedia;
@synthesize hasTarget = _hasTarget;
@synthesize messageId = _messageId;
@synthesize number = _number;
@synthesize actorName = _actorName;
@synthesize actorUsername = _actorUsername;
@synthesize targetName = _targetName;
@synthesize beforeText = _beforeText;
@synthesize afterText = _afterText;

- (id)initWithRow:(const noshi_admin_event *)row {
    self = [super init];
    if (!self) return nil;
    _eventId = row->id;
    _date = row->date;
    _kind = (noshi_admin_event_kind)row->kind;
    _flag = row->flag != 0;
    _hasMedia = row->has_media != 0;
    _hasTarget = row->has_target != 0;
    _messageId = row->message_id;
    _number = row->new_number;
    _actorName = [NoshiLogUtf8(row->actor_name) copy];
    _actorUsername = [NoshiLogUtf8(row->actor_username) copy];
    _targetName = [NoshiLogUtf8(row->target_name) copy];
    _beforeText = [NoshiLogUtf8(row->old_text) copy];
    _afterText = [NoshiLogUtf8(row->new_text) copy];
    return self;
}

- (void)dealloc {
    [_actorName release];
    [_actorUsername release];
    [_targetName release];
    [_beforeText release];
    [_afterText release];
    [super dealloc];
}

@end

@implementation NoshiSession (AdminLog)

- (void)loadAdminLogOfDialog:(NoshiDialog *)dialog query:(NSString *)query beforeId:(long long)maxId
                  completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *text = [[query copy] autorelease];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_admin_log_request(arena, &peer, text.length ? [text UTF8String] : NULL, maxId, NOSHI_ADMIN_LOG_PAGE, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *events = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_admin_event *rows = calloc(NOSHI_ADMIN_LOG_PAGE, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_admin_log_parse(result->value, rows, NOSHI_ADMIN_LOG_PAGE, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                events = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [events addObject:[[[NoshiAdminEvent alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: channels.getAdminLog answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(events, deliveredError); [done release]; }];
    }];
}

@end
