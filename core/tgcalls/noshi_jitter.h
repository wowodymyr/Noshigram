#ifndef NOSHI_JITTER_H
#define NOSHI_JITTER_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the buffer between the network and the speaker for the audio of a call: Opus packets arrive out of order, late,
   twice or not at all, and the speaker wants one in order whenever it runs low */

#define NOSHI_JITTER_SLOTS 32
#define NOSHI_JITTER_MAX_PACKET 1280
#define NOSHI_JITTER_UNDERRUN_READS 10

typedef struct noshi_jitter_slot {
    uint8_t used;
    uint16_t sequence;
    uint16_t len;
    uint8_t data[NOSHI_JITTER_MAX_PACKET];
} noshi_jitter_slot;

typedef struct noshi_jitter {
    noshi_jitter_slot slots[NOSHI_JITTER_SLOTS];
    uint16_t expected;
    uint8_t has_expected;
    uint8_t playing;
    uint8_t target;
    unsigned count;
    unsigned empty_reads;
    unsigned late;
    unsigned duplicates;
    unsigned lost;
    unsigned resets;
} noshi_jitter;

typedef enum noshi_jitter_kind {
    NOSHI_JITTER_EMPTY,   /* nothing to play: still filling, or the packets stopped */
    NOSHI_JITTER_FRAME,   /* the next packet, copied out */
    NOSHI_JITTER_LOST     /* the next packet never came; later ones did */
} noshi_jitter_kind;

/* target is the number of packets to hold before playing starts, from 1 to 16 (NOSHI_E_ARG otherwise) */
noshi_status noshi_jitter_init(noshi_jitter *j, unsigned target);

/* a packet by its sequence number */
noshi_status noshi_jitter_put(noshi_jitter *j, uint16_t sequence, const uint8_t *data, size_t len);

/* the next packet for the speaker. out takes up to capacity bytes (NOSHI_JITTER_MAX_PACKET is always enough) and len the length */
noshi_jitter_kind noshi_jitter_get(noshi_jitter *j, uint8_t *out, size_t capacity, size_t *len);

#endif
