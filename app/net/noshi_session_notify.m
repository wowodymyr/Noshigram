#import "noshi_session_notify.h"
#import "noshi_language.h"

#import "noshi_files.h"
#import "noshi_rpc.h"
#import "noshi_session_internal.h"

#include "noshi_notify.h"

@implementation NoshiNotifyEvent

@synthesize peerKind = _peerKind;
@synthesize peerId = _peerId;
@synthesize messageId = _messageId;
@synthesize title = _title;
@synthesize body = _body;
@synthesize sound = _sound;
@synthesize dialog = _dialog;

- (id)initWithEvent:(const noshi_notify_event *)event {
    self = [super init];
    if (!self) return nil;
    _sound = event->sound;
    _peerKind = event->peer_kind;
    _peerId = event->peer_id;
    _messageId = event->message_id;
    _title = [[NSString stringWithUTF8String:event->title] copy];
    _body = [[NSString stringWithUTF8String:event->body] copy];
    if (!_title) _title = [@"" copy];
    if (!_body) _body = [@"" copy];
    return self;
}

- (void)dealloc {
    [_title release];
    [_body release];
    [_dialog release];
    [super dealloc];
}

@end

#define SCAN_DIALOGS 50

/* the look the session took last; worker thread only, and one session lives at a time */
static noshi_notify_state sNotifyState;
static int64_t sNotifyStateAccount;

static NSString *NoshiNotifyStatePath(NSString *directory, int64_t account) {
    return NoshiFilePath(directory, [NSString stringWithFormat:@"notify-state-%lld", (long long)account]);
}

/* the last look of this account from its file, or an empty one that takes the baseline */
static void NoshiNotifyLoadState(NSString *directory, int64_t account) {
    uint8_t bytes[NOSHI_NOTIFY_STATE_BYTES + 1];
    size_t len = 0;
    if (sNotifyStateAccount == account) return;
    sNotifyStateAccount = account;
    noshi_notify_state_init(&sNotifyState);
    noshi_status status = NoshiReadFile(NoshiNotifyStatePath(directory, account), bytes, sizeof(bytes), &len);
    if (status == NOSHI_OK && noshi_notify_state_unpack(bytes, len, &sNotifyState) != NOSHI_OK) {
        NSLog(@"noshigram: the notification state file is unusable, taking a new baseline");
        noshi_notify_state_init(&sNotifyState);
    }
}

static void NoshiNotifySaveState(NSString *directory, int64_t account) {
    uint8_t bytes[NOSHI_NOTIFY_STATE_BYTES];
    size_t len = 0;
    noshi_status status = noshi_notify_state_pack(&sNotifyState, bytes, sizeof(bytes), &len);
    if (status == NOSHI_OK) status = NoshiWriteFile(NoshiNotifyStatePath(directory, account), bytes, len);
    if (status != NOSHI_OK) NSLog(@"noshigram: cannot keep the notification state: %s", noshi_status_name(status));
}

@implementation NoshiSession (Notify)

