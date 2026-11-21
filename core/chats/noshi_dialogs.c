#include "noshi_dialogs.h"
#include "noshi_notify_prefs.h"

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>

#include "noshi_messages.h"
#include "noshi_people.h"
#include "noshi_store.h"
#include "noshi_tl_ids.h"

/* the nearest photo size to this many pixels on the long side is the picture of a chat list row; the small size of a photo is 90 long */
#define DIALOG_THUMB_TARGET 90

/* a text field copied into a fixed buffer: line breaks become spaces, runs of spaces collapse,
   and the cut never lands inside a multi byte sequence */
static size_t utf16_before(const char *text, size_t bytes) {
    size_t units = 0, i;
    for (i = 0; i < bytes; ++i) {
        uint8_t c = (uint8_t)text[i];
        if ((c & 0xC0u) == 0x80u) continue;
        units += c >= 0xF0u ? 2 : 1;
    }
    return units;
}

/* finds the custom emoji of the message where copy_text left them: it collapses runs of spaces, trims the end and cuts at the field size, so the offsets
   of the server (UTF-16 units of the original) are replayed through the same steps; an emoji that the cut or the trim touched is dropped */
static void read_text_emoji(noshi_dialog_row *row, const noshi_tl_value *message) {
    noshi_entity entities[NOSHI_MESSAGE_ENTITIES_MAX];
    size_t start_byte[NOSHI_MESSAGE_ENTITIES_MAX], end_byte[NOSHI_MESSAGE_ENTITIES_MAX];
    char urls[1];
    uint8_t found = 0;
    const uint8_t *data;
    size_t len, i, k, out = 0, units = 0, text_len = strlen(row->text);
    int space = 1;
    row->emoji_count = 0;
    if (!text_len || noshi_tl_get_bytes(message, "message", &data, &len) != NOSHI_OK) return;
    noshi_entities_read(message, entities, NOSHI_MESSAGE_ENTITIES_MAX, urls, 0, &found);
    for (k = 0; k < found; ++k) start_byte[k] = end_byte[k] = SIZE_MAX;
    for (i = 0; i <= len; ++i) {
        uint8_t c = i < len ? data[i] : 0;
        int lead = i == len || (c & 0xC0u) != 0x80u;
        if (lead) {
            for (k = 0; k < found; ++k) {
                if (entities[k].kind != NOSHI_ENTITY_CUSTOM_EMOJI) continue;
                if (start_byte[k] == SIZE_MAX && units >= (size_t)entities[k].offset) start_byte[k] = out;
                if (end_byte[k] == SIZE_MAX && units >= (size_t)entities[k].offset + (size_t)entities[k].length) end_byte[k] = out;
            }
            if (i == len) break;
            units += c >= 0xF0u ? 2 : 1;
        }
        if (out + 1 >= sizeof(row->text)) break;
        if (c == '\n' || c == '\r' || c == '\t') c = ' ';
        if (c == ' ') {
            if (space) continue;
            space = 1;
        } else {
            space = 0;
        }
        ++out;
    }
    for (k = 0; k < found && row->emoji_count < NOSHI_DIALOG_EMOJI_MAX; ++k) {
        size_t first, last;
        if (entities[k].kind != NOSHI_ENTITY_CUSTOM_EMOJI || start_byte[k] == SIZE_MAX || end_byte[k] == SIZE_MAX || end_byte[k] > text_len) continue;
        first = utf16_before(row->text, start_byte[k]);
        last = utf16_before(row->text, end_byte[k]);
        if (last <= first) continue;
        row->emoji[row->emoji_count].offset = (uint16_t)first;
        row->emoji[row->emoji_count].length = (uint16_t)(last - first);
        row->emoji[row->emoji_count].document = entities[k].document_id;
        ++row->emoji_count;
    }
}

static void copy_text(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len, i, out = 0;
    int space = 1;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK) return;
    for (i = 0; i < len && out + 1 < cap; ++i) {
        uint8_t c = data[i];
        if (c == '\n' || c == '\r' || c == '\t') c = ' ';
        if (c == ' ') {
            if (space) continue;
            space = 1;
        } else {
            space = 0;
        }
        dst[out++] = (char)c;
    }
    /* a sequence that did not fit whole is dropped with its lead byte */
    if (i < len && out > 0 && ((uint8_t)dst[out - 1] & 0x80u)) {
        while (out > 0 && ((uint8_t)dst[out - 1] & 0xC0u) == 0x80u) --out;
        if (out > 0 && ((uint8_t)dst[out - 1] & 0xC0u) == 0xC0u) --out;
    }
    while (out > 0 && dst[out - 1] == ' ') --out;
    dst[out] = 0;
}

static int same_peer(const noshi_tl_value *peer, int32_t kind, int64_t id) {
    noshi_peer p;
    return noshi_peer_from_tl(peer, &p) == NOSHI_OK && p.kind == kind && p.id == id;
}

static int is_message(const noshi_tl_value *m) {
    uint32_t id = noshi_tl_id(m);
    return id == NOSHI_TL_ID_message || id == NOSHI_TL_ID_messageService || id == NOSHI_TL_ID_messageEmpty;
}

