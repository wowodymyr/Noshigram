#include "noshi_reactions.h"
#include "noshi_reaction_art.h"

#include <stdio.h>
#include <string.h>

#include "noshi_app_config.h"
#include "noshi_messages.h"
#include "noshi_store.h"
#include "noshi_tl_ids.h"

int64_t noshi_quick_reaction_document(const char *value) {
    uint64_t id = 0;
    if (!value || strncmp(value, "animated_", 9) != 0 || !value[9]) return 0;
    for (const char *p = value + 9; *p; ++p) {
        if (*p < '0' || *p > '9') return 0;
        unsigned digit = (unsigned)(*p - '0');
        if (id > ((uint64_t)INT64_MAX - digit) / 10) return 0;
        id = id * 10 + digit;
    }
    return (int64_t)id;
}

static int valid_utf8(const uint8_t *data, size_t len) {
    size_t i = 0;
    while (i < len) {
        uint32_t cp;
        unsigned n, j;
        uint8_t c = data[i++];
        if (c < 0x80u) { if (c < 0x20u || c == 0x7fu) return 0; continue; }
        if (c >= 0xc2u && c <= 0xdfu) { cp = c & 0x1fu; n = 1; }
        else if (c >= 0xe0u && c <= 0xefu) { cp = c & 0x0fu; n = 2; }
        else if (c >= 0xf0u && c <= 0xf4u) { cp = c & 7u; n = 3; }
        else return 0;
        if (n > len - i) return 0;
        for (j = 0; j < n; ++j) {
            c = data[i++];
            if ((c & 0xc0u) != 0x80u) return 0;
            cp = (cp << 6) | (c & 0x3fu);
        }
        if ((n == 2 && cp < 0x800u) || (n == 3 && cp < 0x10000u) ||
            (cp >= 0xd800u && cp <= 0xdfffu) || cp > 0x10ffffu) return 0;
    }
    return 1;
}

static noshi_status read_emoji(const noshi_tl_value *v, const char *field, noshi_reaction *out) {
    const uint8_t *data;
    size_t len;
    if (noshi_tl_get_bytes(v, field, &data, &len) != NOSHI_OK || !len ||
        len >= sizeof(out->emoji) || !data || !valid_utf8(data, len)) return NOSHI_E_MALFORMED;
    out->kind = NOSHI_REACTION_EMOJI;
    memcpy(out->emoji, data, len);
    out->emoji[len] = 0;
    return NOSHI_OK;
}

static noshi_status read_reaction(const noshi_tl_value *v, noshi_reaction *out) {
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(v, NOSHI_TL_ID_reactionEmoji)) return read_emoji(v, "emoticon", out);
    if (noshi_tl_is(v, NOSHI_TL_ID_reactionCustomEmoji)) {
        if (noshi_tl_get_i64(v, "document_id", &out->document_id) != NOSHI_OK || out->document_id <= 0)
            return NOSHI_E_MALFORMED;
        out->kind = NOSHI_REACTION_CUSTOM;
        return NOSHI_OK;
    }
    if (noshi_tl_is(v, NOSHI_TL_ID_reactionPaid)) {
        out->kind = NOSHI_REACTION_PAID;
        return NOSHI_OK;
    }
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_reaction_parse(const noshi_tl_value *value, noshi_reaction *out) {
    if (!out) return NOSHI_E_ARG;
    return read_reaction(value, out);
}

int noshi_reaction_equal(const noshi_reaction *a, const noshi_reaction *b) {
    if (!a || !b || a->kind != b->kind) return 0;
    if (a->kind == NOSHI_REACTION_EMOJI) return !strncmp(a->emoji, b->emoji, sizeof(a->emoji));
    if (a->kind == NOSHI_REACTION_CUSTOM) return a->document_id == b->document_id;
    return a->kind == NOSHI_REACTION_PAID;
}

