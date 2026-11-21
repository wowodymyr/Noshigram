#include "noshi_secret.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "noshi_crypto.h"
#include "noshi_mt_handshake.h"
#include "noshi_random.h"
#include "noshi_tl_ids.h"

#define REKEY_REQUESTED 1
#define REKEY_ACCEPTED 2
#define REKEY_COMMIT_READY 3
#define REKEY_SWITCHED 4

noshi_status noshi_secret_dh_begin(noshi_secret_dh *dh, const uint8_t prime[256], uint32_t generator,
                                      const uint8_t *server_random, size_t random_len) {
    noshi_bn *p = NULL, *g = NULL, *a = NULL, *ga = NULL;
    noshi_status status;
    size_t i;
    if (!dh) return NOSHI_E_ARG;
    memset(dh, 0, sizeof(*dh));
    if (!prime || (random_len && (!server_random || random_len != 256))) return NOSHI_E_ARG;
    status = noshi_mt_check_dh_prime(prime, 256, generator);
    if (status != NOSHI_OK) return status;
    memcpy(dh->prime, prime, 256);
    dh->generator = generator;
    status = noshi_random(dh->exponent, 256);
    if (status != NOSHI_OK) goto done;
    for (i = 0; i < random_len; ++i) dh->exponent[i] ^= server_random[i];
    p = noshi_bn_from_bin(prime, 256);
    g = noshi_bn_from_u64(generator);
    a = noshi_bn_from_bin(dh->exponent, 256);
    if (!p || !g || !a) { status = NOSHI_E_NOMEM; goto done; }
    if (noshi_bn_is_zero(a)) { status = NOSHI_E_SECURITY; goto done; }
    ga = noshi_bn_mod_exp_secret(g, a, p);
    if (!ga) { status = NOSHI_E_CRYPTO; goto done; }
    status = noshi_bn_to_bin_padded(ga, dh->public_value, 256);
    if (status == NOSHI_OK) status = noshi_mt_check_dh_value(prime, 256, dh->public_value, 256);
done:
    noshi_bn_free(p);
    noshi_bn_free(g);
    noshi_bn_free(a);
    noshi_bn_free(ga);
    if (status != NOSHI_OK) noshi_wipe(dh, sizeof(*dh));
    return status;
}

noshi_status noshi_secret_dh_finish(const noshi_secret_dh *dh, const uint8_t *peer_public, size_t len,
                                       noshi_mt_auth_key *out) {
    noshi_bn *p = NULL, *a = NULL, *ga = NULL, *key = NULL;
    uint8_t bytes[256];
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!dh || !peer_public || !len || len > 256) return NOSHI_E_ARG;
    status = noshi_mt_check_dh_value(dh->prime, 256, peer_public, len);
    if (status != NOSHI_OK) return status;
    p = noshi_bn_from_bin(dh->prime, 256);
    a = noshi_bn_from_bin(dh->exponent, 256);
    ga = noshi_bn_from_bin(peer_public, len);
    if (!p || !a || !ga) { status = NOSHI_E_NOMEM; goto done; }
    if (noshi_bn_is_zero(a)) { status = NOSHI_E_STATE; goto done; }
    key = noshi_bn_mod_exp_secret(ga, a, p);
    if (!key) { status = NOSHI_E_CRYPTO; goto done; }
    status = noshi_bn_to_bin_padded(key, bytes, 256);
    if (status == NOSHI_OK) status = noshi_mt_auth_key_set(out, bytes);
done:
    noshi_bn_free(p);
    noshi_bn_free(a);
    noshi_bn_free(ga);
    noshi_bn_free(key);
    noshi_wipe(bytes, sizeof(bytes));
    return status;
}

noshi_status noshi_secret_init(noshi_secret_state *s, int initiator, const noshi_secret_dh *dh,
                                  const noshi_mt_auth_key *key, uint64_t time_seconds) {
    uint8_t hash1[20], hash2[32];
    noshi_status status;
    if (!s) return NOSHI_E_ARG;
    memset(s, 0, sizeof(*s));
    if (!dh || !key || !key->id || (initiator != 0 && initiator != 1)) return NOSHI_E_ARG;
    status = noshi_sha1_one(key->key, 256, hash1);
    if (status == NOSHI_OK) status = noshi_sha256_one(key->key, 256, hash2);
    if (status != NOSHI_OK) return status;
    s->key = *key;
    s->dh = *dh;
    noshi_wipe(s->dh.exponent, 256);
    s->initiator = initiator;
    s->remote_layer = 46;
    s->mt2_first_in = INT32_MAX;
    s->key_created = time_seconds;
    memcpy(s->visualization, hash1, 16);
    memcpy(s->visualization + 16, hash2, 20);
    return NOSHI_OK;
}

