#ifndef NOSHI_PCM_RING_H
#define NOSHI_PCM_RING_H

#include <stddef.h>
#include <stdint.h>

/* a ring of 16 bit samples between exactly one writer and one reader on different threads, with no lock */

#define NOSHI_PCM_RING_SIZE 16384u

typedef struct noshi_pcm_ring {
    int16_t samples[NOSHI_PCM_RING_SIZE];
    uint32_t head;
    uint32_t tail;
} noshi_pcm_ring;

void noshi_pcm_ring_reset(noshi_pcm_ring *r);

/* samples held now */
size_t noshi_pcm_ring_fill(const noshi_pcm_ring *r);

/* writes as many of count samples as fit and returns how many it took; only the writer thread calls this */
size_t noshi_pcm_ring_write(noshi_pcm_ring *r, const int16_t *samples, size_t count);

/* reads up to count samples, returns how many it gave; only the reader thread calls this */
size_t noshi_pcm_ring_read(noshi_pcm_ring *r, int16_t *samples, size_t count);

#endif