noshi_status noshi_reaction_people_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t message_id,
                                               const char *offset, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || message_id <= 0 || (offset && strlen(offset) >= NOSHI_REACTION_OFFSET_MAX)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.getMessageReactionsList");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "id", message_id);
    if (status == NOSHI_OK && offset && offset[0]) status = noshi_tl_set_str(arena, request, "offset", offset);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", NOSHI_REACTION_PEOPLE_PAGE);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_reaction_people_parse(const noshi_tl_value *answer, noshi_reaction_person *rows, size_t capacity,
                                             size_t *count, char *next, size_t next_capacity) {
    const noshi_tl_value *items;
    const uint8_t *offset;
    size_t length;
    if (count) *count = 0;
    if (next && next_capacity) next[0] = 0;
    if (!rows || !capacity || !count || !next || !next_capacity) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_messageReactionsList) || noshi_tl_get_vec(answer, "reactions", &items) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    if (items->u.vec.count > capacity || items->u.vec.count > NOSHI_REACTION_PEOPLE_PAGE) return NOSHI_E_LIMIT;
    if (noshi_tl_has(answer, "next_offset")) {
        if (noshi_tl_get_bytes(answer, "next_offset", &offset, &length) != NOSHI_OK || !offset || !length || length >= next_capacity ||
            length >= NOSHI_REACTION_OFFSET_MAX || memchr(offset, 0, length) || !valid_utf8(offset, length)) return NOSHI_E_MALFORMED;
        memcpy(next, offset, length);
        next[length] = 0;
    }
    for (uint32_t i = 0; i < items->u.vec.count; ++i) {
        const noshi_tl_value *item = items->u.vec.items[i];
        noshi_peer peer;
        noshi_reaction_person row;
        memset(&row, 0, sizeof(row));
        if (!noshi_tl_is(item, NOSHI_TL_ID_messagePeerReaction) || noshi_peer_from_tl(noshi_tl_get(item, "peer_id"), &peer) != NOSHI_OK ||
            peer.id <= 0 || noshi_tl_get_i32(item, "date", &row.date) != NOSHI_OK || row.date < 0 ||
            read_reaction(noshi_tl_get(item, "reaction"), &row.reaction) != NOSHI_OK) {
            next[0] = 0;
            return NOSHI_E_MALFORMED;
        }
        row.peer_kind = peer.kind;
        row.peer_id = peer.id;
        rows[i] = row;
    }
    /* the server names a next offset also on the last page, which showed a button for a page that is not there; a page shorter than the limit asked for is the end */
    if (items->u.vec.count < NOSHI_REACTION_PEOPLE_PAGE) next[0] = 0;
    *count = items->u.vec.count;
    return NOSHI_OK;
}

/* the users in recent_reactions go to the reaction they chose, at most NOSHI_REACTORS_MAX each and once each; an
   entry of a peer that is not a user, one whose reaction the message does not count, and a malformed one are left
   out */
static void read_reactors(const noshi_tl_value *value, noshi_reactions *reactions) {
    const noshi_tl_value *recent;
    uint32_t i;
    uint8_t j, k;
    if (noshi_tl_get_vec(value, "recent_reactions", &recent) != NOSHI_OK) return;
    for (i = 0; i < recent->u.vec.count; ++i) {
        const noshi_tl_value *entry = recent->u.vec.items[i], *peer;
        noshi_reaction chosen;
        int64_t user = 0;
        if (!noshi_tl_is(entry, NOSHI_TL_ID_messagePeerReaction)) continue;
        peer = noshi_tl_get(entry, "peer_id");
        if (!noshi_tl_is(peer, NOSHI_TL_ID_peerUser) || noshi_tl_get_i64(peer, "user_id", &user) != NOSHI_OK || user <= 0) continue;
        if (read_reaction(noshi_tl_get(entry, "reaction"), &chosen) != NOSHI_OK) continue;
        for (j = 0; j < reactions->count; ++j) {
            noshi_reaction *item = &reactions->items[j];
            int seen = 0;
            if (!noshi_reaction_equal(item, &chosen)) continue;
            for (k = 0; k < item->reactor_count; ++k) seen = seen || item->reactors[k] == user;
            if (!seen && item->reactor_count < NOSHI_REACTORS_MAX) item->reactors[item->reactor_count++] = user;
            break;
        }
    }
}

