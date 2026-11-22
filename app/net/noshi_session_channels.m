#import "noshi_session_internal.h"

#include "noshi_channel.h"
#include "noshi_message_actions.h"
#include "noshi_profile.h"

#import "noshi_rpc.h"
#import "noshi_session_channels.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *NoshiChannelUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

NSString *const NoshiDialogsChangedNotification = @"NoshiDialogsChanged";

@implementation NoshiFullChannel

@synthesize dialog = _dialog;
@synthesize linked = _linked;
@synthesize about = _about;
@synthesize username = _username;
@synthesize inviteLink = _inviteLink;
@synthesize megagroup = _megagroup;
@synthesize membershipKnown = _membershipKnown;
@synthesize verified = _verified;
@synthesize muted = _muted;
@synthesize giftsAvailable = _giftsAvailable;
@synthesize canViewStats = _canViewStats;
@synthesize creator = _creator;
@synthesize signatures = _signatures;
@synthesize adminRights = _adminRights;
@synthesize participants = _participants;
@synthesize admins = _admins;
@synthesize banned = _banned;
@synthesize gifts = _gifts;
@synthesize pinnedMessage = _pinnedMessage;
@synthesize sendAsKind = _sendAsKind;
@synthesize sendAsId = _sendAsId;
@synthesize wallpaper = _wallpaper;

- (id)initWithRow:(const noshi_full_channel *)row {
    self = [super init];
    if (!self) return nil;
    noshi_dialog_row dialog = row->dialog;
    _dialog = [[NoshiDialog alloc] initWithRow:&dialog];
    if (row->has_linked) {
        noshi_dialog_row linked = row->linked;
        _linked = [[NoshiDialog alloc] initWithRow:&linked];
    }
    _about = [NoshiChannelUtf8(row->about) copy];
    _username = [NoshiChannelUtf8(row->username) copy];
    _inviteLink = [NoshiChannelUtf8(row->link) copy];
    _megagroup = row->megagroup;
    _membershipKnown = row->membership_known;
    _verified = row->verified;
    _muted = row->muted;
    _giftsAvailable = row->gifts_available;
    _canViewStats = row->can_view_stats;
    _creator = row->creator;
    _signatures = row->signatures;
    _basic = row->basic;
    _adminRights = row->admin_rights;
    _participants = row->participants;
    _admins = row->admins;
    _banned = row->banned;
    _gifts = row->gifts;
    _pinnedMessage = row->pinned_message;
    _sendAsKind = row->send_as_kind;
    _sendAsId = row->send_as_id;
    _wallpaper = row->wallpaper;
    return self;
}

- (void)dealloc {
    [_dialog release];
    [_linked release];
    [_about release];
    [_username release];
    [_inviteLink release];
    [super dealloc];
}

- (BOOL)isAdmin {
    return _creator || _adminRights != 0;
}

- (NSString *)shownLink {
    if (_username.length) return [@"t.me/" stringByAppendingString:_username];
    if (_inviteLink.length) return [_inviteLink hasPrefix:@"https://"] ? [_inviteLink substringFromIndex:8] : _inviteLink;
    return @"";
}

- (NSString *)webLink {
    NSString *shown = self.shownLink;
    return shown.length ? [@"https://" stringByAppendingString:shown] : @"";
}

@end

@implementation NoshiChannelMember

@synthesize person = _person;
@synthesize role = _role;
@synthesize canEdit = _canEdit;
@synthesize isSelf = _isSelf;
@synthesize rights = _rights;
@synthesize date = _date;
@synthesize rank = _rank;

- (id)initWithRow:(const noshi_channel_member *)row {
    self = [super init];
    if (!self) return nil;
    noshi_person_row person = row->person;
    _person = [[NoshiPerson alloc] initWithRow:&person];
    _role = (NoshiChannelRole)row->role;
    _canEdit = row->can_edit;
    _isSelf = row->self;
    _rights = row->rights;
    _date = row->date;
    _rank = [NoshiChannelUtf8(row->rank) copy];
    return self;
}

