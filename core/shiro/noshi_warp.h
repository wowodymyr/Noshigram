#ifndef NOSHI_WARP_H
#define NOSHI_WARP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_wg.h"

/* what Cloudflare WARP needs from a client that is not Cloudflare's */

#define NOSHI_WARP_MAX_PORTS 16
#define NOSHI_WARP_MTU 1280
#define NOSHI_WARP_INSTALL_ID_LEN 22
#define NOSHI_WARP_SIGNATURE_MAX 2048

typedef struct noshi_warp_identity {
    uint8_t private_key[NOSHI_WG_KEY_LEN];
    uint8_t peer_public[NOSHI_WG_KEY_LEN];
    uint8_t reserved[3];
    int has_reserved;
    uint32_t address;                       /* the IPv4 address of this phone inside the tunnel */
    uint32_t endpoint_ip;                   /* of the WireGuard server, host order */
    uint16_t ports[NOSHI_WARP_MAX_PORTS];
    size_t port_count;
} noshi_warp_identity;

/* RFC 4648 base64 with padding. decode is strict: no white space, no missing padding, no stray bits in the last character */
noshi_status noshi_base64_encode(const uint8_t *data, size_t len, char *out, size_t cap, size_t *out_len);
noshi_status noshi_base64_decode(const char *text, size_t text_len, uint8_t *out, size_t cap, size_t *out_len);

/* "a.b.c.d" and nothing else (no leading zeros, no spaces) into host order */
noshi_status noshi_warp_parse_ipv4(const char *text, size_t len, uint32_t *out);

/* a new private key (clamped, from the system's entropy) and its public key */
noshi_status noshi_warp_generate_key(uint8_t private_key[NOSHI_WG_KEY_LEN], uint8_t public_key[NOSHI_WG_KEY_LEN]);

/* the JSON the registration call posts. install_id is NOSHI_WARP_INSTALL_ID_LEN letters and digits drawn by the
   caller, tos the time as "2026-10-21T12:34:56.789Z"; NOSHI_E_LIMIT when cap is too small */
noshi_status noshi_warp_registration_body(const uint8_t public_key[NOSHI_WG_KEY_LEN], const char *install_id, const char *tos, char *out, size_t cap,
                                              size_t *len);

/* the answer of the registration call; every field that is used is checked for its type and its size, and the
   private key is only copied in */
noshi_status noshi_warp_parse_registration(const char *json, size_t len, const uint8_t private_key[NOSHI_WG_KEY_LEN], noshi_warp_identity *out);

typedef struct noshi_warp_profile {
    char signature[2][NOSHI_WARP_SIGNATURE_MAX];
} noshi_warp_profile;

/* the WireGuard configuration for the identity with the framing WARP is reached with; four junk datagrams of 40 to
   70 bytes, then two that look like SIP (an INVITE and a 100 Trying) before the initiation */
noshi_status noshi_warp_wg_config(const noshi_warp_identity *identity, noshi_warp_profile *profile, noshi_wg_config *out);

/* the server for an attempt: the first ones are the endpoint the account came with on each of its ports */
noshi_status noshi_warp_endpoint(const noshi_warp_identity *identity, unsigned attempt, uint32_t *ip, uint16_t *port);

#endif
