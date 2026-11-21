#import "noshi_session_privacy.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

static NSString *NoshiPrivacyText(const char *text) {
    NSString *string = [NSString stringWithUTF8String:text];
    return string ? string : @"";
}

@implementation NoshiPrivacyEntry
@synthesize identifier = _identifier;
@synthesize chat = _chat;
@synthesize name = _name;
@synthesize photo = _photo;

- (id)initWithIdentifier:(long long)identifier chat:(BOOL)chat name:(NSString *)name ref:(const noshi_photo_ref *)ref {
    self = [super init];
    if (!self) return nil;
    _identifier = identifier;
    _chat = chat;
    _name = [name copy];
    _photo = [[NoshiPhoto photoWithRef:ref] retain];
    return self;
}

- (void)dealloc {
    [_name release];
    [_photo release];
    [super dealloc];
}
@end

@implementation NoshiPrivacyRules
@synthesize key = _key;

- (id)initWithKey:(noshi_privacy_key)key rules:(const noshi_privacy_rules *)rules {
    self = [super init];
    if (!self) return nil;
    _key = key;
    _rules = malloc(sizeof(*_rules));
    if (!_rules) {
        [self release];
        return nil;
    }
    *_rules = *rules;
    return self;
}

- (void)dealloc {
    free(_rules);
    [super dealloc];
}

- (noshi_privacy_base)base { return _rules->base; }
- (void)setBase:(noshi_privacy_base)base { _rules->base = base; }
- (const noshi_privacy_rules *)rules { return _rules; }

- (NSUInteger)countAllowed:(BOOL)allowed {
    return allowed ? _rules->allow_users_count + _rules->allow_chats_count : _rules->disallow_users_count + _rules->disallow_chats_count;
}

- (NSArray *)entriesAllowed:(BOOL)allowed {
    NSMutableArray *entries = [NSMutableArray array];
    const noshi_privacy_user *users = allowed ? _rules->allow_users : _rules->disallow_users;
    const noshi_privacy_chat *chats = allowed ? _rules->allow_chats : _rules->disallow_chats;
    size_t userCount = allowed ? _rules->allow_users_count : _rules->disallow_users_count;
    size_t chatCount = allowed ? _rules->allow_chats_count : _rules->disallow_chats_count;
    for (size_t i = 0; i < userCount; ++i) {
        [entries addObject:[[[NoshiPrivacyEntry alloc] initWithIdentifier:users[i].id chat:NO name:NoshiPrivacyText(users[i].name) ref:&users[i].photo] autorelease]];
    }
    for (size_t i = 0; i < chatCount; ++i) {
        [entries addObject:[[[NoshiPrivacyEntry alloc] initWithIdentifier:chats[i].id chat:YES name:NoshiPrivacyText(chats[i].title) ref:&chats[i].photo] autorelease]];
    }
    return entries;
}

static void NoshiPrivacyDropUser(noshi_privacy_user *users, size_t *count, long long identifier) {
    for (size_t i = 0; i < *count; ++i) {
        if (users[i].id != identifier) continue;
        memmove(&users[i], &users[i + 1], (*count - i - 1) * sizeof(*users));
        --*count;
        return;
    }
}

- (BOOL)addUser:(long long)userId hash:(long long)hash name:(NSString *)name photo:(NoshiPhoto *)photo allowed:(BOOL)allowed {
    if (hash == 0) return NO;
    noshi_privacy_user *same = allowed ? _rules->allow_users : _rules->disallow_users;
    size_t *sameCount = allowed ? &_rules->allow_users_count : &_rules->disallow_users_count;
    noshi_privacy_user *other = allowed ? _rules->disallow_users : _rules->allow_users;
    size_t *otherCount = allowed ? &_rules->disallow_users_count : &_rules->allow_users_count;
    NoshiPrivacyDropUser(other, otherCount, userId);
    for (size_t i = 0; i < *sameCount; ++i) if (same[i].id == userId) return YES;
    if (*sameCount >= NOSHI_PRIVACY_EXCEPT_MAX) return NO;
    noshi_privacy_user *slot = &same[(*sameCount)++];
    memset(slot, 0, sizeof(*slot));
    slot->id = userId;
    slot->access_hash = hash;
    if (photo) slot->photo = photo.ref;
    const char *text = name.UTF8String ? name.UTF8String : "";
    size_t length = strlen(text);
    if (length >= sizeof(slot->name)) {
        length = sizeof(slot->name) - 1;
        while (length > 0 && ((uint8_t)text[length] & 0xC0u) == 0x80u) --length;
    }
    memcpy(slot->name, text, length);
    return YES;
}

