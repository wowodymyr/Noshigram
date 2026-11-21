#ifndef NOSHI_FLAC_H
#define NOSHI_FLAC_H

#include "noshi_status.h"

/* decodes a local FLAC to a bounded 16-bit PCM WAV, removing incomplete output on failure */
noshi_status noshi_flac_to_wav(const char *input, const char *output, int (*cancelled)(void *), void *context);

#endif
