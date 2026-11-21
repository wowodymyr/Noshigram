#ifndef NOSHI_BASE64_H
#define NOSHI_BASE64_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* RFC 4648 base64 with padding, written with its terminating zero; cap counts the zero */
noshi_status noshi_base64_encode(const uint8_t *data, size_t len, char *out, size_t cap, size_t *out_len);

#endif
