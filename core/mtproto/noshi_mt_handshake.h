#ifndef NOSHI_MT_HANDSHAKE_H
#define NOSHI_MT_HANDSHAKE_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_bytes.h"
#include "noshi_clock.h"
#include "noshi_mt_keys.h"
#include "noshi_mt_msg.h"
#include "noshi_status.h"

typedef enum noshi_mt_hs_state {
    NOSHI_MT_HS_IDLE = 0,
    NOSHI_MT_HS_WAIT_RES_PQ,
    NOSHI_MT_HS_WAIT_DH_PARAMS,
    NOSHI_MT_HS_WAIT_DH_ANSWER,
    NOSHI_MT_HS_DONE,
    NOSHI_MT_HS_FAILED
} noshi_mt_hs_state;

typedef struct noshi_mt_hs_config {
    int dc_id;
    int is_test;
    const noshi_mt_rsa_key *keys;
    size_t key_count;
    const noshi_clock *clock;
    unsigned max_attempts;
} noshi_mt_hs_config;

typedef struct noshi_mt_hs_result {
    noshi_mt_auth_key key;
    uint64_t server_salt;
    int64_t time_offset_ms;
} noshi_mt_hs_result;

typedef struct noshi_mt_handshake {
    noshi_mt_hs_config config;
    noshi_mt_hs_state state;
    unsigned attempts;
    uint64_t last_msg_id;
    uint8_t nonce[16];
    uint8_t server_nonce[16];
    uint8_t new_nonce[32];
    uint8_t tmp_key[32];
    uint8_t tmp_iv[32];
    uint8_t auth_key[256];
    int64_t server_time;
    uint64_t salt;
    int64_t time_offset_ms;
    uint64_t key_fingerprint;
    noshi_mt_hs_result result;
} noshi_mt_handshake;

void noshi_mt_hs_init(noshi_mt_handshake *hs, const noshi_mt_hs_config *config);
void noshi_mt_hs_wipe(noshi_mt_handshake *hs);

noshi_status noshi_mt_hs_start(noshi_mt_handshake *hs, noshi_writer *out);
noshi_status noshi_mt_hs_receive(noshi_mt_handshake *hs, const uint8_t *packet, size_t len, int allow_padding,
                                     noshi_writer *out);
const noshi_mt_hs_result *noshi_mt_hs_result_get(const noshi_mt_handshake *hs);

noshi_status noshi_mt_factor_pq(uint64_t pq, uint32_t *p, uint32_t *q);
noshi_status noshi_mt_check_dh_prime(const uint8_t *prime, size_t len, uint32_t g);
noshi_status noshi_mt_check_dh_value(const uint8_t *prime, size_t prime_len, const uint8_t *value, size_t value_len);
noshi_status noshi_mt_rsa_pad_encrypt(const noshi_mt_rsa_key *key, const uint8_t *data, size_t len,
                                          uint8_t out[256]);

#endif
