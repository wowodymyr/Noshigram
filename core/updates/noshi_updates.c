#include "noshi_updates.h"

#include <limits.h>
#include <string.h>

#include "noshi_tl_ids.h"
#include "noshi_reactions.h"

#define UPDATE_MAX 4096u

static void select_gap(noshi_updates *u) {
    u->needs_difference = u->global_gap || u->channel_count;
    u->gap_channel = u->global_gap || !u->channel_count ? 0 : u->channels[0];
}

noshi_status noshi_updates_need(noshi_updates *u, int64_t channel_id) {
    uint32_t i;
    if (!u || channel_id < 0) return NOSHI_E_ARG;
    if (!channel_id) u->global_gap = 1;
    else {
        for (i = 0; i < u->channel_count; ++i) if (u->channels[i] == channel_id) return NOSHI_OK;
        if (u->channel_count == 128) return NOSHI_E_LIMIT;
        u->channels[u->channel_count++] = channel_id;
    }
    select_gap(u);
    return NOSHI_OK;
}

static noshi_status gap(noshi_updates *u, int64_t channel_id) {
    noshi_status status = noshi_updates_need(u, channel_id);
    if (status == NOSHI_OK && channel_id) status = noshi_updates_need(u, 0);
    return status == NOSHI_OK ? NOSHI_E_RETRY : status;
}

static noshi_status cursor_read(noshi_updates *u, int64_t channel, noshi_cursor *c) {
    noshi_status status = noshi_store_cursor_get(u->store, channel, c);
    return status == NOSHI_E_NOTFOUND ? NOSHI_OK : status;
}

static noshi_status cursor_value(const noshi_tl_value *v, noshi_cursor *c) {
    memset(c, 0, sizeof(*c));
    if (noshi_tl_get_i32(v, "pts", &c->pts) != NOSHI_OK ||
        noshi_tl_get_i32(v, "qts", &c->qts) != NOSHI_OK ||
        noshi_tl_get_i32(v, "seq", &c->seq) != NOSHI_OK ||
        noshi_tl_get_i32(v, "date", &c->date) != NOSHI_OK ||
        c->pts < 0 || c->qts < 0 || c->seq < 0 || c->date < 0) return NOSHI_E_MALFORMED;
    return NOSHI_OK;
}

static noshi_status transaction_end(noshi_updates *u, noshi_status status) {
    noshi_status cleanup;
    if (status == NOSHI_OK) {
        status = noshi_store_commit(u->store);
        if (status == NOSHI_OK) return status;
    }
    cleanup = noshi_store_rollback(u->store);
    return cleanup == NOSHI_OK ? status : cleanup;
}

noshi_status noshi_updates_init(noshi_updates *u, noshi_store *store, int64_t account_id) {
    noshi_cursor c;
    noshi_status status;
    if (!u || !store || account_id <= 0) return NOSHI_E_ARG;
    memset(u, 0, sizeof(*u));
    u->store = store;
    u->account = account_id;
    status = noshi_store_cursor_get(store, 0, &c);
    u->needs_difference = 1;
    u->global_gap = 1;
    return status == NOSHI_E_NOTFOUND ? NOSHI_OK : status;
}

/* the highest version the message has, found as the newest record below the next message's numbers */
static noshi_status newest_version(void *ctx, int64_t id, const noshi_tl_value *value) {
    (void)value;
    *(int64_t *)ctx = id;
    return NOSHI_OK;
}

