#import "noshi_session_calllog.h"

#import "noshi_person.h"
#import "noshi_rpc.h"
#import "noshi_session_internal.h"

@implementation NoshiCallLogEntry

@synthesize name = _name;
@synthesize initials = _initials;
@synthesize photo = _photo;

- (id)initWithRow:(const noshi_call_log_row *)row {
    self = [super init];
    if (!self) return nil;
    _row = *row;
    NSString *name = [NSString stringWithUTF8String:row->name];
    /* an account that is gone has no name, and a row of the list with none shows only a ghost; it is named for what it is, and so is a call whose person the server did not describe */
    if (!name.length) name = NSLocalizedString(@"chats.deleted", nil);
    _name = [name copy];
    _initials = [(row->deleted ? @"" : NoshiInitialsOfName(_name)) copy];
    _photo = [[NoshiPhoto photoWithRef:&row->photo] retain];
    return self;
}

- (void)dealloc {
    [_name release];
    [_initials release];
    [_photo release];
    [super dealloc];
}

- (int32_t)messageId { return _row.message_id; }
- (int32_t)date { return _row.date; }
- (int32_t)duration { return _row.duration; }
- (BOOL)outgoing { return _row.outgoing != 0; }
- (BOOL)video { return _row.video != 0; }
- (BOOL)missed { return _row.outcome == NOSHI_OUTCOME_MISSED; }
- (BOOL)busy { return _row.outcome == NOSHI_OUTCOME_BUSY; }
- (long long)userId { return _row.user_id; }
- (BOOL)deleted { return _row.deleted != 0; }

- (NSString *)summaryText {
    NSString *kind;
    if (self.missed) kind = NSLocalizedString(self.outgoing ? @"calls.cancelled" : @"calls.missed", nil);
    else if (self.busy) kind = NSLocalizedString(@"calls.busy", nil);
    else kind = NSLocalizedString(self.outgoing ? @"calls.outgoing" : @"calls.incoming", nil);
    if (self.video) kind = [NSString stringWithFormat:NSLocalizedString(@"calls.video", nil), kind];
    if (_row.duration > 0) return [NSString stringWithFormat:@"%@, %d:%02d", kind, (int)(_row.duration / 60), (int)(_row.duration % 60)];
    return kind;
}

- (NoshiDialog *)dialog {
    if (!_row.access_hash) return nil;
    noshi_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = 1;
    row.peer_id = _row.user_id;
    row.peer_hash = _row.access_hash;
    row.kind = NOSHI_DIALOG_USER;
    row.deleted = _row.deleted;
    row.photo = _row.photo;
    snprintf(row.title, sizeof(row.title), "%s", _row.name);
    return [[[NoshiDialog alloc] initWithRow:&row] autorelease];
}

@end

@implementation NoshiSession (CallLog)

- (void)loadCallLog:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_call_log_request(arena, NOSHI_CALL_LOG_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *entries = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_call_log_row *rows = calloc(NOSHI_CALL_LOG_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_call_log_parse(result->value, rows, NOSHI_CALL_LOG_MAX, &count) == NOSHI_OK) {
                entries = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [entries addObject:[[[NoshiCallLogEntry alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: the call log answer was rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:entries error:error completion:done];
        [done release];
    }];
}

@end