- (void)dealloc {
    [_person release];
    [_rank release];
    [super dealloc];
}

@end

/* the reference of a person as a request names it; the access hash is what the server checks */
static noshi_peer_ref NoshiPeerRefOfPerson(NoshiPerson *person) {
    noshi_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = 1;
    peer.id = person.userId;
    peer.access_hash = person.accessHash;
    return peer;
}

/* the shape every write below shares: build the request, run it, hand the rpc error name (nil on success) to the main thread. checkBool reads a Bool answer */
static void NoshiChannelWrite(NoshiSession *session, noshi_status (^build)(noshi_arena *arena, noshi_tl_value **request), BOOL checkBool,
                                void (^completion)(NSString *errorName)) {
    void (^done)(NSString *) = [completion copy];
    [session invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else if (checkBool) {
            noshi_status parsed = noshi_channel_bool_parse(result->value);
            if (parsed == NOSHI_E_STATE) error = @"NOT_MODIFIED";
            else if (parsed != NOSHI_OK) error = @"MALFORMED";
        }
        [session noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [session deliverMain:^{ done(delivered); [done release]; }];
    }];
}

@implementation NoshiSession (Channels)

- (void)loadDiscussionOfPost:(int32_t)postId dialog:(NoshiDialog *)dialog completion:(void (^)(NoshiDialog *, NSString *))completion {
    void (^done)(NoshiDialog *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_discussion_request(arena, &peer, postId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiDialog *discussion = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else {
            noshi_dialog_row row;
            noshi_status status = noshi_discussion_parse(result->value, peer.id, &row);
            if (status == NOSHI_OK) {
                discussion = [[[NoshiDialog alloc] initWithRow:&row] autorelease];
                discussion.discussion = YES;
                discussion.discussionChannel = (long long)peer.id;
                discussion.discussionChannelHash = (long long)peer.access_hash;
                discussion.discussionPost = postId;
                const noshi_tl_value *list = noshi_tl_get(result->value, "messages");
                NSMutableArray *roots = [NSMutableArray array];
                noshi_message_row *messageRow = calloc(1, sizeof(*messageRow));
                if (messageRow && list && list->kind == NOSHI_TL_V_VEC) {
                    for (uint32_t i = 0; i < list->u.vec.count && i < NOSHI_MESSAGES_MAX; ++i) {
                        const noshi_tl_value *value = list->u.vec.items[i];
                        noshi_peer messagePeer;
                        if (noshi_peer_from_tl(noshi_tl_get(value, "peer_id"), &messagePeer) != NOSHI_OK ||
                            messagePeer.kind != 3 || messagePeer.id != row.peer_id || noshi_message_read(value, messageRow) != NOSHI_OK) continue;
                        NoshiMessage *message = [NoshiMessage messageWithRow:messageRow];
                        if (message) [roots addObject:message];
                    }
                } else if (!messageRow) NSLog(@"noshigram: no memory for discussion messages");
                free(messageRow);
                discussion.discussionMessages = roots;
                discussion.discussionPeople = NoshiPeopleOfAnswer(self, result->value);
                NSLog(@"noshigram: the comments of post %d of channel %lld are thread %d of group %lld", postId, (long long)peer.id, (int)row.topic_id, (long long)row.peer_id);
            } else {
                NSLog(@"noshigram: discussion of post %d rejected: %s", postId, noshi_status_name(status));
                error = @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(discussion, delivered); [done release]; }];
    }];
}