/* the text of a message before an edit stays as a version of it: the stored object goes under the kind of the versions, numbered after the ones that are there */
static noshi_status keep_edit(noshi_updates *u, const noshi_tl_value *m, noshi_peer peer, int32_t id) {
    noshi_arena arena;
    noshi_tl_value *previous = NULL;
    const uint8_t *old_text = NULL, *new_text = NULL;
    size_t old_len = 0, new_len = 0;
    int32_t old_edit = 0, new_edit = 0;
    int64_t base = (int64_t)id * NOSHI_EDIT_VERSIONS, top = 0;
    noshi_status status;
    /* only a message that carries an edit date was edited; the same message from a page of history does not */
    if (!noshi_tl_has(m, "edit_date")) return NOSHI_OK;
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    status = noshi_store_get(u->store, NOSHI_RECORD_MESSAGE, peer, id, &arena, &previous);
    if (status == NOSHI_E_NOTFOUND) {
        noshi_arena_free(&arena);
        return NOSHI_OK;
    }
    if (status == NOSHI_OK) {
        noshi_tl_get_bytes(previous, "message", &old_text, &old_len);
        noshi_tl_get_bytes(m, "message", &new_text, &new_len);
        if (noshi_tl_has(previous, "edit_date")) noshi_tl_get_i32(previous, "edit_date", &old_edit);
        noshi_tl_get_i32(m, "edit_date", &new_edit);
        /* the same words, or an older copy, are not a new version */
        if ((old_len == new_len && (!old_len || memcmp(old_text, new_text, old_len) == 0)) || new_edit < old_edit) {
            noshi_arena_free(&arena);
            return NOSHI_OK;
        }
        status = noshi_store_page(u->store, NOSHI_RECORD_MESSAGE_EDIT, peer, base + NOSHI_EDIT_VERSIONS, 1, newest_version, &top);
    }
    if (status == NOSHI_OK) {
        int64_t version = top > base ? top - base + 1 : 1;
        if (version < NOSHI_EDIT_VERSIONS) status = noshi_store_put(u->store, NOSHI_RECORD_MESSAGE_EDIT, peer, base + version, previous);
    }
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_updates_cache_message(noshi_updates *u, const noshi_tl_value *m) {
    noshi_peer peer;
    int32_t id;
    noshi_status status;
    if (!u || !m) return NOSHI_E_ARG;
    if (noshi_tl_get_i32(m, "id", &id) != NOSHI_OK || id <= 0) return NOSHI_E_MALFORMED;
    status = noshi_peer_from_tl(noshi_tl_get(m, "peer_id"), &peer);
    if (status != NOSHI_OK) return status;
    if (u->keep & NOSHI_KEEP_EDITS) {
        status = keep_edit(u, m, peer, id);
        if (status != NOSHI_OK) return status;
    }
    if (noshi_tl_has(noshi_tl_get(m, "reactions"), "min")) {
        noshi_arena arena;
        noshi_writer encoded;
        noshi_tl_value *previous = NULL, *copy = NULL;
        noshi_arena_init(&arena, 16u * 1024u * 1024u);
        status = noshi_store_get(u->store, NOSHI_RECORD_MESSAGE, peer, id, &arena, &previous);
        if (status == NOSHI_E_NOTFOUND) status = NOSHI_OK;
        noshi_writer_init(&encoded, 1024u * 1024u);
        if (status == NOSHI_OK) status = noshi_tl_encode(m, &encoded, NULL);
        if (status == NOSHI_OK) status = noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY,
            encoded.data, encoded.len, &copy);
        if (status == NOSHI_OK) status = noshi_reactions_merge_min((noshi_tl_value *)noshi_tl_get(copy, "reactions"),
            noshi_tl_get(previous, "reactions"));
        if (status == NOSHI_OK) status = noshi_store_put(u->store, NOSHI_RECORD_MESSAGE, peer, id, copy);
        noshi_writer_free(&encoded);
        noshi_arena_free(&arena);
        return status;
    }
    return noshi_store_put(u->store, NOSHI_RECORD_MESSAGE, peer, id, m);
}

/* whether AyuMoments keeps what is deleted in this chat: a private chat, a group, a channel, or a chat with a bot, each by its own switch */
static int keeps_deleted_in(noshi_updates *u, noshi_peer peer) {
    noshi_arena arena;
    noshi_tl_value *record = NULL;
    uint32_t wanted;
    noshi_peer holder = {0, 0};
    if (!(u->keep & NOSHI_KEEP_DELETED)) return 0;
    if (peer.kind == 2) return (u->keep & NOSHI_KEEP_GROUPS) != 0;
    noshi_arena_init(&arena, 1024u * 1024u);
    if (peer.kind == 1) {
        wanted = NOSHI_KEEP_PRIVATE;
        if (noshi_store_get(u->store, NOSHI_RECORD_USER, holder, peer.id, &arena, &record) == NOSHI_OK && noshi_tl_has(record, "bot")) wanted = NOSHI_KEEP_BOTS;
    } else {
        /* a channel is a broadcast or a supergroup, and the chat record knows which */
        wanted = NOSHI_KEEP_GROUPS;
        if (noshi_store_get(u->store, NOSHI_RECORD_CHAT, peer, peer.id, &arena, &record) == NOSHI_OK && noshi_tl_has(record, "broadcast")) wanted = NOSHI_KEEP_CHANNELS;
    }
    noshi_arena_free(&arena);
    return (u->keep & wanted) != 0;
}

/* a message the server says is gone: it is removed from the chat, or kept under the kind of the deleted ones when
   the person asked for that */
static noshi_status delete_message(noshi_updates *u, const noshi_peer *channel, int32_t id) {
    noshi_peer peer;
    noshi_status status;
    if (channel) peer = *channel;
    else {
        status = noshi_store_find_common_message(u->store, id, &peer);
        if (status == NOSHI_E_NOTFOUND) return NOSHI_OK;
        if (status != NOSHI_OK) return status;
    }
    if (keeps_deleted_in(u, peer)) {
        status = noshi_store_move(u->store, NOSHI_RECORD_MESSAGE, NOSHI_RECORD_DELETED_MESSAGE, peer, id);
        return status == NOSHI_E_NOTFOUND ? NOSHI_OK : status;
    }
    return channel ? noshi_store_delete(u->store, NOSHI_RECORD_MESSAGE, peer, id) : noshi_store_delete_common_message(u->store, id);
}