noshi_status noshi_reactions_read(const noshi_tl_value *value, noshi_reactions *out) {
    noshi_reactions parsed;
    const noshi_tl_value *results;
    uint32_t i, j;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!value) return NOSHI_OK;
    memset(&parsed, 0, sizeof(parsed));
    if (!noshi_tl_is(value, NOSHI_TL_ID_messageReactions) ||
        noshi_tl_get_vec(value, "results", &results) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (results->u.vec.count > NOSHI_REACTIONS_MAX) return NOSHI_E_LIMIT;
    parsed.min = noshi_tl_has(value, "min") ? 1 : 0;
    for (i = 0; i < results->u.vec.count; ++i) {
        noshi_reaction *r = &parsed.items[parsed.count];
        const noshi_tl_value *v = results->u.vec.items[i];
        if (!noshi_tl_is(v, NOSHI_TL_ID_reactionCount) ||
            read_reaction(noshi_tl_get(v, "reaction"), r) != NOSHI_OK ||
            noshi_tl_get_i32(v, "count", &r->count) != NOSHI_OK || r->count <= 0) return NOSHI_E_MALFORMED;
        r->chosen = noshi_tl_has(v, "chosen_order") ? 1 : 0;
        if (r->chosen && (noshi_tl_get_i32(v, "chosen_order", &r->chosen_order) != NOSHI_OK || r->chosen_order < 0))
            return NOSHI_E_MALFORMED;
        for (j = 0; j < parsed.count; ++j)
            if (noshi_reaction_equal(r, &parsed.items[j])) return NOSHI_E_MALFORMED;
        ++parsed.count;
    }
    read_reactors(value, &parsed);
    *out = parsed;
    return NOSHI_OK;
}

noshi_faces noshi_reaction_faces(const noshi_reactions *all, size_t index, int private_chat) {
    const noshi_reaction *r;
    int64_t total = 0;
    size_t i;
    if (!all || index >= all->count) return NOSHI_FACES_NONE;
    r = &all->items[index];
    if (r->kind == NOSHI_REACTION_PAID) return NOSHI_FACES_NONE;
    if (private_chat) {
        if (r->count == 2) return NOSHI_FACES_SELF_AND_OTHER;
        if (r->count == 1) return r->chosen ? NOSHI_FACES_SELF : NOSHI_FACES_OTHER;
        return NOSHI_FACES_NONE;
    }
    for (i = 0; i < all->count; ++i) total += all->items[i].count;
    if (r->count <= NOSHI_REACTORS_MAX && total <= NOSHI_REACTORS_MAX && r->reactor_count == r->count) return NOSHI_FACES_REACTORS;
    return NOSHI_FACES_NONE;
}

noshi_status noshi_reaction_catalog_read(const noshi_tl_value *answer, noshi_reaction *items,
                                             size_t cap, size_t *count, int premium) {
    const noshi_tl_value *vec;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!items || !count || !cap) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_availableReactions) ||
        noshi_tl_get_vec(answer, "reactions", &vec) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (vec->u.vec.count > NOSHI_REACTION_CATALOG_MAX) return NOSHI_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        noshi_reaction r;
        const noshi_tl_value *v = vec->u.vec.items[i];
        memset(&r, 0, sizeof(r));
        if (!noshi_tl_is(v, NOSHI_TL_ID_availableReaction)) return NOSHI_E_MALFORMED;
        if (noshi_tl_has(v, "inactive") || (!premium && noshi_tl_has(v, "premium"))) continue;
        if (read_emoji(v, "reaction", &r) != NOSHI_OK) return NOSHI_E_MALFORMED;
        if (n == cap) return NOSHI_E_LIMIT;
        items[n++] = r;
    }
    *count = n;
    return NOSHI_OK;
}

static noshi_status read_art_document(const noshi_tl_value *row, const char *field, const char *emoji, int required, noshi_custom_emoji *out) {
    noshi_status status = noshi_document_picture_read(noshi_tl_get(row, field), emoji, out);
    if (status == NOSHI_E_NOTFOUND && !required) return NOSHI_OK;
    return status == NOSHI_OK ? NOSHI_OK : NOSHI_E_MALFORMED;
}