- (void)loadFullChannelOfDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiFullChannel *, NSString *))completion {
    void (^done)(NoshiFullChannel *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    /* a basic group asks messages.getFullChat and reads the answer into the same row */
    BOOL basic = peer.kind == 2;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return basic ? noshi_full_chat_request(arena, peer.id, request) : noshi_full_channel_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) {
            NSString *error = NoshiRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, delivered); [done release]; }];
            return;
        }
        noshi_full_channel *full = calloc(1, sizeof(*full));
        int32_t now = (int32_t)time(NULL);
        noshi_status status = !full ? NOSHI_E_NOMEM : basic ? noshi_full_chat_parse(result->value, peer.id, now, full) : noshi_full_channel_parse(result->value, peer.id, now, full);
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: %s answer rejected: %s", basic ? "messages.getFullChat" : "channels.getFullChannel", noshi_status_name(status));
            free(full);
            [self deliverMain:^{ done(nil, @"INTERNAL"); [done release]; }];
            return;
        }
        NoshiFullChannel *channel = [[[NoshiFullChannel alloc] initWithRow:full] autorelease];
        free(full);
        [self deliverMain:^{ done(channel, nil); [done release]; }];
    }];
}

- (void)loadMessage:(int32_t)messageId ofChannelDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiMessage *, NSString *))completion {
    void (^done)(NoshiMessage *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_message_request(arena, &peer, messageId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiMessage *message = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_message_row *rows = calloc(NOSHI_MESSAGES_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_messages_parse(result->value, rows, NOSHI_MESSAGES_MAX, &count) == NOSHI_OK && count > 0) message = [NoshiMessage messageWithRow:&rows[0]];
            else error = @"NOT_FOUND";
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(message, deliveredError); [done release]; }];
    }];
}

- (void)joinChannelOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_join_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status parsed = noshi_channel_join_parse(result->value);
            if (parsed == NOSHI_E_UNSUPPORTED) error = @"JOIN_WEBVIEW";
            else if (parsed != NOSHI_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)loadChannelDialogWithId:(long long)channelId completion:(void (^)(NoshiDialog *, NSString *))completion {
    void (^done)(NoshiDialog *, NSString *) = [completion copy];
    [self post:^{
        /* the hash is the one the chats of this account carry; a channel the account never saw has none, and the link cannot be opened */
        NoshiPerson *held = [self storedPersonWithKey:-(int64_t)channelId];
        int64_t hash = held ? (int64_t)held.accessHash : 0;
        if (!hash) {
            [self deliverMain:^{ done(nil, @"CHANNEL_PRIVATE"); [done release]; }];
            return;
        }
        [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_channel_by_id_request(arena, (int64_t)channelId, hash, request);
        } handler:^(const noshi_mt_rpc_result *result) {
            NoshiDialog *dialog = nil;
            NSString *error = nil;
            if (result->status != NOSHI_OK) {
                error = NoshiRpcErrorName(result);
            } else {
                noshi_dialog_row row;
                noshi_status parsed = noshi_channel_dialog_parse(result->value, (int64_t)channelId, &row);
                if (parsed == NOSHI_OK) dialog = [[[NoshiDialog alloc] initWithRow:&row] autorelease];
                else error = parsed == NOSHI_E_NOTFOUND ? @"CHANNEL_PRIVATE" : @"INTERNAL";
            }
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(dialog, delivered); [done release]; }];
        }];
    }];
}

- (void)loadMembershipOfDialog:(NoshiDialog *)dialog completion:(void (^)(BOOL, NSString *))completion {
    void (^done)(BOOL, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_member_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        int member = 0;
        if (result->status != NOSHI_OK) {
            NSString *name = NoshiRpcErrorName(result);
            /* the server's way of saying the account never joined, which is an answer and no failure */
            if (!noshi_channel_already_left(3, [name UTF8String])) error = name;
        } else if (noshi_channel_member_parse(result->value, &member) != NOSHI_OK) {
            error = @"MALFORMED";
        }
        if (error) [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        BOOL joined = member != 0;
        [self deliverMain:^{ done(joined, delivered); [done release]; }];
    }];
}

