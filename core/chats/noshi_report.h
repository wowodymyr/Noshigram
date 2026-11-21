#ifndef NOSHI_REPORT_H
#define NOSHI_REPORT_H

#include <stdint.h>

#include "noshi_messages.h"
#include "noshi_tl.h"

#define NOSHI_REPORT_MESSAGE_MAX 512

typedef enum noshi_report_reason {
    NOSHI_REPORT_SPAM,
    NOSHI_REPORT_VIOLENCE,
    NOSHI_REPORT_PORNOGRAPHY,
    NOSHI_REPORT_CHILD_ABUSE,
    NOSHI_REPORT_COPYRIGHT,
    NOSHI_REPORT_ILLEGAL_DRUGS,
    NOSHI_REPORT_PERSONAL_DETAILS,
    NOSHI_REPORT_OTHER,
    NOSHI_REPORT_REASON_COUNT
} noshi_report_reason;

/* account.reportPeer for a user, group or channel. message is the comment, at most NOSHI_REPORT_MESSAGE_MAX
   bytes (NOSHI_E_LIMIT beyond that); the server wants one for NOSHI_REPORT_OTHER, so an empty one is
   NOSHI_E_ARG there */
noshi_status noshi_report_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_report_reason reason, const char *message,
                                      noshi_tl_value **out);
/* the Bool it answers: NOSHI_OK for true, NOSHI_E_STATE for false (the server took nothing), NOSHI_E_MALFORMED otherwise */
noshi_status noshi_report_parse(const noshi_tl_value *answer);

/* messages.report is a dialogue: the first request names no option and the server answers with a list to choose
   from, each choice is sent back as the bytes it came with */
#define NOSHI_REPORT_OPTIONS_MAX 16
#define NOSHI_REPORT_OPTION_TEXT_MAX 128
#define NOSHI_REPORT_TOKEN_MAX 64
#define NOSHI_REPORT_IDS_MAX 100

typedef enum noshi_report_step {
    NOSHI_REPORT_STEP_DONE = 1,       /* the server took the report */
    NOSHI_REPORT_STEP_CHOOSE,         /* pick one of the options */
    NOSHI_REPORT_STEP_COMMENT         /* the server wants words, or takes none when comment_optional is set */
} noshi_report_step;

typedef struct noshi_report_option {
    char text[NOSHI_REPORT_OPTION_TEXT_MAX];
    uint8_t token[NOSHI_REPORT_TOKEN_MAX];
    size_t token_len;
} noshi_report_option;

typedef struct noshi_message_report_answer {
    noshi_report_step step;
    char title[NOSHI_REPORT_OPTION_TEXT_MAX];
    noshi_report_option options[NOSHI_REPORT_OPTIONS_MAX];
    size_t option_count;
    /* for STEP_COMMENT: the token the comment is sent with */
    uint8_t token[NOSHI_REPORT_TOKEN_MAX];
    size_t token_len;
    uint8_t comment_optional;
} noshi_message_report_answer;

/* messages.report of ids in one chat. token is the option picked so far (NULL or empty for the first request) */
noshi_status noshi_message_report_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                              const uint8_t *token, size_t token_len, const char *comment, noshi_tl_value **out);
/* the reportResult it answers. out is always initialised; NOSHI_E_MALFORMED for anything else or a list with no usable option */
noshi_status noshi_message_report_parse(const noshi_tl_value *answer, noshi_message_report_answer *out);

#endif
