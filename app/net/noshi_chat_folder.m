#import "noshi_chat_folder.h"
#import "noshi_message.h"
#include "noshi_tl_ids.h"

static const char *const rule_names[] = {"contacts", "non_contacts", "groups", "broadcasts", "bots", "exclude_muted", "exclude_read", "exclude_archived"};

static NSString *folder_string(const noshi_tl_value *value, const char *name, NSUInteger maximum) {
    const uint8_t *bytes = NULL;
    size_t length = 0;
    if (noshi_tl_get_bytes(value, name, &bytes, &length) != NOSHI_OK || length > maximum)
        return nil;
    return [[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding] autorelease];
}

static NSData *folder_peers(const noshi_tl_value *value, const char *name, BOOL optional) {
    const noshi_tl_value *list = noshi_tl_get(value, name);
    if (!list && optional)
        return [NSData data];
    if (!list || list->kind != NOSHI_TL_V_VEC || list->u.vec.count > NOSHI_FOLDER_PEERS_MAX)
        return nil;
    NSMutableData *data = [NSMutableData data];
    for (uint32_t i = 0; i < list->u.vec.count; ++i) {
        const noshi_tl_value *input = list->u.vec.items[i];
        noshi_peer_ref peer;
        memset(&peer, 0, sizeof(peer));
        const char *id_name = NULL;
        if (noshi_tl_is(input, NOSHI_TL_ID_inputPeerSelf))
            peer.self = 1;
        else if (noshi_tl_is(input, NOSHI_TL_ID_inputPeerUser)) {
            peer.kind = 1;
            id_name = "user_id";
        } else if (noshi_tl_is(input, NOSHI_TL_ID_inputPeerChat)) {
            peer.kind = 2;
            id_name = "chat_id";
        } else if (noshi_tl_is(input, NOSHI_TL_ID_inputPeerChannel)) {
            peer.kind = 3;
            id_name = "channel_id";
        } else
            return nil;
        if (id_name && (noshi_tl_get_i64(input, id_name, &peer.id) != NOSHI_OK || peer.id <= 0))
            return nil;
        if (peer.kind == 1 || peer.kind == 3) {
            if (noshi_tl_get_i64(input, "access_hash", &peer.access_hash) != NOSHI_OK)
                return nil;
        }
        [data appendBytes:&peer length:sizeof(peer)];
    }
    return data;
}

@implementation NoshiChatFolder
@synthesize emoticon = _emoticon;
@synthesize folderId = _folderId, title = _title, flags = _flags, included = _included, excluded = _excluded, pinned = _pinned, shared = _shared,
            original = _original;
@synthesize titleEntities = _titleEntities;

- (void)setTitle:(NSString *)title {
    if (_title == title || [_title isEqualToString:title]) return;
    [_title release];
    _title = [title copy];
    [_titleEntities release];
    _titleEntities = nil;
    _titleEntitiesChanged = YES;
}

- (void)setTitleEntities:(NSArray *)entities {
    NSArray *copy = [entities copy];
    [_titleEntities release];
    _titleEntities = copy;
    _titleEntitiesChanged = YES;
}

