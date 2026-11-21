#ifndef NOSHI_SRP_H
#define NOSHI_SRP_H

#include "noshi_tl.h"

typedef struct noshi_srp_proof {
    int64_t id;
    uint8_t A[256];
    uint8_t M1[32];
} noshi_srp_proof;

noshi_status noshi_srp_check(const noshi_tl_value *account_password,
                                const uint8_t *password, size_t len, noshi_srp_proof *out);
noshi_status noshi_srp_verifier(const noshi_tl_value *algo, const uint8_t *password, size_t len,
                                   noshi_arena *arena, noshi_tl_value **new_algo, uint8_t verifier[256]);

#endif
