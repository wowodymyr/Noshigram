#include "noshi_name_color.h"

#include <string.h>

#include "noshi_tl_ids.h"

noshi_status noshi_name_colors_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "help.getPeerColors");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* the first color of a help.peerColorSet, as 0xRRGGBB; NOSHI_E_NOTFOUND when the set is of another kind or has none */
static noshi_status first_color(const noshi_tl_value *set, uint32_t *color) {
    const noshi_tl_value *list = NULL;
    if (!noshi_tl_is(set, NOSHI_TL_ID_help_peerColorSet) || noshi_tl_get_vec(set, "colors", &list) != NOSHI_OK || list->u.vec.count == 0 ||
        !list->u.vec.items[0] || list->u.vec.items[0]->kind != NOSHI_TL_V_I32) return NOSHI_E_NOTFOUND;
    *color = (uint32_t)list->u.vec.items[0]->u.i32 & 0xFFFFFFu;
    return NOSHI_OK;
}

noshi_status noshi_name_colors_parse(const noshi_tl_value *answer, noshi_name_color_option *rows, size_t cap, size_t *count) {
    const noshi_tl_value *options = NULL;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !rows || !cap || !count) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_help_peerColorsNotModified)) return NOSHI_OK;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_help_peerColors) || noshi_tl_get_vec(answer, "colors", &options) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (options->u.vec.count > cap) return NOSHI_E_LIMIT;
    for (i = 0; i < options->u.vec.count; ++i) {
        const noshi_tl_value *option = options->u.vec.items[i];
        noshi_name_color_option row;
        int32_t id = 0;
        memset(&row, 0, sizeof(row));
        if (!noshi_tl_is(option, NOSHI_TL_ID_help_peerColorOption) || noshi_tl_get_i32(option, "color_id", &id) != NOSHI_OK || id < 0 ||
            id > NOSHI_NAME_COLOR_MAX) continue;
        if (first_color(noshi_tl_get(option, "colors"), &row.light) != NOSHI_OK) continue;
        if (first_color(noshi_tl_get(option, "dark_colors"), &row.dark) != NOSHI_OK) row.dark = row.light;
        row.id = id;
        row.hidden = noshi_tl_has(option, "hidden") ? 1 : 0;
        rows[n++] = row;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_name_color_set_request(noshi_arena *arena, int32_t id, noshi_tl_value **out) {
    noshi_tl_value *request, *color;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || id < 0 || id > NOSHI_NAME_COLOR_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.updateColor");
    color = noshi_tl_new_obj(arena, "peerColor");
    if (!request || !color) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, color, "color", id);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "color", color);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_name_color_set_parse(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolTrue)) return NOSHI_OK;
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolFalse)) return NOSHI_E_STATE;
    return NOSHI_E_MALFORMED;
}
