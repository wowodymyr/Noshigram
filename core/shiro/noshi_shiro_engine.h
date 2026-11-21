#ifndef NOSHI_SHIRO_ENGINE_H
#define NOSHI_SHIRO_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_warp.h"

/* a WireGuard tunnel that lives in the process: one UDP socket to the server, a TCP stack behind it, and streams
   that other parts of the program open to addresses on the far side */

typedef enum noshi_shiro_state {
    NOSHI_SHIRO_HANDSHAKING = 0,
    NOSHI_SHIRO_UP,
    NOSHI_SHIRO_DOWN
} noshi_shiro_state;

typedef struct noshi_shiro_events {
    void *context;
    /* on the engine's thread; keep it short; DOWN comes with the reason: NOSHI_E_TIMEOUT for a server that does
       not answer, NOSHI_E_SECURITY for a reply that does not authenticate */
    void (*state)(void *context, noshi_shiro_state state, noshi_status reason);
    /* one line of what the tunnel does, never with a key or with payload */
    void (*trace)(void *context, const char *line);
} noshi_shiro_events;

typedef struct noshi_shiro_stats {
    uint64_t bytes_in, bytes_out;           /* UDP payload bytes to and from the server */
    uint32_t handshakes;
    uint64_t session_age_ms;
    unsigned streams;
} noshi_shiro_stats;

typedef struct noshi_shiro_engine noshi_shiro_engine;

/* starts the thread and the first handshake with the server at endpoint_ip:endpoint_port */
noshi_status noshi_shiro_engine_start(noshi_shiro_engine **out, const noshi_warp_identity *identity, uint32_t endpoint_ip, uint16_t endpoint_port,
                                          const noshi_shiro_events *events);

/* ends everything: the streams are closed, the keys wiped, the thread joined */
void noshi_shiro_engine_stop(noshi_shiro_engine *engine);

/* a stream to ip:port (host order) on the far side, as a connected non blocking socket for the caller to use like
   any TCP socket; waits until the far side has answered or timeout_ms has passed */
noshi_status noshi_shiro_engine_open(noshi_shiro_engine *engine, uint32_t ip, uint16_t port, int timeout_ms, int *fd);

/* the same in two steps, so that the wait for the far side is not made while the caller holds the engine: dial queues the stream and returns at once with the descriptor
   to wait on and the time the wait ends; finish waits (it touches no engine, and an engine that is stopped meanwhile closes the stream, which is an error here) and
   gives the stream. a dial that succeeded must be followed by a finish */
noshi_status noshi_shiro_engine_dial(noshi_shiro_engine *engine, uint32_t ip, uint16_t port, int timeout_ms, int *wait_fd, uint64_t *deadline_ms);
noshi_status noshi_shiro_dial_finish(int wait_fd, uint64_t deadline_ms, int *fd);

/* a datagram socket for UDP through the tunnel, as a non blocking local socket for the caller to use with send and
   recv */
noshi_status noshi_shiro_engine_open_udp(noshi_shiro_engine *engine, int *fd);

noshi_shiro_state noshi_shiro_engine_state(noshi_shiro_engine *engine);
void noshi_shiro_engine_stats(noshi_shiro_engine *engine, noshi_shiro_stats *stats);

#endif