static const noshi_tl_value *find_message(const noshi_tl_value *messages, int32_t kind, int64_t peer_id, int32_t id) {
    uint32_t i;
    for (i = 0; i < messages->u.vec.count; ++i) {
        const noshi_tl_value *m = messages->u.vec.items[i];
        int32_t message_id;
        if (!is_message(m) || noshi_tl_get_i32(m, "id", &message_id) != NOSHI_OK || message_id != id) continue;
        if (same_peer(noshi_tl_get(m, "peer_id"), kind, peer_id)) return m;
    }
    return NULL;
}

/* a message of the favorites names the chat it came from in saved_peer_id, not in peer_id */
static const noshi_tl_value *find_saved_message(const noshi_tl_value *messages, int32_t kind, int64_t peer_id, int32_t id) {
    uint32_t i;
    for (i = 0; i < messages->u.vec.count; ++i) {
        const noshi_tl_value *m = messages->u.vec.items[i];
        int32_t message_id;
        if (!is_message(m) || noshi_tl_get_i32(m, "id", &message_id) != NOSHI_OK || message_id != id) continue;
        if (same_peer(noshi_tl_get(m, "saved_peer_id"), kind, peer_id)) return m;
    }
    return NULL;
}

static const noshi_tl_value *find_entity(const noshi_tl_value *list, int64_t id) {
    uint32_t i;
    /* a live update has no users of its own when it is not in a container */
    if (!list || list->kind != NOSHI_TL_V_VEC) return NULL;
    for (i = 0; i < list->u.vec.count; ++i) {
        const noshi_tl_value *e = list->u.vec.items[i];
        int64_t entity_id;
        if (noshi_tl_get_i64(e, "id", &entity_id) == NOSHI_OK && entity_id == id) return e;
    }
    return NULL;
}

static void user_title(char *dst, size_t cap, const noshi_tl_value *user) {
    char first[NOSHI_DIALOG_TITLE_MAX], last[NOSHI_DIALOG_TITLE_MAX];
    size_t a, b;
    copy_text(first, sizeof(first), user, "first_name");
    copy_text(last, sizeof(last), user, "last_name");
    a = strlen(first);
    b = strlen(last);
    if (a + b + 2 > cap) {
        /* a pair too long for the row keeps the first name whole */
        last[0] = 0;
        b = 0;
    }
    if (a && b) {
        memcpy(dst, first, a);
        dst[a] = ' ';
        memcpy(dst + a + 1, last, b + 1);
    } else if (a || b) {
        memcpy(dst, a ? first : last, (a ? a : b) + 1);
    } else {
        copy_text(dst, cap, user, "username");
    }
    dst[cap - 1] = 0;
}

static void read_hash(noshi_dialog_row *row, const noshi_tl_value *entity) {
    int64_t hash;
    /* a min object comes from a mention and carries no hash that works for this account */
    if (!noshi_tl_has(entity, "min") && noshi_tl_get_i64(entity, "access_hash", &hash) == NOSHI_OK) row->peer_hash = hash;
}

/* the community a chat or bot was added to, with what opening it needs when the answer carries the community itself */
static void read_linked_community(noshi_dialog_row *row, const noshi_tl_value *entity, const noshi_tl_value *chats) {
    const noshi_tl_value *community;
    int64_t id;
    if (!entity || noshi_tl_get_i64(entity, "linked_community_id", &id) != NOSHI_OK || id <= 0) return;
    row->linked_community_id = id;
    community = chats ? find_entity(chats, id) : NULL;
    if (!community) return;
    if (!noshi_tl_has(community, "min")) {
        int64_t hash;
        if (noshi_tl_get_i64(community, "access_hash", &hash) == NOSHI_OK) row->linked_community_hash = hash;
    }
    copy_text(row->linked_community_title, sizeof(row->linked_community_title), community, "title");
}

static void fill_user(noshi_dialog_row *row, const noshi_tl_value *users, const noshi_tl_value *chats, int64_t self_id) {
    const noshi_tl_value *user = find_entity(users, row->peer_id);
    row->kind = NOSHI_DIALOG_USER;
    row->saved = row->peer_id == self_id;
    row->contact = user && noshi_tl_has(user, "contact");
    if (!user || noshi_tl_is(user, NOSHI_TL_ID_userEmpty)) {
        row->deleted = 1;
        row->presence = NOSHI_PRESENCE_DELETED;
        return;
    }
    if (noshi_tl_has(user, "self")) row->saved = 1;
    if (noshi_tl_has(user, "bot")) row->kind = NOSHI_DIALOG_BOT;
    if (noshi_tl_has(user, "verified")) row->verified = 1;
    if (noshi_tl_has(user, "premium")) row->premium = 1;
    noshi_emoji_status_read(user, &row->emoji_status, &row->emoji_status_until);
    if (noshi_tl_has(user, "deleted")) row->deleted = 1;
    noshi_presence_read(noshi_tl_get(user, "status"), &row->presence, &row->seen);
    if (row->peer_id == NOSHI_TELEGRAM_SERVICE_USER_ID) { row->presence = NOSHI_PRESENCE_UNKNOWN; row->seen = 0; }
    if (row->deleted) {
        row->presence = NOSHI_PRESENCE_DELETED;
        row->seen = 0;
    }
    noshi_photo_ref_read(user, 1, row->peer_id, &row->photo);
    read_hash(row, user);
    user_title(row->title, sizeof(row->title), user);
    read_linked_community(row, user, chats);
}

/* a group closes its field when everyone is barred from messages or when the account alone is; the creator and admins write through both; the group wide bar
   is read first, as the official clients do, so a member who is also banned is told the whole group is closed */
