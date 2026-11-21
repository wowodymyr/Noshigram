#ifndef NOSHI_RANDOM_H
#define NOSHI_RANDOM_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* mtproto nonces and dh exponents require kernel entropy */
noshi_status noshi_random(void *buf, size_t n);
noshi_status noshi_random_u64(uint64_t *out);

#endif