void noshi_secret_free(noshi_secret_state *s) {
    if (s) noshi_wipe(s, sizeof(*s));
}

static noshi_status old_schedule(const noshi_mt_auth_key *k, const uint8_t msg_key[16], uint8_t key[32], uint8_t iv[32]) {
    noshi_slice parts[3];
    uint8_t a[20], b[20], c[20], d[20];
    noshi_status status;
    /* layer 46 peers need the mtproto 1.0 schedule until they advertise layer 73 */
    parts[0].data = msg_key; parts[0].len = 16;
    parts[1].data = k->key; parts[1].len = 32;
    status = noshi_sha1(parts, 2, a);
    parts[0].data = k->key + 32; parts[0].len = 16;
    parts[1].data = msg_key; parts[1].len = 16;
    parts[2].data = k->key + 48; parts[2].len = 16;
    if (status == NOSHI_OK) status = noshi_sha1(parts, 3, b);
    parts[0].data = k->key + 64; parts[0].len = 32;
    if (status == NOSHI_OK) status = noshi_sha1(parts, 2, c);
    parts[0].data = msg_key; parts[0].len = 16;
    parts[1].data = k->key + 96; parts[1].len = 32;
    if (status == NOSHI_OK) status = noshi_sha1(parts, 2, d);
    if (status == NOSHI_OK) {
        memcpy(key, a, 8); memcpy(key + 8, b + 8, 12); memcpy(key + 20, c + 4, 12);
        memcpy(iv, a + 8, 12); memcpy(iv + 12, b, 8); memcpy(iv + 20, c + 16, 4); memcpy(iv + 24, d, 8);
    }
    noshi_wipe(a, sizeof(a)); noshi_wipe(b, sizeof(b)); noshi_wipe(c, sizeof(c)); noshi_wipe(d, sizeof(d));
    return status;
}

static noshi_status seal_bytes(const noshi_secret_state *s, const uint8_t *body, size_t len, noshi_writer *out) {
    noshi_writer plain;
    uint8_t msg_key[16], key[32], iv[32], h[20], random;
    unsigned x = s->initiator ? 0u : 8u;
    int modern = s->remote_layer >= 73;
    size_t padding, total, mark = out->len;
    noshi_status status;
    noshi_writer_init(&plain, NOSHI_SECRET_MESSAGE_MAX + 1024u);
    status = noshi_random(&random, 1);
    if (status != NOSHI_OK) goto done;
    padding = modern ? 12u + ((16u - (4u + len + 12u) % 16u) % 16u) + (random % 4u) * 16u :
                       (16u - (4u + len) % 16u) % 16u;
    status = noshi_wr_u32le(&plain, (uint32_t)len);
    if (status == NOSHI_OK) status = noshi_wr_bytes(&plain, body, len);
    if (status == NOSHI_OK) status = noshi_wr_zero(&plain, padding);
    if (status == NOSHI_OK) status = noshi_random(plain.data + 4 + len, padding);
    total = plain.len;
    if (status != NOSHI_OK) goto done;
    if (modern) {
        status = noshi_mt_message_key(&s->key, x, plain.data, total, msg_key);
        if (status == NOSHI_OK) status = noshi_mt_key_schedule(&s->key, x, msg_key, key, iv);
    } else {
        status = noshi_sha1_one(plain.data, 4 + len, h);
        memcpy(msg_key, h + 4, 16);
        if (status == NOSHI_OK) status = old_schedule(&s->key, msg_key, key, iv);
    }
    if (status == NOSHI_OK) status = noshi_wr_reserve(out, 24 + total);
    if (status == NOSHI_OK) status = noshi_aes_ige(key, iv, 1, plain.data, out->data + mark + 24, total);
    if (status == NOSHI_OK) {
        noshi_put_u64le(out->data + mark, s->key.id);
        memcpy(out->data + mark + 8, msg_key, 16);
        out->len += 24 + total;
    }
done:
    noshi_wipe(key, sizeof(key)); noshi_wipe(iv, sizeof(iv)); noshi_wipe(h, sizeof(h));
    if (plain.data) noshi_wipe(plain.data, plain.cap);
    noshi_writer_free(&plain);
    return status;
}