static void read_send_ban(noshi_dialog_row *row, const noshi_tl_value *chat) {
    const noshi_tl_value *everyone = noshi_tl_get(chat, "default_banned_rights");
    const noshi_tl_value *alone = noshi_tl_get(chat, "banned_rights");
    row->send_ban = NOSHI_SEND_OPEN;
    row->send_ban_until = 0;
    if (noshi_tl_has(chat, "creator") || noshi_tl_get(chat, "admin_rights")) return;
    if (everyone && noshi_tl_has(everyone, "send_messages")) {
        row->send_ban = NOSHI_SEND_BAN_GROUP;
    } else if (alone && noshi_tl_has(alone, "send_messages")) {
        row->send_ban = NOSHI_SEND_BAN_ACCOUNT;
        if (noshi_tl_get_i32(alone, "until_date", &row->send_ban_until) != NOSHI_OK || row->send_ban_until < 0) row->send_ban_until = 0;
    }
}

static void fill_chat(noshi_dialog_row *row, const noshi_tl_value *chats) {
    const noshi_tl_value *chat = find_entity(chats, row->peer_id);
    row->kind = row->peer_kind == 3 ? NOSHI_DIALOG_CHANNEL : NOSHI_DIALOG_GROUP;
    if (!chat) return;
    row->noforwards = noshi_tl_has(chat, "noforwards") ? 1 : 0;
    copy_text(row->title, sizeof(row->title), chat, "title");
    if (noshi_tl_get_i32(chat, "participants_count", &row->participants_count) != NOSHI_OK || row->participants_count < 0) row->participants_count = 0;
    if (row->peer_kind == 3 && noshi_tl_has(chat, "megagroup")) row->kind = NOSHI_DIALOG_GROUP;
    if (row->kind == NOSHI_DIALOG_CHANNEL) {
        const noshi_tl_value *rights = noshi_tl_get(chat, "admin_rights");
        row->can_post = noshi_tl_has(chat, "creator") || (rights && noshi_tl_has(rights, "post_messages")) ? 1 : 0;
        row->admin = noshi_tl_has(chat, "creator") || rights ? 1 : 0;
    }
    if (row->kind == NOSHI_DIALOG_GROUP) read_send_ban(row, chat);
    if (noshi_tl_has(chat, "verified")) row->verified = 1;
    if (row->peer_kind == 3 && noshi_tl_has(chat, "forum")) row->forum = 1;
    if (noshi_tl_is(chat, NOSHI_TL_ID_community)) {
        row->community = 1;
        row->community_collapsed = noshi_tl_has(chat, "collapsed_in_dialogs") ? 1 : 0;
    }
    row->left = noshi_tl_has(chat, "left") ? 1 : 0;
    row->join_to_send = noshi_tl_has(chat, "join_to_send") ? 1 : 0;
    noshi_photo_ref_read(chat, row->peer_kind, row->peer_id, &row->photo);
    if (row->peer_kind == 3) read_hash(row, chat);
    read_linked_community(row, chat, chats);
}

void noshi_dialog_peer_read(noshi_dialog_row *row, const noshi_tl_value *users, const noshi_tl_value *chats, int64_t self_id) {
    if (row->peer_kind == 1) fill_user(row, users, chats, self_id);
    else fill_chat(row, chats);
}

