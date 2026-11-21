#include "noshi_effects.h"

#include <string.h>

#include "noshi_tl_ids.h"

noshi_status noshi_effects_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getAvailableEffects");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_effects_parse(const noshi_tl_value *answer, noshi_effect *rows, size_t cap, size_t *count) {
    const noshi_tl_value *list, *docs = NULL;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_availableEffects)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "effects", &list) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "documents", &docs) != NOSHI_OK) docs = NULL;
    for (i = 0; i < list->u.vec.count && *count < cap; ++i) {
        const noshi_tl_value *item = list->u.vec.items[i];
        const uint8_t *emoticon;
        size_t length;
        noshi_effect *row = &rows[*count];
        if (!item || !noshi_tl_is(item, NOSHI_TL_ID_availableEffect)) continue;
        memset(row, 0, sizeof(*row));
        if (noshi_tl_get_i64(item, "id", &row->id) != NOSHI_OK || row->id == 0) continue;
        if (noshi_tl_get_bytes(item, "emoticon", &emoticon, &length) != NOSHI_OK || length == 0 || length >= sizeof(row->emoticon) || memchr(emoticon, 0, length)) continue;
        memcpy(row->emoticon, emoticon, length);
        row->emoticon[length] = 0;
        row->premium = noshi_tl_has(item, "premium_required") ? 1 : 0;
        if (noshi_tl_has(item, "static_icon_id")) noshi_tl_get_i64(item, "static_icon_id", &row->sticker_id);
        if (noshi_tl_has(item, "effect_animation_id")) noshi_tl_get_i64(item, "effect_animation_id", &row->animation_id);
        {
            int64_t sticker_id = 0;
            noshi_tl_get_i64(item, "effect_sticker_id", &sticker_id);
            if (docs) {
                uint32_t k;
                for (k = 0; k < docs->u.vec.count; ++k) {
                    const noshi_tl_value *doc = docs->u.vec.items[k];
                    int64_t doc_id = 0;
                    if (!doc || noshi_tl_get_i64(doc, "id", &doc_id) != NOSHI_OK) continue;
                    if (row->animation_id && doc_id == row->animation_id) noshi_document_picture_read(doc, "", &row->animation);
                    if (sticker_id && doc_id == sticker_id) noshi_document_picture_read(doc, "", &row->sticker);
                }
            }
        }
        ++*count;
    }
    return NOSHI_OK;
}

noshi_status noshi_set_effect(noshi_arena *arena, noshi_tl_value *request, int64_t effect) {
    if (!arena || !request || effect == 0) return NOSHI_E_ARG;
    return noshi_tl_set_i64(arena, request, "effect", effect);
}