- (void)loadMembersOfDialog:(NoshiDialog *)dialog list:(NoshiChannelList)list query:(NSString *)query offset:(NSInteger)offset
                 completion:(void (^)(NSArray *, NSInteger, NSString *))completion {
    void (^done)(NSArray *, NSInteger, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    noshi_member_list kind = list == NoshiChannelListAdmins ? NOSHI_MEMBERS_ADMINS : (list == NoshiChannelListBlacklist ? NOSHI_MEMBERS_KICKED : NOSHI_MEMBERS_RECENT);
    NSString *text = [[query copy] autorelease];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_members_request(arena, &peer, kind, text.length ? [text UTF8String] : NULL, (int32_t)offset, NOSHI_MEMBERS_PAGE, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *members = nil;
        NSInteger total = 0;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_channel_member *rows = calloc(NOSHI_MEMBERS_MAX, sizeof(*rows));
            size_t count = 0;
            int32_t all = 0;
            noshi_status status = rows ? noshi_channel_members_parse(result->value, rows, NOSHI_MEMBERS_MAX, &count, &all) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                members = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [members addObject:[[[NoshiChannelMember alloc] initWithRow:&rows[i]] autorelease]];
                total = all;
            } else {
                NSLog(@"noshigram: channels.getParticipants answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(members, total, deliveredError); [done release]; }];
    }];
}

- (void)setAdminRights:(uint32_t)rights rank:(NSString *)rank ofPerson:(NoshiPerson *)person inDialog:(NoshiDialog *)dialog
            completion:(void (^)(NSString *))completion {
    noshi_peer_ref channel = NoshiPeerRefOfDialog(dialog);
    noshi_peer_ref user = NoshiPeerRefOfPerson(person);
    NSString *title = [[rank copy] autorelease];
    NoshiChannelWrite(self, ^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_admin_request(arena, &channel, &user, rights, title.length ? [title UTF8String] : NULL, request);
    }, NO, completion);
}

- (void)setBanned:(BOOL)banned person:(NoshiPerson *)person inDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref channel = NoshiPeerRefOfDialog(dialog);
    noshi_peer_ref user = NoshiPeerRefOfPerson(person);
    NoshiChannelWrite(self, ^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_ban_request(arena, &channel, &user, banned ? 1 : 0, request);
    }, NO, completion);
}

- (void)inviteUserDialog:(NoshiDialog *)user toDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref channel = NoshiPeerRefOfDialog(dialog);
    noshi_peer_ref who = NoshiPeerRefOfDialog(user);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_invite_request(arena, &channel, &who, 1, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        size_t missing = 0;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_channel_invite_missing(result->value, &missing) != NOSHI_OK) error = @"MALFORMED";
        /* the server answers with the people it could not add instead of an error, the usual cause being their privacy settings */
        else if (missing > 0) error = @"USER_PRIVACY_RESTRICTED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)setTitle:(NSString *)title ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref channel = NoshiPeerRefOfDialog(dialog);
    NSString *text = [[title copy] autorelease];
    NoshiChannelWrite(self, ^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_title_request(arena, &channel, [text UTF8String], request);
    }, NO, completion);
}

- (void)setAbout:(NSString *)about ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref channel = NoshiPeerRefOfDialog(dialog);
    NSString *text = [[about copy] autorelease];
    NoshiChannelWrite(self, ^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_about_request(arena, &channel, [text UTF8String], request);
    }, YES, completion);
}

- (void)setUsername:(NSString *)username ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref channel = NoshiPeerRefOfDialog(dialog);
    NSString *text = [[username copy] autorelease];
    NoshiChannelWrite(self, ^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_username_request(arena, &channel, [text UTF8String], 0, request);
    }, YES, completion);
}

- (void)checkUsername:(NSString *)username ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref channel = NoshiPeerRefOfDialog(dialog);
    NSString *text = [[username copy] autorelease];
    NoshiChannelWrite(self, ^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_username_request(arena, &channel, [text UTF8String], 1, request);
    }, YES, completion);
}

- (void)setSignatures:(BOOL)enabled ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref channel = NoshiPeerRefOfDialog(dialog);
    NoshiChannelWrite(self, ^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_signatures_request(arena, &channel, enabled ? 1 : 0, request);
    }, NO, completion);
}

- (void)setContentProtected:(BOOL)enabled ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NoshiChannelWrite(self, ^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_chat_sharing_request(arena, &peer, enabled ? 1 : 0, request);
    }, NO, completion);
}

@end
