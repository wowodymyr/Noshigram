#ifndef NOSHI_TGC_NEGOTIATE_H
#define NOSHI_TGC_NEGOTIATE_H

#include <stdint.h>

#include "noshi_status.h"
#include "noshi_tgc_signal.h"

/* the offer and answer of media channels in a tgcalls v2 call (ContentNegotiationContext of tgcalls); each side
   offers the channels it sends and answers the channels the other side offers, so a call is two independent
   negotiations */

#define NOSHI_TGC_OPUS_PAYLOAD 111
#define NOSHI_TGC_VP8_PAYLOAD 100
/* the payload numbers of the called side are shifted, as in tgcalls, so the two directions never share one by accident */
#define NOSHI_TGC_CALLEE_PAYLOAD_SHIFT 3

enum { NOSHI_TGC_STREAM_AUDIO = 0, NOSHI_TGC_STREAM_VIDEO = 1, NOSHI_TGC_STREAM_COUNT = 2 };

/* one direction of one kind of media, once it is agreed */
typedef struct noshi_tgc_stream {
    uint8_t active;
    uint32_t ssrc;
    uint8_t payload_type;
    /* video: the sender of this stream takes a picture loss indication, and a full intra request */
    uint8_t pli;
    uint8_t fir;
} noshi_tgc_stream;

typedef struct noshi_tgc_negotiator {
    uint8_t is_outgoing;
    uint8_t want_video;
    uint8_t need_offer;
    uint8_t pending;
    uint32_t pending_id;
    /* the newest offer of the other side that arrived while ours was out, which the caller does not answer until
       its own is answered */
    uint8_t has_deferred;
    noshi_tgc_negotiate deferred;
    uint32_t local_ssrc[NOSHI_TGC_STREAM_COUNT];
    /* what the other side accepted of the channels we offered, indexed by kind; what we accepted of theirs */
    noshi_tgc_stream outgoing[NOSHI_TGC_STREAM_COUNT];
    noshi_tgc_stream incoming[NOSHI_TGC_STREAM_COUNT];
    /* a change of either array happened since the owner last looked; the owner clears it */
    uint8_t changed;
} noshi_tgc_negotiator;

/* is_outgoing is true for the caller */
noshi_status noshi_tgc_negotiator_init(noshi_tgc_negotiator *n, int is_outgoing, uint32_t audio_ssrc, uint32_t video_ssrc);

/* offers or stops offering video; the next offer carries the change */
void noshi_tgc_negotiator_set_video(noshi_tgc_negotiator *n, int on);

/* true when an offer is due: a change is waiting and none is out */
int noshi_tgc_negotiator_wants_offer(const noshi_tgc_negotiator *n);

/* the next offer, with exchange_id (nonzero) as its id */
noshi_status noshi_tgc_negotiator_make_offer(noshi_tgc_negotiator *n, uint32_t exchange_id, noshi_tgc_negotiate *offer);

/* a NegotiateChannels message from the other side: the answer to our offer, or an offer of theirs. send_answer
   says whether answer holds something to send back */
noshi_status noshi_tgc_negotiator_receive(noshi_tgc_negotiator *n, const noshi_tgc_negotiate *remote, noshi_tgc_negotiate *answer,
                                              int *send_answer);

#endif
