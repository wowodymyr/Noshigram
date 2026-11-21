#include "noshi_translate.h"

#include <string.h>

#include "noshi_tl_ids.h"

static int valid_lang(const char *lang) {
    size_t i;
    if (!lang || !lang[0]) return 0;
    for (i = 0; lang[i]; ++i) {
        char c = lang[i];
        if (i + 1 >= NOSHI_TRANSLATE_LANG_MAX) return 0;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')) return 0;
    }
    return 1;
}

noshi_status noshi_translate_request(noshi_arena *arena, const char *text, const char *to_lang, noshi_tl_value **out) {
    noshi_tl_value *request, *item, *list;
    noshi_status status;
    size_t length;
    if (out) *out = NULL;
    if (!arena || !text || !out || !valid_lang(to_lang)) return NOSHI_E_ARG;
    length = strlen(text);
    if (!length || length > NOSHI_TRANSLATE_TEXT_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.translateText");
    item = noshi_tl_new_obj(arena, "textWithEntities");
    list = noshi_tl_new_vec(arena, 1);
    if (!request || !item || !list) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, item, "text", text);
    if (status == NOSHI_OK) status = noshi_tl_set(item, "entities", noshi_tl_new_vec(arena, 0));
    if (status == NOSHI_OK) status = noshi_tl_vec_set(list, 0, item);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "text", list);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "to_lang", to_lang);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_translate_parse(const noshi_tl_value *answer, char *out, size_t cap) {
    const noshi_tl_value *list, *item;
    const uint8_t *data;
    size_t len;
    if (!out || !cap) return NOSHI_E_ARG;
    out[0] = 0;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_translateResult)) return NOSHI_E_MALFORMED;
    list = noshi_tl_get(answer, "result");
    if (!list || list->kind != NOSHI_TL_V_VEC || list->u.vec.count < 1) return NOSHI_E_MALFORMED;
    item = list->u.vec.items[0];
    if (!noshi_tl_is(item, NOSHI_TL_ID_textWithEntities) || noshi_tl_get_bytes(item, "text", &data, &len) != NOSHI_OK || !data) return NOSHI_E_MALFORMED;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(out, data, len);
    out[len] = 0;
    return NOSHI_OK;
}
