#ifndef NOSHI_TGC_GROUP_H
#define NOSHI_TGC_GROUP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_dtls.h"
#include "noshi_status.h"
#include "noshi_tgc_group_join.h"
#include "noshi_tgc_ice.h"
#include "noshi_tgc_srtp.h"

/* the media connection of one group call (a voice chat): the phone joins with phone.joinGroupCall and its transport description, the server answers with
   its candidates, fingerprint and the ids of the audio description, and from there one ICE path, one DTLS session and one SRTP context carry the audio of
   everybody. the server is ICE lite and starts the DTLS handshake itself, so this side is the controlling ICE agent and, with the setup the server names,
   the DTLS server. no socket lives here: the owner opens one connected UDP socket for each endpoint and feeds what arrives */

/* a connection that has no media path this long after the answer of the server is given up */
#define NOSHI_TGC_GROUP_CONNECT_TIMEOUT_MS 30000
#define NOSHI_TGC_GROUP_PAYLOAD_MAX 1100

typedef enum noshi_tgc_group_state {
    NOSHI_TGC_GROUP_NEW,          /* made, the server has not answered yet */
    NOSHI_TGC_GROUP_CONNECTING,   /* the answer is in; no media path yet */
    NOSHI_TGC_GROUP_CONNECTED,    /* ICE and DTLS are up, audio flows */
    NOSHI_TGC_GROUP_RECONNECTING, /* the path went silent */
    NOSHI_TGC_GROUP_FAILED        /* the handshake or the path failed for good; the owner leaves the call */
} noshi_tgc_group_state;

typedef struct noshi_tgc_group_events {
    void *context;
    /* a datagram for the socket of endpoint number index (see noshi_tgc_group_endpoint) */
    void (*send_datagram)(void *context, unsigned index, const uint8_t *data, size_t len);
    void (*state)(void *context, noshi_tgc_group_state state);
    /* an Opus packet of the source ssrc, with its sequence number and 48 kHz timestamp. level is the audio level the sender wrote into the packet, 0 (loud)
       to 127 (silent) in -dBov, and -1 when the packet has none; voice is its voice activity bit */
    void (*audio)(void *context, uint32_t ssrc, const uint8_t *opus, size_t len, uint16_t sequence, uint32_t timestamp, int level, int voice);
    /* optional: one line of what happens; never a key, a password or media */
    void (*trace)(void *context, const char *line);
} noshi_tgc_group_events;

typedef struct noshi_tgc_group noshi_tgc_group;

/* makes the connection with a random ssrc, ICE credentials and a DTLS certificate; NOSHI_E_CRYPTO when the certificate cannot be made */
noshi_status noshi_tgc_group_new(noshi_tgc_group **out, const noshi_tgc_group_events *events);
void noshi_tgc_group_free(noshi_tgc_group *group);

/* the ssrc of this phone's audio, as joined with */
uint32_t noshi_tgc_group_ssrc(const noshi_tgc_group *group);

/* the JSON for the params of phone.joinGroupCall */
noshi_status noshi_tgc_group_join_payload(const noshi_tgc_group *group, char *out, size_t capacity, size_t *len);

/* the answer of the server (updateGroupCallConnection): sets the remote credentials, the fingerprint and the DTLS role, and makes an endpoint of each IPv4 UDP
   candidate. NOSHI_E_STATE when it was applied before, NOSHI_E_UNSUPPORTED when no candidate can be used, NOSHI_E_SECURITY for a fingerprint the
   DTLS layer refuses */
noshi_status noshi_tgc_group_apply(noshi_tgc_group *group, const noshi_tgc_group_transport *transport, uint64_t now_ms);

/* the address of endpoint number index (IPv4, host order); NOSHI_E_NOTFOUND past the last one. valid after noshi_tgc_group_apply */
noshi_status noshi_tgc_group_endpoint(const noshi_tgc_group *group, unsigned index, uint32_t *ip, uint16_t *port);

/* a datagram that arrived at the socket of endpoint number index */
noshi_status noshi_tgc_group_datagram(noshi_tgc_group *group, unsigned index, const uint8_t *data, size_t len, uint64_t now_ms);

/* the timers: ICE checks, the DTLS flight, the connection timeout; every 20 to 50 ms */
void noshi_tgc_group_tick(noshi_tgc_group *group, uint64_t now_ms);

/* the microphone: one Opus packet of `samples` samples at 48 kHz, with the level of the frame (0 to 127, -dBov) and whether it holds speech;
   NOSHI_E_STATE until the media path is up */
noshi_status noshi_tgc_group_send_audio(noshi_tgc_group *group, const uint8_t *opus, size_t len, uint32_t samples, int level, int voice);

/* a source that left the call gives its place in the SRTP table back */
void noshi_tgc_group_forget(noshi_tgc_group *group, uint32_t ssrc);

noshi_tgc_group_state noshi_tgc_group_get_state(const noshi_tgc_group *group);
/* the stage of the path for the diagnostics: ice state, dtls state, packets of audio in and out */
void noshi_tgc_group_diagnostics(const noshi_tgc_group *group, int *ice, int *dtls, unsigned *audio_in, unsigned *audio_out);

#endif