static void fill_message(noshi_dialog_row *row, const noshi_tl_value *m, const noshi_tl_value *users, const noshi_tl_value *chats, int64_t self_id) {
    const noshi_tl_value *from;
    noshi_peer sender;
    noshi_media_info media;
    int32_t date = 0;
    if (!m || noshi_tl_is(m, NOSHI_TL_ID_messageEmpty)) return;
    noshi_tl_get_i32(m, "date", &date);
    row->date = date;
    row->outgoing = noshi_tl_has(m, "out") ? 1 : 0;
    row->forwarded = noshi_tl_get(m, "fwd_from") != NULL;
    from = noshi_tl_get(m, "from_id");
    if (noshi_peer_from_tl(from, &sender) == NOSHI_OK && sender.kind == 1) {
        row->sender_is_self = sender.id == self_id || row->outgoing;
        /* a user chat names nobody; a group names who spoke last unless it was us */
        if (row->kind != NOSHI_DIALOG_USER && row->kind != NOSHI_DIALOG_BOT && !row->sender_is_self) {
            const noshi_tl_value *user = find_entity(users, sender.id);
            if (user) {
                user_title(row->sender, sizeof(row->sender), user);
                row->sender_id = sender.id;
                noshi_photo_ref_read(user, 1, sender.id, &row->sender_photo);
            }
        }
    } else if (noshi_peer_from_tl(from, &sender) == NOSHI_OK && sender.kind != 1 && row->kind != NOSHI_DIALOG_USER && row->kind != NOSHI_DIALOG_BOT) {
        /* a message sent as a channel or as the group itself carries a chat in from_id; its title is the name, even when our own account sent it */
        const noshi_tl_value *source = find_entity(chats, sender.id);
        row->sender_is_self = 0;
        if (source) {
            copy_text(row->sender, sizeof(row->sender), source, "title");
            row->sender_id = sender.id;
            noshi_photo_ref_read(source, sender.kind, sender.id, &row->sender_photo);
        }
    } else {
        row->sender_is_self = row->outgoing;
    }
    if (noshi_tl_is(m, NOSHI_TL_ID_messageService)) {
        int64_t target = 0;
        row->preview = NOSHI_PREVIEW_SERVICE;
        row->emoji_count = 0;
        row->service = noshi_service_summary(noshi_tl_get(m, "action"), row->text, sizeof(row->text), &row->service_value, &target);
        row->service_actor_is_target = target > 0 && noshi_peer_from_tl(from, &sender) == NOSHI_OK && sender.kind == 1 && sender.id == target;
        if (target > 0) {
            const noshi_tl_value *user = find_entity(users, target);
            if (user) user_title(row->service_target, sizeof(row->service_target), user);
        }
        return;
    }
    copy_text(row->text, sizeof(row->text), m, "message");
    read_text_emoji(row, m);
    noshi_media_classify_sized(noshi_tl_get(m, "media"), DIALOG_THUMB_TARGET, &media);
    row->preview = media.kind;
    /* a photo is its own picture; a video, gif or round video shows the thumbnail the server keeps beside it. a spoiler is blurred until it is tapped, and the list has no tap, so it shows no picture */
    if (media.spoiler) memset(&row->thumb, 0, sizeof(row->thumb));
    else if (media.kind == NOSHI_PREVIEW_PHOTO) row->thumb = media.ref;
    else if (media.kind == NOSHI_PREVIEW_VIDEO || media.kind == NOSHI_PREVIEW_GIF || media.kind == NOSHI_PREVIEW_VIDEO_MESSAGE) row->thumb = media.preview;
    /* a caption wins over the sticker emoji or file name that would stand in for it */
    /* a thrown game emoji reads in the list as its emoji */
    if (media.kind == NOSHI_PREVIEW_DICE && !row->text[0]) {
        snprintf(row->text, sizeof(row->text), "%s", media.alt);
        row->preview = NOSHI_PREVIEW_TEXT;
    }
    if (!row->text[0]) {
        const char *detail = media.kind == NOSHI_PREVIEW_STICKER ? media.alt : (media.kind == NOSHI_PREVIEW_FILE ? media.name : "");
        snprintf(row->text, sizeof(row->text), "%s", detail);
    }
    if (row->preview == NOSHI_PREVIEW_TEXT && !row->text[0]) row->preview = NOSHI_PREVIEW_NONE;
}

noshi_status noshi_found_request(noshi_arena *arena, const char *query, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!arena || !query || !out || limit < 1 || limit > NOSHI_DIALOGS_MAX || strlen(query) > 256) return NOSHI_E_ARG;
    *out = NULL;
    request = noshi_tl_new_obj(arena, "contacts.search");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "q", query);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static int row_exists(const noshi_dialog_row *rows, size_t n, int32_t kind, int64_t id) {
    size_t i;
    for (i = 0; i < n; ++i) if (rows[i].peer_kind == kind && rows[i].peer_id == id) return 1;
    return 0;
}

noshi_status noshi_found_parse(const noshi_tl_value *answer, int64_t self_id, noshi_dialog_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *lists[2], *chats, *users;
    static const char *const names[2] = {"my_results", "results"};
    size_t n = 0;
    uint32_t list, i;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_contacts_found)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, names[0], &lists[0]) != NOSHI_OK || noshi_tl_get_vec(answer, names[1], &lists[1]) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK || noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (list = 0; list < 2; ++list) {
        for (i = 0; i < lists[list]->u.vec.count && n < cap; ++i) {
            noshi_dialog_row *row = &rows[n];
            noshi_peer peer;
            const noshi_tl_value *entity;
            if (noshi_peer_from_tl(lists[list]->u.vec.items[i], &peer) != NOSHI_OK || row_exists(rows, n, peer.kind, peer.id)) continue;
            entity = find_entity(peer.kind == 1 ? users : chats, peer.id);
            if (!entity) continue;
            memset(row, 0, sizeof(*row));
            row->peer_kind = peer.kind;
            row->peer_id = peer.id;
            if (peer.kind == 1) fill_user(row, users, chats, self_id);
            else fill_chat(row, chats);
            if (row->deleted) continue;
            {
                char name[NOSHI_DIALOG_TITLE_MAX];
                copy_text(name, sizeof(name), entity, "username");
                if (name[0]) snprintf(row->text, sizeof(row->text), "@%s", name);
            }
            row->preview = row->text[0] ? NOSHI_PREVIEW_TEXT : NOSHI_PREVIEW_NONE;
            ++n;
        }
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_search_parse(const noshi_tl_value *answer, int64_t self_id, noshi_dialog_row *rows, size_t cap,
                                    size_t *count, int32_t *next_rate) {
    const noshi_tl_value *messages, *chats, *users;
    uint32_t i;
    size_t n = 0;
    int32_t rate = 0;
    if (count) *count = 0;
    if (next_rate) *next_rate = 0;
    if (!answer || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_messages) && !noshi_tl_is(answer, NOSHI_TL_ID_messages_messagesSlice) &&
        !noshi_tl_is(answer, NOSHI_TL_ID_messages_channelMessages)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "messages", &messages) != NOSHI_OK || noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK) return NOSHI_E_MALFORMED;
    chats = noshi_tl_get(answer, "chats");
    for (i = 0; i < messages->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *m = messages->u.vec.items[i];
        noshi_dialog_row *row = &rows[n];
        noshi_peer peer;
        int32_t id;
        if (!noshi_tl_is(m, NOSHI_TL_ID_message) || noshi_tl_get_i32(m, "id", &id) != NOSHI_OK || id <= 0 ||
            noshi_peer_from_tl(noshi_tl_get(m, "peer_id"), &peer) != NOSHI_OK) continue;
        memset(row, 0, sizeof(*row));
        row->peer_kind = peer.kind;
        row->peer_id = peer.id;
        if (peer.kind == 1) {
            if (!find_entity(users, peer.id)) continue;
            fill_user(row, users, chats, self_id);
        } else {
            if (!find_entity(chats, peer.id)) continue;
            fill_chat(row, chats);
        }
        row->top_message = id;
        fill_message(row, m, users, chats, self_id);
        ++n;
    }
    if (noshi_tl_get_i32(answer, "next_rate", &rate) == NOSHI_OK && next_rate) *next_rate = rate;
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_dialog_message_row(const noshi_tl_value *message, const noshi_tl_value *users, const noshi_tl_value *chats, int64_t self_id,
                                          noshi_dialog_kind kind, noshi_dialog_row *row) {
    noshi_peer peer;
    int32_t id = 0;
    if (!row) return NOSHI_E_ARG;
    memset(row, 0, sizeof(*row));
    if (!message || (!noshi_tl_is(message, NOSHI_TL_ID_message) && !noshi_tl_is(message, NOSHI_TL_ID_messageService))) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_i32(message, "id", &id) != NOSHI_OK || id <= 0 ||
        noshi_peer_from_tl(noshi_tl_get(message, "peer_id"), &peer) != NOSHI_OK || peer.id <= 0) return NOSHI_E_MALFORMED;
    row->peer_kind = peer.kind;
    row->peer_id = peer.id;
    row->kind = kind;
    row->top_message = id;
    fill_message(row, message, users, chats, self_id);
    return NOSHI_OK;
}