- (BOOL)addChat:(long long)chatId title:(NSString *)title photo:(NoshiPhoto *)photo allowed:(BOOL)allowed {
    noshi_privacy_chat *same = allowed ? _rules->allow_chats : _rules->disallow_chats;
    size_t *sameCount = allowed ? &_rules->allow_chats_count : &_rules->disallow_chats_count;
    noshi_privacy_chat *other = allowed ? _rules->disallow_chats : _rules->allow_chats;
    size_t *otherCount = allowed ? &_rules->disallow_chats_count : &_rules->allow_chats_count;
    for (size_t i = 0; i < *otherCount; ++i) {
        if (other[i].id != chatId) continue;
        memmove(&other[i], &other[i + 1], (*otherCount - i - 1) * sizeof(*other));
        --*otherCount;
        break;
    }
    for (size_t i = 0; i < *sameCount; ++i) if (same[i].id == chatId) return YES;
    if (*sameCount >= NOSHI_PRIVACY_EXCEPT_MAX) return NO;
    noshi_privacy_chat *slot = &same[(*sameCount)++];
    memset(slot, 0, sizeof(*slot));
    slot->id = chatId;
    if (photo) slot->photo = photo.ref;
    const char *text = title.UTF8String ? title.UTF8String : "";
    size_t length = strlen(text);
    if (length >= sizeof(slot->title)) {
        length = sizeof(slot->title) - 1;
        while (length > 0 && ((uint8_t)text[length] & 0xC0u) == 0x80u) --length;
    }
    memcpy(slot->title, text, length);
    return YES;
}

- (void)removeEntry:(NoshiPrivacyEntry *)entry allowed:(BOOL)allowed {
    if (entry.chat) {
        noshi_privacy_chat *chats = allowed ? _rules->allow_chats : _rules->disallow_chats;
        size_t *count = allowed ? &_rules->allow_chats_count : &_rules->disallow_chats_count;
        for (size_t i = 0; i < *count; ++i) {
            if (chats[i].id != entry.identifier) continue;
            memmove(&chats[i], &chats[i + 1], (*count - i - 1) * sizeof(*chats));
            --*count;
            return;
        }
    } else {
        NoshiPrivacyDropUser(allowed ? _rules->allow_users : _rules->disallow_users, allowed ? &_rules->allow_users_count : &_rules->disallow_users_count, entry.identifier);
    }
}
@end

@implementation NoshiBlockedPeer
@synthesize name = _name;
@synthesize photo = _photo;

- (id)initWithRow:(const noshi_blocked_row *)row {
    self = [super init];
    if (!self) return nil;
    _row = *row;
    _name = [NoshiPrivacyText(row->name) copy];
    _photo = [[NoshiPhoto photoWithRef:&row->photo] retain];
    return self;
}

- (void)dealloc {
    [_photo release];
    [_name release];
    [super dealloc];
}

- (int32_t)kind { return _row.kind; }
- (long long)identifier { return _row.id; }
- (long long)accessHash { return _row.access_hash; }
- (int32_t)date { return _row.date; }
@end

@implementation NoshiSession (Privacy)

/* an answer of rules, parsed on the worker into a fresh copy for the main thread */
- (NoshiPrivacyRules *)privacyRulesOfResult:(const noshi_mt_rpc_result *)result key:(noshi_privacy_key)key error:(NSString **)error {
    noshi_privacy_rules *rules = malloc(sizeof(*rules));
    NoshiPrivacyRules *made = nil;
    if (!rules) {
        *error = @"INTERNAL";
        return nil;
    }
    noshi_status status = noshi_privacy_parse(result->value, rules);
    if (status == NOSHI_OK) {
        made = [[[NoshiPrivacyRules alloc] initWithKey:key rules:rules] autorelease];
    } else {
        NSLog(@"noshigram: the privacy rules were rejected: %s", noshi_status_name(status));
        /* a list longer than the screen can hold must not be edited, or what is cut would be lost on the server */
        *error = status == NOSHI_E_LIMIT ? @"PRIVACY_TOO_MANY" : @"INTERNAL";
    }
    free(rules);
    return made;
}

- (void)runPrivacyRequest:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build key:(noshi_privacy_key)key
               completion:(void (^)(NoshiPrivacyRules *, NSString *))completion {
    void (^done)(NoshiPrivacyRules *, NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NoshiPrivacyRules *rules = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else rules = [self privacyRulesOfResult:result key:key error:&error];
        [self noteRpcError:error];
        NoshiPrivacyRules *delivered = [rules retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, deliveredError); [delivered release]; [done release]; }];
    }];
}

