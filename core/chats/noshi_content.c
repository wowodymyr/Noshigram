#include "noshi_content.h"

#include <string.h>

#include "noshi_tl_ids.h"

noshi_status noshi_content_settings_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.getContentSettings");
    if (!request) return NOSHI_E_NOMEM;
    *out = request;
    return NOSHI_OK;
}

noshi_status noshi_content_settings_parse(const noshi_tl_value *answer, noshi_content_settings *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_account_contentSettings)) return NOSHI_E_MALFORMED;
    out->sensitive_enabled = noshi_tl_has(answer, "sensitive_enabled") ? 1 : 0;
    out->sensitive_can_change = noshi_tl_has(answer, "sensitive_can_change") ? 1 : 0;
    return NOSHI_OK;
}

noshi_status noshi_content_set_request(noshi_arena *arena, int sensitive_enabled, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status = NOSHI_OK;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.setContentSettings");
    if (!request) return NOSHI_E_NOMEM;
    if (sensitive_enabled) status = noshi_tl_set_flag(request, "sensitive_enabled");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_content_set_parse(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolTrue)) return NOSHI_OK;
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolFalse)) return NOSHI_E_STATE;
    return NOSHI_E_MALFORMED;
}