noshi_status noshi_dialogs_parse(const noshi_tl_value *answer, int64_t self_id, int32_t now,
                                     noshi_dialog_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *dialogs, *messages, *chats, *users;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return NOSHI_E_ARG;
    int saved_list = noshi_tl_is(answer, NOSHI_TL_ID_messages_savedDialogs) || noshi_tl_is(answer, NOSHI_TL_ID_messages_savedDialogsSlice);
    if (!saved_list && !noshi_tl_is(answer, NOSHI_TL_ID_messages_dialogs) && !noshi_tl_is(answer, NOSHI_TL_ID_messages_dialogsSlice) &&
        !noshi_tl_is(answer, NOSHI_TL_ID_messages_peerDialogs))
        return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "dialogs", &dialogs) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "messages", &messages) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (i = 0; i < dialogs->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *d = dialogs->u.vec.items[i];
        const noshi_tl_value *settings;
        noshi_dialog_row *row;
        noshi_peer peer;
        int32_t value;
        int folder = noshi_tl_is(d, NOSHI_TL_ID_dialogFolder);
        int community = noshi_tl_is(d, NOSHI_TL_ID_dialogCommunity);
        if (folder) {
            const noshi_tl_value *info = noshi_tl_get(d, "folder");
            int32_t unmuted = 0, muted = 0;
            if (noshi_tl_get_i32(info, "id", &value) != NOSHI_OK || value <= 0) continue;
            row = &rows[n];
            memset(row, 0, sizeof(*row));
            row->folder = 1;
            row->folder_id = value;
            row->kind = NOSHI_DIALOG_GROUP;
            copy_text(row->title, sizeof(row->title), info, "title");
            noshi_tl_get_i32(d, "unread_unmuted_peers_count", &unmuted);
            noshi_tl_get_i32(d, "unread_muted_peers_count", &muted);
            if (unmuted < 0) unmuted = 0;
            if (muted < 0) muted = 0;
            row->unread_count = unmuted > INT32_MAX - muted ? INT32_MAX : unmuted + muted;
            row->muted = unmuted == 0 && muted > 0;
            /* the archive has no chat peer, pin or last-message preview of its own */
            if (n > 0) {
                noshi_dialog_row entry = *row;
                memmove(rows + 1, rows, n * sizeof(*rows));
                rows[0] = entry;
            }
            ++n;
            continue;
        }
        if (community) {
            /* a community entry names no peer, only the id of the community, which the chats of the answer carry like a channel */
            peer.kind = 3;
            if (noshi_tl_get_i64(d, "community_id", &peer.id) != NOSHI_OK || peer.id <= 0 || !find_entity(chats, peer.id)) continue;
        } else if (!noshi_tl_is(d, saved_list ? NOSHI_TL_ID_savedDialog : NOSHI_TL_ID_dialog) || noshi_peer_from_tl(noshi_tl_get(d, "peer"), &peer) != NOSHI_OK) {
            continue;
        }
        row = &rows[n];
        memset(row, 0, sizeof(*row));
        row->peer_kind = peer.kind;
        row->peer_id = peer.id;
        if (peer.kind == 1) fill_user(row, users, chats, self_id);
        else fill_chat(row, chats);
        if (noshi_tl_get_i32(d, "folder_id", &value) == NOSHI_OK) row->folder_id = value;
        row->pinned = noshi_tl_has(d, "pinned") ? 1 : 0;
        row->unread_mark = noshi_tl_has(d, "unread_mark") ? 1 : 0;
        if (noshi_tl_get_i32(d, "unread_count", &value) == NOSHI_OK && value > 0) row->unread_count = value;
        if (noshi_tl_get_i32(d, "unread_mentions_count", &value) == NOSHI_OK && value > 0) row->mentions = value;
        if (noshi_tl_get_i32(d, "unread_reactions_count", &value) == NOSHI_OK && value > 0) row->reactions = value;
        if (noshi_tl_get_i32(d, "read_inbox_max_id", &value) == NOSHI_OK && value > 0) row->read_inbox_max_id = value;
        if (noshi_tl_get_i32(d, "read_outbox_max_id", &value) == NOSHI_OK && value > 0) row->read_outbox_max_id = value;
        settings = noshi_tl_get(d, "notify_settings");
        if (noshi_tl_get_i32(settings, "mute_until", &value) == NOSHI_OK && value > now) row->muted = 1;
        noshi_peer_notify_read(settings, &row->notify);
        if (noshi_tl_get_i32(d, "top_message", &value) == NOSHI_OK && value > 0) {
            row->top_message = value;
            fill_message(row, saved_list ? find_saved_message(messages, peer.kind, peer.id, value) : find_message(messages, peer.kind, peer.id, value), users, chats, self_id);
            if (row->outgoing && noshi_tl_get_i32(d, "read_outbox_max_id", &value) == NOSHI_OK) row->read = value >= row->top_message;
        }
        ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_saved_dialogs_request(noshi_arena *arena, int32_t offset_date, int32_t offset_id, int32_t offset_peer_kind, int64_t offset_peer_id,
                                             int64_t offset_peer_hash, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || offset_date < 0 || offset_id < 0 || limit < 1 || limit > NOSHI_DIALOGS_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getSavedDialogs");
    if (!request) return NOSHI_E_NOMEM;
    if (offset_peer_kind) {
        noshi_peer_ref offset = {offset_peer_kind, offset_peer_id, offset_peer_hash, 0, 0};
        status = noshi_input_peer(arena, &offset, &input);
    } else {
        input = noshi_tl_new_obj(arena, "inputPeerEmpty");
        status = input ? NOSHI_OK : NOSHI_E_NOMEM;
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "offset_peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_date", offset_date);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_topics_request(noshi_arena *arena, int32_t peer_kind, int64_t peer_id, int64_t peer_hash, int32_t offset_date,
                                      int32_t offset_id, int32_t offset_topic, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || peer_kind != 3 || peer_id <= 0 || peer_hash == 0 || offset_date < 0 || offset_id < 0 || offset_topic < 0 ||
        limit < 1 || limit > NOSHI_DIALOGS_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getForumTopics");
    input = noshi_tl_new_obj(arena, "inputPeerChannel");
    if (!request || !input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "channel_id", peer_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", peer_hash);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_date", offset_date);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_topic", offset_topic);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_topics_parse(const noshi_tl_value *answer, const noshi_dialog_row *forum, int64_t self_id, int32_t now,
                                    noshi_dialog_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *topics, *messages, *users, *chats;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !forum || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_forumTopics)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "topics", &topics) != NOSHI_OK || noshi_tl_get_vec(answer, "messages", &messages) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK) return NOSHI_E_MALFORMED;
    chats = noshi_tl_get(answer, "chats");
    for (i = 0; i < topics->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *t = topics->u.vec.items[i], *settings;
        noshi_dialog_row *row = &rows[n];
        int32_t value;
        int64_t icon;
        if (!noshi_tl_is(t, NOSHI_TL_ID_forumTopic) || noshi_tl_get_i32(t, "id", &value) != NOSHI_OK || value <= 0) continue;
        *row = *forum;
        row->forum = 0;
        row->pinned = noshi_tl_has(t, "pinned") ? 1 : 0;
        row->topic_id = value;
        row->topic_closed = noshi_tl_has(t, "closed") ? 1 : 0;
        row->unread_mark = row->outgoing = row->read = row->sender_is_self = row->forwarded = 0;
        row->unread_count = row->mentions = row->reactions = row->date = row->top_message = 0;
        row->read_inbox_max_id = row->read_outbox_max_id = 0;
        row->preview = NOSHI_PREVIEW_NONE;
        row->sender[0] = row->text[0] = 0;
        row->emoji_count = 0;
        row->muted = 0;
        copy_text(row->title, sizeof(row->title), t, "title");
        if (noshi_tl_get_i32(t, "icon_color", &value) == NOSHI_OK) row->topic_icon_color = value & 0xFFFFFF;
        if (noshi_tl_get_i64(t, "icon_emoji_id", &icon) == NOSHI_OK && icon > 0) row->topic_icon_emoji = icon;
        if (noshi_tl_get_i32(t, "unread_count", &value) == NOSHI_OK && value > 0) row->unread_count = value;
        if (noshi_tl_get_i32(t, "unread_mentions_count", &value) == NOSHI_OK && value > 0) row->mentions = value;
        if (noshi_tl_get_i32(t, "unread_reactions_count", &value) == NOSHI_OK && value > 0) row->reactions = value;
        if (noshi_tl_get_i32(t, "read_inbox_max_id", &value) == NOSHI_OK && value > 0) row->read_inbox_max_id = value;
        if (noshi_tl_get_i32(t, "read_outbox_max_id", &value) == NOSHI_OK && value > 0) row->read_outbox_max_id = value;
        settings = noshi_tl_get(t, "notify_settings");
        if (noshi_tl_get_i32(settings, "mute_until", &value) == NOSHI_OK && value > now) row->muted = 1;
        noshi_peer_notify_read(settings, &row->notify);
        if (noshi_tl_get_i32(t, "top_message", &value) == NOSHI_OK && value > 0) {
            row->top_message = value;
            fill_message(row, find_message(messages, forum->peer_kind, forum->peer_id, value), users, chats, self_id);
            if (row->outgoing && row->read_outbox_max_id > 0) row->read = row->read_outbox_max_id >= row->top_message;
        }
        ++n;
    }
    *count = n;
    return NOSHI_OK;
}

