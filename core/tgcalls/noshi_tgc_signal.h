#ifndef NOSHI_TGC_SIGNAL_H
#define NOSHI_TGC_SIGNAL_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the messages of the tgcalls v2 signaling (Signaling.cpp of tgcalls), read from and written as the JSON the
   official clients exchange */

#define NOSHI_TGC_MAX_CONTENTS 4
#define NOSHI_TGC_MAX_PAYLOADS 4
#define NOSHI_TGC_MAX_FEEDBACK 6
#define NOSHI_TGC_MAX_PARAMS 6
#define NOSHI_TGC_MAX_EXTENSIONS 8
#define NOSHI_TGC_MAX_GROUPS 3
#define NOSHI_TGC_MAX_GROUP_SSRCS 4
#define NOSHI_TGC_MAX_CANDIDATES 24
#define NOSHI_TGC_MAX_FINGERPRINTS 2

#define NOSHI_TGC_NAME_LEN 24
#define NOSHI_TGC_FEEDBACK_LEN 20
#define NOSHI_TGC_PARAM_KEY_LEN 32
#define NOSHI_TGC_PARAM_VALUE_LEN 64
#define NOSHI_TGC_URI_LEN 96
#define NOSHI_TGC_UFRAG_LEN 64
#define NOSHI_TGC_PWD_LEN 128
#define NOSHI_TGC_FINGERPRINT_LEN 128
#define NOSHI_TGC_CANDIDATE_LEN 384

typedef enum noshi_tgc_message_type {
    NOSHI_TGC_MESSAGE_NONE = 0,
    NOSHI_TGC_MESSAGE_INITIAL_SETUP,
    NOSHI_TGC_MESSAGE_NEGOTIATE_CHANNELS,
    NOSHI_TGC_MESSAGE_CANDIDATES,
    NOSHI_TGC_MESSAGE_MEDIA_STATE
} noshi_tgc_message_type;

typedef struct noshi_tgc_feedback {
    char type[NOSHI_TGC_FEEDBACK_LEN];
    char subtype[NOSHI_TGC_FEEDBACK_LEN];
} noshi_tgc_feedback;

typedef struct noshi_tgc_param {
    char key[NOSHI_TGC_PARAM_KEY_LEN];
    char value[NOSHI_TGC_PARAM_VALUE_LEN];
} noshi_tgc_param;

typedef struct noshi_tgc_payload {
    uint8_t id;
    char name[NOSHI_TGC_NAME_LEN];
    uint32_t clockrate;
    uint32_t channels;
    uint8_t feedback_count;
    noshi_tgc_feedback feedback[NOSHI_TGC_MAX_FEEDBACK];
    uint8_t param_count;
    noshi_tgc_param params[NOSHI_TGC_MAX_PARAMS];
} noshi_tgc_payload;

typedef struct noshi_tgc_extension {
    uint8_t id;
    char uri[NOSHI_TGC_URI_LEN];
} noshi_tgc_extension;

typedef struct noshi_tgc_ssrc_group {
    char semantics[NOSHI_TGC_NAME_LEN];
    uint8_t count;
    uint32_t ssrcs[NOSHI_TGC_MAX_GROUP_SSRCS];
} noshi_tgc_ssrc_group;

typedef struct noshi_tgc_content {
    uint8_t video;              /* 0 audio, 1 video */
    uint32_t ssrc;
    uint8_t group_count;
    noshi_tgc_ssrc_group groups[NOSHI_TGC_MAX_GROUPS];
    uint8_t payload_count;
    noshi_tgc_payload payloads[NOSHI_TGC_MAX_PAYLOADS];
    uint8_t extension_count;
    noshi_tgc_extension extensions[NOSHI_TGC_MAX_EXTENSIONS];
} noshi_tgc_content;

typedef struct noshi_tgc_fingerprint {
    char hash[NOSHI_TGC_NAME_LEN];
    char setup[NOSHI_TGC_NAME_LEN];
    char value[NOSHI_TGC_FINGERPRINT_LEN];
} noshi_tgc_fingerprint;

typedef struct noshi_tgc_initial_setup {
    char ufrag[NOSHI_TGC_UFRAG_LEN];
    char pwd[NOSHI_TGC_PWD_LEN];
    uint8_t renomination;
    uint8_t fingerprint_count;
    noshi_tgc_fingerprint fingerprints[NOSHI_TGC_MAX_FINGERPRINTS];
} noshi_tgc_initial_setup;

typedef struct noshi_tgc_negotiate {
    uint32_t exchange_id;
    uint8_t content_count;
    noshi_tgc_content contents[NOSHI_TGC_MAX_CONTENTS];
} noshi_tgc_negotiate;

typedef struct noshi_tgc_candidates {
    uint8_t count;
    char sdp[NOSHI_TGC_MAX_CANDIDATES][NOSHI_TGC_CANDIDATE_LEN];
} noshi_tgc_candidates;

typedef enum noshi_tgc_video_state {
    NOSHI_TGC_VIDEO_INACTIVE = 0,
    NOSHI_TGC_VIDEO_SUSPENDED,
    NOSHI_TGC_VIDEO_ACTIVE
} noshi_tgc_video_state;

typedef struct noshi_tgc_media_state {
    uint8_t muted;
    uint8_t low_battery;
    uint8_t video_state;        /* noshi_tgc_video_state */
    uint16_t video_rotation;    /* 0, 90, 180 or 270 degrees */
    uint8_t screencast_state;   /* noshi_tgc_video_state */
} noshi_tgc_media_state;

typedef struct noshi_tgc_message {
    noshi_tgc_message_type type;
    union {
        noshi_tgc_initial_setup initial_setup;
        noshi_tgc_negotiate negotiate;
        noshi_tgc_candidates candidates;
        noshi_tgc_media_state media_state;
    } u;
} noshi_tgc_message;

/* reads one message. out is always initialised */
noshi_status noshi_tgc_message_parse(const char *text, size_t len, noshi_tgc_message *out);

/* writes the message as JSON, NUL terminated, and the length of it to len; NOSHI_E_ARG for a message of no type
   or a value that cannot be sent (an empty ufrag, a content with ssrc 0), NOSHI_E_LIMIT when the buffer is too
   small */
noshi_status noshi_tgc_message_write(const noshi_tgc_message *message, char *out, size_t capacity, size_t *len);

#endif