static noshi_status cache_vector(noshi_updates *u, const noshi_tl_value *v, const char *field,
                                  noshi_record_kind kind) {
    const noshi_tl_value *vec = noshi_tl_get(v, field);
    uint32_t i;
    if (!vec) return NOSHI_OK;
    if (vec->kind != NOSHI_TL_V_VEC || vec->u.vec.count > UPDATE_MAX) return NOSHI_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        const noshi_tl_value *item = vec->u.vec.items[i];
        noshi_status status;
        noshi_peer peer = {0, 0};
        int64_t id;
        if (kind == NOSHI_RECORD_MESSAGE) status = noshi_updates_cache_message(u, item);
        else {
            if (noshi_tl_get_i64(item, "id", &id) != NOSHI_OK || id <= 0) return NOSHI_E_MALFORMED;
            if (kind == NOSHI_RECORD_CHAT) {
                peer.kind = noshi_tl_is(item, NOSHI_TL_ID_channel) || noshi_tl_is(item, NOSHI_TL_ID_channelForbidden) ||
                            noshi_tl_is(item, NOSHI_TL_ID_community) || noshi_tl_is(item, NOSHI_TL_ID_communityForbidden) ? 3 : 2;
                peer.id = id;
            }
            /* a user or channel seen in part (min) has no access hash that works for this account and no photo the account can fetch; it is left out when the store holds the
               whole object, or the photo of everyone who ever showed up in a group as a stub would vanish */
            if ((kind == NOSHI_RECORD_USER || kind == NOSHI_RECORD_CHAT) && noshi_tl_has(item, "min")) {
                noshi_arena arena;
                noshi_tl_value *held = NULL;
                int whole;
                noshi_arena_init(&arena, 1024u * 1024u);
                whole = noshi_store_get(u->store, kind, peer, id, &arena, &held) == NOSHI_OK && held && !noshi_tl_has(held, "min");
                noshi_arena_free(&arena);
                if (whole) continue;
            }
            status = noshi_store_put(u->store, kind, peer, id, item);
        }
        if (status != NOSHI_OK) return status;
    }
    return NOSHI_OK;
}

static noshi_status update_channel(const noshi_tl_value *v, int64_t *out) {
    const noshi_tl_value *m, *peer;
    *out = 0;
    if (noshi_tl_has(v, "channel_id")) {
        if (noshi_tl_get_i64(v, "channel_id", out) != NOSHI_OK || *out <= 0) return NOSHI_E_MALFORMED;
        return NOSHI_OK;
    }
    m = noshi_tl_get(v, "message");
    peer = noshi_tl_get(m, "peer_id");
    if (noshi_tl_is(peer, NOSHI_TL_ID_peerChannel)) {
        if (noshi_tl_get_i64(peer, "channel_id", out) != NOSHI_OK || *out <= 0) return NOSHI_E_MALFORMED;
    }
    return NOSHI_OK;
}

