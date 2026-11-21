#include "noshi_mt_msg.h"

#include <string.h>

#include "noshi_crypto.h"
#include "noshi_random.h"

#define HEADER_LEN 32u
#define MIN_PADDING 12u
#define MAX_PADDING 1024u
#define MAX_BODY (4u * 1024u * 1024u)

uint64_t noshi_mt_next_msg_id(uint64_t unix_ms, uint64_t *last_msg_id) {
    uint64_t seconds = unix_ms / 1000u;
    uint64_t fraction = (unix_ms % 1000u) * 4294967296ull / 1000u;
    uint64_t id = ((seconds << 32) | fraction) & ~(uint64_t)3;
    if (id <= *last_msg_id) id = (*last_msg_id + 4u) & ~(uint64_t)3;
    *last_msg_id = id;
    return id;
}

noshi_status noshi_mt_auth_key_set(noshi_mt_auth_key *k, const uint8_t key[NOSHI_MT_AUTH_KEY_LEN]) {
    uint8_t digest[NOSHI_SHA1_LEN];
    noshi_status s;
    if (!k || !key) return NOSHI_E_ARG;
    s = noshi_sha1_one(key, NOSHI_MT_AUTH_KEY_LEN, digest);
    if (s != NOSHI_OK) return s;
    memcpy(k->key, key, NOSHI_MT_AUTH_KEY_LEN);
    k->id = noshi_get_u64le(digest + 12);
    return NOSHI_OK;
}

noshi_status noshi_mt_plain_wrap(uint64_t msg_id, const uint8_t *body, size_t len, noshi_writer *out) {
    size_t mark;
    noshi_status s;
    if (!out || !body || len == 0 || len % 4 || len > MAX_BODY) return NOSHI_E_ARG;
    mark = out->len;
    s = noshi_wr_u64le(out, 0);
    if (s == NOSHI_OK) s = noshi_wr_u64le(out, msg_id);
    if (s == NOSHI_OK) s = noshi_wr_u32le(out, (uint32_t)len);
    if (s == NOSHI_OK) s = noshi_wr_bytes(out, body, len);
    if (s != NOSHI_OK) out->len = mark;
    return s;
}

noshi_status noshi_mt_plain_unwrap(const uint8_t *packet, size_t len, int allow_padding,
                                       uint64_t *msg_id, const uint8_t **body, size_t *body_len) {
    uint32_t n;
    if (!packet || !msg_id || !body || !body_len) return NOSHI_E_ARG;
    if (len < 24) return NOSHI_E_MALFORMED;
    if (noshi_get_u64le(packet) != 0) return NOSHI_E_MALFORMED;
    n = noshi_get_u32le(packet + 16);
    if (n == 0 || n % 4 || n > len - 20) return NOSHI_E_MALFORMED;
    if (!allow_padding && n != len - 20) return NOSHI_E_MALFORMED;
    *msg_id = noshi_get_u64le(packet + 8);
    *body = packet + 20;
    *body_len = n;
    return NOSHI_OK;
}

noshi_status noshi_mt_key_schedule(const noshi_mt_auth_key *k, unsigned x, const uint8_t msg_key[16],
                               uint8_t aes_key[32], uint8_t aes_iv[32]) {
    uint8_t a[32], b[32];
    noshi_slice pa[2], pb[2];
    noshi_status s;
    if (!k || !msg_key || !aes_key || !aes_iv || (x != 0 && x != 8)) return NOSHI_E_ARG;
    pa[0].data = msg_key;
    pa[0].len = 16;
    pa[1].data = k->key + x;
    pa[1].len = 36;
    pb[0].data = k->key + 40 + x;
    pb[0].len = 36;
    pb[1].data = msg_key;
    pb[1].len = 16;
    s = noshi_sha256(pa, 2, a);
    if (s != NOSHI_OK) return s;
    s = noshi_sha256(pb, 2, b);
    if (s != NOSHI_OK) return s;
    memcpy(aes_key, a, 8);
    memcpy(aes_key + 8, b + 8, 16);
    memcpy(aes_key + 24, a + 24, 8);
    memcpy(aes_iv, b, 8);
    memcpy(aes_iv + 8, a + 8, 16);
    memcpy(aes_iv + 24, b + 24, 8);
    return NOSHI_OK;
}

noshi_status noshi_mt_message_key(const noshi_mt_auth_key *k, unsigned x, const uint8_t *plain, size_t len,
                                      uint8_t msg_key[16]) {
    uint8_t large[32];
    noshi_slice parts[2];
    noshi_status s;
    if (!k || (!plain && len) || !msg_key || (x != 0 && x != 8)) return NOSHI_E_ARG;
    parts[0].data = k->key + 88 + x;
    parts[0].len = 32;
    parts[1].data = plain;
    parts[1].len = len;
    s = noshi_sha256(parts, 2, large);
    if (s != NOSHI_OK) return s;
    memcpy(msg_key, large + 8, 16);
    return NOSHI_OK;
}

