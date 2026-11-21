#ifndef NOSHI_TGC_SCTP_H
#define NOSHI_TGC_SCTP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the one data channel of a tgcalls call: SCTP (RFC 4960) over the DTLS session (RFC 8261), with the data channel
   protocol (RFC 8832) on its stream 0 */

#define NOSHI_TGC_SCTP_PORT 5000
/* the largest packet this sends, so that it fits the 1100 byte limit of one DTLS write */
#define NOSHI_TGC_SCTP_MAX_PACKET 1100
/* the largest packet taken in: one DTLS datagram */
#define NOSHI_TGC_SCTP_MAX_INPUT 1500
#define NOSHI_TGC_SCTP_MAX_COOKIE 400
#define NOSHI_TGC_SCTP_MAX_MESSAGE 900
#define NOSHI_TGC_SCTP_WINDOW 16
#define NOSHI_TGC_SCTP_RX_SLOTS 32
#define NOSHI_TGC_SCTP_RX_MESSAGE_MAX 16384
#define NOSHI_TGC_SCTP_CHANNEL_LABEL "data"

typedef enum noshi_tgc_sctp_state {
    NOSHI_TGC_SCTP_CLOSED,
    NOSHI_TGC_SCTP_COOKIE_WAIT,
    NOSHI_TGC_SCTP_COOKIE_ECHOED,
    NOSHI_TGC_SCTP_ESTABLISHED,
    NOSHI_TGC_SCTP_FAILED
} noshi_tgc_sctp_state;

typedef struct noshi_tgc_sctp_events {
    void *context;
    /* one SCTP packet for the DTLS session to carry */
    void (*send)(void *context, const uint8_t *packet, size_t len);
    /* the channel opened (true) or the association ended (false) */
    void (*channel)(void *context, int open);
    /* a text message of the other side, NUL terminated, valid during the call */
    void (*message)(void *context, const char *text, size_t len);
} noshi_tgc_sctp_events;

typedef struct noshi_tgc_sctp_chunk {
    uint8_t used;
    uint32_t tsn;
    uint16_t ssn;
    uint32_t ppid;
    uint16_t len;
    uint8_t tries;
    uint64_t sent_ms;
    uint8_t data[NOSHI_TGC_SCTP_MAX_MESSAGE + 4];
} noshi_tgc_sctp_chunk;

typedef struct noshi_tgc_sctp_rx {
    uint8_t used;
    uint8_t flags;
    uint32_t tsn;
    uint16_t stream;
    uint16_t ssn;
    uint32_t ppid;
    uint16_t len;
    uint8_t data[NOSHI_TGC_SCTP_MAX_INPUT];
} noshi_tgc_sctp_rx;

typedef struct noshi_tgc_sctp {
    noshi_tgc_sctp_events events;
    noshi_tgc_sctp_state state;
    uint8_t opener;
    uint8_t channel_open;
    uint8_t open_sent;
    uint32_t my_tag;
    uint32_t peer_tag;
    uint32_t my_initial_tsn;
    uint32_t next_tsn;
    uint32_t peer_rwnd;
    uint16_t next_ssn;
    uint8_t cookie[32];
    uint8_t has_cookie;
    uint8_t answered_init;
    /* the other side's INIT or INIT ACK, remembered until the association stands */
    uint32_t peer_initial_tsn;
    uint8_t has_peer_init;
    uint32_t cumulative;        /* the highest TSN received with none missing before it */
    uint8_t cumulative_valid;
    uint8_t need_sack;
    uint32_t dup_tsn[4];
    uint8_t dup_count;
    noshi_tgc_sctp_chunk window[NOSHI_TGC_SCTP_WINDOW];
    noshi_tgc_sctp_rx rx[NOSHI_TGC_SCTP_RX_SLOTS];
    uint8_t assembling;
    uint8_t assembly[NOSHI_TGC_SCTP_RX_MESSAGE_MAX + 1];
    size_t assembly_len;
    uint16_t assembly_stream;
    uint32_t assembly_ppid;
    uint64_t t1_due;
    uint8_t t1_tries;
    uint64_t t3_due;
    uint64_t rto_ms;
    uint8_t t3_tries;
    uint8_t echo[NOSHI_TGC_SCTP_MAX_COOKIE];
    size_t echo_len;
} noshi_tgc_sctp;

/* is_opener: this side sends the DATA_CHANNEL_OPEN (the side that placed the call). tag and initial_tsn come from
   the owner's random source; neither is zero; NOSHI_E_ARG otherwise */
noshi_status noshi_tgc_sctp_init(noshi_tgc_sctp *s, int is_opener, uint32_t tag, uint32_t initial_tsn, const uint8_t cookie[32],
                                     const noshi_tgc_sctp_events *events);

/* the DTLS session is up: sends the INIT, which both sides do */
noshi_status noshi_tgc_sctp_start(noshi_tgc_sctp *s, uint64_t now_ms);

/* one packet from the DTLS session; NOSHI_E_MALFORMED for a bad checksum, a wrong verification tag or a damaged
   chunk; the packet is dropped, which is what SCTP does with such a packet */
noshi_status noshi_tgc_sctp_input(noshi_tgc_sctp *s, const uint8_t *packet, size_t len, uint64_t now_ms);

/* timers: INIT and COOKIE ECHO repeats, retransmission of unacknowledged data, a delayed SACK; every 50 ms or so */
void noshi_tgc_sctp_tick(noshi_tgc_sctp *s, uint64_t now_ms);

/* one text message on the channel, up to NOSHI_TGC_SCTP_MAX_MESSAGE bytes; NOSHI_E_STATE until the channel is
   open, NOSHI_E_LIMIT for a message too long or when the window of unacknowledged data is full */
noshi_status noshi_tgc_sctp_send_text(noshi_tgc_sctp *s, const char *text, size_t len, uint64_t now_ms);

/* sends an ABORT and closes */
void noshi_tgc_sctp_abort(noshi_tgc_sctp *s);

uint32_t noshi_tgc_crc32c(const uint8_t *data, size_t len);

#endif
