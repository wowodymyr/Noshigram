#include "noshi_call.h"

#include <string.h>

#include "noshi_crypto.h"
#include "noshi_mt_handshake.h"
#include "noshi_random.h"
#include "noshi_tl_ids.h"

#define KEY NOSHI_CALL_KEY_LEN

noshi_status noshi_call_dh_request(noshi_arena *arena, int32_t version, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || version < 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getDhConfig");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, request, "version", version);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "random_length", KEY);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_call_dh_parse(const noshi_tl_value *answer, const noshi_call_dh *known, noshi_call_dh *out, uint8_t random[KEY]) {
    const uint8_t *bytes;
    size_t len;
    int32_t g = 0, version = 0;
    if (!out || !random) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    memset(random, 0, KEY);
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_dhConfigNotModified)) {
        if (!known || known->version <= 0 || known->g <= 0) return NOSHI_E_STATE;
        if (noshi_tl_get_bytes(answer, "random", &bytes, &len) != NOSHI_OK || len != KEY) return NOSHI_E_MALFORMED;
        *out = *known;
        memcpy(random, bytes, KEY);
        return NOSHI_OK;
    }
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_dhConfig)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_i32(answer, "g", &g) != NOSHI_OK || noshi_tl_get_i32(answer, "version", &version) != NOSHI_OK || version <= 0)
        return NOSHI_E_MALFORMED;
    if (noshi_tl_get_bytes(answer, "p", &bytes, &len) != NOSHI_OK || len != KEY) return NOSHI_E_SECURITY;
    /* the prime may come from the cache of an earlier call of the same version, which was checked then */
    if (!(known && known->version == version && known->g == g && memcmp(known->p, bytes, KEY) == 0) &&
        noshi_mt_check_dh_prime(bytes, len, (uint32_t)g) != NOSHI_OK) return NOSHI_E_SECURITY;
    memcpy(out->p, bytes, KEY);
    out->g = g;
    out->version = version;
    if (noshi_tl_get_bytes(answer, "random", &bytes, &len) != NOSHI_OK || len != KEY) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    memcpy(random, bytes, KEY);
    return NOSHI_OK;
}

noshi_status noshi_call_make_secret_from(const noshi_call_dh *dh, const uint8_t seed[KEY], const uint8_t server_random[KEY],
                                            uint8_t secret[KEY], uint8_t pub[KEY]) {
    noshi_bn *p = NULL, *g = NULL, *a = NULL, *value = NULL;
    noshi_status status = NOSHI_E_NOMEM;
    size_t i;
    if (!dh || !seed || !server_random || !secret || !pub || dh->g <= 0) return NOSHI_E_ARG;
    memset(pub, 0, KEY);
    for (i = 0; i < KEY; ++i) secret[i] = (uint8_t)(seed[i] ^ server_random[i]);
    p = noshi_bn_from_bin(dh->p, KEY);
    g = noshi_bn_from_u64((uint64_t)dh->g);
    a = noshi_bn_from_bin(secret, KEY);
    if (p && g && a) value = noshi_bn_mod_exp_secret(g, a, p);
    if (value) status = noshi_bn_to_bin_padded(value, pub, KEY);
    if (status == NOSHI_OK) status = noshi_mt_check_dh_value(dh->p, KEY, pub, KEY) == NOSHI_OK ? NOSHI_OK : NOSHI_E_SECURITY;
    noshi_bn_free(p);
    noshi_bn_free(g);
    noshi_bn_free(a);
    noshi_bn_free(value);
    if (status != NOSHI_OK) {
        memset(secret, 0, KEY);
        memset(pub, 0, KEY);
    }
    return status;
}

noshi_status noshi_call_make_secret(const noshi_call_dh *dh, const uint8_t server_random[KEY], uint8_t secret[KEY], uint8_t pub[KEY]) {
    uint8_t seed[KEY];
    noshi_status status = noshi_random(seed, sizeof(seed));
    if (status != NOSHI_OK) return status;
    status = noshi_call_make_secret_from(dh, seed, server_random, secret, pub);
    memset(seed, 0, sizeof(seed));
    return status;
}