noshi_status noshi_updates_short_to_message(noshi_arena *a, int64_t account, const noshi_tl_value *v, noshi_tl_value **out) {
    noshi_tl_value *m, *peer, *from;
    int64_t peer_id, from_id;
    int32_t id, date;
    uint32_t i;
    int chat;
    static const char *const optional[] = {"out", "mentioned", "media_unread", "silent", "fwd_from",
                                           "via_bot_id", "reply_to", "entities", "ttl_period"};
    noshi_status status;
    if (out) *out = NULL;
    if (!a || !v || !out) return NOSHI_E_ARG;
    chat = noshi_tl_is(v, NOSHI_TL_ID_updateShortChatMessage);
    if (!chat && !noshi_tl_is(v, NOSHI_TL_ID_updateShortMessage)) return NOSHI_E_ARG;
    if (noshi_tl_get_i64(v, chat ? "chat_id" : "user_id", &peer_id) != NOSHI_OK || peer_id <= 0 ||
        noshi_tl_get_i32(v, "id", &id) != NOSHI_OK || id <= 0 ||
        noshi_tl_get_i32(v, "date", &date) != NOSHI_OK) return NOSHI_E_MALFORMED;
    from_id = noshi_tl_has(v, "out") ? account : peer_id;
    if (chat && noshi_tl_get_i64(v, "from_id", &from_id) != NOSHI_OK) return NOSHI_E_MALFORMED;
    m = noshi_tl_new_obj(a, "message");
    peer = noshi_tl_new_obj(a, chat ? "peerChat" : "peerUser");
    from = noshi_tl_new_obj(a, "peerUser");
    status = m && peer && from ? noshi_tl_set_i64(a, peer, chat ? "chat_id" : "user_id", peer_id) : NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_i64(a, from, "user_id", from_id);
    if (status == NOSHI_OK) status = noshi_tl_set(m, "peer_id", peer);
    if (status == NOSHI_OK) status = noshi_tl_set(m, "from_id", from);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(a, m, "id", id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(a, m, "date", date);
    if (status == NOSHI_OK) status = noshi_tl_set(m, "message", (noshi_tl_value *)noshi_tl_get(v, "message"));
    for (i = 0; status == NOSHI_OK && i < sizeof(optional) / sizeof(optional[0]); ++i) {
        const noshi_tl_value *value = noshi_tl_get(v, optional[i]);
        if (value) status = noshi_tl_set(m, optional[i], (noshi_tl_value *)value);
    }
    if (status == NOSHI_OK) *out = m;
    return status;
}

static noshi_status short_message(noshi_updates *u, const noshi_tl_value *v) {
    noshi_arena a;
    noshi_tl_value *m = NULL;
    noshi_status status;
    noshi_arena_init(&a, 65536);
    status = noshi_updates_short_to_message(&a, u->account, v, &m);
    if (status == NOSHI_OK) status = noshi_updates_cache_message(u, m);
    noshi_arena_free(&a);
    return status;
}

/* the voice notes and round videos of these ids were played on another phone or by the other side: they are no longer new */
static noshi_status apply_contents_read(noshi_updates *u, const noshi_tl_value *v, int64_t channel) {
    const noshi_tl_value *vec = noshi_tl_get(v, "messages");
    uint32_t i;
    if (!vec || vec->kind != NOSHI_TL_V_VEC || vec->u.vec.count > UPDATE_MAX) return NOSHI_E_MALFORMED;
    for (i = 0; i < vec->u.vec.count; ++i) {
        const noshi_tl_value *item = vec->u.vec.items[i];
        noshi_peer peer = {3, channel};
        noshi_arena arena;
        noshi_tl_value *message = NULL;
        noshi_status status;
        if (!item || item->kind != NOSHI_TL_V_I32 || item->u.i32 <= 0) return NOSHI_E_MALFORMED;
        if (!channel) {
            status = noshi_store_find_common_message(u->store, item->u.i32, &peer);
            if (status == NOSHI_E_NOTFOUND) continue;
            if (status != NOSHI_OK) return status;
        }
        noshi_arena_init(&arena, 2u * 1024u * 1024u);
        status = noshi_store_get(u->store, NOSHI_RECORD_MESSAGE, peer, item->u.i32, &arena, &message);
        /* a message that is not held needs nothing: it arrives with the flag as the server has it */
        if (status == NOSHI_OK && noshi_tl_has(message, "media_unread")) {
            status = noshi_tl_clear(message, "media_unread");
            if (status == NOSHI_OK) status = noshi_store_put(u->store, NOSHI_RECORD_MESSAGE, peer, item->u.i32, message);
        } else if (status == NOSHI_E_NOTFOUND) {
            status = NOSHI_OK;
        }
        noshi_arena_free(&arena);
        if (status != NOSHI_OK) return status;
    }
    return NOSHI_OK;
}

static noshi_status apply_reactions(noshi_updates *u, const noshi_tl_value *v) {
    noshi_peer peer;
    int32_t id;
    noshi_arena arena;
    noshi_tl_value *message = NULL;
    noshi_tl_value *reactions = (noshi_tl_value *)noshi_tl_get(v, "reactions");
    noshi_reactions parsed;
    noshi_status status;
    if (noshi_peer_from_tl(noshi_tl_get(v, "peer"), &peer) != NOSHI_OK ||
        noshi_tl_get_i32(v, "msg_id", &id) != NOSHI_OK || id <= 0 || !reactions) return NOSHI_E_MALFORMED;
    status = noshi_reactions_read(reactions, &parsed);
    if (status != NOSHI_OK) return status;
    noshi_arena_init(&arena, 8u * 1024u * 1024u);
    status = noshi_store_get(u->store, NOSHI_RECORD_MESSAGE, peer, id, &arena, &message);
    /* an update for unloaded history must not create a message without its text and media */
    if (status == NOSHI_E_NOTFOUND) status = NOSHI_OK;
    else if (status == NOSHI_OK) {
        noshi_writer encoded;
        noshi_writer_init(&encoded, 65536);
        status = noshi_tl_encode(reactions, &encoded, NULL);
        if (status == NOSHI_OK) status = noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY,
            encoded.data, encoded.len, &reactions);
        noshi_writer_free(&encoded);
        if (status == NOSHI_OK) status = noshi_reactions_merge_min(reactions, noshi_tl_get(message, "reactions"));
        if (status == NOSHI_OK) status = noshi_tl_set(message, "reactions", reactions);
        if (status == NOSHI_OK) status = noshi_store_put(u->store, NOSHI_RECORD_MESSAGE, peer, id, message);
    }
    noshi_arena_free(&arena);
    return status;
}

/* the status of a person who came online or left: the stored user is what the chat list and a reopened chat read, and the server sends this update
   instead of the whole user */
static noshi_status apply_user_status(noshi_updates *u, const noshi_tl_value *v) {
    noshi_peer peer = {0, 0};
    int64_t user_id;
    noshi_arena arena;
    noshi_tl_value *user = NULL, *status = (noshi_tl_value *)noshi_tl_get(v, "status");
    noshi_status result;
    if (noshi_tl_get_i64(v, "user_id", &user_id) != NOSHI_OK || user_id <= 0 || !status) return NOSHI_E_MALFORMED;
    noshi_arena_init(&arena, 1024u * 1024u);
    result = noshi_store_get(u->store, NOSHI_RECORD_USER, peer, user_id, &arena, &user);
    /* a user that is not held arrives whole, with its status, when it is needed */
    if (result == NOSHI_E_NOTFOUND) result = NOSHI_OK;
    else if (result == NOSHI_OK) {
        noshi_writer encoded;
        noshi_writer_init(&encoded, 256);
        result = noshi_tl_encode(status, &encoded, NULL);
        if (result == NOSHI_OK) result = noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, encoded.data, encoded.len, &status);
        noshi_writer_free(&encoded);
        if (result == NOSHI_OK) result = noshi_tl_set(user, "status", status);
        if (result == NOSHI_OK) result = noshi_store_put(u->store, NOSHI_RECORD_USER, peer, user_id, user);
    }
    noshi_arena_free(&arena);
    return result;
}

