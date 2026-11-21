#include "noshi_tgc_cipher.h"

#include <string.h>

#include "noshi_bytes.h"
#include "noshi_crypto.h"

/* the signaling kind of EncryptedConnection adds 128 to the offset into the key */
#define SIGNALING_OFFSET 128
#define REPLAY_WINDOW 64u
#define MIN_PACKET (NOSHI_TGC_MSG_KEY_LEN + NOSHI_TGC_COUNTER_LEN + 1)

static noshi_status ctr256(const uint8_t key[32], const uint8_t iv[16], const uint8_t *in, uint8_t *out, size_t len) {
    noshi_aes_ctr *ctr = noshi_aes_ctr_new(key, iv);
    noshi_status status;
    if (!ctr) return NOSHI_E_CRYPTO;
    status = noshi_aes_ctr_apply(ctr, in, out, len);
    noshi_aes_ctr_free(ctr);
    return status;
}

noshi_status noshi_tgc_cipher_init(noshi_tgc_cipher *c, const uint8_t key[NOSHI_TGC_KEY_LEN], int is_outgoing) {
    if (!c) return NOSHI_E_ARG;
    memset(c, 0, sizeof(*c));
    if (!key) return NOSHI_E_ARG;
    memcpy(c->key, key, NOSHI_TGC_KEY_LEN);
    c->out_shift = (uint8_t)((is_outgoing ? 0 : 8) + SIGNALING_OFFSET);
    c->in_shift = (uint8_t)((is_outgoing ? 8 : 0) + SIGNALING_OFFSET);
    return NOSHI_OK;
}

/* prepare_aes_key_iv of tgcalls: both halves of the key and the iv come from two hashes that mix the msg_key with the call key */
static noshi_status derive(const uint8_t key[NOSHI_TGC_KEY_LEN], const uint8_t msg_key[NOSHI_TGC_MSG_KEY_LEN], unsigned shift,
                             uint8_t aes_key[32], uint8_t iv[16]) {
    noshi_slice first[2], second[2];
    uint8_t a[NOSHI_SHA256_LEN], b[NOSHI_SHA256_LEN];
    noshi_status status;
    first[0].data = msg_key;
    first[0].len = NOSHI_TGC_MSG_KEY_LEN;
    first[1].data = key + shift;
    first[1].len = 36;
    second[0].data = key + 40 + shift;
    second[0].len = 36;
    second[1].data = msg_key;
    second[1].len = NOSHI_TGC_MSG_KEY_LEN;
    status = noshi_sha256(first, 2, a);
    if (status == NOSHI_OK) status = noshi_sha256(second, 2, b);
    if (status == NOSHI_OK) {
        memcpy(aes_key, a, 8);
        memcpy(aes_key + 8, b + 8, 16);
        memcpy(aes_key + 24, a + 24, 8);
        memcpy(iv, b, 4);
        memcpy(iv + 4, a + 8, 8);
        memcpy(iv + 12, b + 24, 4);
    }
    memset(a, 0, sizeof(a));
    memset(b, 0, sizeof(b));
    return status;
}

/* the msg_key is bytes 8 to 24 of SHA-256(key[88 + shift .. +32] || plaintext) */
static noshi_status message_key(const uint8_t key[NOSHI_TGC_KEY_LEN], unsigned shift, const uint8_t *plain, size_t plain_len,
                                  uint8_t msg_key[NOSHI_TGC_MSG_KEY_LEN]) {
    noshi_slice parts[2];
    uint8_t large[NOSHI_SHA256_LEN];
    noshi_status status;
    parts[0].data = key + 88 + shift;
    parts[0].len = 32;
    parts[1].data = plain;
    parts[1].len = plain_len;
    status = noshi_sha256(parts, 2, large);
    if (status == NOSHI_OK) memcpy(msg_key, large + 8, NOSHI_TGC_MSG_KEY_LEN);
    memset(large, 0, sizeof(large));
    return status;
}