noshi_status noshi_reaction_art_read(const noshi_tl_value *answer, noshi_reaction_art *items, size_t cap, size_t *count) {
    const noshi_tl_value *vec;
    uint32_t i;
    if (count) *count = 0;
    if (!items || !count || !cap) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_availableReactions) ||
        noshi_tl_get_vec(answer, "reactions", &vec) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (vec->u.vec.count > cap) return NOSHI_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        noshi_reaction_art *art = &items[i];
        noshi_reaction r;
        const noshi_tl_value *v = vec->u.vec.items[i];
        memset(art, 0, sizeof(*art));
        memset(&r, 0, sizeof(r));
        if (!noshi_tl_is(v, NOSHI_TL_ID_availableReaction) || read_emoji(v, "reaction", &r) != NOSHI_OK) return NOSHI_E_MALFORMED;
        snprintf(art->emoji, sizeof(art->emoji), "%s", r.emoji);
        if (read_art_document(v, "static_icon", art->emoji, 1, &art->icon) != NOSHI_OK ||
            read_art_document(v, "appear_animation", art->emoji, 1, &art->appear) != NOSHI_OK ||
            read_art_document(v, "select_animation", art->emoji, 1, &art->select) != NOSHI_OK ||
            read_art_document(v, "activate_animation", art->emoji, 1, &art->activate) != NOSHI_OK ||
            read_art_document(v, "effect_animation", art->emoji, 1, &art->effect) != NOSHI_OK ||
            read_art_document(v, "around_animation", art->emoji, 0, &art->around) != NOSHI_OK) return NOSHI_E_MALFORMED;
    }
    *count = vec->u.vec.count;
    return NOSHI_OK;
}

noshi_status noshi_reaction_policy_read(const noshi_tl_value *answer, noshi_reactions *allowed, int *all) {
    const noshi_tl_value *full, *policy, *vec;
    uint32_t i;
    if (!allowed || !all) return NOSHI_E_ARG;
    memset(allowed, 0, sizeof(*allowed));
    *all = 0;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chatFull)) return NOSHI_E_MALFORMED;
    full = noshi_tl_get(answer, "full_chat");
    if (!noshi_tl_is(full, NOSHI_TL_ID_chatFull) && !noshi_tl_is(full, NOSHI_TL_ID_channelFull))
        return NOSHI_E_MALFORMED;
    policy = noshi_tl_get(full, "available_reactions");
    if (!policy || noshi_tl_is(policy, NOSHI_TL_ID_chatReactionsNone)) return NOSHI_OK;
    if (noshi_tl_is(policy, NOSHI_TL_ID_chatReactionsAll)) { *all = 1; return NOSHI_OK; }
    if (!noshi_tl_is(policy, NOSHI_TL_ID_chatReactionsSome) ||
        noshi_tl_get_vec(policy, "reactions", &vec) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (vec->u.vec.count > NOSHI_REACTIONS_MAX) return NOSHI_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        noshi_status status = read_reaction(vec->u.vec.items[i], &allowed->items[i]);
        if (status != NOSHI_OK) { memset(allowed, 0, sizeof(*allowed)); return status; }
        ++allowed->count;
    }
    return NOSHI_OK;
}

int noshi_reaction_policy_custom(const noshi_tl_value *answer) {
    const noshi_tl_value *full, *policy;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chatFull)) return 0;
    full = noshi_tl_get(answer, "full_chat");
    if (!noshi_tl_is(full, NOSHI_TL_ID_chatFull) && !noshi_tl_is(full, NOSHI_TL_ID_channelFull)) return 0;
    policy = noshi_tl_get(full, "available_reactions");
    return noshi_tl_is(policy, NOSHI_TL_ID_chatReactionsAll) && noshi_tl_has(policy, "allow_custom");
}