- (id)init {
    self = [super init];
    if (self) {
        _included = [[NSData alloc] init];
        _excluded = [[NSData alloc] init];
        _pinned = [[NSData alloc] init];
    }
    return self;
}
- (void)dealloc {
    [_title release];
    [_titleEntities release];
    [_emoticon release];
    [_included release];
    [_excluded release];
    [_pinned release];
    [_original release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone {
    NoshiChatFolder *copy = [[NoshiChatFolder allocWithZone:zone] init];
    copy.folderId = _folderId;
    copy.title = _title;
    copy->_titleEntities = [_titleEntities retain];
    copy->_titleEntitiesChanged = _titleEntitiesChanged;
    copy.flags = _flags;
    copy.included = _included;
    copy.excluded = _excluded;
    copy.pinned = _pinned;
    copy->_shared = _shared;
    copy.emoticon = _emoticon;
    copy->_original = [_original retain];
    return copy;
}

+ (NoshiChatFolder *)folderWithValue:(const noshi_tl_value *)value {
    NoshiChatFolder *folder = [[[self alloc] init] autorelease];
    if (noshi_tl_is(value, NOSHI_TL_ID_dialogFilterDefault)) {
        folder.title = NSLocalizedString(@"folders.all", nil);
        return folder;
    }
    BOOL shared = noshi_tl_is(value, NOSHI_TL_ID_dialogFilterChatlist);
    if (!shared && !noshi_tl_is(value, NOSHI_TL_ID_dialogFilter))
        return nil;
    int32_t identifier = 0;
    if (noshi_tl_get_i32(value, "id", &identifier) != NOSHI_OK || identifier < 2)
        return nil;
    NSString *title = folder_string(noshi_tl_get(value, "title"), "text", 512);
    NSData *included = folder_peers(value, "include_peers", NO);
    NSData *excluded = folder_peers(value, "exclude_peers", shared);
    NSData *pinned = folder_peers(value, "pinned_peers", NO);
    if (!title.length || !included || !excluded || !pinned)
        return nil;
    folder.folderId = identifier;
    folder.title = title;
    noshi_entity entities[NOSHI_MESSAGE_ENTITIES_MAX];
    char urls[1] = {0};
    uint8_t count = 0;
    noshi_entities_read(noshi_tl_get(value, "title"), entities, NOSHI_MESSAGE_ENTITIES_MAX, urls, sizeof(urls), &count);
    NSArray *runs = NoshiTextEntities(title, entities, count, urls);
    NSMutableArray *custom = [NSMutableArray array];
    for (NoshiTextEntity *entity in runs)
        if (entity.style == NoshiTextStyleCustomEmoji && entity.documentId > 0) [custom addObject:entity];
    folder->_titleEntities = [custom copy];
    folder->_titleEntitiesChanged = NO;
    folder.included = included;
    folder.excluded = excluded;
    folder.pinned = pinned;
    folder->_shared = shared;
    folder.emoticon = folder_string(value, "emoticon", 32);
    for (NSUInteger i = 0; i < 8; ++i)
        if (noshi_tl_has(value, rule_names[i]))
            folder->_flags |= 1u << i;
    noshi_writer writer;
    noshi_writer_init(&writer, 256 * 1024);
    if (noshi_tl_encode(value, &writer, NULL) != NOSHI_OK) {
        noshi_writer_free(&writer);
        return nil;
    }
    folder->_original = [[NSData alloc] initWithBytes:writer.data length:writer.len];
    noshi_writer_free(&writer);
    return folder;
}

static noshi_status build_peers(noshi_arena *arena, noshi_tl_value *filter, const char *name, NSData *data) {
    if (data.length % sizeof(noshi_peer_ref) || data.length / sizeof(noshi_peer_ref) > NOSHI_FOLDER_PEERS_MAX)
        return NOSHI_E_ARG;
    uint32_t count = (uint32_t)(data.length / sizeof(noshi_peer_ref));
    noshi_tl_value *list = noshi_tl_new_vec(arena, count);
    if (!list)
        return NOSHI_E_NOMEM;
    const noshi_peer_ref *peers = data.bytes;
    for (uint32_t i = 0; i < count; ++i) {
        noshi_tl_value *peer = NULL;
        noshi_status status = noshi_input_peer(arena, &peers[i], &peer);
        if (status != NOSHI_OK)
            return status;
        status = noshi_tl_vec_set(list, i, peer);
        if (status != NOSHI_OK)
            return status;
    }
    return noshi_tl_set(filter, name, list);
}

- (noshi_status)buildInArena:(noshi_arena *)arena value:(noshi_tl_value **)value {
    *value = NULL;
    if (_folderId < 2 || !_title.length || _title.length > 12 || (_flags & ~255u))
        return NOSHI_E_ARG;
    noshi_tl_value *filter = noshi_tl_new_obj(arena, _shared ? "dialogFilterChatlist" : "dialogFilter");
    noshi_tl_value *title = NULL;
    if (!filter)
        return NOSHI_E_NOMEM;
    noshi_status status = noshi_tl_set_i32(arena, filter, "id", _folderId);
    noshi_tl_value *original = NULL;
    if (_original.length) {
        noshi_tl_limits limits = noshi_tl_default_limits;
        status = noshi_tl_decode_all(arena, &limits, NOSHI_TL_REF_ANY, _original.bytes, _original.length, &original);
        if (status != NOSHI_OK)
            return status;
    }
    /* server fields outside the editor survive an edit of the rules */
    if (original) {
        const char *fields[] = {"emoticon", "color", "title_noanimate", "has_my_invites"};
        for (NSUInteger i = 0; i < 4; ++i) {
            noshi_tl_value *field = (noshi_tl_value *)noshi_tl_get(original, fields[i]);
            if (field && status == NOSHI_OK)
                status = noshi_tl_set(filter, fields[i], field);
        }
        if (!_titleEntitiesChanged && [_title isEqualToString:folder_string(noshi_tl_get(original, "title"), "text", 512)])
            title = (noshi_tl_value *)noshi_tl_get(original, "title");
    }
    if (!title) {
        if (_titleEntities.count > NOSHI_MESSAGE_ENTITIES_MAX) return NOSHI_E_ARG;
        noshi_send_entity entities[NOSHI_MESSAGE_ENTITIES_MAX];
        memset(entities, 0, sizeof(entities));
        NSUInteger index = 0;
        NSArray *ordered = [_titleEntities sortedArrayUsingComparator:^NSComparisonResult(NoshiTextEntity *a, NoshiTextEntity *b) {
            if (a.range.location < b.range.location) return NSOrderedAscending;
            if (a.range.location > b.range.location) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        NSUInteger previousEnd = 0;
        for (NoshiTextEntity *entity in ordered) {
            NSRange range = entity.range;
            if (entity.style != NoshiTextStyleCustomEmoji || entity.documentId <= 0 ||
                !range.length || range.location < previousEnd || range.location > _title.length || range.length > _title.length - range.location)
                return NOSHI_E_ARG;
            previousEnd = NSMaxRange(range);
            entities[index].kind = NOSHI_ENTITY_CUSTOM_EMOJI;
            entities[index].offset = (int32_t)range.location;
            entities[index].length = (int32_t)range.length;
            entities[index].id = entity.documentId;
            ++index;
        }
        if (status == NOSHI_OK)
            status = noshi_folder_title_build(arena, _title.UTF8String, entities, index, &title);
    }
    if (status == NOSHI_OK)
        status = noshi_tl_set(filter, "title", title);
    if (!_shared)
        for (NSUInteger i = 0; i < 8; ++i)
            if ((_flags & (1u << i)) && status == NOSHI_OK)
                status = noshi_tl_set_flag(filter, rule_names[i]);
    if (status == NOSHI_OK)
        status = build_peers(arena, filter, "include_peers", _included);
    if (status == NOSHI_OK && !_shared)
        status = build_peers(arena, filter, "exclude_peers", _excluded);
    if (status == NOSHI_OK)
        status = build_peers(arena, filter, "pinned_peers", _pinned);
    if (status == NOSHI_OK)
        *value = filter;
    return status;
}

- (noshi_folder_rules)rules {
    noshi_folder_rules rules = {_flags,
                                  _included.bytes,
                                  _included.length / sizeof(noshi_peer_ref),
                                  _excluded.bytes,
                                  _excluded.length / sizeof(noshi_peer_ref),
                                  _pinned.bytes,
                                  _pinned.length / sizeof(noshi_peer_ref)};
    return rules;
}
static noshi_dialog_row folder_dialog(NoshiDialog *dialog) {
    noshi_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = dialog.peerKind;
    row.peer_id = dialog.peerId;
    row.kind = dialog.kind;
    row.saved = dialog.saved;
    row.contact = dialog.contact;
    row.folder = dialog.folder;
    row.folder_id = dialog.folderId;
    row.muted = dialog.muted;
    row.unread_count = (int32_t)MIN(INT32_MAX, dialog.unreadCount);
    row.unread_mark = dialog.unread;
    row.mentions = (int32_t)MIN(INT32_MAX, dialog.mentions);
    row.reactions = (int32_t)MIN(INT32_MAX, dialog.reactions);
    row.community = dialog.community;
    return row;
}
- (NoshiDialog *)dialogWithRow:(const noshi_dialog_row *)source {
    noshi_dialog_row row = *source;
    noshi_folder_rules rules = [self rules];
    if (_folderId)
        row.pinned = noshi_folder_pin_index(&rules, &row) != SIZE_MAX;
    return [[[NoshiDialog alloc] initWithRow:&row] autorelease];
}

- (BOOL)containsDialog:(NoshiDialog *)dialog {
    if (!_folderId)
        return dialog.folderId == 0;
    noshi_folder_rules rules = [self rules];
    noshi_dialog_row row = folder_dialog(dialog);
    return noshi_folder_contains(&rules, &row) != 0;
}
- (NSUInteger)pinIndexForDialog:(NoshiDialog *)dialog {
    noshi_folder_rules rules = [self rules];
    noshi_dialog_row row = folder_dialog(dialog);
    return noshi_folder_pin_index(&rules, &row);
}
@end