noshi_status noshi_call_make_key(const noshi_call_dh *dh, const uint8_t other_pub[KEY], const uint8_t secret[KEY], uint8_t key[KEY],
                                    int64_t *fingerprint) {
    noshi_bn *p = NULL, *other = NULL, *a = NULL, *value = NULL;
    uint8_t digest[NOSHI_SHA1_LEN];
    noshi_status status = NOSHI_E_NOMEM;
    int i;
    uint64_t id = 0;
    if (!dh || !other_pub || !secret || !key || !fingerprint) return NOSHI_E_ARG;
    memset(key, 0, KEY);
    *fingerprint = 0;
    if (noshi_mt_check_dh_value(dh->p, KEY, other_pub, KEY) != NOSHI_OK) return NOSHI_E_SECURITY;
    p = noshi_bn_from_bin(dh->p, KEY);
    other = noshi_bn_from_bin(other_pub, KEY);
    a = noshi_bn_from_bin(secret, KEY);
    if (p && other && a) value = noshi_bn_mod_exp_secret(other, a, p);
    if (value) status = noshi_bn_to_bin_padded(value, key, KEY);
    noshi_bn_free(p);
    noshi_bn_free(other);
    noshi_bn_free(a);
    noshi_bn_free(value);
    if (status == NOSHI_OK) status = noshi_sha1_one(key, KEY, digest);
    if (status != NOSHI_OK) {
        memset(key, 0, KEY);
        return status;
    }
    for (i = 7; i >= 0; --i) id = (id << 8) | digest[NOSHI_SHA1_LEN - 8 + i];
    *fingerprint = (int64_t)id;
    return NOSHI_OK;
}

noshi_status noshi_call_commit(const uint8_t pub[KEY], uint8_t hash[32]) {
    if (!pub || !hash) return NOSHI_E_ARG;
    return noshi_sha256_one(pub, KEY, hash);
}

noshi_status noshi_call_emoji_indexes(const uint8_t key[KEY], const uint8_t caller_pub[KEY], uint16_t indexes[NOSHI_CALL_EMOJI_SHOWN]) {
    uint8_t joined[2 * KEY], digest[32];
    noshi_status status;
    int i, j;
    if (!key || !caller_pub || !indexes) return NOSHI_E_ARG;
    memcpy(joined, key, KEY);
    memcpy(joined + KEY, caller_pub, KEY);
    status = noshi_sha256_one(joined, sizeof(joined), digest);
    memset(joined, 0, sizeof(joined));
    if (status != NOSHI_OK) return status;
    for (i = 0; i < NOSHI_CALL_EMOJI_SHOWN; ++i) {
        /* eight bytes, big endian, with the top bit dropped so the number stays positive, as every other client reads them */
        uint64_t value = (uint64_t)(digest[8 * i] & 0x7F);
        for (j = 1; j < 8; ++j) value = (value << 8) | digest[8 * i + j];
        indexes[i] = (uint16_t)(value % NOSHI_CALL_EMOJI_COUNT);
    }
    return NOSHI_OK;
}

static noshi_status protocol(noshi_arena *arena, int p2p, noshi_tl_value **out) {
    static const char *const names[] = {NOSHI_CALL_TGCALLS_VERSION, NOSHI_CALL_LIBRARY_VERSION};
    noshi_tl_value *p = noshi_tl_new_obj(arena, "phoneCallProtocol"), *versions = noshi_tl_new_vec(arena, 2);
    noshi_status status = NOSHI_OK;
    uint32_t i;
    if (!p || !versions) return NOSHI_E_NOMEM;
    for (i = 0; i < 2 && status == NOSHI_OK; ++i) {
        noshi_tl_value *version = noshi_tl_new_str(arena, names[i]);
        if (!version) return NOSHI_E_NOMEM;
        status = noshi_tl_vec_set(versions, i, version);
    }
    if (status == NOSHI_OK && p2p) status = noshi_tl_set_flag(p, "udp_p2p");
    if (status == NOSHI_OK) status = noshi_tl_set_flag(p, "udp_reflector");
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, p, "min_layer", NOSHI_CALL_MIN_LAYER);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, p, "max_layer", NOSHI_CALL_MAX_LAYER);
    if (status == NOSHI_OK) status = noshi_tl_set(p, "library_versions", versions);
    if (status == NOSHI_OK) *out = p;
    return status;
}