noshi_status noshi_mt_encrypt(const noshi_mt_auth_key *k, int from_client, const noshi_mt_header *h,
                                  const uint8_t *body, size_t len, noshi_writer *out) {
    unsigned x = from_client ? 0u : 8u;
    uint8_t r;
    size_t pad, total, mark;
    uint8_t msg_key[16], aes_key[32], aes_iv[32];
    uint8_t *plain;
    noshi_status s;
    if (!k || !h || !body || !out || len == 0 || len % 4 || len > MAX_BODY) return NOSHI_E_ARG;
    s = noshi_random(&r, 1);
    if (s != NOSHI_OK) return s;
    /* authenticated padding must meet mtproto 2.0's minimum and aes block size */
    pad = MIN_PADDING + ((16u - (HEADER_LEN + len + MIN_PADDING) % 16u) % 16u) + 16u * (r % 3u);
    total = HEADER_LEN + len + pad;
    mark = out->len;
    s = noshi_wr_reserve(out, 24 + total);
    if (s != NOSHI_OK) return s;
    plain = out->data + out->len + 24;
    noshi_put_u64le(plain, h->salt);
    noshi_put_u64le(plain + 8, h->session_id);
    noshi_put_u64le(plain + 16, h->msg_id);
    noshi_put_u32le(plain + 24, (uint32_t)h->seq_no);
    noshi_put_u32le(plain + 28, (uint32_t)len);
    memcpy(plain + HEADER_LEN, body, len);
    s = noshi_random(plain + HEADER_LEN + len, pad);
    if (s != NOSHI_OK) return s;
    s = noshi_mt_message_key(k, x, plain, total, msg_key);
    if (s == NOSHI_OK) s = noshi_mt_key_schedule(k, x, msg_key, aes_key, aes_iv);
    if (s == NOSHI_OK) s = noshi_aes_ige(aes_key, aes_iv, 1, plain, plain, total);
    noshi_wipe(aes_key, sizeof(aes_key));
    noshi_wipe(aes_iv, sizeof(aes_iv));
    if (s != NOSHI_OK) {
        out->len = mark;
        return s;
    }
    noshi_put_u64le(out->data + out->len, k->id);
    memcpy(out->data + out->len + 8, msg_key, 16);
    out->len += 24 + total;
    return NOSHI_OK;
}

noshi_status noshi_mt_decrypt(const noshi_mt_auth_key *k, int from_client, int allow_padding,
                                  const uint8_t *packet, size_t len, noshi_writer *plain,
                                  noshi_mt_header *h, const uint8_t **body, size_t *body_len) {
    unsigned x = from_client ? 0u : 8u;
    uint8_t msg_key[16], expect[16], aes_key[32], aes_iv[32];
    size_t enc_len, mark, data_len, pad;
    uint8_t *p;
    noshi_status s;
    if (!k || !packet || !plain || !h || !body || !body_len) return NOSHI_E_ARG;
    if (len < 24 + 16 + 16) return NOSHI_E_MALFORMED;
    enc_len = len - 24;
    if (enc_len % 16) {
        if (!allow_padding) return NOSHI_E_MALFORMED;
        enc_len -= enc_len % 16;
    }
    if (noshi_get_u64le(packet) != k->id) return NOSHI_E_SECURITY;
    memcpy(msg_key, packet + 8, 16);
    mark = plain->len;
    s = noshi_wr_reserve(plain, enc_len);
    if (s != NOSHI_OK) return s;
    p = plain->data + plain->len;
    s = noshi_mt_key_schedule(k, x, msg_key, aes_key, aes_iv);
    if (s == NOSHI_OK) s = noshi_aes_ige(aes_key, aes_iv, 0, packet + 24, p, enc_len);
    noshi_wipe(aes_key, sizeof(aes_key));
    noshi_wipe(aes_iv, sizeof(aes_iv));
    if (s != NOSHI_OK) return s;
    s = noshi_mt_message_key(k, x, p, enc_len, expect);
    if (s != NOSHI_OK) return s;
    /* a wrong key or a tampered packet decrypts to noise, this is the only authentication the packet has */
    if (!noshi_ct_equal(msg_key, expect, 16)) return NOSHI_E_SECURITY;
    data_len = noshi_get_u32le(p + 28);
    if (data_len == 0 || data_len % 4 || data_len > enc_len - HEADER_LEN) return NOSHI_E_MALFORMED;
    pad = enc_len - HEADER_LEN - data_len;
    if (pad < MIN_PADDING || pad > MAX_PADDING) return NOSHI_E_MALFORMED;
    h->salt = noshi_get_u64le(p);
    h->session_id = noshi_get_u64le(p + 8);
    h->msg_id = noshi_get_u64le(p + 16);
    h->seq_no = (int32_t)noshi_get_u32le(p + 24);
    *body = p + HEADER_LEN;
    *body_len = data_len;
    plain->len = mark + enc_len;
    return NOSHI_OK;
}
