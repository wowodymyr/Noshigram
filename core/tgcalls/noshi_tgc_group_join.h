#ifndef NOSHI_TGC_GROUP_JOIN_H
#define NOSHI_TGC_GROUP_JOIN_H

#include <stddef.h>
#include <stdint.h>
#include "noshi_status.h"

/* the local transport description sent in phone.joinGroupCall */
noshi_status noshi_tgc_group_join_json(uint32_t audio_ssrc, const char *ufrag, const char *pwd,
                                          const char *fingerprint, char *out, size_t cap, size_t *len);

#define NOSHI_TGC_GROUP_CANDIDATES_MAX 32
typedef struct noshi_tgc_group_candidate {
    char ip[46];
    char protocol[8];
    char type[16];
    uint16_t port;
    uint32_t priority;
} noshi_tgc_group_candidate;

typedef struct noshi_tgc_group_transport {
    char ufrag[64];
    char pwd[128];
    char fingerprint[96];
    char setup[16];
    size_t candidate_count;
    noshi_tgc_group_candidate candidates[NOSHI_TGC_GROUP_CANDIDATES_MAX];
    /* from the "audio" part of the same answer, when it names them; the values every client has used so far otherwise */
    uint8_t audio_payload_type;     /* the Opus payload type, 111 by default */
    uint8_t audio_level_ext;        /* the id of the ssrc-audio-level header extension, 1 by default */
} noshi_tgc_group_transport;

/* the transport from updateGroupCallConnection, bounded before it reaches ICE */
noshi_status noshi_tgc_group_transport_parse(const char *json, size_t len, noshi_tgc_group_transport *out);

#endif
