#ifndef NOSHI_CLOCK_H
#define NOSHI_CLOCK_H

#include <stdint.h>

/* injected so protocol state machines run in tests without sleeping */
typedef struct noshi_clock {
    uint64_t (*realtime_ms)(void *ctx);
    uint64_t (*monotonic_ms)(void *ctx);
    void *ctx;
} noshi_clock;

extern const noshi_clock noshi_system_clock;

#endif
