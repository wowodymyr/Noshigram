#ifndef NOSHI_DTLS_H
#define NOSHI_DTLS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* DTLS 1.2 with SRTP keying (RFC 5764) for the media path of a call; input takes what arrived from the network and
   poll gives what has to be sent, so no socket lives here and the whole handshake can run in memory */

#define NOSHI_DTLS_FINGERPRINT_LEN 95
#define NOSHI_DTLS_MAX_DATAGRAM 1500
/* the most one write may carry: a record has to fit the 1200 byte MTU the session is set to, with its header, tag and explicit nonce */
#define NOSHI_DTLS_MAX_APP_DATA 1100
#define NOSHI_DTLS_SRTP_KEY_LEN 16
#define NOSHI_DTLS_SRTP_SALT_LEN 14

typedef struct noshi_dtls noshi_dtls;

typedef enum noshi_dtls_state {
    NOSHI_DTLS_IDLE,          /* made, not started */
    NOSHI_DTLS_HANDSHAKING,
    NOSHI_DTLS_CONNECTED,
    NOSHI_DTLS_FAILED
} noshi_dtls_state;

/* makes the session and its certificate; NOSHI_E_CRYPTO when the library cannot make one */
noshi_status noshi_dtls_new(noshi_dtls **out);
void noshi_dtls_free(noshi_dtls *d);

/* "AA:BB:...:FF", 95 characters, the SHA-256 of the certificate as RFC 4572 writes it; valid as long as d */
const char *noshi_dtls_local_fingerprint(const noshi_dtls *d);

/* the fingerprint the other side announced; only "sha-256" (any case) is understood; the value is 32 hex pairs
   with colons, either case */
noshi_status noshi_dtls_set_peer_fingerprint(noshi_dtls *d, const char *hash, const char *fingerprint);

/* starts the handshake as the client (sends the first flight) or the server (waits for it); NOSHI_E_STATE when
   it was started before */
noshi_status noshi_dtls_start(noshi_dtls *d, int is_client);

/* one datagram from the network; NOSHI_E_LIMIT above NOSHI_DTLS_MAX_DATAGRAM, NOSHI_E_LIMIT also when too
   many wait for a start */
noshi_status noshi_dtls_input(noshi_dtls *d, const uint8_t *datagram, size_t len);

/* the next datagram to send, in out; NOSHI_E_RETRY when there is none */
noshi_status noshi_dtls_poll(noshi_dtls *d, uint8_t *out, size_t capacity, size_t *len);

/* milliseconds until the handshake wants on_timeout called to resend its flight; NOSHI_E_STATE when no timer runs */
noshi_status noshi_dtls_timeout(noshi_dtls *d, uint32_t *ms);
/* the time given by timeout has passed: resends the flight */
noshi_status noshi_dtls_on_timeout(noshi_dtls *d);

noshi_dtls_state noshi_dtls_get_state(const noshi_dtls *d);
/* why the session failed, empty until it did */
const char *noshi_dtls_failure(const noshi_dtls *d);

/* once CONNECTED: the SRTP keys of the two directions as a 16 byte key and a 14 byte salt each; send is for what
   this side sends; NOSHI_E_STATE before that */
noshi_status noshi_dtls_srtp_keys(noshi_dtls *d, uint8_t send_key[NOSHI_DTLS_SRTP_KEY_LEN], uint8_t send_salt[NOSHI_DTLS_SRTP_SALT_LEN],
                                      uint8_t recv_key[NOSHI_DTLS_SRTP_KEY_LEN], uint8_t recv_salt[NOSHI_DTLS_SRTP_SALT_LEN]);

/* application data: write one message of up to NOSHI_DTLS_MAX_APP_DATA bytes (NOSHI_E_LIMIT above that,
   NOSHI_E_STATE before CONNECTED); read gives the next decrypted message */
noshi_status noshi_dtls_write(noshi_dtls *d, const uint8_t *data, size_t len);
noshi_status noshi_dtls_read(noshi_dtls *d, uint8_t *out, size_t capacity, size_t *len);

#endif