static int32_t sum_counts(int32_t total, int32_t add) {
    if (add <= 0) return total;
    return total > INT32_MAX - add ? INT32_MAX : total + add;
}

noshi_status noshi_forum_summarize(const noshi_dialog_row *topics, size_t count, int32_t last_message, noshi_forum_summary *out) {
    const noshi_dialog_row *named = NULL, *second = NULL;
    size_t i;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!topics && count) return NOSHI_E_ARG;
    for (i = 0; i < count; ++i) {
        const noshi_dialog_row *topic = &topics[i];
        if (topic->topic_id <= 0) continue;
        out->unread_count = sum_counts(out->unread_count, topic->unread_count);
        out->mentions = sum_counts(out->mentions, topic->mentions);
        out->reactions = sum_counts(out->reactions, topic->reactions);
        if (topic->top_message <= 0) continue;
        if (!named || (named->top_message != last_message && topic->top_message > named->top_message)) named = topic;
    }
    for (i = 0; named && i < count; ++i) {
        const noshi_dialog_row *topic = &topics[i];
        if (topic == named || topic->topic_id <= 0 || topic->top_message <= 0) continue;
        if (!second || topic->top_message > second->top_message) second = topic;
    }
    if (named) {
        out->topic_id = named->topic_id;
        out->topic_icon_emoji = named->topic_icon_emoji;
        out->topic_icon_color = named->topic_icon_color;
        memcpy(out->topic_title, named->title, sizeof(out->topic_title));
    }
    if (second) {
        out->second_topic_id = second->topic_id;
        out->second_icon_emoji = second->topic_icon_emoji;
        out->second_icon_color = second->topic_icon_color;
        memcpy(out->second_title, second->title, sizeof(out->second_title));
    }
    return NOSHI_OK;
}

