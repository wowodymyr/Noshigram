#include "noshi_send_as.h"

#include <string.h>

#include "noshi_store.h"
#include "noshi_tl_ids.h"

/* a user is an input peer with its hash, a channel the same, a chat by its id alone; saved messages is the account itself */
static noshi_status identity_peer(noshi_arena *arena, const noshi_peer_ref *who, noshi_tl_value **out) {
    noshi_tl_value *input = NULL;
    noshi_status status;
    *out = NULL;
    if (!who || who->self || who->id <= 0 || who->access_hash == 0 || (who->kind != 1 && who->kind != 3)) return NOSHI_E_ARG;
    input = noshi_tl_new_obj(arena, who->kind == 1 ? "inputPeerUser" : "inputPeerChannel");
    if (!input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, who->kind == 1 ? "user_id" : "channel_id", who->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", who->access_hash);
    if (status == NOSHI_OK) *out = input;
    return status;
}

noshi_status noshi_send_as_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || peer->kind == 1 || peer->self) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "channels.getSendAs");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_send_as_parse(const noshi_tl_value *answer, int64_t self_id, noshi_dialog_row *rows, uint8_t *premium_required, size_t cap,
                                     size_t *count) {
    const noshi_tl_value *peers, *chats, *users;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !rows || !premium_required || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_channels_sendAsPeers)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "peers", &peers) != NOSHI_OK || noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (i = 0; i < peers->u.vec.count && n < cap && n < NOSHI_SEND_AS_MAX; ++i) {
        const noshi_tl_value *item = peers->u.vec.items[i];
        noshi_dialog_row *row = &rows[n];
        noshi_peer peer;
        if (!noshi_tl_is(item, NOSHI_TL_ID_sendAsPeer) || noshi_peer_from_tl(noshi_tl_get(item, "peer"), &peer) != NOSHI_OK) continue;
        if (peer.kind != 1 && peer.kind != 3) continue;
        memset(row, 0, sizeof(*row));
        row->peer_kind = peer.kind;
        row->peer_id = peer.id;
        noshi_dialog_peer_read(row, users, chats, self_id);
        if (row->deleted || !row->title[0]) continue;
        premium_required[n] = noshi_tl_has(item, "premium_required") ? 1 : 0;
        ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_set_send_as(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *send_as) {
    noshi_tl_value *input;
    noshi_status status;
    if (!arena || !request) return NOSHI_E_ARG;
    status = identity_peer(arena, send_as, &input);
    if (status != NOSHI_OK) return status;
    return noshi_tl_set(request, "send_as", input);
}

noshi_status noshi_save_default_send_as_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_peer_ref *send_as,
                                                    noshi_tl_value **out) {
    noshi_tl_value *request, *input, *identity = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !send_as || !out || peer->kind == 1 || peer->self) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    /* the account itself is the choice "as myself", which the server wants as inputPeerSelf */
    if (send_as->self) {
        identity = noshi_tl_new_obj(arena, "inputPeerSelf");
        if (!identity) return NOSHI_E_NOMEM;
    } else {
        status = identity_peer(arena, send_as, &identity);
        if (status != NOSHI_OK) return status;
    }
    request = noshi_tl_new_obj(arena, "messages.saveDefaultSendAs");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "send_as", identity);
    if (status == NOSHI_OK) *out = request;
    return status;
}