noshi_status noshi_reaction_list_request(noshi_arena *arena, int recent, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || limit < 1 || limit > 100) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, recent ? "messages.getRecentReactions" : "messages.getTopReactions");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_reaction_list_read(const noshi_tl_value *answer, noshi_reaction *items, size_t cap, size_t *count) {
    const noshi_tl_value *vec;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!items || !count || !cap) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_reactionsNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_reactions) || noshi_tl_get_vec(answer, "reactions", &vec) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    for (i = 0; i < vec->u.vec.count && n < cap; ++i) {
        noshi_reaction r;
        if (read_reaction(vec->u.vec.items[i], &r) != NOSHI_OK || r.kind != NOSHI_REACTION_CUSTOM) continue;
        items[n++] = r;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_reaction_build(noshi_arena *arena, const noshi_reaction *r, noshi_tl_value **out) {
    size_t len;
    *out = NULL;
    if (r->kind == NOSHI_REACTION_EMOJI) {
        const char *end = memchr(r->emoji, 0, sizeof(r->emoji));
        if (!end) return NOSHI_E_ARG;
        len = (size_t)(end - r->emoji);
        if (!len || !valid_utf8((const uint8_t *)r->emoji, len)) return NOSHI_E_ARG;
        *out = noshi_tl_new_obj(arena, "reactionEmoji");
        return *out ? noshi_tl_set_str(arena, *out, "emoticon", r->emoji) : NOSHI_E_NOMEM;
    }
    if (r->kind == NOSHI_REACTION_CUSTOM && r->document_id > 0) {
        *out = noshi_tl_new_obj(arena, "reactionCustomEmoji");
        return *out ? noshi_tl_set_i64(arena, *out, "document_id", r->document_id) : NOSHI_E_NOMEM;
    }
    return NOSHI_E_ARG;
}

noshi_status noshi_paid_reaction_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, int32_t count, int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *input, *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || id <= 0 || count < 1 || count > NOSHI_PAID_REACTION_MAX || random_id == 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.sendPaidReaction");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "count", count);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_send_reactions_request(noshi_arena *arena, const noshi_peer_ref *peer,
                                              int32_t id, const noshi_reaction *items, size_t count,
                                              noshi_tl_value **out) {
    noshi_tl_value *input, *request, *vec;
    noshi_status status;
    size_t i, j;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || id <= 0 || count > NOSHI_REACTIONS_MAX || (count && !items)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.sendReaction");
    vec = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!request || !vec) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", id);
    for (i = 0; status == NOSHI_OK && i < count; ++i) {
        noshi_tl_value *r;
        for (j = 0; j < i; ++j) if (noshi_reaction_equal(&items[i], &items[j])) return NOSHI_E_ARG;
        status = noshi_reaction_build(arena, &items[i], &r);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(vec, (uint32_t)i, r);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "reaction", vec);
    if (status == NOSHI_OK && count) status = noshi_tl_set_flag(request, "add_to_recent");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_get_reactions_request(noshi_arena *arena, const noshi_peer_ref *peer,
                                             const int32_t *ids, size_t count, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    size_t i;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !ids || !count || count > NOSHI_MESSAGES_MAX) return NOSHI_E_ARG;
    for (i = 0; i < count; ++i) if (ids[i] <= 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.getMessagesReactions");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32_vec(arena, request, "id", ids, (uint32_t)count);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_reaction_update_read(const noshi_tl_value *updates, int32_t peer_kind, int64_t peer_id,
                                            int32_t message_id, noshi_reactions *out) {
    const noshi_tl_value *vec = NULL, *one = NULL;
    uint32_t count, i;
    noshi_status found = NOSHI_E_NOTFOUND;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!updates || peer_kind < 1 || peer_kind > 3 || peer_id <= 0 || message_id <= 0) return NOSHI_E_ARG;
    if (noshi_tl_is(updates, NOSHI_TL_ID_updateShort)) {
        one = noshi_tl_get(updates, "update");
        if (!one) return NOSHI_E_MALFORMED;
        count = 1;
    } else if (noshi_tl_is(updates, NOSHI_TL_ID_updates) || noshi_tl_is(updates, NOSHI_TL_ID_updatesCombined)) {
        if (noshi_tl_get_vec(updates, "updates", &vec) != NOSHI_OK) return NOSHI_E_MALFORMED;
        count = vec->u.vec.count;
        if (count > 4096) return NOSHI_E_LIMIT;
    } else if (noshi_tl_is(updates, NOSHI_TL_ID_updatesTooLong)) return NOSHI_E_RETRY;
    else return NOSHI_E_MALFORMED;
    for (i = 0; i < count; ++i) {
        const noshi_tl_value *update = one ? one : vec->u.vec.items[i];
        noshi_peer peer;
        noshi_reactions parsed;
        int32_t id;
        noshi_status status;
        if (!noshi_tl_is(update, NOSHI_TL_ID_updateMessageReactions)) continue;
        if (noshi_peer_from_tl(noshi_tl_get(update, "peer"), &peer) != NOSHI_OK ||
            noshi_tl_get_i32(update, "msg_id", &id) != NOSHI_OK || id <= 0) return NOSHI_E_MALFORMED;
        if (peer.kind != peer_kind || peer.id != peer_id || id != message_id) continue;
        if (!noshi_tl_get(update, "reactions")) return NOSHI_E_MALFORMED;
        status = noshi_reactions_read(noshi_tl_get(update, "reactions"), &parsed);
        if (status != NOSHI_OK) { memset(out, 0, sizeof(*out)); return status; }
        *out = parsed;
        found = NOSHI_OK;
    }
    return found;
}

