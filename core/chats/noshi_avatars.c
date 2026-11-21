#include "noshi_avatars.h"

#include <string.h>

#include "noshi_tl_ids.h"

noshi_status noshi_user_photos_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request, *user;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !peer || limit < 1 || limit > NOSHI_AVATARS_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "photos.getUserPhotos");
    if (!request) return NOSHI_E_NOMEM;
    if (peer->self) {
        user = noshi_tl_new_obj(arena, "inputUserSelf");
        if (!user) return NOSHI_E_NOMEM;
        status = NOSHI_OK;
    } else {
        if (peer->kind != 1 || peer->id <= 0 || peer->access_hash == 0) return NOSHI_E_ARG;
        user = noshi_tl_new_obj(arena, "inputUser");
        if (!user) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i64(arena, user, "user_id", peer->id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, user, "access_hash", peer->access_hash);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "user_id", user);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "max_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* a photo the viewer can fetch has a file; photoEmpty and photos without a usable size read as no source */
static int keep_photo(const noshi_tl_value *photo, noshi_media_info *out) {
    noshi_photo_read(photo, NOSHI_AVATAR_TARGET, out);
    return out->ref.source != NOSHI_MEDIA_SOURCE_NONE;
}

noshi_status noshi_user_avatars_parse(const noshi_tl_value *answer, noshi_media_info *photos, size_t cap, size_t *count, int32_t *total) {
    const noshi_tl_value *list;
    uint32_t i;
    if (!photos || !count || !total) return NOSHI_E_ARG;
    *count = 0;
    *total = 0;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_photos_photos) && !noshi_tl_is(answer, NOSHI_TL_ID_photos_photosSlice)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "photos", &list) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (noshi_tl_is(answer, NOSHI_TL_ID_photos_photosSlice)) {
        if (noshi_tl_get_i32(answer, "count", total) != NOSHI_OK || *total < 0) {
            *total = 0;
            return NOSHI_E_MALFORMED;
        }
    } else {
        *total = (int32_t)list->u.vec.count;
    }
    for (i = 0; i < list->u.vec.count && *count < cap; ++i) {
        if (keep_photo(list->u.vec.items[i], &photos[*count])) ++*count;
    }
    return NOSHI_OK;
}

noshi_status noshi_chat_avatars_parse(const noshi_tl_value *answer, noshi_media_info *photos, size_t cap, size_t *count) {
    const noshi_tl_value *list;
    uint32_t i;
    if (!photos || !count) return NOSHI_E_ARG;
    *count = 0;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_messages) && !noshi_tl_is(answer, NOSHI_TL_ID_messages_messagesSlice) &&
        !noshi_tl_is(answer, NOSHI_TL_ID_messages_channelMessages)) {
        return NOSHI_E_MALFORMED;
    }
    if (noshi_tl_get_vec(answer, "messages", &list) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (i = 0; i < list->u.vec.count && *count < cap; ++i) {
        const noshi_tl_value *message = list->u.vec.items[i], *action;
        if (!noshi_tl_is(message, NOSHI_TL_ID_messageService)) continue;
        action = noshi_tl_get(message, "action");
        if (!noshi_tl_is(action, NOSHI_TL_ID_messageActionChatEditPhoto)) continue;
        if (keep_photo(noshi_tl_get(action, "photo"), &photos[*count])) ++*count;
    }
    return NOSHI_OK;
}
