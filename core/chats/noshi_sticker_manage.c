#include "noshi_sticker_manage.h"

#include "noshi_tl_ids.h"

noshi_status noshi_sticker_uninstall_request(noshi_arena *arena, int64_t id, int64_t access_hash, noshi_tl_value **out) {
    noshi_tl_value *request, *set;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || id <= 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.uninstallStickerSet");
    set = noshi_tl_new_obj(arena, "inputStickerSetID");
    if (!request || !set) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, set, "id", id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, set, "access_hash", access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stickerset", set);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_sticker_install_request(noshi_arena *arena, int64_t id, int64_t access_hash, noshi_tl_value **out) {
    noshi_tl_value *request, *set;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || id <= 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.installStickerSet");
    set = noshi_tl_new_obj(arena, "inputStickerSetID");
    if (!request || !set) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, set, "id", id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, set, "access_hash", access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stickerset", set);
    /* the Bool of archived: false, the set goes into the installed ones */
    if (status == NOSHI_OK) status = noshi_tl_set(request, "archived", noshi_tl_new_obj(arena, "boolFalse"));
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_sticker_reorder_request(noshi_arena *arena, const int64_t *ids, size_t count, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    size_t i, j;
    if (out) *out = NULL;
    if (!arena || !out || !ids || count == 0 || count > NOSHI_STICKER_ORDER_MAX) return NOSHI_E_ARG;
    for (i = 0; i < count; ++i) {
        if (ids[i] <= 0) return NOSHI_E_ARG;
        for (j = 0; j < i; ++j) {
            if (ids[j] == ids[i]) return NOSHI_E_ARG;
        }
    }
    request = noshi_tl_new_obj(arena, "messages.reorderStickerSets");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64_vec(arena, request, "order", ids, (uint32_t)count);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_sticker_install_parse(const noshi_tl_value *answer) {
    /* an archived answer lists the sets that made room; the set itself is in either way */
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSetInstallResultSuccess) || noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSetInstallResultArchive)) return NOSHI_OK;
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_sticker_manage_parse(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolTrue)) return NOSHI_OK;
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolFalse)) return NOSHI_E_STATE;
    return NOSHI_E_MALFORMED;
}
