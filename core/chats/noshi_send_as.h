#ifndef NOSHI_SEND_AS_H
#define NOSHI_SEND_AS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_dialogs.h"
#include "noshi_messages.h"
#include "noshi_tl.h"

/* the server lists at most this many; a longer list is cut here */
#define NOSHI_SEND_AS_MAX 50

/* channels.getSendAs: who the account may write as in a group or channel (itself, its channels, an anonymous admin
   identity); the peer must be a channel with its hash, or a basic group */
noshi_status noshi_send_as_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out);

/* the channels.sendAsPeers answer as one dialog row per identity, in the server's order (the account itself comes
   first there) */
noshi_status noshi_send_as_parse(const noshi_tl_value *answer, int64_t self_id, noshi_dialog_row *rows, uint8_t *premium_required, size_t cap,
                                     size_t *count);

/* sets send_as of a send request (text, media, sticker, location, contact) to this identity, which must be a user
   with its hash or a channel with its hash */
noshi_status noshi_set_send_as(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *send_as);

/* messages.saveDefaultSendAs: the identity the account writes as in that chat from now on, on every device */
noshi_status noshi_save_default_send_as_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_peer_ref *send_as,
                                                    noshi_tl_value **out);

#endif
