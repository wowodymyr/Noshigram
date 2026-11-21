#ifndef NOSHI_VOIP_BRIDGE_H
#define NOSHI_VOIP_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* the glue between the app and libtgvoip: a C face on the call engine, so the Objective-C side never meets the C++ classes. The engine
   runs its own threads, and every callback below arrives on one of them, not on the main thread */

#define NOSHI_VOIP_KEY_LEN 256
#define NOSHI_VOIP_TAG_LEN 16

/* the states libtgvoip reports, as its own numbers */
enum {
    NOSHI_VOIP_WAIT_INIT = 1,
    NOSHI_VOIP_WAIT_INIT_ACK,
    NOSHI_VOIP_ESTABLISHED,
    NOSHI_VOIP_FAILED,
    NOSHI_VOIP_RECONNECTING
};

typedef struct noshi_voip noshi_voip;

typedef struct noshi_voip_endpoint {
    int64_t id;
    uint16_t port;
    uint8_t tcp;
    char ip[48];
    char ipv6[48];
    uint8_t peer_tag[NOSHI_VOIP_TAG_LEN];
} noshi_voip_endpoint;

typedef void (*noshi_voip_state_callback)(void *context, int state);
typedef void (*noshi_voip_bars_callback)(void *context, int bars);

/* the library version the engine speaks, to name in the call protocol */
const char *noshi_voip_version(void);

/* makes an engine for one call over the endpoints with the shared key; nothing runs until noshi_voip_start. allow_p2p is the call's flag,
   max_layer the layer its protocol settled on. NULL when the arguments are unusable */
noshi_voip *noshi_voip_create(const noshi_voip_endpoint *endpoints, size_t count, const uint8_t key[NOSHI_VOIP_KEY_LEN], int outgoing,
                                  int allow_p2p, int32_t max_layer, noshi_voip_state_callback state, noshi_voip_bars_callback bars,
                                  void *context);
/* opens the audio and starts connecting */
void noshi_voip_start(noshi_voip *voip);
void noshi_voip_set_muted(noshi_voip *voip, int muted);
/* the signal bars from 1 to 4 */
int noshi_voip_bars(noshi_voip *voip);
/* the last error: 0 none, 1 incompatible, 2 timeout, 3 audio io, 4 proxy */
int noshi_voip_last_error(noshi_voip *voip);
/* the endpoint id the call settled on, zero before it did */
int64_t noshi_voip_relay_id(noshi_voip *voip);
/* stops the threads and frees the engine; it joins them, so it is not for the main thread */
void noshi_voip_destroy(noshi_voip *voip);

#ifdef __cplusplus
}
#endif

#endif
