#ifndef NOSHI_TGC_CIPHER_H
#define NOSHI_TGC_CIPHER_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the encryption of the signaling data of a tgcalls call: what travels in phone.sendSignalingData and
   updatePhoneCallSignalingData */

#define NOSHI_TGC_KEY_LEN 256
#define NOSHI_TGC_MSG_KEY_LEN 16
#define NOSHI_TGC_COUNTER_LEN 4
/* the largest plain message either side sends */
#define NOSHI_TGC_SIGNAL_MAX 16384
#define NOSHI_TGC_PACKET_MAX (NOSHI_TGC_MSG_KEY_LEN + NOSHI_TGC_COUNTER_LEN + NOSHI_TGC_SIGNAL_MAX)
/* the 22 bits of counter after the two flag bits; tgcalls masks them off an incoming counter and a sender never reaches them */
#define NOSHI_TGC_COUNTER_MAX 0x3FFFFFFFu

typedef struct noshi_tgc_cipher {
    uint8_t key[NOSHI_TGC_KEY_LEN];
    uint8_t out_shift;
    uint8_t in_shift;
    uint32_t sent;
    uint32_t highest;
    uint64_t window;
} noshi_tgc_cipher;

/* key is the 256 byte call key. is_outgoing is true on the side that placed the call */
noshi_status noshi_tgc_cipher_init(noshi_tgc_cipher *c, const uint8_t key[NOSHI_TGC_KEY_LEN], int is_outgoing);

/* writes the sealed packet of plain to out and its length to out_len; NOSHI_E_LIMIT for an empty or oversized
   message or too small a buffer, NOSHI_E_STATE once the counter is used up */
noshi_status noshi_tgc_cipher_seal(noshi_tgc_cipher *c, const uint8_t *plain, size_t plain_len, uint8_t *out, size_t capacity,
                                       size_t *out_len);

/* opens a sealed packet */
noshi_status noshi_tgc_cipher_open(noshi_tgc_cipher *c, const uint8_t *packet, size_t packet_len, uint8_t *out, size_t capacity,
                                       size_t *out_len);

void noshi_tgc_cipher_wipe(noshi_tgc_cipher *c);

#endif
