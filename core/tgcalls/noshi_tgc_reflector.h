#ifndef NOSHI_TGC_REFLECTOR_H
#define NOSHI_TGC_REFLECTOR_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the packets of a Telegram reflector, the relay server both phones of a call reach (ReflectorPort of tgcalls) */

#define NOSHI_TGC_PEER_TAG_LEN 16
#define NOSHI_TGC_TAG_PREFIX_LEN 12
#define NOSHI_TGC_REFLECTOR_HELLO_UDP_LEN 40
#define NOSHI_TGC_REFLECTOR_HELLO_TCP_LEN 24
#define NOSHI_TGC_REFLECTOR_WRAP_OVERHEAD 24
#define NOSHI_TGC_REFLECTOR_MAX_PAYLOAD 1500
#define NOSHI_TGC_REFLECTOR_MAX_DATAGRAM (NOSHI_TGC_REFLECTOR_WRAP_OVERHEAD + NOSHI_TGC_REFLECTOR_MAX_PAYLOAD + 3)
#define NOSHI_TGC_REFLECTOR_HOST_MAX 40
#define NOSHI_TGC_TCP_PROLOGUE 0xEEEEEEEEu
#define NOSHI_TGC_TCP_MAX_FRAME 65536u

typedef struct noshi_tgc_reflector {
    uint8_t server_id;
    uint8_t prefix[NOSHI_TGC_TAG_PREFIX_LEN];
    uint32_t local_tag;
    uint8_t tcp;
    uint8_t ready;
} noshi_tgc_reflector;

/* server_id from 1 to 255; the peer_tag is the 16 bytes of the connection; local_tag nonzero (NOSHI_E_ARG otherwise) */
noshi_status noshi_tgc_reflector_init(noshi_tgc_reflector *r, uint8_t server_id, const uint8_t peer_tag[NOSHI_TGC_PEER_TAG_LEN], uint32_t local_tag, int tcp);

/* the packet that makes this phone known to the server: 40 bytes over UDP, 24 over TCP (after the stream
   prologue); sent again every 500 ms until the server answers, then every 10 s */
noshi_status noshi_tgc_reflector_hello(const noshi_tgc_reflector *r, uint8_t *out, size_t capacity, size_t *len);

/* a payload for the phone with remote_tag; the packet is padded to a multiple of 4; NOSHI_E_LIMIT for a payload
   over 1500 or a buffer that is too small */
noshi_status noshi_tgc_reflector_wrap(const noshi_tgc_reflector *r, uint32_t remote_tag, const uint8_t *payload, size_t len, uint8_t *out,
                                          size_t capacity, size_t *out_len);

/* a packet from the server; NOSHI_E_MALFORMED for one too short or whose first 12 bytes are not this
   connection's */
noshi_status noshi_tgc_reflector_unwrap(noshi_tgc_reflector *r, const uint8_t *packet, size_t len, uint32_t *sender_tag, const uint8_t **payload,
                                            size_t *payload_len);

/* "reflector-<server id>-<tag>.reflector" and back; the parser accepts exactly that shape, with decimal numbers, server id 1 to 255 and tag nonzero */
noshi_status noshi_tgc_reflector_host(uint8_t server_id, uint32_t tag, char *out, size_t capacity);
noshi_status noshi_tgc_reflector_parse_host(const char *host, uint8_t *server_id, uint32_t *tag);

/* the candidate line this phone announces for the reflector, and a line of the other phone read back: "candidate:F
   1 udp P HOST PORT typ relay ..." */
noshi_status noshi_tgc_reflector_candidate_sdp(const noshi_tgc_reflector *r, uint16_t port, uint32_t priority, const char *ufrag, char *out, size_t capacity);
noshi_status noshi_tgc_reflector_parse_candidate(const char *sdp, uint8_t *server_id, uint32_t *tag, uint16_t *port, uint32_t *priority);

/* the server ids the tgcalls clients give the connections of a call */
noshi_status noshi_tgc_reflector_server_ids(const int64_t *ids, size_t count, uint8_t *out);

/* the stream form of the TCP reflector: one prologue word at the start, then each packet as a 32 bit little endian length and its bytes */
noshi_status noshi_tgc_tcp_frame(const uint8_t *packet, size_t len, int first, uint8_t *out, size_t capacity, size_t *out_len);

typedef struct noshi_tgc_tcp_reader {
    uint8_t buf[NOSHI_TGC_TCP_MAX_FRAME + 4];
    size_t used;
    size_t pending;
} noshi_tgc_tcp_reader;

/* adds stream bytes; NOSHI_E_LIMIT when more than a frame and its length can wait (the stream is broken and must be closed) */
noshi_status noshi_tgc_tcp_reader_push(noshi_tgc_tcp_reader *rd, const uint8_t *data, size_t len);
/* the next whole frame, in place in the reader's buffer until the following call of push or next; NOSHI_E_RETRY when none is complete yet, NOSHI_E_MALFORMED for a length over
   the frame limit */
noshi_status noshi_tgc_tcp_reader_next(noshi_tgc_tcp_reader *rd, const uint8_t **frame, size_t *len);

#endif