noshi_status noshi_community_parse(const noshi_tl_value *answer, noshi_community_info *info, noshi_dialog_row *rows,
                                       size_t cap, size_t *count) {
    const noshi_tl_value *full, *peers, *chats, *users, *self;
    size_t n = 0;
    uint32_t i;
    int64_t id;
    if (count) *count = 0;
    if (!answer || !info || !rows || !count || cap == 0) return NOSHI_E_ARG;
    memset(info, 0, sizeof(*info));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chatFull)) return NOSHI_E_MALFORMED;
    full = noshi_tl_get(answer, "full_chat");
    if (!noshi_tl_is(full, NOSHI_TL_ID_communityFull) || noshi_tl_get_i64(full, "id", &id) != NOSHI_OK ||
        noshi_tl_get_vec(full, "linked_peers", &peers) != NOSHI_OK || noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK) return NOSHI_E_MALFORMED;
    self = find_entity(chats, id);
    if (self) {
        copy_text(info->title, sizeof(info->title), self, "title");
        info->collapsed = noshi_tl_has(self, "collapsed_in_dialogs") ? 1 : 0;
        noshi_photo_ref_read(self, 3, id, &info->photo);
    }
    copy_text(info->about, sizeof(info->about), full, "about");
    for (i = 0; i < peers->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *link = peers->u.vec.items[i], *visible;
        noshi_dialog_row *row = &rows[n];
        noshi_peer peer;
        if (!noshi_tl_is(link, NOSHI_TL_ID_communityPeer) || noshi_peer_from_tl(noshi_tl_get(link, "peer"), &peer) != NOSHI_OK ||
            peer.kind == 1 || row_exists(rows, n, peer.kind, peer.id) || !find_entity(chats, peer.id)) continue;
        visible = noshi_tl_get(link, "visible");
        if (visible && noshi_tl_is(visible, NOSHI_TL_ID_boolFalse)) continue;
        memset(row, 0, sizeof(*row));
        row->peer_kind = peer.kind;
        row->peer_id = peer.id;
        fill_chat(row, chats);
        ++n;
    }
    (void)users;
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_community_previews_apply(const noshi_tl_value *answer, int64_t self_id, int32_t now,
                                               noshi_dialog_row *rows, size_t count) {
    noshi_dialog_row *live;
    noshi_status status;
    size_t found = 0;
    if (!rows || count > NOSHI_DIALOGS_MAX) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_peerDialogs)) return NOSHI_E_MALFORMED;
    live = calloc(NOSHI_DIALOGS_MAX, sizeof(*live));
    if (!live) return NOSHI_E_NOMEM;
    status = noshi_dialogs_parse(answer, self_id, now, live, NOSHI_DIALOGS_MAX, &found);
    for (size_t i = 0; status == NOSHI_OK && i < count; ++i) {
        for (size_t j = 0; j < found; ++j) {
            const noshi_dialog_row *source = &live[j];
            noshi_dialog_row *row = &rows[i];
            if (source->folder || source->peer_kind != row->peer_kind || source->peer_id != row->peer_id) continue;
            row->top_message = source->top_message;
            row->date = source->date;
            row->preview = source->preview;
            row->thumb = source->thumb;
            row->service = source->service;
            row->service_value = source->service_value;
            row->service_actor_is_target = source->service_actor_is_target;
            memcpy(row->service_target, source->service_target, sizeof(row->service_target));
            row->outgoing = source->outgoing;
            row->forwarded = source->forwarded;
            row->read = source->read;
            row->read_inbox_max_id = source->read_inbox_max_id;
            row->read_outbox_max_id = source->read_outbox_max_id;
            row->unread_count = source->unread_count;
            row->mentions = source->mentions;
            row->reactions = source->reactions;
            row->unread_mark = source->unread_mark;
            row->muted = source->muted;
            row->notify = source->notify;
            row->sender_is_self = source->sender_is_self;
            row->sender_id = source->sender_id;
            row->sender_photo = source->sender_photo;
            memcpy(row->sender, source->sender, sizeof(row->sender));
            memcpy(row->text, source->text, sizeof(row->text));
            row->emoji_count = source->emoji_count;
            memcpy(row->emoji, source->emoji, sizeof(row->emoji));
            break;
        }
    }
    free(live);
    return status;
}

