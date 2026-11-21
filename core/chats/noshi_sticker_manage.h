#ifndef NOSHI_STICKER_MANAGE_H
#define NOSHI_STICKER_MANAGE_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_tl.h"

/* keeping the installed sticker sets of the account in order, for the Stickers and Emoji screen: taking one away
   and putting them in another order */

#define NOSHI_STICKER_ORDER_MAX 400

/* messages.installStickerSet for the set with this id and access hash, not archived; the id must be positive */
noshi_status noshi_sticker_install_request(noshi_arena *arena, int64_t id, int64_t access_hash, noshi_tl_value **out);
noshi_status noshi_sticker_install_parse(const noshi_tl_value *answer);
/* messages.uninstallStickerSet for the set with this id and access hash; the id must be positive */
noshi_status noshi_sticker_uninstall_request(noshi_arena *arena, int64_t id, int64_t access_hash, noshi_tl_value **out);
/* messages.reorderStickerSets: the ids of the sets of the account in the new order */
noshi_status noshi_sticker_reorder_request(noshi_arena *arena, const int64_t *ids, size_t count, noshi_tl_value **out);
/* the Bool either call answers: NOSHI_OK for true, NOSHI_E_STATE for false, NOSHI_E_MALFORMED otherwise */
noshi_status noshi_sticker_manage_parse(const noshi_tl_value *answer);

#endif