static noshi_status input_call(noshi_arena *arena, int64_t id, int64_t access_hash, noshi_tl_value **out) {
    noshi_tl_value *input = noshi_tl_new_obj(arena, "inputPhoneCall");
    noshi_status status;
    if (!input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "id", id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", access_hash);
    if (status == NOSHI_OK) *out = input;
    return status;
}

noshi_status noshi_call_request_request(noshi_arena *arena, const noshi_peer_ref *user, int32_t random_id, const uint8_t hash[32], int video, int p2p,
                                           noshi_tl_value **out) {
    noshi_tl_value *request, *input, *proto = NULL;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !user || !hash || user->kind != 1 || user->id <= 0 || user->access_hash == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "phone.requestCall");
    input = noshi_tl_new_obj(arena, "inputUser");
    if (!request || !input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "user_id", user->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", user->access_hash);
    if (status == NOSHI_OK) status = protocol(arena, p2p, &proto);
    if (status == NOSHI_OK && video) status = noshi_tl_set_flag(request, "video");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "user_id", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, request, "g_a_hash", hash, 32);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "protocol", proto);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_call_accept_request(noshi_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t pub[KEY], int p2p, noshi_tl_value **out) {
    noshi_tl_value *request, *peer = NULL, *proto = NULL;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !pub || call_id == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "phone.acceptCall");
    if (!request) return NOSHI_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == NOSHI_OK) status = protocol(arena, p2p, &proto);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", peer);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, request, "g_b", pub, KEY);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "protocol", proto);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_call_confirm_request(noshi_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t pub[KEY], int64_t fingerprint, int p2p,
                                           noshi_tl_value **out) {
    noshi_tl_value *request, *peer = NULL, *proto = NULL;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !pub || call_id == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "phone.confirmCall");
    if (!request) return NOSHI_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == NOSHI_OK) status = protocol(arena, p2p, &proto);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", peer);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, request, "g_a", pub, KEY);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "key_fingerprint", fingerprint);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "protocol", proto);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_call_signaling_request(noshi_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t *data, size_t len, noshi_tl_value **out) {
    noshi_tl_value *request, *peer = NULL;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !data || call_id == 0) return NOSHI_E_ARG;
    if (len == 0 || len > 16384) return NOSHI_E_LIMIT;
    request = noshi_tl_new_obj(arena, "phone.sendSignalingData");
    if (!request) return NOSHI_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", peer);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, request, "data", data, len);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_call_received_request(noshi_arena *arena, int64_t call_id, int64_t access_hash, noshi_tl_value **out) {
    noshi_tl_value *request, *peer = NULL;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || call_id == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "phone.receivedCall");
    if (!request) return NOSHI_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", peer);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_call_discard_request(noshi_arena *arena, int64_t call_id, int64_t access_hash, int32_t duration, noshi_call_reason reason,
                                           int64_t connection_id, noshi_tl_value **out) {
    static const char *const names[] = {NULL, "phoneCallDiscardReasonMissed", "phoneCallDiscardReasonDisconnect", "phoneCallDiscardReasonHangup",
                                        "phoneCallDiscardReasonBusy"};
    noshi_tl_value *request, *peer = NULL, *why;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || call_id == 0 || duration < 0 || reason <= NOSHI_CALL_REASON_NONE || reason > NOSHI_CALL_REASON_BUSY) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "phone.discardCall");
    why = noshi_tl_new_obj(arena, names[reason]);
    if (!request || !why) return NOSHI_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", peer);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "duration", duration);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "reason", why);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "connection_id", connection_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static void copy_string(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK || !data || len >= cap) return;
    memcpy(dst, data, len);
    dst[len] = 0;
}