- (void)loadPrivacy:(noshi_privacy_key)key completion:(void (^)(NoshiPrivacyRules *, NSString *))completion {
    [self runPrivacyRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_privacy_get_request(arena, key, request);
    } key:key completion:completion];
}

- (void)savePrivacy:(NoshiPrivacyRules *)rules completion:(void (^)(NoshiPrivacyRules *, NSString *))completion {
    noshi_privacy_key key = rules.key;
    NSData *copy = [NSData dataWithBytes:rules.rules length:sizeof(noshi_privacy_rules)];
    [self runPrivacyRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_privacy_set_request(arena, key, copy.bytes, request);
    } key:key completion:completion];
}

- (void)loadBlockedFrom:(int32_t)offset completion:(void (^)(NSArray *, int32_t, NSString *))completion {
    void (^done)(NSArray *, int32_t, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_blocked_request(arena, offset, NOSHI_BLOCKED_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *peers = nil;
        int32_t total = 0;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_blocked_row *rows = calloc(NOSHI_BLOCKED_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_blocked_parse(result->value, rows, NOSHI_BLOCKED_MAX, &count, &total) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                peers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [peers addObject:[[[NoshiBlockedPeer alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: the blocked list was rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *delivered = [peers retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, total, deliveredError); [delivered release]; [done release]; }];
    }];
}

/* a call whose answer is only good or not */
- (void)runPrivacyPlain:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

NSString *const NoshiPeerBlockDidChangeNotification = @"NoshiPeerBlockDidChange";

- (void)setBlocked:(BOOL)blocked kind:(int32_t)kind identifier:(long long)identifier hash:(long long)hash completion:(void (^)(NSString *))completion {
    noshi_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = kind;
    peer.id = identifier;
    peer.access_hash = hash;
    void (^done)(NSString *) = [completion copy];
    long long who = identifier;
    int32_t whoKind = kind;
    [self runPrivacyPlain:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_block_request(arena, &peer, blocked, request);
    } completion:^(NSString *errorName) {
        /* every screen that shows the person learns of it, whoever made the change: the profile, the list of the blocked, the button of a chat */
        if (!errorName) {
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiPeerBlockDidChangeNotification object:nil
                userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:who], @"peer", [NSNumber numberWithInt:whoKind], @"kind", [NSNumber numberWithBool:blocked], @"blocked", nil]];
        }
        if (done) done(errorName);
        [done release];
    }];
}

/* a call whose answer is one number */
- (void)runPrivacyNumber:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build parse:(noshi_status (^)(const noshi_tl_value *answer, int32_t *value))parse
              completion:(void (^)(int32_t, NSString *))completion {
    void (^done)(int32_t, NSString *) = [completion copy];
    noshi_status (^reader)(const noshi_tl_value *, int32_t *) = [parse copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        int32_t value = 0;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status status = reader(result->value, &value);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: a privacy setting was rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(value, delivered); [done release]; }];
        [reader release];
    }];
}

- (void)loadAccountTTL:(void (^)(int32_t, NSString *))completion {
    [self runPrivacyNumber:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_account_ttl_request(arena, request);
    } parse:^noshi_status(const noshi_tl_value *answer, int32_t *value) {
        return noshi_account_ttl_parse(answer, value);
    } completion:completion];
}

- (void)setAccountTTL:(int32_t)days completion:(void (^)(NSString *))completion {
    [self runPrivacyPlain:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_account_ttl_set_request(arena, days, request);
    } completion:completion];
}

- (void)loadHistoryTTL:(void (^)(int32_t, NSString *))completion {
    [self runPrivacyNumber:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_history_ttl_request(arena, request);
    } parse:^noshi_status(const noshi_tl_value *answer, int32_t *value) {
        return noshi_history_ttl_parse(answer, value);
    } completion:completion];
}

- (void)setHistoryTTL:(int32_t)seconds completion:(void (^)(NSString *))completion {
    [self runPrivacyPlain:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_history_ttl_set_request(arena, seconds, request);
    } completion:completion];
}

- (void)clearPaymentsCredentials:(BOOL)credentials info:(BOOL)info completion:(void (^)(NSString *))completion {
    [self runPrivacyPlain:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_clear_payments_request(arena, credentials, info, request);
    } completion:completion];
}

- (void)resetSavedContactsWithCompletion:(void (^)(NSString *))completion {
    [self runPrivacyPlain:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_reset_saved_contacts_request(arena, request);
    } completion:completion];
}

@end
