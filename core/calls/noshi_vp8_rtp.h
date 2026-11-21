#ifndef NOSHI_VP8_RTP_H
#define NOSHI_VP8_RTP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* VP8 over RTP (RFC 7741): cutting one encoded frame into packet payloads and joining the payloads back into a
   frame */

#define NOSHI_VP8_MAX_FRAME (512u * 1024u)
#define NOSHI_VP8_MAX_PAYLOAD 1400u
#define NOSHI_VP8_MIN_PAYLOAD 16u
/* the descriptor this sender writes: the extension byte and a 15 bit picture id */
#define NOSHI_VP8_DESCRIPTOR_LEN 4u

typedef struct noshi_vp8_packetizer {
    const uint8_t *frame;
    size_t length;
    size_t offset;
    size_t max_payload;
    uint16_t picture_id;
    uint8_t non_reference;
    uint8_t started;
} noshi_vp8_packetizer;

/* frame is borrowed and must stay put until the last packet is taken. max_payload is the room of one packet for
   the descriptor and the frame bytes together */
noshi_status noshi_vp8_packetizer_init(noshi_vp8_packetizer *p, const uint8_t *frame, size_t length, size_t max_payload,
                                           uint16_t picture_id, int non_reference);

/* the next payload: descriptor then frame bytes; the frame is cut into equal parts, so no packet is a sliver.
   marker is set on the last one */
noshi_status noshi_vp8_packetizer_next(noshi_vp8_packetizer *p, uint8_t *out, size_t capacity, size_t *out_len, int *marker);

typedef struct noshi_vp8_frame_info {
    uint8_t ready;      /* a whole frame is in the storage, length bytes of it */
    uint8_t key_frame;
    size_t length;
    uint32_t timestamp;
} noshi_vp8_frame_info;

typedef struct noshi_vp8_depacketizer {
    uint8_t *frame;
    size_t capacity;
    size_t length;
    uint32_t timestamp;
    uint16_t last_sequence;
    uint8_t has_sequence;
    uint8_t in_frame;
    /* set by any loss or damage and cleared by the next complete key frame; while set no inter frame is handed out, and the
       caller should ask the sender for a key frame (a picture loss indication) */
    uint8_t need_key_frame;
    uint32_t dropped_frames;
} noshi_vp8_depacketizer;

/* storage of at least capacity bytes, up to NOSHI_VP8_MAX_FRAME, belongs to the caller */
noshi_status noshi_vp8_depacketizer_init(noshi_vp8_depacketizer *d, uint8_t *storage, size_t capacity);

/* one payload in sequence order, with the sequence, timestamp and marker of its RTP header. info is always set;
   the frame in the storage is good until the next push */
noshi_status noshi_vp8_depacketizer_push(noshi_vp8_depacketizer *d, uint16_t sequence, uint32_t timestamp, int marker,
                                             const uint8_t *payload, size_t len, noshi_vp8_frame_info *info);

#endif