static noshi_status apply_one(noshi_updates *u, const noshi_tl_value *v, int authoritative,
                               int apply_unordered, noshi_cursor *global) {
    int64_t channel = 0;
    int32_t pts = 0, count = 0, qts = 0;
    int has_pts = noshi_tl_has(v, "pts"), has_qts = noshi_tl_has(v, "qts");
    noshi_cursor local;
    noshi_status status;
    uint32_t id = noshi_tl_id(v);
    if (!id) return NOSHI_E_MALFORMED;
    status = update_channel(v, &channel);
    if (status != NOSHI_OK) return status;
    if (id == NOSHI_TL_ID_updateChannelTooLong) {
        if (!authoritative) return gap(u, channel);
        status = noshi_updates_need(u, channel);
        if (status != NOSHI_OK) return status;
        return noshi_store_journal_add(u->store, v);
    }
    if (!authoritative) {
        if (has_pts) {
            if (noshi_tl_get_i32(v, "pts", &pts) != NOSHI_OK || pts < 0) return NOSHI_E_MALFORMED;
            if (noshi_tl_has(v, "pts_count") &&
                (noshi_tl_get_i32(v, "pts_count", &count) != NOSHI_OK || count < 0)) return NOSHI_E_MALFORMED;
            if (channel) {
                status = noshi_store_cursor_get(u->store, channel, &local);
                if (status == NOSHI_E_NOTFOUND) { return gap(u, channel); }
                if (status != NOSHI_OK) return status;
            } else local = *global;
            if ((int64_t)local.pts + count > pts) return NOSHI_OK;
            if ((int64_t)local.pts + count < pts) { return gap(u, channel); }
            local.pts = pts;
            if (channel) {
                status = noshi_store_cursor_put(u->store, channel, &local);
                if (status != NOSHI_OK) return status;
            } else global->pts = pts;
        } else if (has_qts) {
            if (noshi_tl_get_i32(v, "qts", &qts) != NOSHI_OK || qts < 0) return NOSHI_E_MALFORMED;
            if ((int64_t)global->qts + 1 > qts) return NOSHI_OK;
            if ((int64_t)global->qts + 1 < qts) { return gap(u, 0); }
            global->qts = qts;
        } else if (!apply_unordered) return NOSHI_OK;
    }
    if (id == NOSHI_TL_ID_updateNewMessage || id == NOSHI_TL_ID_updateEditMessage ||
        id == NOSHI_TL_ID_updateNewChannelMessage || id == NOSHI_TL_ID_updateEditChannelMessage ||
        id == NOSHI_TL_ID_updateNewScheduledMessage) {
        status = noshi_updates_cache_message(u, noshi_tl_get(v, "message"));
    } else if (id == NOSHI_TL_ID_updateShortMessage || id == NOSHI_TL_ID_updateShortChatMessage) {
        status = short_message(u, v);
    } else if (id == NOSHI_TL_ID_updateMessageReactions) {
        status = apply_reactions(u, v);
    } else if (id == NOSHI_TL_ID_updateReadMessagesContents || id == NOSHI_TL_ID_updateChannelReadMessagesContents) {
        status = apply_contents_read(u, v, channel);
    } else if (id == NOSHI_TL_ID_updateMessageID) {
        int32_t server_id;
        int64_t random_id;
        if (noshi_tl_get_i32(v, "id", &server_id) != NOSHI_OK || server_id <= 0 ||
            noshi_tl_get_i64(v, "random_id", &random_id) != NOSHI_OK) return NOSHI_E_MALFORMED;
        status = noshi_store_outbox_set(u->store, random_id, NOSHI_OUTBOX_SENT, server_id, 0);
        /* another device's random_id is not in this outbox */
        if (status == NOSHI_E_NOTFOUND) status = NOSHI_OK;
    } else if (id == NOSHI_TL_ID_updateDeleteChannelMessages || id == NOSHI_TL_ID_updateDeleteMessages) {
        const noshi_tl_value *vec = noshi_tl_get(v, "messages");
        uint32_t i;
        noshi_peer peer = {3, channel};
        if (!vec || vec->kind != NOSHI_TL_V_VEC || vec->u.vec.count > UPDATE_MAX) return NOSHI_E_MALFORMED;
        for (i = 0; i < vec->u.vec.count; ++i) {
            const noshi_tl_value *item = vec->u.vec.items[i];
            if (!item || item->kind != NOSHI_TL_V_I32 || item->u.i32 <= 0) return NOSHI_E_MALFORMED;
            status = delete_message(u, channel ? &peer : NULL, item->u.i32);
            if (status != NOSHI_OK) return status;
        }
    } else if (id == NOSHI_TL_ID_updateDraftMessage) {
        /* the account keeps the draft and the client event shows it live; a journal entry per edit from another phone would only pile up */
        return NOSHI_OK;
    } else if (id == NOSHI_TL_ID_updateUserTyping || id == NOSHI_TL_ID_updateChatUserTyping ||
               id == NOSHI_TL_ID_updateChannelUserTyping) {
        /* typing expires in seconds and cannot be replayed from the journal */
        return NOSHI_OK;
    } else if (id == NOSHI_TL_ID_updateUserStatus) {
        status = apply_user_status(u, v);
    } else if (id == NOSHI_TL_ID_updateNotifySettings) {
        /* the settings of the account are read through account.getNotifySettings and getNotifyExceptions, which answer with a list of these, and nothing
           consumes them from the journal */
        return NOSHI_OK;
    } else status = NOSHI_OK;
    /* all accepted updates survive a crash until their owning feature consumes the journal */
    if (status == NOSHI_OK) status = noshi_store_journal_add(u->store, v);
    return status;
}

