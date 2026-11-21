#include "noshi_drafts.h"

#include "noshi_store.h"
#include "noshi_tl_ids.h"

#include <string.h>

static int is_vec(const noshi_tl_value *v) {
    return v && v->kind == NOSHI_TL_V_VEC;
}

noshi_status noshi_draft_read(const noshi_tl_value *draft, int32_t topic_id, noshi_draft *out) {
    const uint8_t *text;
    size_t len;
    const noshi_tl_value *reply;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!draft) return NOSHI_E_ARG;
    if (noshi_tl_is(draft, NOSHI_TL_ID_draftMessageEmpty)) {
        /* the date is optional there and only says when the draft was cleared */
        if (noshi_tl_get_i32(draft, "date", &out->date) != NOSHI_OK) out->date = 0;
        return NOSHI_OK;
    }
    if (!noshi_tl_is(draft, NOSHI_TL_ID_draftMessage)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_bytes(draft, "message", &text, &len) != NOSHI_OK || len >= sizeof(out->text)) return NOSHI_E_MALFORMED;
    memcpy(out->text, text, len);
    out->text[len] = 0;
    if (noshi_tl_get_i32(draft, "date", &out->date) != NOSHI_OK) out->date = 0;
    out->no_webpage = noshi_tl_has(draft, "no_webpage") ? 1 : 0;
    reply = noshi_tl_get(draft, "reply_to");
    if (reply && noshi_tl_is(reply, NOSHI_TL_ID_inputReplyToMessage)) {
        int32_t id = 0;
        if (noshi_tl_get_i32(reply, "reply_to_msg_id", &id) == NOSHI_OK && id > 0 && id != topic_id) out->reply_to = id;
    }
    noshi_entities_read(draft, out->entities, NOSHI_MESSAGE_ENTITIES_MAX, out->urls, sizeof(out->urls), &out->entity_count);
    out->present = out->text[0] || out->reply_to ? 1 : 0;
    return NOSHI_OK;
}

noshi_status noshi_draft_save_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *text, const noshi_send_entity *entities,
                                          size_t entity_count, int32_t reply_to, int no_webpage, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *list = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !text || !out || reply_to < 0 || strlen(text) >= NOSHI_DRAFT_TEXT_MAX) return NOSHI_E_ARG;
    status = noshi_send_entities_build(arena, text, entities, entity_count, &list);
    if (status != NOSHI_OK) return status;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.saveDraft");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    /* a topic draft names the topic root, the way a message sent there does */
    if (status == NOSHI_OK) status = noshi_set_reply(arena, request, peer, reply_to);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", text);
    if (status == NOSHI_OK && list) status = noshi_tl_set(request, "entities", list);
    if (status == NOSHI_OK && no_webpage) status = noshi_tl_set_flag(request, "no_webpage");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_draft_update_read(const noshi_tl_value *update, int32_t *peer_kind, int64_t *peer_id, int32_t *topic_id,
                                         const noshi_tl_value **draft) {
    noshi_peer peer;
    const noshi_tl_value *body;
    int32_t top = 0;
    if (!peer_kind || !peer_id || !topic_id || !draft) return NOSHI_E_ARG;
    *peer_kind = 0;
    *peer_id = 0;
    *topic_id = 0;
    *draft = NULL;
    if (!noshi_tl_is(update, NOSHI_TL_ID_updateDraftMessage)) return NOSHI_E_UNSUPPORTED;
    if (noshi_tl_has(update, "saved_peer_id")) return NOSHI_E_UNSUPPORTED;
    if (noshi_peer_from_tl(noshi_tl_get(update, "peer"), &peer) != NOSHI_OK) return NOSHI_E_MALFORMED;
    body = noshi_tl_get(update, "draft");
    if (!body) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_i32(update, "top_msg_id", &top) != NOSHI_OK) top = 0;
    /* the General topic is the chat itself for everything the app does with threads */
    if (top < 0) return NOSHI_E_MALFORMED;
    *peer_kind = peer.kind;
    *peer_id = peer.id;
    *topic_id = top > 1 ? top : 0;
    *draft = body;
    return NOSHI_OK;
}

noshi_status noshi_draft_dialogs_visit(const noshi_tl_value *answer, noshi_draft_visit visit, void *ctx) {
    const noshi_tl_value *dialogs;
    uint32_t i;
    if (!answer || !visit) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_dialogsNotModified)) return NOSHI_OK;
    dialogs = noshi_tl_get(answer, "dialogs");
    if (!is_vec(dialogs)) return NOSHI_E_MALFORMED;
    for (i = 0; i < dialogs->u.vec.count; ++i) {
        const noshi_tl_value *dialog = dialogs->u.vec.items[i];
        noshi_peer peer;
        noshi_status status;
        if (!noshi_tl_is(dialog, NOSHI_TL_ID_dialog)) continue;
        if (noshi_peer_from_tl(noshi_tl_get(dialog, "peer"), &peer) != NOSHI_OK) continue;
        status = visit(ctx, peer.kind, peer.id, 0, noshi_tl_get(dialog, "draft"));
        if (status != NOSHI_OK) return status;
    }
    return NOSHI_OK;
}

noshi_status noshi_draft_topics_visit(const noshi_tl_value *answer, int32_t peer_kind, int64_t peer_id, noshi_draft_visit visit, void *ctx) {
    const noshi_tl_value *topics;
    uint32_t i;
    if (!answer || !visit || peer_kind != 3 || peer_id <= 0) return NOSHI_E_ARG;
    topics = noshi_tl_get(answer, "topics");
    if (!is_vec(topics)) return NOSHI_E_MALFORMED;
    for (i = 0; i < topics->u.vec.count; ++i) {
        const noshi_tl_value *topic = topics->u.vec.items[i];
        int32_t id = 0;
        noshi_status status;
        if (!noshi_tl_is(topic, NOSHI_TL_ID_forumTopic) || noshi_tl_get_i32(topic, "id", &id) != NOSHI_OK || id <= 0) continue;
        status = visit(ctx, peer_kind, peer_id, id > 1 ? id : 0, noshi_tl_get(topic, "draft"));
        if (status != NOSHI_OK) return status;
    }
    return NOSHI_OK;
}