noshi_status noshi_secret_seal(const noshi_secret_state *s, const noshi_tl_value *message,
                                  noshi_writer *out, noshi_secret_state *next) {
    noshi_arena arena;
    noshi_tl_value *layer;
    noshi_writer body;
    uint8_t random[15];
    noshi_status status;
    int64_t random_id;
    size_t mark;
    if (!s || !message || !out || !next || next == s) return NOSHI_E_ARG;
    *next = *s;
    if (s->discarded || s->in_count < 0 || s->out_count < 0 || s->out_count >= INT32_MAX / 2 ||
        s->remote_layer < 46 || !s->key.id) return NOSHI_E_STATE;
    if (noshi_tl_get_i64(message, "random_id", &random_id) != NOSHI_OK || !random_id) return NOSHI_E_ARG;
    noshi_arena_init(&arena, 65536);
    noshi_writer_init(&body, NOSHI_SECRET_MESSAGE_MAX);
    mark = out->len;
    layer = noshi_tl_new_obj(&arena, "decryptedMessageLayer");
    status = noshi_random(random, sizeof(random));
    if (status == NOSHI_OK) status = layer ? noshi_tl_set_bytes(&arena, layer, "random_bytes", random, sizeof(random)) : NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_i32(&arena, layer, "layer", s->remote_layer < NOSHI_SECRET_LAYER ? s->remote_layer : NOSHI_SECRET_LAYER);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(&arena, layer, "in_seq_no", s->in_count * 2 + (s->initiator ? 0 : 1));
    if (status == NOSHI_OK) status = noshi_tl_set_i32(&arena, layer, "out_seq_no", s->out_count * 2 + (s->initiator ? 1 : 0));
    if (status == NOSHI_OK) status = noshi_tl_set(layer, "message", (noshi_tl_value *)message);
    if (status == NOSHI_OK) status = noshi_tl_encode(layer, &body, NULL);
    if (status == NOSHI_OK) status = seal_bytes(s, body.data, body.len, out);
    if (status == NOSHI_OK) {
        ++next->out_count;
        ++next->key_uses;
        const noshi_tl_value *action = noshi_tl_get(message, "action");
        if (noshi_tl_is(action, NOSHI_TL_ID_decryptedMessageActionCommitKey) && s->rekey_state == REKEY_COMMIT_READY) {
            next->previous = s->key;
            next->key = s->future;
            memset(&next->future, 0, sizeof(next->future));
            next->rekey_state = REKEY_SWITCHED;
            next->key_uses = 0;
        }
    } else out->len = mark;
    if (body.data) noshi_wipe(body.data, body.cap);
    noshi_writer_free(&body);
    noshi_arena_free(&arena);
    return status;
}

static noshi_status decrypt_bytes(const noshi_mt_auth_key *auth, unsigned x, int modern,
                                    const uint8_t *packet, size_t len, noshi_writer *plain, size_t *body_len) {
    uint8_t key[32], iv[32], actual[16], h[20];
    size_t total = len - 24, padding;
    uint32_t n;
    noshi_status status;
    status = modern ? noshi_mt_key_schedule(auth, x, packet + 8, key, iv) : old_schedule(auth, packet + 8, key, iv);
    if (status == NOSHI_OK) status = noshi_wr_reserve(plain, total);
    if (status == NOSHI_OK) status = noshi_aes_ige(key, iv, 0, packet + 24, plain->data, total);
    noshi_wipe(key, sizeof(key)); noshi_wipe(iv, sizeof(iv));
    if (status != NOSHI_OK) return status;
    plain->len = total;
    n = noshi_get_u32le(plain->data);
    if (n < 4 || n % 4 || n > total - 4) return NOSHI_E_SECURITY;
    padding = total - n - 4;
    if (padding > (modern ? 1024u : 15u) || (modern && padding < 12)) return NOSHI_E_SECURITY;
    if (modern) status = noshi_mt_message_key(auth, x, plain->data, total, actual);
    else {
        status = noshi_sha1_one(plain->data, 4u + n, h);
        memcpy(actual, h + 4, 16);
    }
    if (status == NOSHI_OK && !noshi_ct_equal(actual, packet + 8, 16)) status = NOSHI_E_SECURITY;
    noshi_wipe(h, sizeof(h));
    if (status == NOSHI_OK) *body_len = n;
    return status;
}