- (void)scanNotificationsAnnouncing:(BOOL)announce options:(NoshiNotifyScanOptions)options completion:(NoshiNotifyScanCompletion)completion {
    NoshiNotifyScanCompletion done = [completion copy];
    BOOL russian = [NoshiInterfaceLanguage() isEqualToString:@"ru"];
    [self post:^{
        if ([self workerAccount] <= 0) {
            [self deliverMain:^{ done(nil, 0, nil, 0, 0, @"NO_ACCOUNT"); [done release]; }];
            return;
        }
        [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            noshi_tl_value *call = noshi_tl_new_obj(arena, "messages.getDialogs");
            noshi_tl_value *empty = noshi_tl_new_obj(arena, "inputPeerEmpty");
            if (!call || !empty) return NOSHI_E_NOMEM;
            noshi_status status = noshi_tl_set(call, "offset_peer", empty);
            if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, call, "offset_date", 0);
            if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, call, "offset_id", 0);
            if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, call, "limit", SCAN_DIALOGS);
            if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, call, "folder_id", 0);
            if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, call, "hash", 0);
            if (status == NOSHI_OK) *request = call;
            return status;
        } handler:^(const noshi_mt_rpc_result *result) {
            if (result->status != NOSHI_OK) {
                NSString *error = NoshiRpcErrorName(result);
                [self noteRpcError:error];
                /* the wait the server asks for travels with the name, which is how the notifier knows how long to leave the list alone */
                NSString *delivered = error;
                if ([error isEqualToString:@"FLOOD_WAIT"] && result->error_text) {
                    char name[128];
                    int32_t seconds = 0;
                    noshi_mt_rpc_error_split(result->error_text, name, sizeof(name), &seconds);
                    delivered = [NSString stringWithFormat:@"FLOOD_WAIT:%d", (int)seconds];
                }
                delivered = [[delivered copy] autorelease];
                [self deliverMain:^{ done(nil, 0, nil, 0, 0, delivered); [done release]; }];
                return;
            }
            noshi_dialog_row *rows = calloc(NOSHI_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            int32_t now = (int32_t)[[NSDate date] timeIntervalSince1970];
            noshi_status status = rows ? noshi_dialogs_parse(result->value, [self workerAccount], now, rows, NOSHI_DIALOGS_MAX, &count) : NOSHI_E_NOMEM;
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: the chat list for notifications was rejected: %s", noshi_status_name(status));
                free(rows);
                [self deliverMain:^{ done(nil, 0, nil, 0, 0, @"INTERNAL"); [done release]; }];
                return;
            }
            noshi_notify_settings settings;
            noshi_notify_event events[NOSHI_NOTIFY_EVENTS_MAX];
            size_t found = 0, more = 0, i;
            NSInteger badge = 0, unreadChats = 0;
            memset(&settings, 0, sizeof(settings));
            settings.enabled = announce ? 1 : 0;
            settings.rules = options.rules;
            settings.russian = russian ? 1 : 0;
            NoshiNotifyLoadState([self workerDirectory], [self workerAccount]);
            status = noshi_notify_diff(&sNotifyState, &settings, rows, count, now, options.activeKind, options.activePeer, events, NOSHI_NOTIFY_EVENTS_MAX, &found, &more);
            for (i = 0; i < count; ++i) {
                noshi_notify_decision decision;
                if (rows[i].folder || rows[i].deleted || rows[i].saved || rows[i].unread_count <= 0) continue;
                noshi_notify_decide(&options.rules, noshi_notify_scope_of(rows[i].peer_kind, rows[i].kind == NOSHI_DIALOG_CHANNEL), &rows[i].notify, now, &decision);
                if (decision.notify) ++unreadChats;
                if (!decision.notify && !options.badgeMuted) continue;
                badge += options.badgeMessages ? rows[i].unread_count : 1;
            }
            if (!options.badgeShown) badge = 0;
            NSMutableArray *list = [NSMutableArray arrayWithCapacity:found];
            for (i = 0; i < found; ++i) {
                NoshiNotifyEvent *event = [[[NoshiNotifyEvent alloc] initWithEvent:&events[i]] autorelease];
                for (size_t j = 0; j < count; ++j) {
                    if (rows[j].peer_kind != events[i].peer_kind || rows[j].peer_id != events[i].peer_id || rows[j].folder) continue;
                    event.dialog = [[[NoshiDialog alloc] initWithRow:&rows[j]] autorelease];
                    break;
                }
                [list addObject:event];
            }
            free(rows);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: the notification comparison failed: %s", noshi_status_name(status));
                [self deliverMain:^{ done(nil, 0, nil, 0, 0, @"INTERNAL"); [done release]; }];
                return;
            }
            NoshiNotifySaveState([self workerDirectory], [self workerAccount]);
            char moreText[96];
            noshi_notify_more_text(&settings, more, moreText, sizeof(moreText));
            NSString *moreString = more ? [NSString stringWithUTF8String:moreText] : nil;
            [self deliverMain:^{ done(list, more, moreString, badge, unreadChats, nil); [done release]; }];
        }];
    }];
}

@end