noshi_status noshi_community_collapse_request(noshi_arena *arena, int64_t id, int64_t access_hash, int collapsed, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || id <= 0 || access_hash == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "communities.toggleCommunityCollapsedInDialogs");
    input = noshi_tl_new_obj(arena, "inputChannel");
    if (!request || !input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "channel_id", id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", access_hash);
    if (status == NOSHI_OK && collapsed) status = noshi_tl_set_flag(request, "collapsed");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "community", input);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_dialogs_ensure_archive(noshi_dialog_row *rows, size_t cap, size_t *count) {
    if (!rows || !count || *count > cap) return NOSHI_E_ARG;
    for (size_t i = 0; i < *count; ++i) if (rows[i].folder && rows[i].folder_id == 1) return NOSHI_OK;
    if (*count == cap) return NOSHI_E_LIMIT;
    memmove(rows + 1, rows, *count * sizeof(*rows));
    memset(rows, 0, sizeof(*rows));
    rows[0].folder = 1;
    rows[0].folder_id = 1;
    rows[0].kind = NOSHI_DIALOG_GROUP;
    ++*count;
    return NOSHI_OK;
}

noshi_status noshi_archive_summary_parse(const noshi_tl_value *info, const noshi_tl_value *contents,
                                              int64_t self_id, int32_t now, noshi_dialog_row *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    noshi_dialog_row folder;
    size_t folders = 0, count = 0;
    noshi_status status = noshi_dialogs_parse(info, self_id, now, &folder, 1, &folders);
    if (status != NOSHI_OK) return status;
    if (folders && (!folder.folder || folder.folder_id != 1)) return NOSHI_E_MALFORMED;
    noshi_dialog_row *rows = calloc(NOSHI_DIALOGS_MAX, sizeof(*rows));
    if (!rows) return NOSHI_E_NOMEM;
    status = noshi_dialogs_parse(contents, self_id, now, rows, NOSHI_DIALOGS_MAX, &count);
    if (status == NOSHI_OK && !folders && count) status = NOSHI_E_MALFORMED;
    if (status == NOSHI_OK) {
        if (folders) *out = folder;
        else { out->folder = 1; out->folder_id = 1; out->kind = NOSHI_DIALOG_GROUP; }
        /* the counters of the folder entry are the server's own and can disagree with the chats inside, showing one unread chat on the entry while every chat of the
           archive is read. a list that came whole (not a slice) is all there is to count, so the entry counts what the person finds when it opens */
        if (folders && noshi_tl_is(contents, NOSHI_TL_ID_messages_dialogs)) {
            int32_t unmuted = 0, muted = 0;
            for (size_t i = 0; i < count; ++i) {
                const noshi_dialog_row *row = rows + i;
                if (row->folder || row->folder_id != 1 || row->deleted || (!row->unread_count && !row->unread_mark)) continue;
                if (row->muted) ++muted; else ++unmuted;
            }
            out->unread_count = unmuted > INT32_MAX - muted ? INT32_MAX : unmuted + muted;
            out->muted = unmuted == 0 && muted > 0;
        }
        size_t used = 0;
        for (size_t i = 0; i < count; ++i) {
            const noshi_dialog_row *row = rows + i;
            if (row->folder || row->folder_id != 1 || !row->title[0]) continue;
            size_t length = strlen(row->title), room = sizeof(out->text) - used - 1;
            size_t separator = used ? 2 : 0;
            if (room <= separator) break;
            room -= separator;
            size_t take = length < room ? length : room;
            while (take && take < length && ((uint8_t)row->title[take] & 0xC0u) == 0x80u) --take;
            if (!take) break;
            if (separator) { memcpy(out->text + used, ", ", separator); used += separator; }
            memcpy(out->text + used, row->title, take);
            used += take;
            out->text[used] = 0;
            if (take < length) break;
        }
        out->preview = used ? NOSHI_PREVIEW_TEXT : NOSHI_PREVIEW_NONE;
    }
    free(rows);
    return status;
}
