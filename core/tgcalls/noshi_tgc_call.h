#ifndef NOSHI_TGC_CALL_H
#define NOSHI_TGC_CALL_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_dtls.h"
#include "noshi_status.h"
#include "noshi_tgc_cipher.h"
#include "noshi_tgc_ice.h"
#include "noshi_tgc_negotiate.h"
#include "noshi_tgc_sctp.h"
#include "noshi_tgc_signal.h"
#include "noshi_tgc_srtp.h"
#include "noshi_vp8_rtp.h"

/* one call over tgcalls version 7.0.0 (the "v2" protocol with the signaling in JSON), from the key to the media */

#define NOSHI_TGC_CALL_VIDEO_FRAME_MAX (256u * 1024u)
#define NOSHI_TGC_CALL_PLI_INTERVAL_MS 400
/* a call that has no media path this long after it started is given up; the reflectors did not answer, or the
   other phone cannot be reached, and waiting more only leaves the person on a screen that says connecting */
#define NOSHI_TGC_CALL_CONNECT_TIMEOUT_MS 40000
#define NOSHI_TGC_CALL_RTP_PAYLOAD_MAX 1100

typedef enum noshi_tgc_call_state {
    NOSHI_TGC_CALL_CONNECTING,    /* no media path yet */
    NOSHI_TGC_CALL_CONNECTED,     /* the media path is up and the audio channel is agreed in both directions */
    NOSHI_TGC_CALL_RECONNECTING,  /* the path went silent */
    NOSHI_TGC_CALL_FAILED         /* the handshake or the transport failed for good; the owner ends the call */
} noshi_tgc_call_state;

typedef struct noshi_tgc_call_events {
    void *context;
    /* sealed signaling bytes for phone.sendSignalingData */
    void (*send_signaling)(void *context, const uint8_t *data, size_t len);
    /* a datagram for the socket of reflector number index (the owner frames it first when that reflector is reached over TCP) */
    void (*send_datagram)(void *context, unsigned index, const uint8_t *data, size_t len);
    void (*state)(void *context, noshi_tgc_call_state state);
    /* the agreed channels changed: read them with noshi_tgc_call_streams */
    void (*streams)(void *context);
    /* the other side's mute, video state (0 inactive, 1 suspended, 2 active) and the rotation of its video in degrees */
    void (*remote_media)(void *context, int muted, int video_state, int rotation);
    /* an Opus packet of the other side, with the sequence number and the RTP timestamp (48 kHz) it carried */
    void (*audio)(void *context, const uint8_t *opus, size_t len, uint16_t sequence, uint32_t timestamp);
    /* one whole VP8 frame, valid during the call; the timestamp is the 90 kHz RTP clock */
    void (*video)(void *context, const uint8_t *frame, size_t len, int key_frame, uint32_t timestamp);
    /* the other side asks for a key frame of our video */
    void (*key_frame_requested)(void *context);
    /* optional: one line of what happens, for the log of a call; it never holds a key, a password or media */
    void (*trace)(void *context, const char *line);
} noshi_tgc_call_events;

/* a TURN server of the call: IPv4 in host order, with the credentials the server gave */
typedef struct noshi_tgc_call_turn {
    uint32_t ip;
    uint16_t port;
    char username[128];
    char password[128];
} noshi_tgc_call_turn;

typedef struct noshi_tgc_call_config {
    int is_outgoing;
    uint8_t key[NOSHI_TGC_KEY_LEN];
    int with_video;                         /* the camera is on from the start */
    noshi_tgc_ice_reflector_config reflectors[NOSHI_TGC_ICE_MAX_REFLECTORS];
    size_t reflector_count;
    /* the TURN servers, whose sockets come after the reflectors' in the numbering of datagrams: reflector_count + the position in this list */
    noshi_tgc_call_turn turns[NOSHI_TGC_ICE_MAX_TURNS];
    size_t turn_count;
} noshi_tgc_call_config;

typedef struct noshi_tgc_call noshi_tgc_call;

/* NOSHI_E_ARG for a bad configuration (no reflector, a key not given...), NOSHI_E_NOMEM, NOSHI_E_CRYPTO when the DTLS certificate cannot be made */
noshi_status noshi_tgc_call_new(noshi_tgc_call **out, const noshi_tgc_call_config *config, const noshi_tgc_call_events *events);
void noshi_tgc_call_free(noshi_tgc_call *call);

/* begins: the calling side sends its InitialSetup and its offer; both sides start saying hello to their reflectors */
noshi_status noshi_tgc_call_start(noshi_tgc_call *call, uint64_t now_ms);

/* signaling bytes that arrived in updatePhoneCallSignalingData; one that cannot be opened or read is dropped (NOSHI_E_SECURITY, NOSHI_E_MALFORMED,
   NOSHI_E_RETRY for a repeat), which is not a failure of the call */
noshi_status noshi_tgc_call_signaling(noshi_tgc_call *call, const uint8_t *data, size_t len, uint64_t now_ms);

/* a datagram that arrived at the socket of reflector number index */
noshi_status noshi_tgc_call_datagram(noshi_tgc_call *call, unsigned index, const uint8_t *data, size_t len, uint64_t now_ms);

void noshi_tgc_call_tick(noshi_tgc_call *call, uint64_t now_ms);

/* the microphone: an Opus packet of a 20 ms frame (or `samples` samples at 48 kHz); NOSHI_E_STATE until the
   audio channel is agreed and the media path is up */
noshi_status noshi_tgc_call_send_audio(noshi_tgc_call *call, const uint8_t *opus, size_t len, uint32_t samples, uint64_t now_ms);

/* the camera: one encoded VP8 frame; timestamp is the 90 kHz clock; NOSHI_E_STATE until the video channel is
   agreed and the path is up */
noshi_status noshi_tgc_call_send_video(noshi_tgc_call *call, const uint8_t *frame, size_t len, uint32_t timestamp, uint64_t now_ms);

/* asks the other side for a key frame of its video (the decoder lost its reference); at most one request per
   NOSHI_TGC_CALL_PLI_INTERVAL_MS */
noshi_status noshi_tgc_call_request_key_frame(noshi_tgc_call *call, uint64_t now_ms);

/* the camera goes on or off: the video channel is offered or withdrawn, and the media state sent */
void noshi_tgc_call_set_video(noshi_tgc_call *call, int on, int rotation, uint64_t now_ms);
void noshi_tgc_call_set_muted(noshi_tgc_call *call, int muted, uint64_t now_ms);

/* the channels agreed so far: what is sent and what is received, by kind */
void noshi_tgc_call_streams(const noshi_tgc_call *call, noshi_tgc_stream outgoing[NOSHI_TGC_STREAM_COUNT], noshi_tgc_stream incoming[NOSHI_TGC_STREAM_COUNT]);

noshi_tgc_call_state noshi_tgc_call_get_state(const noshi_tgc_call *call);
/* the stage of the path for the diagnostics: ice state, dtls state, sctp state */
void noshi_tgc_call_diagnostics(const noshi_tgc_call *call, int *ice, int *dtls, int *sctp, unsigned *signals_in, unsigned *signals_out);

#endif