noshi_status noshi_secret_open(const noshi_secret_state *s, const uint8_t *packet, size_t len,
                                  noshi_arena *arena, noshi_tl_value **message, noshi_secret_state *next) {
    noshi_writer plain;
    noshi_tl_value *layer = NULL;
    const noshi_mt_auth_key *auth;
    const uint8_t *random;
    size_t n = 0, random_len;
    int modern = 1;
    int32_t in_seq, out_seq, peer_layer, raw_in, raw_out;
    unsigned x;
    uint64_t fingerprint;
    noshi_status status;
    if (!message) return NOSHI_E_ARG;
    *message = NULL;
    if (!s || !packet || !arena || !next || next == s) return NOSHI_E_ARG;
    *next = *s;
    if (s->discarded) return NOSHI_E_STATE;
    if (len < 40 || len > NOSHI_SECRET_MESSAGE_MAX + 1048u || (len - 24) % 16) return NOSHI_E_MALFORMED;
    fingerprint = noshi_get_u64le(packet);
    if (fingerprint == s->key.id) auth = &s->key;
    else if (fingerprint && fingerprint == s->previous.id) auth = &s->previous;
    else if (fingerprint && fingerprint == s->future.id && s->rekey_state == REKEY_ACCEPTED) auth = &s->future;
    else return NOSHI_E_SECURITY;
    x = s->initiator ? 8u : 0u;
    noshi_writer_init(&plain, NOSHI_SECRET_MESSAGE_MAX + 1024u);
    status = decrypt_bytes(auth, x, 1, packet, len, &plain, &n);
    if (status == NOSHI_E_SECURITY && s->mt2_first_in == INT32_MAX) {
        modern = 0;
        status = decrypt_bytes(auth, 0, 0, packet, len, &plain, &n);
    }
    if (status == NOSHI_OK) status = noshi_tl_decode_all(arena, NULL, NOSHI_TL_REF_ANY, plain.data + 4, n, &layer);
    if (status != NOSHI_OK) goto done;
    if (!noshi_tl_is(layer, NOSHI_TL_ID_decryptedMessageLayer) ||
        noshi_tl_get_i32(layer, "in_seq_no", &in_seq) != NOSHI_OK ||
        noshi_tl_get_i32(layer, "out_seq_no", &out_seq) != NOSHI_OK ||
        noshi_tl_get_i32(layer, "layer", &peer_layer) != NOSHI_OK ||
        noshi_tl_get_bytes(layer, "random_bytes", &random, &random_len) != NOSHI_OK || random_len < 15 ||
        in_seq < 0 || out_seq < 0 || (in_seq & 1) != s->initiator || (out_seq & 1) == s->initiator || peer_layer < 46) {
        status = NOSHI_E_SECURITY; goto done;
    }
    if (peer_layer > NOSHI_SECRET_LAYER) { status = NOSHI_E_UNSUPPORTED; goto done; }
    raw_in = in_seq / 2; raw_out = out_seq / 2;
    if (!modern && raw_out >= s->mt2_first_in) { status = NOSHI_E_SECURITY; goto done; }
    if (raw_out < s->in_count) { status = NOSHI_E_NOTFOUND; goto done; }
    if (raw_in < s->remote_ack || raw_in > s->out_count) { status = NOSHI_E_SECURITY; goto done; }
    if (raw_out > s->in_count) { status = NOSHI_E_RETRY; goto done; }
    *message = (noshi_tl_value *)noshi_tl_get(layer, "message");
    if (!*message) { status = NOSHI_E_MALFORMED; goto done; }
    if (s->in_count >= INT32_MAX / 2) { status = NOSHI_E_LIMIT; goto done; }
    ++next->in_count;
    next->remote_ack = raw_in;
    if (peer_layer > next->remote_layer) next->remote_layer = peer_layer;
    if ((modern || peer_layer >= 73) && raw_out < next->mt2_first_in) next->mt2_first_in = raw_out;
    ++next->key_uses;
    if (auth == &s->future) {
        next->previous = s->key;
        next->key = s->future;
        noshi_wipe(&next->future, sizeof(next->future));
        next->rekey_state = REKEY_SWITCHED;
        next->key_uses = 0;
    }
    if (fingerprint == next->key.id && next->rekey_state == REKEY_SWITCHED) {
        noshi_wipe(&next->previous, sizeof(next->previous));
        next->rekey_state = 0;
        next->exchange = 0;
    }
done:
    if (status == NOSHI_E_SECURITY) { next->discarded = 1; *message = NULL; }
    if (plain.data) noshi_wipe(plain.data, plain.cap);
    noshi_writer_free(&plain);
    return status;
}

