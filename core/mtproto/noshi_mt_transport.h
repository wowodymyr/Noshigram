#ifndef NOSHI_MT_TRANSPORT_H
#define NOSHI_MT_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_bytes.h"
#include "noshi_crypto.h"
#include "noshi_status.h"

#define NOSHI_MT_MAX_FRAME (2u * 1024u * 1024u)
#define NOSHI_MT_SECRET_LEN 16

typedef enum noshi_mt_transport_kind {
    NOSHI_MT_ABRIDGED = 1,
    NOSHI_MT_INTERMEDIATE = 2,
    NOSHI_MT_PADDED_INTERMEDIATE = 3
} noshi_mt_transport_kind;

typedef enum noshi_mt_frame_kind {
    NOSHI_MT_FRAME_DATA = 1,
    NOSHI_MT_FRAME_QUICK_ACK,
    NOSHI_MT_FRAME_ERROR
} noshi_mt_frame_kind;

typedef struct noshi_mt_frame {
    noshi_mt_frame_kind kind;
    const uint8_t *data;
    size_t len;
    uint32_t quick_ack;
    int32_t error_code;
} noshi_mt_frame;

typedef struct noshi_mt_obfuscation {
    int enabled;
    int has_secret;
    uint8_t secret[NOSHI_MT_SECRET_LEN];
    int16_t dc_id;
} noshi_mt_obfuscation;

typedef struct noshi_mt_transport {
    noshi_mt_transport_kind kind;
    int server_side;
    int synced;
    noshi_mt_obfuscation obf;
    noshi_aes_ctr *enc;
    noshi_aes_ctr *dec;
    noshi_writer rx;
    size_t rx_pos;
} noshi_mt_transport;

void noshi_mt_transport_init(noshi_mt_transport *t);
void noshi_mt_transport_free(noshi_mt_transport *t);

noshi_status noshi_mt_transport_start(noshi_mt_transport *t, noshi_mt_transport_kind kind,
                                          const noshi_mt_obfuscation *obf, noshi_writer *out);
noshi_status noshi_mt_transport_start_server(noshi_mt_transport *t, const uint8_t *secret);

noshi_status noshi_mt_transport_wrap(noshi_mt_transport *t, const uint8_t *payload, size_t len,
                                         int request_quick_ack, noshi_writer *out);
noshi_status noshi_mt_transport_feed(noshi_mt_transport *t, const uint8_t *data, size_t len);
/* returned frames alias rx, so another feed or next call can invalidate them */
noshi_status noshi_mt_transport_next(noshi_mt_transport *t, noshi_mt_frame *frame);

int noshi_mt_transport_padded(const noshi_mt_transport *t);

#endif
