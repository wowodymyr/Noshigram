#ifndef NOSHI_TCPIP_H
#define NOSHI_TCPIP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the TCP of one phone inside a tunnel: IPv4 only, client side only, no options but the segment size */

#define NOSHI_TCPIP_MAX_CONNECTIONS 32
/* each direction of a connection keeps this many bytes, which is also the largest window without the scaling option */
#define NOSHI_TCPIP_BUFFER 65536
#define NOSHI_TCPIP_MIN_MTU 576
#define NOSHI_TCPIP_MAX_MTU 1500

typedef void (*noshi_tcpip_emit)(void *context, const uint8_t *packet, size_t len);

typedef struct noshi_tcpip noshi_tcpip;

/* local_ip is the address the tunnel gave this phone; mtu from NOSHI_TCPIP_MIN_MTU to NOSHI_TCPIP_MAX_MTU is the size of the largest packet sent */
noshi_status noshi_tcpip_new(noshi_tcpip **out, uint32_t local_ip, uint16_t mtu, noshi_tcpip_emit emit, void *context);
void noshi_tcpip_free(noshi_tcpip *stack);

/* a packet that came out of the tunnel */
void noshi_tcpip_input(noshi_tcpip *stack, const uint8_t *packet, size_t len, uint64_t now_ms);

/* timers: retransmission, delayed acknowledgements, giving up */
void noshi_tcpip_tick(noshi_tcpip *stack, uint64_t now_ms);

/* whether the peer has to answer this packet of the stack: a segment that carries data, a SYN or a FIN. A bare acknowledgement, a reset and anything that is not an IPv4 TCP
   packet of a known shape are answered by nobody, except that a packet this reader cannot parse counts as one that is (the caller then keeps its older, stricter reading) */
int noshi_tcpip_packet_expects_answer(const uint8_t *packet, size_t len);

/* the connection id stays valid until released; NOSHI_E_LIMIT when all slots are taken, NOSHI_E_NOMEM,
   NOSHI_E_ARG for port 0 or address 0 */
noshi_status noshi_tcpip_connect(noshi_tcpip *stack, uint32_t remote_ip, uint16_t remote_port, uint64_t now_ms, uint32_t *id);

typedef enum noshi_tcpip_state {
    NOSHI_TCPIP_CONNECTING = 0,   /* the SYN is out */
    NOSHI_TCPIP_OPEN,             /* data may flow both ways (maybe one of them already ended) */
    NOSHI_TCPIP_DONE,             /* both directions ended and acknowledged */
    NOSHI_TCPIP_FAILED            /* reset by the peer, or no answer in time */
} noshi_tcpip_state;

typedef struct noshi_tcpip_info {
    noshi_tcpip_state state;
    size_t readable;            /* bytes waiting for noshi_tcpip_recv */
    size_t send_space;          /* bytes noshi_tcpip_send will take now */
    int peer_closed;            /* the peer's FIN arrived and everything before it was received */
    int closed_by_us;           /* noshi_tcpip_close was called */
    noshi_status error;       /* NOSHI_E_TIMEOUT, NOSHI_E_IO (reset) or NOSHI_OK */
} noshi_tcpip_info;

/* NOSHI_E_NOTFOUND for an id that is not a connection of this stack */
noshi_status noshi_tcpip_info_get(const noshi_tcpip *stack, uint32_t id, noshi_tcpip_info *info);

/* queues up to len bytes and sends what the windows allow; *accepted says how many were taken (0 when the buffer
   is full: retry after the peer acknowledges) */
noshi_status noshi_tcpip_send(noshi_tcpip *stack, uint32_t id, const uint8_t *data, size_t len, uint64_t now_ms, size_t *accepted);

/* takes what has arrived, in order; NOSHI_E_RETRY when nothing is there yet, NOSHI_E_EOF when the peer closed
   and everything was read, NOSHI_E_IO or NOSHI_E_TIMEOUT for a failed connection */
noshi_status noshi_tcpip_recv(noshi_tcpip *stack, uint32_t id, uint8_t *buf, size_t cap, uint64_t now_ms, size_t *got);

/* no more data from us: the FIN follows the queued bytes */
noshi_status noshi_tcpip_close(noshi_tcpip *stack, uint32_t id, uint64_t now_ms);

/* frees the slot */
void noshi_tcpip_release(noshi_tcpip *stack, uint32_t id, uint64_t now_ms);

typedef struct noshi_tcpip_stats {
    uint32_t segments_in, segments_out, bad_packets, retransmits, fast_retransmits, out_of_order, resets_sent;
} noshi_tcpip_stats;

void noshi_tcpip_stats_get(const noshi_tcpip *stack, noshi_tcpip_stats *stats);

#endif
