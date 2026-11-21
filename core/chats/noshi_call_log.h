#ifndef NOSHI_CALL_LOG_H
#define NOSHI_CALL_LOG_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_messages.h"
#include "noshi_people.h"
#include "noshi_status.h"
#include "noshi_tl.h"

/* the calls of the account, for the Calls tab: one row for each service message of a call, newest first, with the
   person on the other end */

#define NOSHI_CALL_LOG_MAX 100

typedef struct noshi_call_log_row {
    int32_t message_id;
    int32_t date;
    int32_t duration;           /* seconds talked, zero for a call that did not connect */
    uint8_t outgoing;
    uint8_t video;
    uint8_t outcome;            /* noshi_call_outcome */
    int64_t user_id;            /* the other person */
    int64_t access_hash;
    uint8_t deleted;
    noshi_photo_ref photo;
    char name[NOSHI_PERSON_NAME_MAX];
} noshi_call_log_row;

/* a messages.searchGlobal for phone call messages, no text, the newest limit of them (1 to NOSHI_CALL_LOG_MAX) */
noshi_status noshi_call_log_request(noshi_arena *arena, int32_t limit, noshi_tl_value **out);
/* the answer to it: only messages of a call with a person are kept, a message that cannot be read or whose person
   the answer does not carry is skipped */
noshi_status noshi_call_log_parse(const noshi_tl_value *answer, noshi_call_log_row *rows, size_t cap, size_t *count);

#endif