noshi_status noshi_tgc_cipher_seal(noshi_tgc_cipher *c, const uint8_t *plain, size_t plain_len, uint8_t *out, size_t capacity,
                                       size_t *out_len) {
    uint8_t body[NOSHI_TGC_COUNTER_LEN + NOSHI_TGC_SIGNAL_MAX];
    uint8_t aes_key[32], iv[16];
    noshi_status status;
    uint32_t counter;
    if (out_len) *out_len = 0;
    if (!c || !plain || !out || !out_len) return NOSHI_E_ARG;
    if (plain_len == 0 || plain_len > NOSHI_TGC_SIGNAL_MAX) return NOSHI_E_LIMIT;
    if (capacity < NOSHI_TGC_MSG_KEY_LEN + NOSHI_TGC_COUNTER_LEN + plain_len) return NOSHI_E_LIMIT;
    if (c->sent >= NOSHI_TGC_COUNTER_MAX) return NOSHI_E_STATE;
    counter = ++c->sent;
    noshi_put_u32be(body, counter);
    memcpy(body + NOSHI_TGC_COUNTER_LEN, plain, plain_len);
    status = message_key(c->key, c->out_shift, body, NOSHI_TGC_COUNTER_LEN + plain_len, out);
    if (status == NOSHI_OK) status = derive(c->key, out, c->out_shift, aes_key, iv);
    if (status == NOSHI_OK) status = ctr256(aes_key, iv, body, out + NOSHI_TGC_MSG_KEY_LEN, NOSHI_TGC_COUNTER_LEN + plain_len);
    memset(aes_key, 0, sizeof(aes_key));
    memset(iv, 0, sizeof(iv));
    memset(body, 0, sizeof(body));
    if (status == NOSHI_OK) *out_len = NOSHI_TGC_MSG_KEY_LEN + NOSHI_TGC_COUNTER_LEN + plain_len;
    return status;
}

/* true when the counter is new; commits it to the window only when commit is set */
static int counter_is_fresh(const noshi_tgc_cipher *c, uint32_t counter, uint32_t *distance_out) {
    if (counter > c->highest) {
        *distance_out = 0;
        return 1;
    }
    *distance_out = c->highest - counter;
    if (*distance_out >= REPLAY_WINDOW) return 0;
    return (c->window & ((uint64_t)1 << *distance_out)) == 0;
}

noshi_status noshi_tgc_cipher_open(noshi_tgc_cipher *c, const uint8_t *packet, size_t packet_len, uint8_t *out, size_t capacity,
                                       size_t *out_len) {
    uint8_t body[NOSHI_TGC_COUNTER_LEN + NOSHI_TGC_SIGNAL_MAX];
    uint8_t aes_key[32], iv[16], expect[NOSHI_TGC_MSG_KEY_LEN];
    size_t body_len, diff = 0, i;
    uint32_t counter, distance;
    noshi_status status;
    if (out_len) *out_len = 0;
    if (!c || !packet || !out || !out_len) return NOSHI_E_ARG;
    if (packet_len < MIN_PACKET || packet_len > NOSHI_TGC_PACKET_MAX) return NOSHI_E_MALFORMED;
    body_len = packet_len - NOSHI_TGC_MSG_KEY_LEN;
    status = derive(c->key, packet, c->in_shift, aes_key, iv);
    if (status == NOSHI_OK) status = ctr256(aes_key, iv, packet + NOSHI_TGC_MSG_KEY_LEN, body, body_len);
    if (status == NOSHI_OK) status = message_key(c->key, c->in_shift, body, body_len, expect);
    memset(aes_key, 0, sizeof(aes_key));
    memset(iv, 0, sizeof(iv));
    if (status != NOSHI_OK) {
        memset(body, 0, sizeof(body));
        return status;
    }
    /* constant time: the msg_key is a mac, and how much of it matched is not for the sender to learn */
    for (i = 0; i < NOSHI_TGC_MSG_KEY_LEN; ++i) diff |= (size_t)(expect[i] ^ packet[i]);
    if (diff != 0) {
        memset(body, 0, sizeof(body));
        return NOSHI_E_SECURITY;
    }
    /* the top two bits of the counter are flags of the framing tgcalls uses between its own messages, not part of the number */
    counter = ((uint32_t)body[0] << 24 | (uint32_t)body[1] << 16 | (uint32_t)body[2] << 8 | body[3]) & NOSHI_TGC_COUNTER_MAX;
    if (!counter_is_fresh(c, counter, &distance)) {
        memset(body, 0, sizeof(body));
        return NOSHI_E_RETRY;
    }
    if (capacity < body_len - NOSHI_TGC_COUNTER_LEN) {
        memset(body, 0, sizeof(body));
        return NOSHI_E_LIMIT;
    }
    if (counter > c->highest) {
        uint32_t shift = counter - c->highest;
        c->window = shift >= REPLAY_WINDOW ? 1 : ((c->window << shift) | 1);
        c->highest = counter;
    } else {
        c->window |= (uint64_t)1 << distance;
    }
    memcpy(out, body + NOSHI_TGC_COUNTER_LEN, body_len - NOSHI_TGC_COUNTER_LEN);
    *out_len = body_len - NOSHI_TGC_COUNTER_LEN;
    memset(body, 0, sizeof(body));
    return NOSHI_OK;
}

void noshi_tgc_cipher_wipe(noshi_tgc_cipher *c) {
    if (c) memset(c, 0, sizeof(*c));
}
