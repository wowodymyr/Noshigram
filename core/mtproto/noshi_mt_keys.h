#ifndef NOSHI_MT_KEYS_H
#define NOSHI_MT_KEYS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

typedef struct noshi_mt_rsa_key {
    uint64_t fingerprint;
    const uint8_t *n;
    size_t n_len;
    uint32_t e;
} noshi_mt_rsa_key;

const noshi_mt_rsa_key *noshi_mt_default_keys(int is_test, size_t *count);
noshi_status noshi_mt_rsa_fingerprint(const uint8_t *n, size_t n_len, uint32_t e, uint64_t *out);
const noshi_mt_rsa_key *noshi_mt_find_key(const noshi_mt_rsa_key *keys, size_t count, uint64_t fingerprint);

#endif
