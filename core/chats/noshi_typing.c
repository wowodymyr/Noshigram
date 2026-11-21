#include "noshi_typing.h"

#include "noshi_tl_ids.h"

#include <string.h>

noshi_status noshi_typing_request(noshi_arena *arena, const noshi_peer_ref *peer, int cancel, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *action;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || peer->topic_id < 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.setTyping");
    action = noshi_tl_new_obj(arena, cancel ? "sendMessageCancelAction" : "sendMessageTypingAction");
    if (!request || !action) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK && peer->topic_id > 1) status = noshi_tl_set_i32(arena, request, "top_msg_id", peer->topic_id);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "action", action);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static noshi_typing_action action_of(const noshi_tl_value *action) {
    if (!action || action->kind != NOSHI_TL_V_OBJ) return NOSHI_TYPING_CANCEL;
    switch (noshi_tl_id(action)) {
    case NOSHI_TL_ID_sendMessageTypingAction:
    case NOSHI_TL_ID_sendMessageTextDraftAction:
    case NOSHI_TL_ID_sendMessageRichMessageDraftAction:
        return NOSHI_TYPING_TEXT;
    case NOSHI_TL_ID_sendMessageRecordAudioAction:
    case NOSHI_TL_ID_sendMessageRecordRoundAction:
        return NOSHI_TYPING_VOICE;
    case NOSHI_TL_ID_sendMessageUploadPhotoAction:
        return NOSHI_TYPING_PHOTO;
    case NOSHI_TL_ID_sendMessageRecordVideoAction:
    case NOSHI_TL_ID_sendMessageUploadVideoAction:
    case NOSHI_TL_ID_sendMessageUploadRoundAction:
        return NOSHI_TYPING_VIDEO;
    case NOSHI_TL_ID_sendMessageUploadAudioAction:
    case NOSHI_TL_ID_sendMessageUploadDocumentAction:
        return NOSHI_TYPING_FILE;
    case NOSHI_TL_ID_sendMessageChooseStickerAction:
        return NOSHI_TYPING_STICKER;
    case NOSHI_TL_ID_sendMessageGamePlayAction:
    case NOSHI_TL_ID_sendMessageGeoLocationAction:
    case NOSHI_TL_ID_sendMessageChooseContactAction:
    case NOSHI_TL_ID_sendMessageHistoryImportAction:
        return NOSHI_TYPING_OTHER;
    default:
        /* a cancel, a stop of a draft, or an action of a newer layer: none of them shows anything */
        return NOSHI_TYPING_CANCEL;
    }
}

/* the person a Peer names; 0 when it is not a user (a channel posting as itself) */
static int64_t user_of_peer(const noshi_tl_value *peer) {
    int64_t id = 0;
    if (!peer || !noshi_tl_is(peer, NOSHI_TL_ID_peerUser) || noshi_tl_get_i64(peer, "user_id", &id) != NOSHI_OK || id <= 0) return 0;
    return id;
}

int noshi_typing_read(const noshi_tl_value *update, noshi_typing *out) {
    int64_t id = 0;
    int32_t top = 0;
    if (out) memset(out, 0, sizeof(*out));
    if (!update || !out) return 0;
    if (noshi_tl_is(update, NOSHI_TL_ID_updateUserTyping)) {
        if (noshi_tl_get_i64(update, "user_id", &id) != NOSHI_OK || id <= 0) return 0;
        out->peer_kind = 1;
        out->peer_id = id;
        out->user_id = id;
    } else if (noshi_tl_is(update, NOSHI_TL_ID_updateChatUserTyping)) {
        if (noshi_tl_get_i64(update, "chat_id", &id) != NOSHI_OK || id <= 0) return 0;
        out->peer_kind = 2;
        out->peer_id = id;
        out->user_id = user_of_peer(noshi_tl_get(update, "from_id"));
    } else if (noshi_tl_is(update, NOSHI_TL_ID_updateChannelUserTyping)) {
        if (noshi_tl_get_i64(update, "channel_id", &id) != NOSHI_OK || id <= 0) return 0;
        out->peer_kind = 3;
        out->peer_id = id;
        out->user_id = user_of_peer(noshi_tl_get(update, "from_id"));
    } else {
        return 0;
    }
    if (noshi_tl_has(update, "top_msg_id") && noshi_tl_get_i32(update, "top_msg_id", &top) == NOSHI_OK && top > 0) out->top_message = top;
    if (!noshi_tl_get(update, "action")) {
        memset(out, 0, sizeof(*out));
        return 0;
    }
    out->action = action_of(noshi_tl_get(update, "action"));
    return 1;
}
