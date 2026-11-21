#ifndef NOSHI_AVATARS_H
#define NOSHI_AVATARS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_media.h"
#include "noshi_messages.h"
#include "noshi_tl.h"

/* the profile photos one screen asks for; a person with more shows the newest ones */
#define NOSHI_AVATARS_MAX 40
/* the long side of the photo size picked for the full screen viewer */
#define NOSHI_AVATAR_TARGET 1280

/* photos.getUserPhotos of the user a peer names (kind 1 with an access hash, or oneself), the newest first. limit is 1 to NOSHI_AVATARS_MAX; any other
   peer or limit is NOSHI_E_ARG */
noshi_status noshi_user_photos_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t limit, noshi_tl_value **out);
/* a photos.photos or photos.photosSlice: every photo that can be fetched is put in photos (at most cap) as
   noshi_photo_read reads it at NOSHI_AVATAR_TARGET, count says how many */
noshi_status noshi_user_avatars_parse(const noshi_tl_value *answer, noshi_media_info *photos, size_t cap, size_t *count, int32_t *total);
/* a messages answer to noshi_chat_photos_request: the photo of each service message that changed the photo of
   the chat, in server order; other messages and photos that cannot be fetched are skipped */
noshi_status noshi_chat_avatars_parse(const noshi_tl_value *answer, noshi_media_info *photos, size_t cap, size_t *count);

#endif