static noshi_status apply_vector(noshi_updates *u, const noshi_tl_value *v, const char *field,
                                   int authoritative, int unordered, noshi_cursor *global) {
    const noshi_tl_value *vec = noshi_tl_get(v, field);
    uint32_t i;
    if (!vec) return NOSHI_OK;
    if (vec->kind != NOSHI_TL_V_VEC || vec->u.vec.count > UPDATE_MAX) return NOSHI_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        noshi_status status = apply_one(u, vec->u.vec.items[i], authoritative, unordered, global);
        if (status != NOSHI_OK) return status;
    }
    return NOSHI_OK;
}

static noshi_status apply(noshi_updates *u, const noshi_tl_value *v, int64_t random_id) {
    noshi_cursor c;
    noshi_status status;
    int32_t seq = 0, start = 0, date = 0;
    int unordered = 1;
    uint32_t id;
    if (!u || !v) return NOSHI_E_ARG;
    id = noshi_tl_id(v);
    if (id == NOSHI_TL_ID_updatesTooLong) { return gap(u, 0); }
    status = noshi_store_cursor_get(u->store, 0, &c);
    if (status == NOSHI_E_NOTFOUND) { return gap(u, 0); }
    if (status != NOSHI_OK) return status;
    if (noshi_tl_has(v, "seq")) {
        if (noshi_tl_get_i32(v, "seq", &seq) != NOSHI_OK || seq < 0) return NOSHI_E_MALFORMED;
        start = seq;
        if (noshi_tl_has(v, "seq_start") && noshi_tl_get_i32(v, "seq_start", &start) != NOSHI_OK) return NOSHI_E_MALFORMED;
        if (start < 0 || start > seq) return NOSHI_E_MALFORMED;
        if (start && (int64_t)c.seq + 1 > start) unordered = 0;
        if (start && (int64_t)c.seq + 1 < start) { return gap(u, 0); }
    }
    if (noshi_tl_has(v, "date") && (noshi_tl_get_i32(v, "date", &date) != NOSHI_OK || date < 0)) return NOSHI_E_MALFORMED;
    status = noshi_store_begin(u->store);
    if (status != NOSHI_OK) return status;
    status = cache_vector(u, v, "users", NOSHI_RECORD_USER);
    if (status == NOSHI_OK) status = cache_vector(u, v, "chats", NOSHI_RECORD_CHAT);
    if (status == NOSHI_OK) {
        if (id == NOSHI_TL_ID_updates || id == NOSHI_TL_ID_updatesCombined)
            status = apply_vector(u, v, "updates", 0, unordered, &c);
        else if (id == NOSHI_TL_ID_updateShort) status = apply_one(u, noshi_tl_get(v, "update"), 0, 1, &c);
        else if (id == NOSHI_TL_ID_updateShortMessage || id == NOSHI_TL_ID_updateShortChatMessage ||
                 id == NOSHI_TL_ID_updateShortSentMessage) status = apply_one(u, v, 0, 1, &c);
        else status = NOSHI_E_UNSUPPORTED;
    }
    if (status == NOSHI_OK && random_id && id == NOSHI_TL_ID_updateShortSentMessage) {
        int32_t server_id;
        status = noshi_tl_get_i32(v, "id", &server_id);
        if (status == NOSHI_OK) status = noshi_store_outbox_set(u->store, random_id, NOSHI_OUTBOX_SENT, server_id, 0);
    }
    if (status == NOSHI_OK) {
        if (unordered && seq) c.seq = seq;
        if (date > c.date) c.date = date;
        status = noshi_store_cursor_put(u->store, 0, &c);
    }
    return transaction_end(u, status);
}

noshi_status noshi_updates_state(noshi_updates *u, const noshi_tl_value *state) {
    noshi_cursor c;
    noshi_status status;
    if (!u || !state) return NOSHI_E_ARG;
    status = cursor_value(state, &c);
    if (status != NOSHI_OK) return status;
    status = noshi_store_begin(u->store);
    if (status != NOSHI_OK) return status;
    status = noshi_store_cursor_put(u->store, 0, &c);
    status = transaction_end(u, status);
    if (status == NOSHI_OK) { u->global_gap = 0; select_gap(u); }
    return status;
}

