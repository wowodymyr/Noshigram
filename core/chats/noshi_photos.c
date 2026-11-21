#include "noshi_photos.h"

#include <string.h>

#include "noshi_tl_ids.h"

int noshi_photo_ref_read(const noshi_tl_value *entity, int32_t peer_kind, int64_t peer_id, noshi_photo_ref *out) {
    const noshi_tl_value *photo;
    int64_t photo_id = 0, hash = 0;
    int32_t dc = 0;
    if (!out) return 0;
    memset(out, 0, sizeof(*out));
    if (!entity || peer_id <= 0 || peer_kind < 1 || peer_kind > 3) return 0;
    photo = noshi_tl_get(entity, "photo");
    if (!noshi_tl_is(photo, NOSHI_TL_ID_userProfilePhoto) && !noshi_tl_is(photo, NOSHI_TL_ID_chatPhoto)) return 0;
    if (noshi_tl_get_i64(photo, "photo_id", &photo_id) != NOSHI_OK || photo_id <= 0 ||
        noshi_tl_get_i32(photo, "dc_id", &dc) != NOSHI_OK || dc <= 0 || dc > 1000) return 0;
    if (peer_kind != 2) {
        /* a min object comes from a mention and carries no hash that works for this account */
        if (noshi_tl_has(entity, "min") || noshi_tl_get_i64(entity, "access_hash", &hash) != NOSHI_OK) return 0;
    }
    out->photo_id = photo_id;
    out->dc = dc;
    out->peer_kind = peer_kind;
    out->peer_id = peer_id;
    out->access_hash = hash;
    return 1;
}

noshi_status noshi_photo_location(noshi_arena *arena, const noshi_photo_ref *ref, noshi_tl_value **out) {
    noshi_tl_value *location, *peer;
    noshi_status status;
    const char *ctor, *id_field;
    if (out) *out = NULL;
    if (!arena || !ref || !out || ref->photo_id <= 0) return NOSHI_E_ARG;
    if (ref->peer_kind == 1) { ctor = "inputPeerUser"; id_field = "user_id"; }
    else if (ref->peer_kind == 2) { ctor = "inputPeerChat"; id_field = "chat_id"; }
    else if (ref->peer_kind == 3) { ctor = "inputPeerChannel"; id_field = "channel_id"; }
    else return NOSHI_E_ARG;
    peer = noshi_tl_new_obj(arena, ctor);
    location = noshi_tl_new_obj(arena, "inputPeerPhotoFileLocation");
    if (!peer || !location) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, peer, id_field, ref->peer_id);
    if (status == NOSHI_OK && ref->peer_kind != 2) status = noshi_tl_set_i64(arena, peer, "access_hash", ref->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set(location, "peer", peer);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, location, "photo_id", ref->photo_id);
    if (status != NOSHI_OK) return status;
    *out = location;
    return NOSHI_OK;
}