static void read_protocol(const noshi_tl_value *call, noshi_phone_call *out) {
    const noshi_tl_value *proto = noshi_tl_get(call, "protocol"), *versions;
    if (!noshi_tl_is(proto, NOSHI_TL_ID_phoneCallProtocol)) return;
    noshi_tl_get_i32(proto, "min_layer", &out->min_layer);
    noshi_tl_get_i32(proto, "max_layer", &out->max_layer);
    versions = noshi_tl_get(proto, "library_versions");
    if (versions && versions->kind == NOSHI_TL_V_VEC && versions->u.vec.count > 0) {
        const noshi_tl_value *first = versions->u.vec.items[0];
        if (first && first->kind == NOSHI_TL_V_BYTES && first->u.bytes.len < sizeof(out->version)) {
            memcpy(out->version, first->u.bytes.data, first->u.bytes.len);
            out->version[first->u.bytes.len] = 0;
        }
    }
}

static void read_connections(const noshi_tl_value *call, noshi_phone_call *out) {
    const noshi_tl_value *list = noshi_tl_get(call, "connections");
    uint32_t i;
    for (i = 0; list && list->kind == NOSHI_TL_V_VEC && i < list->u.vec.count && out->connection_count < NOSHI_CALL_CONNECTIONS_MAX; ++i) {
        const noshi_tl_value *item = list->u.vec.items[i];
        noshi_call_connection *c = &out->connections[out->connection_count];
        const uint8_t *tag;
        size_t tag_len;
        int32_t port = 0;
        if (!noshi_tl_is(item, NOSHI_TL_ID_phoneConnection)) continue;
        memset(c, 0, sizeof(*c));
        if (noshi_tl_get_bytes(item, "peer_tag", &tag, &tag_len) != NOSHI_OK || tag_len != NOSHI_CALL_TAG_LEN) continue;
        if (noshi_tl_get_i32(item, "port", &port) != NOSHI_OK || port <= 0 || port > 65535) continue;
        noshi_tl_get_i64(item, "id", &c->id);
        c->tcp = noshi_tl_has(item, "tcp") ? 1 : 0;
        c->port = (uint16_t)port;
        copy_string(c->ip, sizeof(c->ip), item, "ip");
        copy_string(c->ipv6, sizeof(c->ipv6), item, "ipv6");
        if (!c->ip[0] && !c->ipv6[0]) continue;
        memcpy(c->peer_tag, tag, NOSHI_CALL_TAG_LEN);
        ++out->connection_count;
    }
}

static void read_turns(const noshi_tl_value *call, noshi_phone_call *out) {
    const noshi_tl_value *list = noshi_tl_get(call, "connections");
    uint32_t i;
    for (i = 0; list && list->kind == NOSHI_TL_V_VEC && i < list->u.vec.count && out->turn_count < NOSHI_CALL_TURNS_MAX; ++i) {
        const noshi_tl_value *item = list->u.vec.items[i];
        noshi_call_turn *t = &out->turns[out->turn_count];
        int32_t port = 0;
        if (!noshi_tl_is(item, NOSHI_TL_ID_phoneConnectionWebrtc) || !noshi_tl_has(item, "turn")) continue;
        memset(t, 0, sizeof(*t));
        if (noshi_tl_get_i32(item, "port", &port) != NOSHI_OK || port <= 0 || port > 65535) continue;
        noshi_tl_get_i64(item, "id", &t->id);
        t->port = (uint16_t)port;
        copy_string(t->ip, sizeof(t->ip), item, "ip");
        copy_string(t->username, sizeof(t->username), item, "username");
        copy_string(t->password, sizeof(t->password), item, "password");
        if (!t->ip[0] || !t->username[0]) continue;
        ++out->turn_count;
    }
}

static void read_g(const noshi_tl_value *call, const char *field, noshi_phone_call *out) {
    const uint8_t *data;
    size_t len;
    if (noshi_tl_get_bytes(call, field, &data, &len) != NOSHI_OK || len != KEY) return;
    memcpy(out->g, data, KEY);
    out->has_g = 1;
}

