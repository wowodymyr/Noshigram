#ifndef NOSHI_TGC_SRTP_H
#define NOSHI_TGC_SRTP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* SRTP and SRTCP of RFC 3711 with the one profile a tgcalls call settles on, SRTP_AES128_CM_SHA1_80: AES-128 in
   counter mode and an 80 bit HMAC-SHA1 tag */

#define NOSHI_TGC_SRTP_KEY_LEN 16
#define NOSHI_TGC_SRTP_SALT_LEN 14
#define NOSHI_TGC_SRTP_TAG_LEN 10
/* a group call hears one stream per speaker, so the table is larger than a call of two needs */
#define NOSHI_TGC_SRTP_STREAMS 32
#define NOSHI_TGC_SRTCP_TRAILER_LEN (4 + NOSHI_TGC_SRTP_TAG_LEN)
#define NOSHI_TGC_SRTP_AUTH_KEY_LEN 20
#define NOSHI_TGC_SRTP_WINDOW 128

typedef struct noshi_tgc_srtp_window {
    uint64_t highest;
    uint8_t has_highest;
    uint8_t bits[NOSHI_TGC_SRTP_WINDOW / 8];
} noshi_tgc_srtp_window;

typedef struct noshi_tgc_srtp_stream {
    uint8_t used;
    uint32_t ssrc;
    uint32_t roc;
    uint16_t last_seq;
    uint8_t has_seq;
    /* sending SRTCP: the index of the last packet of this sender; the replay window is for receiving */
    uint32_t rtcp_index;
    noshi_tgc_srtp_window replay;
} noshi_tgc_srtp_stream;

typedef struct noshi_tgc_srtp {
    uint8_t rtp_key[NOSHI_TGC_SRTP_KEY_LEN];
    uint8_t rtp_salt[NOSHI_TGC_SRTP_SALT_LEN];
    uint8_t rtp_auth[NOSHI_TGC_SRTP_AUTH_KEY_LEN];
    uint8_t rtcp_key[NOSHI_TGC_SRTP_KEY_LEN];
    uint8_t rtcp_salt[NOSHI_TGC_SRTP_SALT_LEN];
    uint8_t rtcp_auth[NOSHI_TGC_SRTP_AUTH_KEY_LEN];
    noshi_tgc_srtp_stream streams[NOSHI_TGC_SRTP_STREAMS];
    /* RTCP state by the ssrc in the first header: the SRTCP index of each sender and the replay window of each */
    noshi_tgc_srtp_stream rtcp_streams[NOSHI_TGC_SRTP_STREAMS];
} noshi_tgc_srtp;

/* derives the six session keys from the master key and salt of one direction (RFC 3711 section 4.3, key derivation rate 0) */
noshi_status noshi_tgc_srtp_init(noshi_tgc_srtp *s, const uint8_t master_key[NOSHI_TGC_SRTP_KEY_LEN],
                                     const uint8_t master_salt[NOSHI_TGC_SRTP_SALT_LEN]);

/* the RTP packet in pkt (len bytes) is encrypted in place and the tag appended, so capacity must be at least len +
   10 */
noshi_status noshi_tgc_srtp_protect(noshi_tgc_srtp *s, uint8_t *pkt, size_t len, size_t capacity, size_t *out_len);

/* checks the tag and the replay window, then decrypts in place; out_len is the plain packet length */
noshi_status noshi_tgc_srtp_unprotect(noshi_tgc_srtp *s, uint8_t *pkt, size_t len, size_t *out_len);

/* the same for RTCP: the packet (a compound of whole RTCP packets, at least 8 bytes) is encrypted after its first
   8 bytes, and the SRTCP index and the tag are appended */
noshi_status noshi_tgc_srtcp_protect(noshi_tgc_srtp *s, uint8_t *pkt, size_t len, size_t capacity, size_t *out_len);
noshi_status noshi_tgc_srtcp_unprotect(noshi_tgc_srtp *s, uint8_t *pkt, size_t len, size_t *out_len);

/* drops the state of the stream of this ssrc (RTP and RTCP), for a source that left; a later packet of the ssrc starts a new stream */
void noshi_tgc_srtp_forget(noshi_tgc_srtp *s, uint32_t ssrc);

void noshi_tgc_srtp_wipe(noshi_tgc_srtp *s);

#endif