int noshi_secret_rekey_due(const noshi_secret_state *s, uint64_t time_seconds) {
    return s && !s->discarded && s->rekey_state == 0 &&
        (s->key_uses >= 100 || (s->out_count > 0 && time_seconds >= s->key_created && time_seconds - s->key_created >= 604800u));
}

noshi_status noshi_secret_rekey_start(const noshi_secret_state *s, noshi_arena *arena,
                                         noshi_tl_value **action, noshi_secret_state *next) {
    noshi_status status;
    uint64_t id;
    if (!action) return NOSHI_E_ARG;
    *action = NULL;
    if (!s || !next || next == s || !arena || s->discarded || s->rekey_state) return NOSHI_E_STATE;
    *next = *s;
    status = noshi_secret_dh_begin(&next->dh, s->dh.prime, s->dh.generator, NULL, 0);
    if (status == NOSHI_OK) status = noshi_random_u64(&id);
    if (status != NOSHI_OK) return status;
    if (!id) return NOSHI_E_CRYPTO;
    next->exchange = (int64_t)id;
    next->rekey_state = REKEY_REQUESTED;
    *action = noshi_tl_new_obj(arena, "decryptedMessageActionRequestKey");
    status = *action ? noshi_tl_set_i64(arena, *action, "exchange_id", next->exchange) : NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, *action, "g_a", next->dh.public_value, 256);
    return status;
}

static void install_future(noshi_secret_state *next, uint64_t time_seconds) {
    next->previous = next->key;
    next->key = next->future;
    noshi_wipe(&next->future, sizeof(next->future));
    noshi_wipe(next->dh.exponent, sizeof(next->dh.exponent));
    next->key_created = time_seconds;
    next->key_uses = 0;
    next->rekey_state = REKEY_SWITCHED;
}