noshi_status noshi_reactions_merge_min(noshi_tl_value *incoming, const noshi_tl_value *previous) {
    noshi_reactions next, old;
    const noshi_tl_value *results, *old_results;
    uint32_t i, j;
    noshi_status status = noshi_reactions_read(incoming, &next);
    if (status != NOSHI_OK || !incoming || !next.min) return status;
    status = noshi_reactions_read(previous, &old);
    if (status != NOSHI_OK) return status;
    results = noshi_tl_get(incoming, "results");
    old_results = noshi_tl_get(previous, "results");
    for (i = 0; i < next.count; ++i) {
        for (j = 0; j < old.count; ++j) {
            if (old.items[j].chosen && noshi_reaction_equal(&next.items[i], &old.items[j])) {
                status = noshi_tl_set(results->u.vec.items[i], "chosen_order",
                    (noshi_tl_value *)noshi_tl_get(old_results->u.vec.items[j], "chosen_order"));
                if (status != NOSHI_OK) return status;
                break;
            }
        }
    }
    return NOSHI_OK;
}

static noshi_status read_limit(const noshi_tl_value *config, const char *key, int32_t fallback, int32_t *out) {
    int32_t value;
    noshi_status status = noshi_app_config_i32(config, key, &value);
    if (status == NOSHI_E_NOTFOUND) { *out = fallback; return NOSHI_OK; }
    if (status != NOSHI_OK) return status;
    if (value < 1 || value > NOSHI_REACTIONS_MAX) return NOSHI_E_MALFORMED;
    *out = value;
    return NOSHI_OK;
}

noshi_status noshi_reaction_limits_read(const noshi_tl_value *config, int32_t *standard, int32_t *premium) {
    int32_t a, b;
    noshi_status status;
    if (!standard || !premium) return NOSHI_E_ARG;
    *standard = 1;
    *premium = 3;
    status = read_limit(config, "reactions_user_max_default", 1, &a);
    if (status == NOSHI_OK) status = read_limit(config, "reactions_user_max_premium", 3, &b);
    if (status != NOSHI_OK) return status;
    *standard = a;
    *premium = b;
    return NOSHI_OK;
}

size_t noshi_reaction_choices_after_pick(const noshi_reaction *chosen, size_t count, const noshi_reaction *pick, size_t limit,
                                           noshi_reaction *out, size_t capacity) {
    size_t n = 0, skip, i;
    if (!pick || !out || !limit || limit > capacity || (count && !chosen)) return 0;
    for (i = 0; i < count; ++i) {
        if (chosen[i].kind == NOSHI_REACTION_PAID || noshi_reaction_equal(&chosen[i], pick)) continue;
        if (n == capacity) return 0;
        out[n++] = chosen[i];
    }
    /* the list is sent in order of choosing, oldest first, so the server keeps the order and the oldest go when there is no room for pick */
    for (i = 1; i < n; ++i) {
        noshi_reaction t = out[i];
        size_t j = i;
        for (; j > 0 && out[j - 1].chosen_order > t.chosen_order; --j) out[j] = out[j - 1];
        out[j] = t;
    }
    skip = n + 1 > limit ? n + 1 - limit : 0;
    if (skip) memmove(out, out + skip, (n - skip) * sizeof(*out));
    n -= skip;
    out[n++] = *pick;
    return n;
}
