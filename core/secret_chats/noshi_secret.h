#ifndef NOSHI_SECRET_H
#define NOSHI_SECRET_H

#include "noshi_mt_msg.h"
#include "noshi_tl.h"

#define NOSHI_SECRET_LAYER 151
#define NOSHI_SECRET_MESSAGE_MAX (1024u * 1024u)

typedef struct noshi_secret_dh {
    uint8_t prime[256];
    uint8_t exponent[256];
    uint8_t public_value[256];
    uint32_t generator;
} noshi_secret_dh;

typedef struct noshi_secret_state {
    noshi_mt_auth_key key;
    noshi_mt_auth_key previous;
    noshi_mt_auth_key future;
    noshi_secret_dh dh;
    uint8_t visualization[36];
    int initiator;
    int32_t remote_layer;
    int32_t in_count;
    int32_t out_count;
    int32_t remote_ack;
    int32_t mt2_first_in;
    int32_t ttl;
    uint32_t key_uses;
    uint64_t key_created;
    int64_t exchange;
    int rekey_state;
    int discarded;
} noshi_secret_state;

noshi_status noshi_secret_dh_begin(noshi_secret_dh *dh, const uint8_t prime[256], uint32_t generator,
                                      const uint8_t *server_random, size_t random_len);
noshi_status noshi_secret_dh_finish(const noshi_secret_dh *dh, const uint8_t *peer_public, size_t len,
                                       noshi_mt_auth_key *out);
noshi_status noshi_secret_init(noshi_secret_state *s, int initiator, const noshi_secret_dh *dh,
                                  const noshi_mt_auth_key *key, uint64_t time_seconds);
void noshi_secret_free(noshi_secret_state *s);
/* persisting the sequence with its packet prevents reuse after a crash */
noshi_status noshi_secret_seal(const noshi_secret_state *s, const noshi_tl_value *message,
                                  noshi_writer *out, noshi_secret_state *next);
noshi_status noshi_secret_open(const noshi_secret_state *s, const uint8_t *packet, size_t len,
                                  noshi_arena *arena, noshi_tl_value **message, noshi_secret_state *next);
int noshi_secret_rekey_due(const noshi_secret_state *s, uint64_t time_seconds);
noshi_status noshi_secret_rekey_start(const noshi_secret_state *s, noshi_arena *arena,
                                         noshi_tl_value **action, noshi_secret_state *next);
noshi_status noshi_secret_action(const noshi_secret_state *s, const noshi_tl_value *action,
                                    uint64_t time_seconds, noshi_arena *arena,
                                    noshi_tl_value **response, noshi_secret_state *next);
noshi_status noshi_secret_file_fingerprint(const uint8_t key[32], const uint8_t iv[32], uint32_t *out);
uint64_t noshi_secret_expiry(int32_t ttl, uint64_t read_at, uint32_t media_duration);

#endif
