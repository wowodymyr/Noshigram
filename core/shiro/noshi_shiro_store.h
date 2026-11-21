#ifndef NOSHI_SHIRO_STORE_H
#define NOSHI_SHIRO_STORE_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_warp.h"

/* the bytes of the file the phone keeps its WARP account in: the private key, the server key and the addresses the
   registration returned */

#define NOSHI_SHIRO_STORE_LEN 113u

/* NOSHI_E_ARG for an identity the tunnel could not use (no endpoint, no address, no port, more ports than the identity holds), NOSHI_E_LIMIT when cap is
   smaller than NOSHI_SHIRO_STORE_LEN */
noshi_status noshi_shiro_store_pack(const noshi_warp_identity *identity, uint8_t *out, size_t cap, size_t *len);

/* NOSHI_E_MALFORMED for a wrong size, magic or flag, or for the same identity that pack would refuse. out is zeroed on every failure */
noshi_status noshi_shiro_store_unpack(const uint8_t *data, size_t len, noshi_warp_identity *out);

#endif
