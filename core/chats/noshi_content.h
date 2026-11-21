#ifndef NOSHI_CONTENT_H
#define NOSHI_CONTENT_H

#include <stdint.h>

#include "noshi_tl.h"

/* the content settings of the account: whether media meant for adults is shown, and whether this account may change that at all (a person who is a
   minor or whose country forbids it may not) */
typedef struct noshi_content_settings {
    uint8_t sensitive_enabled;
    uint8_t sensitive_can_change;
} noshi_content_settings;

/* account.getContentSettings */
noshi_status noshi_content_settings_request(noshi_arena *arena, noshi_tl_value **out);
/* an account.contentSettings answer; anything else is NOSHI_E_MALFORMED, and out is zero then */
noshi_status noshi_content_settings_parse(const noshi_tl_value *answer, noshi_content_settings *out);
/* account.setContentSettings: shows the sensitive media or hides it */
noshi_status noshi_content_set_request(noshi_arena *arena, int sensitive_enabled, noshi_tl_value **out);
/* the Bool it answers: NOSHI_OK for true, NOSHI_E_STATE for false, NOSHI_E_MALFORMED otherwise */
noshi_status noshi_content_set_parse(const noshi_tl_value *answer);

#endif