noshi_status noshi_updates_difference(noshi_updates *u, int64_t channel, const noshi_tl_value *v) {
    noshi_cursor c, next;
    noshi_status status;
    uint32_t id;
    int more = 0, history = 0;
    if (!u || !v || channel < 0) return NOSHI_E_ARG;
    id = noshi_tl_id(v);
    status = cursor_read(u, channel, &c);
    if (status != NOSHI_OK) return status;
    next = c;
    if (!channel) {
        if (id == NOSHI_TL_ID_updates_difference || id == NOSHI_TL_ID_updates_differenceSlice) {
            more = id == NOSHI_TL_ID_updates_differenceSlice;
            status = cursor_value(noshi_tl_get(v, more ? "intermediate_state" : "state"), &next);
        } else if (id == NOSHI_TL_ID_updates_differenceEmpty) {
            if (noshi_tl_get_i32(v, "date", &next.date) != NOSHI_OK ||
                noshi_tl_get_i32(v, "seq", &next.seq) != NOSHI_OK) status = NOSHI_E_MALFORMED;
        } else if (id == NOSHI_TL_ID_updates_differenceTooLong) {
            status = noshi_tl_get_i32(v, "pts", &next.pts);
            history = 1;
            more = 1;
        } else status = NOSHI_E_UNSUPPORTED;
    } else {
        if (id == NOSHI_TL_ID_updates_channelDifferenceTooLong) {
            status = noshi_tl_get_i32(noshi_tl_get(v, "dialog"), "pts", &next.pts);
            history = 1;
        } else if (id == NOSHI_TL_ID_updates_channelDifference || id == NOSHI_TL_ID_updates_channelDifferenceEmpty)
            status = noshi_tl_get_i32(v, "pts", &next.pts);
        else status = NOSHI_E_UNSUPPORTED;
        more = !noshi_tl_has(v, "final");
    }
    if (status != NOSHI_OK) return status;
    /* the date of the cursor is raised by the date of every container of live updates, which can be later than the
       date the server gives for its state */
    if (next.date < c.date) next.date = c.date;
    if (next.pts < c.pts || next.qts < c.qts || next.seq < c.seq) return NOSHI_E_MALFORMED;
    status = noshi_store_begin(u->store);
    if (status != NOSHI_OK) return status;
    status = cache_vector(u, v, "users", NOSHI_RECORD_USER);
    if (status == NOSHI_OK) status = cache_vector(u, v, "chats", NOSHI_RECORD_CHAT);
    if (status == NOSHI_OK) status = cache_vector(u, v, "new_messages", NOSHI_RECORD_MESSAGE);
    if (status == NOSHI_OK) status = cache_vector(u, v, "messages", NOSHI_RECORD_MESSAGE);
    if (status == NOSHI_OK) status = apply_vector(u, v, "other_updates", 1, 1, &c);
    if (status == NOSHI_OK) status = noshi_store_journal_add(u->store, v);
    if (status == NOSHI_OK) status = noshi_store_cursor_put(u->store, channel, &next);
    status = transaction_end(u, status);
    if (status == NOSHI_OK) {
        uint32_t i;
        if (!channel) u->global_gap = more;
        else if (!more) {
            for (i = 0; i < u->channel_count; ++i) if (u->channels[i] == channel) {
                memmove(u->channels + i, u->channels + i + 1, (u->channel_count - i - 1u) * sizeof(u->channels[0]));
                --u->channel_count;
                break;
            }
        }
        u->more_difference = more;
        u->needs_history = history;
        select_gap(u);
    }
    return status;
}

noshi_status noshi_updates_request(noshi_updates *u, int64_t channel,
                                      const noshi_tl_value *input_channel, noshi_arena *arena,
                                      noshi_tl_value **out) {
    noshi_cursor c;
    noshi_tl_value *v, *filter;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!u || !arena || channel < 0) return NOSHI_E_ARG;
    status = noshi_store_cursor_get(u->store, channel, &c);
    if (status != NOSHI_OK && status != NOSHI_E_NOTFOUND) return status;
    if (!channel && status == NOSHI_E_NOTFOUND) {
        v = noshi_tl_new_obj(arena, "updates.getState");
        if (!v) return NOSHI_E_NOMEM;
    } else if (!channel) {
        v = noshi_tl_new_obj(arena, "updates.getDifference");
        status = v ? noshi_tl_set_i32(arena, v, "pts", c.pts) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, v, "qts", c.qts);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, v, "date", c.date);
        if (status != NOSHI_OK) return status;
    } else {
        int64_t id;
        if (noshi_tl_get_i64(input_channel, "channel_id", &id) != NOSHI_OK || id != channel) return NOSHI_E_ARG;
        /* a channel without a cursor must first load its dialog pts, zero would skip its history */
        if (status == NOSHI_E_NOTFOUND) return NOSHI_E_NOTFOUND;
        v = noshi_tl_new_obj(arena, "updates.getChannelDifference");
        filter = noshi_tl_new_obj(arena, "channelMessagesFilterEmpty");
        status = v && filter ? noshi_tl_set(v, "channel", (noshi_tl_value *)input_channel) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = noshi_tl_set(v, "filter", filter);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, v, "pts", c.pts);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, v, "limit", 100);
        if (status != NOSHI_OK) return status;
    }
    *out = v;
    return NOSHI_OK;
}