noshi_status noshi_secret_action(const noshi_secret_state *s, const noshi_tl_value *action,
                                    uint64_t time_seconds, noshi_arena *arena,
                                    noshi_tl_value **response, noshi_secret_state *next) {
    uint32_t id;
    int64_t exchange = 0, fingerprint;
    const uint8_t *value;
    size_t len;
    noshi_status status = NOSHI_OK;
    if (!response) return NOSHI_E_ARG;
    *response = NULL;
    if (!s || !action || !arena || !next || next == s || s->discarded) return NOSHI_E_STATE;
    *next = *s;
    id = noshi_tl_id(action);
    if (noshi_tl_has(action, "exchange_id") && noshi_tl_get_i64(action, "exchange_id", &exchange) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (id == NOSHI_TL_ID_decryptedMessageActionRequestKey) {
        if (!exchange) return NOSHI_E_SECURITY;
        if (s->rekey_state == REKEY_REQUESTED && exchange <= s->exchange) {
            if (exchange == s->exchange) {
                next->rekey_state = 0; next->exchange = 0;
                noshi_wipe(next->dh.exponent, 256);
            }
            return NOSHI_OK;
        }
        if (s->rekey_state && s->rekey_state != REKEY_REQUESTED) return NOSHI_E_STATE;
        if (noshi_tl_get_bytes(action, "g_a", &value, &len) != NOSHI_OK) return NOSHI_E_MALFORMED;
        status = noshi_secret_dh_begin(&next->dh, s->dh.prime, s->dh.generator, NULL, 0);
        if (status == NOSHI_OK) status = noshi_secret_dh_finish(&next->dh, value, len, &next->future);
        if (status != NOSHI_OK) return status;
        next->exchange = exchange;
        next->rekey_state = REKEY_ACCEPTED;
        *response = noshi_tl_new_obj(arena, "decryptedMessageActionAcceptKey");
        status = *response ? noshi_tl_set_i64(arena, *response, "exchange_id", exchange) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, *response, "key_fingerprint", (int64_t)next->future.id);
        if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, *response, "g_b", next->dh.public_value, 256);
    } else if (id == NOSHI_TL_ID_decryptedMessageActionAcceptKey) {
        if (exchange != s->exchange || s->rekey_state != REKEY_REQUESTED) return NOSHI_E_STATE;
        if (noshi_tl_get_i64(action, "key_fingerprint", &fingerprint) != NOSHI_OK ||
            noshi_tl_get_bytes(action, "g_b", &value, &len) != NOSHI_OK) return NOSHI_E_MALFORMED;
        status = noshi_secret_dh_finish(&s->dh, value, len, &next->future);
        if (status != NOSHI_OK) return status;
        if (next->future.id != (uint64_t)fingerprint) return NOSHI_E_SECURITY;
        next->rekey_state = REKEY_COMMIT_READY;
        next->key_created = time_seconds;
        noshi_wipe(next->dh.exponent, 256);
        *response = noshi_tl_new_obj(arena, "decryptedMessageActionCommitKey");
        status = *response ? noshi_tl_set_i64(arena, *response, "exchange_id", exchange) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, *response, "key_fingerprint", fingerprint);
    } else if (id == NOSHI_TL_ID_decryptedMessageActionCommitKey) {
        if (exchange != s->exchange || s->rekey_state != REKEY_ACCEPTED) return NOSHI_E_STATE;
        if (noshi_tl_get_i64(action, "key_fingerprint", &fingerprint) != NOSHI_OK) return NOSHI_E_MALFORMED;
        if ((uint64_t)fingerprint != s->future.id) return NOSHI_E_SECURITY;
        install_future(next, time_seconds);
        /* commit arrived in sequence, so the receiver no longer needs the previous key */
        noshi_wipe(&next->previous, sizeof(next->previous));
        next->rekey_state = 0;
        next->exchange = 0;
        *response = noshi_tl_new_obj(arena, "decryptedMessageActionNoop");
        if (!*response) status = NOSHI_E_NOMEM;
    } else if (id == NOSHI_TL_ID_decryptedMessageActionAbortKey) {
        if (exchange == s->exchange && s->rekey_state == REKEY_REQUESTED) {
            next->rekey_state = 0; next->exchange = 0;
            noshi_wipe(next->dh.exponent, 256);
            noshi_wipe(&next->future, sizeof(next->future));
        }
    } else if (id == NOSHI_TL_ID_decryptedMessageActionNotifyLayer) {
        int32_t layer;
        if (noshi_tl_get_i32(action, "layer", &layer) != NOSHI_OK || layer < 46) return NOSHI_E_MALFORMED;
        if (layer > NOSHI_SECRET_LAYER) return NOSHI_E_UNSUPPORTED;
        if (layer > next->remote_layer) next->remote_layer = layer;
    } else if (id == NOSHI_TL_ID_decryptedMessageActionSetMessageTTL) {
        if (noshi_tl_get_i32(action, "ttl_seconds", &next->ttl) != NOSHI_OK || next->ttl < 0) return NOSHI_E_MALFORMED;
    } else if (id != NOSHI_TL_ID_decryptedMessageActionNoop && id != NOSHI_TL_ID_decryptedMessageActionReadMessages &&
               id != NOSHI_TL_ID_decryptedMessageActionDeleteMessages && id != NOSHI_TL_ID_decryptedMessageActionScreenshotMessages &&
               id != NOSHI_TL_ID_decryptedMessageActionFlushHistory && id != NOSHI_TL_ID_decryptedMessageActionTyping &&
               id != NOSHI_TL_ID_decryptedMessageActionResend) return NOSHI_E_UNSUPPORTED;
    return status;
}

noshi_status noshi_secret_file_fingerprint(const uint8_t key[32], const uint8_t iv[32], uint32_t *out) {
    noshi_slice parts[2];
    uint8_t hash[16];
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = 0;
    if (!key || !iv) return NOSHI_E_ARG;
    parts[0].data = key; parts[0].len = 32;
    parts[1].data = iv; parts[1].len = 32;
    status = noshi_md5(parts, 2, hash);
    if (status == NOSHI_OK) *out = noshi_get_u32le(hash) ^ noshi_get_u32le(hash + 4);
    return status;
}

uint64_t noshi_secret_expiry(int32_t ttl, uint64_t read_at, uint32_t media_duration) {
    uint64_t seconds;
    if (ttl <= 0 || !read_at) return 0;
    seconds = (uint32_t)ttl;
    if (media_duration > seconds) seconds = (uint64_t)media_duration + 1u;
    return seconds > UINT64_MAX - read_at ? UINT64_MAX : read_at + seconds;
}
