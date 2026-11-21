#ifndef NOSHI_WG_H
#define NOSHI_WG_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the initiating side of WireGuard (Noise IKpsk2 over curve25519, ChaCha20-Poly1305 and BLAKE2s) with the framing
   options of AmneziaWG */

#define NOSHI_WG_KEY_LEN 32
#define NOSHI_WG_INITIATION_LEN 148
#define NOSHI_WG_RESPONSE_LEN 92
#define NOSHI_WG_HEADER_LEN 16
#define NOSHI_WG_TAG_LEN 16
#define NOSHI_WG_REPLAY_BITS 256
/* the largest IP packet the tunnel carries */
#define NOSHI_WG_MAX_PLAIN 1500
#define NOSHI_WG_MAX_DATAGRAM (NOSHI_WG_HEADER_LEN + NOSHI_WG_MAX_PLAIN + 16 + NOSHI_WG_TAG_LEN)
#define NOSHI_WG_MAX_JUNK 32
#define NOSHI_WG_MAX_JUNK_LEN 1400
#define NOSHI_WG_MAX_PREFIX 1024
#define NOSHI_WG_SIGNATURES 5
/* the timers of the protocol (WireGuard whitepaper, section 6.1) */
#define NOSHI_WG_REKEY_AFTER_MS 120000u
#define NOSHI_WG_REJECT_AFTER_MS 180000u
#define NOSHI_WG_KEEPALIVE_MS 25000u

typedef struct noshi_wg_config {
    uint8_t private_key[NOSHI_WG_KEY_LEN];
    uint8_t peer_public[NOSHI_WG_KEY_LEN];
    uint8_t preshared[NOSHI_WG_KEY_LEN];      /* all zeros when the peer has none */
    uint8_t reserved[3];
    int has_reserved;
    uint16_t junk_count, junk_min, junk_max;
    uint16_t s1, s2;                            /* random bytes in front of the initiation, and in front of the response the peer sends */
    uint32_t h1, h2, h4;                        /* type field of the initiation, the response and the data message; 0 keeps 1, 2 and 4 */
    /* texts such as "<b 0x4142><r 8><t>" that become datagrams of their own; NULL or empty ones are skipped; they
       must outlive the handshake call */
    const char *signature[NOSHI_WG_SIGNATURES];
} noshi_wg_config;

/* the sizes and counts must be inside their limits and the keys must not be zero */
noshi_status noshi_wg_config_check(const noshi_wg_config *config);

/* a signature text turned into bytes: <b 0x..> literal bytes, <r N> N random bytes (up to 1024), <t> the unix time
   in seconds as 4 bytes little endian, <c> a counter field (4 bytes, value 1) */
noshi_status noshi_wg_signature_render(const char *spec, uint32_t unix_seconds, uint8_t *out, size_t cap, size_t *len);

typedef struct noshi_wg_session {
    int active;
    uint8_t send_key[NOSHI_WG_KEY_LEN];
    uint8_t recv_key[NOSHI_WG_KEY_LEN];
    uint32_t local_index;
    uint32_t remote_index;
    uint32_t data_type;
    uint8_t reserved[3];
    int has_reserved;
    uint64_t send_counter;
    int received_any;
    uint64_t recv_max;
    uint64_t recv_window[NOSHI_WG_REPLAY_BITS / 64];
    uint64_t born_ms;                           /* the monotonic time the keys were made */
} noshi_wg_session;

typedef struct noshi_wg_handshake {
    int pending;
    noshi_wg_config config;
    uint8_t static_public[NOSHI_WG_KEY_LEN];
    uint8_t mac1_key[NOSHI_WG_KEY_LEN];
    uint8_t ephemeral_private[NOSHI_WG_KEY_LEN];
    uint8_t chain[NOSHI_WG_KEY_LEN];
    uint8_t hash[NOSHI_WG_KEY_LEN];
    uint32_t local_index;
} noshi_wg_handshake;

/* one datagram to send; called in order: the signatures, then the junk, then the initiation */
typedef void (*noshi_wg_emit)(void *context, const uint8_t *data, size_t len);

/* builds the initiation and hands every datagram to emit. unix_seconds and nanos stamp the message (TAI64N) */
noshi_status noshi_wg_handshake_begin(noshi_wg_handshake *hs, const noshi_wg_config *config, uint64_t unix_seconds, uint32_t nanos,
                                          noshi_wg_emit emit, void *context);

/* a datagram that may be the answer */
noshi_status noshi_wg_handshake_finish(noshi_wg_handshake *hs, const uint8_t *packet, size_t len, uint64_t now_ms, noshi_wg_session *session);

/* wipes keys and state */
void noshi_wg_handshake_clear(noshi_wg_handshake *hs);
void noshi_wg_session_clear(noshi_wg_session *session);

/* one IP packet (or none, for a keepalive) into a data datagram; the plain text is padded with zeros to a multiple
   of 16 bytes as the protocol does, so the IP total length field has to be what tells where the packet ends. out
   needs NOSHI_WG_MAX_DATAGRAM bytes */
noshi_status noshi_wg_seal(noshi_wg_session *session, const uint8_t *plain, size_t len, uint8_t *out, size_t cap, size_t *out_len);

/* a datagram of the peer; NOSHI_E_MALFORMED when it is not a data message for this session, NOSHI_E_RETRY for
   a counter that was seen or is too old */
noshi_status noshi_wg_open(noshi_wg_session *session, const uint8_t *packet, size_t len, uint8_t *plain, size_t cap, size_t *plain_len);

/* the age of the keys in milliseconds on the monotonic clock the owner uses */
uint64_t noshi_wg_session_age_ms(const noshi_wg_session *session, uint64_t now_ms);

#endif