noshi_status noshi_updates_apply(noshi_updates *u, const noshi_tl_value *v) {
    return apply(u, v, 0);
}

noshi_status noshi_updates_sent(noshi_updates *u, int64_t random_id, const noshi_tl_value *v) {
    if (!random_id) return NOSHI_E_ARG;
    return apply(u, v, random_id);
}

noshi_status noshi_updates_cache(noshi_updates *u, const noshi_tl_value *v) {
    noshi_status status;
    const noshi_tl_value *dialogs;
    uint32_t i;
    if (!u || !v) return NOSHI_E_ARG;
    status = noshi_store_begin(u->store);
    if (status != NOSHI_OK) return status;
    status = cache_vector(u, v, "users", NOSHI_RECORD_USER);
    if (status == NOSHI_OK) status = cache_vector(u, v, "chats", NOSHI_RECORD_CHAT);
    if (status == NOSHI_OK) status = cache_vector(u, v, "messages", NOSHI_RECORD_MESSAGE);
    dialogs = noshi_tl_get(v, "dialogs");
    if (status == NOSHI_OK && dialogs) {
        if (dialogs->kind != NOSHI_TL_V_VEC || dialogs->u.vec.count > UPDATE_MAX) status = NOSHI_E_MALFORMED;
        else for (i = 0; i < dialogs->u.vec.count && status == NOSHI_OK; ++i) {
            const noshi_tl_value *dialog = dialogs->u.vec.items[i];
            noshi_peer peer;
            status = noshi_peer_from_tl(noshi_tl_get(dialog, "peer"), &peer);
            if (status == NOSHI_OK) status = noshi_store_put(u->store, NOSHI_RECORD_DIALOG, peer, peer.id, dialog);
            if (status == NOSHI_OK && peer.kind == 3 && noshi_tl_has(dialog, "pts")) {
                noshi_cursor c;
                int32_t pts;
                status = cursor_read(u, peer.id, &c);
                if (status == NOSHI_OK) status = noshi_tl_get_i32(dialog, "pts", &pts);
                /* a cached dialog must not move the updates cursor past events that have not been applied */
                if (status == NOSHI_OK && c.pts == 0) { c.pts = pts; status = noshi_store_cursor_put(u->store, peer.id, &c); }
            }
        }
    }
    return transaction_end(u, status);
}

static int quiet_update(const noshi_tl_value *item) {
    return noshi_tl_is(item, NOSHI_TL_ID_updateUserStatus) || noshi_tl_is(item, NOSHI_TL_ID_updateUserTyping) ||
           noshi_tl_is(item, NOSHI_TL_ID_updateChatUserTyping) || noshi_tl_is(item, NOSHI_TL_ID_updateChannelUserTyping) ||
           noshi_tl_is(item, NOSHI_TL_ID_updateUserName) || noshi_tl_is(item, NOSHI_TL_ID_updateUserEmojiStatus) ||
           noshi_tl_is(item, NOSHI_TL_ID_updateReadHistoryOutbox) || noshi_tl_is(item, NOSHI_TL_ID_updateReadChannelOutbox) ||
           noshi_tl_is(item, NOSHI_TL_ID_updateReadChannelDiscussionOutbox) || noshi_tl_is(item, NOSHI_TL_ID_updateDraftMessage);
}

int noshi_updates_quiet(const noshi_tl_value *updates) {
    const noshi_tl_value *vec;
    uint32_t i;
    if (!updates) return 0;
    if (noshi_tl_is(updates, NOSHI_TL_ID_updateShort)) return quiet_update(noshi_tl_get(updates, "update"));
    if (!noshi_tl_is(updates, NOSHI_TL_ID_updates) && !noshi_tl_is(updates, NOSHI_TL_ID_updatesCombined)) return 0;
    vec = noshi_tl_get(updates, "updates");
    if (!vec || vec->kind != NOSHI_TL_V_VEC || vec->u.vec.count == 0) return 0;
    for (i = 0; i < vec->u.vec.count; ++i) {
        if (!quiet_update(vec->u.vec.items[i])) return 0;
    }
    return 1;
}

static int list_visible_update(const noshi_tl_value *item) {
    return noshi_tl_is(item, NOSHI_TL_ID_updateReadHistoryOutbox) || noshi_tl_is(item, NOSHI_TL_ID_updateReadChannelOutbox);
}

int noshi_updates_list_visible(const noshi_tl_value *updates) {
    const noshi_tl_value *vec;
    uint32_t i;
    if (!updates) return 0;
    if (noshi_tl_is(updates, NOSHI_TL_ID_updateShort)) return list_visible_update(noshi_tl_get(updates, "update"));
    vec = noshi_tl_get(updates, "updates");
    if (!vec || vec->kind != NOSHI_TL_V_VEC) return 0;
    for (i = 0; i < vec->u.vec.count; ++i) {
        if (list_visible_update(vec->u.vec.items[i])) return 1;
    }
    return 0;
}
