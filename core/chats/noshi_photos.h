#ifndef NOSHI_PHOTOS_H
#define NOSHI_PHOTOS_H

#include <stdint.h>

#include "noshi_tl.h"

/* what it takes to fetch a profile photo: where the file lives and who it belongs to */
typedef struct noshi_photo_ref {
    int64_t photo_id;       /* zero when the peer has no usable photo */
    int32_t dc;
    int32_t peer_kind;      /* 1 user, 2 chat, 3 channel, as noshi_peer */
    int64_t peer_id;
    int64_t access_hash;    /* zero for a basic group, which needs none */
} noshi_photo_ref;

/* reads the photo of a user, chat or channel object; a missing, empty or malformed photo, or a user or channel
   seen only in part (min) whose access hash cannot be used, leaves a zeroed ref and returns 0 */
int noshi_photo_ref_read(const noshi_tl_value *entity, int32_t peer_kind, int64_t peer_id, noshi_photo_ref *out);

/* an inputPeerPhotoFileLocation for the small (160 pixel) variant, built in arena */
noshi_status noshi_photo_location(noshi_arena *arena, const noshi_photo_ref *ref, noshi_tl_value **out);

#endif