noshi_status noshi_phone_call_parse(const noshi_tl_value *call, noshi_phone_call *out) {
    const noshi_tl_value *reason;
    const uint8_t *data;
    size_t len;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!call) return NOSHI_E_MALFORMED;
    if (noshi_tl_is(call, NOSHI_TL_ID_phoneCallEmpty)) {
        out->kind = NOSHI_CALL_EMPTY;
        return noshi_tl_get_i64(call, "id", &out->id) == NOSHI_OK ? NOSHI_OK : NOSHI_E_MALFORMED;
    }
    if (noshi_tl_is(call, NOSHI_TL_ID_phoneCallDiscarded)) {
        out->kind = NOSHI_CALL_DISCARDED;
        if (noshi_tl_get_i64(call, "id", &out->id) != NOSHI_OK) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        noshi_tl_get_i32(call, "duration", &out->duration);
        out->need_rating = noshi_tl_has(call, "need_rating") ? 1 : 0;
        out->video = noshi_tl_has(call, "video") ? 1 : 0;
        reason = noshi_tl_get(call, "reason");
        if (noshi_tl_is(reason, NOSHI_TL_ID_phoneCallDiscardReasonMissed)) out->reason = NOSHI_CALL_REASON_MISSED;
        else if (noshi_tl_is(reason, NOSHI_TL_ID_phoneCallDiscardReasonDisconnect)) out->reason = NOSHI_CALL_REASON_DISCONNECT;
        else if (noshi_tl_is(reason, NOSHI_TL_ID_phoneCallDiscardReasonHangup)) out->reason = NOSHI_CALL_REASON_HANGUP;
        else if (noshi_tl_is(reason, NOSHI_TL_ID_phoneCallDiscardReasonBusy)) out->reason = NOSHI_CALL_REASON_BUSY;
        return NOSHI_OK;
    }
    if (noshi_tl_is(call, NOSHI_TL_ID_phoneCallWaiting)) out->kind = NOSHI_CALL_WAITING;
    else if (noshi_tl_is(call, NOSHI_TL_ID_phoneCallRequested)) out->kind = NOSHI_CALL_REQUESTED;
    else if (noshi_tl_is(call, NOSHI_TL_ID_phoneCallAccepted)) out->kind = NOSHI_CALL_ACCEPTED;
    else if (noshi_tl_is(call, NOSHI_TL_ID_phoneCall)) out->kind = NOSHI_CALL_ACTIVE;
    else return NOSHI_E_MALFORMED;
    if (noshi_tl_get_i64(call, "id", &out->id) != NOSHI_OK || out->id == 0 || noshi_tl_get_i64(call, "access_hash", &out->access_hash) != NOSHI_OK ||
        noshi_tl_get_i32(call, "date", &out->date) != NOSHI_OK || noshi_tl_get_i64(call, "admin_id", &out->admin_id) != NOSHI_OK ||
        noshi_tl_get_i64(call, "participant_id", &out->participant_id) != NOSHI_OK) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    out->video = noshi_tl_has(call, "video") ? 1 : 0;
    out->p2p_allowed = noshi_tl_has(call, "p2p_allowed") ? 1 : 0;
    read_protocol(call, out);
    if (out->kind == NOSHI_CALL_WAITING) {
        noshi_tl_get_i32(call, "receive_date", &out->receive_date);
    } else if (out->kind == NOSHI_CALL_REQUESTED) {
        if (noshi_tl_get_bytes(call, "g_a_hash", &data, &len) != NOSHI_OK || len != 32) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        memcpy(out->g_hash, data, 32);
        out->has_hash = 1;
    } else if (out->kind == NOSHI_CALL_ACCEPTED) {
        read_g(call, "g_b", out);
    } else {
        read_g(call, "g_a_or_b", out);
        noshi_tl_get_i64(call, "key_fingerprint", &out->key_fingerprint);
        read_connections(call, out);
        read_turns(call, out);
    }
    return NOSHI_OK;
}

noshi_status noshi_phone_call_from_answer(const noshi_tl_value *answer, noshi_phone_call *out) {
    if (!out) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_phone_phoneCall)) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    return noshi_phone_call_parse(noshi_tl_get(answer, "phone_call"), out);
}
