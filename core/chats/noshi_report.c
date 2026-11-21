#include "noshi_report.h"

#include <string.h>

#include "noshi_tl_ids.h"

static const char *const reason_names[NOSHI_REPORT_REASON_COUNT] = {
    "inputReportReasonSpam",
    "inputReportReasonViolence",
    "inputReportReasonPornography",
    "inputReportReasonChildAbuse",
    "inputReportReasonCopyright",
    "inputReportReasonIllegalDrugs",
    "inputReportReasonPersonalDetails",
    "inputReportReasonOther",
};

noshi_status noshi_report_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_report_reason reason, const char *message,
                                      noshi_tl_value **out) {
    noshi_tl_value *request, *input, *why;
    noshi_status status;
    size_t len;
    if (out) *out = NULL;
    if (!arena || !out || (unsigned)reason >= NOSHI_REPORT_REASON_COUNT) return NOSHI_E_ARG;
    if (!message) message = "";
    len = strlen(message);
    if (len > NOSHI_REPORT_MESSAGE_MAX) return NOSHI_E_LIMIT;
    if (reason == NOSHI_REPORT_OTHER && !len) return NOSHI_E_ARG;
    /* the saved messages are the account itself, which nobody reports */
    if (peer && peer->self) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "account.reportPeer");
    why = noshi_tl_new_obj(arena, reason_names[reason]);
    if (!request || !why) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "reason", why);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", message);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_report_parse(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolTrue)) return NOSHI_OK;
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolFalse)) return NOSHI_E_STATE;
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_message_report_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                              const uint8_t *token, size_t token_len, const char *comment, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !peer || !out || !ids || count == 0 || count > NOSHI_REPORT_IDS_MAX || peer->self) return NOSHI_E_ARG;
    if (!token && token_len) return NOSHI_E_ARG;
    if (token_len > NOSHI_REPORT_TOKEN_MAX) return NOSHI_E_LIMIT;
    if (!comment) comment = "";
    if (strlen(comment) > NOSHI_REPORT_MESSAGE_MAX) return NOSHI_E_LIMIT;
    for (i = 0; i < count; ++i) if (ids[i] <= 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.report");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32_vec(arena, request, "id", ids, (uint32_t)count);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, request, "option", token ? token : (const uint8_t *)"", token_len);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", comment);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* text is cut at a character boundary when it does not fit */
static void copy_text(char *dst, size_t cap, const uint8_t *data, size_t len) {
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static noshi_status read_token(const noshi_tl_value *obj, uint8_t *token, size_t *token_len) {
    const uint8_t *data;
    size_t len;
    if (noshi_tl_get_bytes(obj, "option", &data, &len) != NOSHI_OK || len > NOSHI_REPORT_TOKEN_MAX) return NOSHI_E_MALFORMED;
    if (len) memcpy(token, data, len);
    *token_len = len;
    return NOSHI_OK;
}

noshi_status noshi_message_report_parse(const noshi_tl_value *answer, noshi_message_report_answer *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(answer, NOSHI_TL_ID_reportResultReported)) {
        out->step = NOSHI_REPORT_STEP_DONE;
        return NOSHI_OK;
    }
    if (noshi_tl_is(answer, NOSHI_TL_ID_reportResultAddComment)) {
        if (read_token(answer, out->token, &out->token_len) != NOSHI_OK) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        out->step = NOSHI_REPORT_STEP_COMMENT;
        out->comment_optional = noshi_tl_has(answer, "optional") ? 1 : 0;
        return NOSHI_OK;
    }
    if (noshi_tl_is(answer, NOSHI_TL_ID_reportResultChooseOption)) {
        const noshi_tl_value *list;
        const uint8_t *data;
        size_t len, i;
        uint32_t n;
        if (noshi_tl_get_vec(answer, "options", &list) != NOSHI_OK || noshi_tl_get_bytes(answer, "title", &data, &len) != NOSHI_OK) return NOSHI_E_MALFORMED;
        copy_text(out->title, sizeof(out->title), data, len);
        n = list->u.vec.count;
        for (i = 0; i < n && out->option_count < NOSHI_REPORT_OPTIONS_MAX; ++i) {
            const noshi_tl_value *item = list->u.vec.items[i];
            noshi_report_option *option = &out->options[out->option_count];
            if (!item || noshi_tl_get_bytes(item, "text", &data, &len) != NOSHI_OK || !len) continue;
            if (read_token(item, option->token, &option->token_len) != NOSHI_OK) continue;
            copy_text(option->text, sizeof(option->text), data, len);
            ++out->option_count;
        }
        if (!out->option_count) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        out->step = NOSHI_REPORT_STEP_CHOOSE;
        return NOSHI_OK;
    }
    return NOSHI_E_MALFORMED;
}
