#include "noshi_group_call.h"

#include <string.h>

#include "noshi_store.h"
#include "noshi_tl_ids.h"

static void copy_text(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data = NULL;
    size_t len = 0;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static int is_vec(const noshi_tl_value *v) {
    return v && v->kind == NOSHI_TL_V_VEC;
}

static int flag(const noshi_tl_value *object, const char *name) {
    return noshi_tl_has(object, name) ? 1 : 0;
}

noshi_status noshi_group_call_ref_read(const noshi_tl_value *input, noshi_group_call_ref *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(input, NOSHI_TL_ID_inputGroupCall) || noshi_tl_get_i64(input, "id", &out->id) != NOSHI_OK ||
        noshi_tl_get_i64(input, "access_hash", &out->access_hash) != NOSHI_OK || out->id == 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    return NOSHI_OK;
}

noshi_status noshi_group_call_info_read(const noshi_tl_value *call, noshi_group_call_info *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(call, NOSHI_TL_ID_groupCallDiscarded)) {
        out->discarded = 1;
        if (noshi_tl_get_i64(call, "id", &out->ref.id) != NOSHI_OK || noshi_tl_get_i64(call, "access_hash", &out->ref.access_hash) != NOSHI_OK ||
            out->ref.id == 0) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        noshi_tl_get_i32(call, "duration", &out->duration);
        return NOSHI_OK;
    }
    if (!noshi_tl_is(call, NOSHI_TL_ID_groupCall) || noshi_tl_get_i64(call, "id", &out->ref.id) != NOSHI_OK ||
        noshi_tl_get_i64(call, "access_hash", &out->ref.access_hash) != NOSHI_OK || out->ref.id == 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    out->join_muted = (uint8_t)flag(call, "join_muted");
    out->can_change_join_muted = (uint8_t)flag(call, "can_change_join_muted");
    out->creator = (uint8_t)flag(call, "creator");
    out->rtmp_stream = (uint8_t)flag(call, "rtmp_stream");
    out->conference = (uint8_t)flag(call, "conference");
    out->can_start_video = (uint8_t)flag(call, "can_start_video");
    noshi_tl_get_i32(call, "participants_count", &out->participants_count);
    noshi_tl_get_i32(call, "version", &out->version);
    noshi_tl_get_i32(call, "schedule_date", &out->schedule_date);
    copy_text(out->title, sizeof(out->title), call, "title");
    copy_text(out->invite_link, sizeof(out->invite_link), call, "invite_link");
    return NOSHI_OK;
}

static const noshi_tl_value *find_by_id(const noshi_tl_value *vector, int64_t id) {
    uint32_t i;
    if (!is_vec(vector)) return NULL;
    for (i = 0; i < vector->u.vec.count; ++i) {
        int64_t found = 0;
        const noshi_tl_value *item = vector->u.vec.items[i];
        if (noshi_tl_get_i64(item, "id", &found) == NOSHI_OK && found == id) return item;
    }
    return NULL;
}

noshi_status noshi_group_participant_read(const noshi_tl_value *participant, const noshi_tl_value *users, const noshi_tl_value *chats,
                                              noshi_group_participant *out) {
    noshi_peer peer;
    int32_t source = 0;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(participant, NOSHI_TL_ID_groupCallParticipant) || noshi_peer_from_tl(noshi_tl_get(participant, "peer"), &peer) != NOSHI_OK ||
        peer.id <= 0 || noshi_tl_get_i32(participant, "source", &source) != NOSHI_OK) return NOSHI_E_MALFORMED;
    out->peer_kind = peer.kind;
    out->peer_id = peer.id;
    out->source = (uint32_t)source;
    noshi_tl_get_i32(participant, "date", &out->date);
    noshi_tl_get_i32(participant, "active_date", &out->active_date);
    noshi_tl_get_i32(participant, "volume", &out->volume);
    out->muted = (uint8_t)flag(participant, "muted");
    out->left = (uint8_t)flag(participant, "left");
    out->can_self_unmute = (uint8_t)flag(participant, "can_self_unmute");
    out->just_joined = (uint8_t)flag(participant, "just_joined");
    out->self = (uint8_t)flag(participant, "self");
    out->muted_by_you = (uint8_t)flag(participant, "muted_by_you");
    out->has_video = (uint8_t)flag(participant, "video");
    out->has_presentation = (uint8_t)flag(participant, "presentation");
    if (peer.kind == 1) {
        const noshi_tl_value *user = find_by_id(users, peer.id);
        noshi_person_row person;
        if (user && noshi_person_parse(user, &person) == NOSHI_OK) {
            out->access_hash = person.access_hash;
            out->deleted = person.deleted;
            out->photo = person.photo;
            memcpy(out->name, person.name, sizeof(out->name));
        }
    } else {
        const noshi_tl_value *chat = find_by_id(chats, peer.id);
        if (chat) copy_text(out->name, sizeof(out->name), chat, "title");
    }
    return NOSHI_OK;
}

noshi_status noshi_group_participants_read(const noshi_tl_value *vector, const noshi_tl_value *users, const noshi_tl_value *chats,
                                               noshi_group_participant *out, size_t cap, size_t *count) {
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!out || !count || cap == 0) return NOSHI_E_ARG;
    if (!is_vec(vector)) return NOSHI_E_MALFORMED;
    for (i = 0; i < vector->u.vec.count && n < cap; ++i) {
        if (noshi_group_participant_read(vector->u.vec.items[i], users, chats, &out[n]) == NOSHI_OK) ++n;
    }
    *count = n;
    return NOSHI_OK;
}

static void next_offset_of(const noshi_tl_value *answer, char *out, size_t cap) {
    if (out && cap) copy_text(out, cap, answer, "participants_next_offset");
}

noshi_status noshi_group_call_answer_parse(const noshi_tl_value *answer, noshi_group_call_info *info, noshi_group_participant *participants, size_t cap,
                                               size_t *count, char *next_offset, size_t offset_cap) {
    noshi_status status;
    if (count) *count = 0;
    if (next_offset && offset_cap) next_offset[0] = 0;
    if (!answer || !info || !participants || !count) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_phone_groupCall)) return NOSHI_E_MALFORMED;
    status = noshi_group_call_info_read(noshi_tl_get(answer, "call"), info);
    if (status != NOSHI_OK) return status;
    status = noshi_group_participants_read(noshi_tl_get(answer, "participants"), noshi_tl_get(answer, "users"), noshi_tl_get(answer, "chats"), participants,
                                             cap, count);
    if (status != NOSHI_OK) return status;
    next_offset_of(answer, next_offset, offset_cap);
    return NOSHI_OK;
}

noshi_status noshi_group_participants_answer_parse(const noshi_tl_value *answer, noshi_group_participant *participants, size_t cap, size_t *count,
                                                       int32_t *version, char *next_offset, size_t offset_cap) {
    noshi_status status;
    if (count) *count = 0;
    if (version) *version = 0;
    if (next_offset && offset_cap) next_offset[0] = 0;
    if (!answer || !participants || !count) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_phone_groupParticipants)) return NOSHI_E_MALFORMED;
    status = noshi_group_participants_read(noshi_tl_get(answer, "participants"), noshi_tl_get(answer, "users"), noshi_tl_get(answer, "chats"), participants,
                                             cap, count);
    if (status != NOSHI_OK) return status;
    if (version) noshi_tl_get_i32(answer, "version", version);
    if (next_offset && offset_cap) copy_text(next_offset, offset_cap, answer, "next_offset");
    return NOSHI_OK;
}

noshi_status noshi_group_update_call(const noshi_tl_value *update, noshi_group_call_info *out) {
    if (out) memset(out, 0, sizeof(*out));
    if (!out) return NOSHI_E_ARG;
    if (!noshi_tl_is(update, NOSHI_TL_ID_updateGroupCall)) return NOSHI_E_MALFORMED;
    return noshi_group_call_info_read(noshi_tl_get(update, "call"), out);
}

noshi_status noshi_group_update_participants(const noshi_tl_value *update, const noshi_tl_value *container, noshi_group_call_ref *call,
                                                 noshi_group_participant *out, size_t cap, size_t *count, int32_t *version) {
    noshi_status status;
    if (count) *count = 0;
    if (version) *version = 0;
    if (!call || !out || !count || cap == 0) return NOSHI_E_ARG;
    memset(call, 0, sizeof(*call));
    if (!noshi_tl_is(update, NOSHI_TL_ID_updateGroupCallParticipants)) return NOSHI_E_MALFORMED;
    status = noshi_group_call_ref_read(noshi_tl_get(update, "call"), call);
    if (status != NOSHI_OK) return status;
    status = noshi_group_participants_read(noshi_tl_get(update, "participants"), container ? noshi_tl_get(container, "users") : NULL,
                                             container ? noshi_tl_get(container, "chats") : NULL, out, cap, count);
    if (status != NOSHI_OK) return status;
    if (version) noshi_tl_get_i32(update, "version", version);
    return NOSHI_OK;
}

noshi_status noshi_group_update_connection(const noshi_tl_value *update, const char **json, size_t *len, int *presentation) {
    const noshi_tl_value *params;
    const uint8_t *data = NULL;
    size_t n = 0;
    if (json) *json = NULL;
    if (len) *len = 0;
    if (presentation) *presentation = 0;
    if (!json || !len) return NOSHI_E_ARG;
    if (!noshi_tl_is(update, NOSHI_TL_ID_updateGroupCallConnection)) return NOSHI_E_MALFORMED;
    params = noshi_tl_get(update, "params");
    if (!noshi_tl_is(params, NOSHI_TL_ID_dataJSON) || noshi_tl_get_bytes(params, "data", &data, &n) != NOSHI_OK || !data || n == 0) return NOSHI_E_MALFORMED;
    *json = (const char *)data;
    *len = n;
    if (presentation) *presentation = flag(update, "presentation");
    return NOSHI_OK;
}

static noshi_status input_call(noshi_arena *arena, const noshi_group_call_ref *call, noshi_tl_value **out) {
    noshi_tl_value *input;
    noshi_status status;
    *out = NULL;
    if (!arena || !call || call->id == 0) return NOSHI_E_ARG;
    input = noshi_tl_new_obj(arena, "inputGroupCall");
    if (!input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "id", call->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", call->access_hash);
    if (status == NOSHI_OK) *out = input;
    return status;
}

/* a request object of this method with its call set */
static noshi_status call_request(noshi_arena *arena, const noshi_group_call_ref *call, const char *method, noshi_tl_value **request) {
    noshi_tl_value *input = NULL;
    noshi_status status = input_call(arena, call, &input);
    *request = NULL;
    if (status != NOSHI_OK) return status;
    *request = noshi_tl_new_obj(arena, method);
    if (!*request) return NOSHI_E_NOMEM;
    return noshi_tl_set(*request, "call", input);
}

noshi_status noshi_group_call_get_request(noshi_arena *arena, const noshi_group_call_ref *call, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || limit < 0 || limit > NOSHI_GROUP_PARTICIPANTS_MAX) return NOSHI_E_ARG;
    status = call_request(arena, call, "phone.getGroupCall", &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_participants_get_request(noshi_arena *arena, const noshi_group_call_ref *call, const char *offset, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || limit <= 0 || limit > NOSHI_GROUP_PARTICIPANTS_MAX || (offset && strlen(offset) >= NOSHI_GROUP_OFFSET_MAX)) return NOSHI_E_ARG;
    status = call_request(arena, call, "phone.getGroupParticipants", &request);
    if (status == NOSHI_OK) {
        noshi_tl_value *ids = noshi_tl_new_vec(arena, 0), *sources = noshi_tl_new_vec(arena, 0);
        if (!ids || !sources) return NOSHI_E_NOMEM;
        status = noshi_tl_set(request, "ids", ids);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "sources", sources);
    }
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "offset", offset ? offset : "");
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_join_request(noshi_arena *arena, const noshi_group_call_ref *call, int muted, const char *params, size_t params_len,
                                          const char *invite_hash, noshi_tl_value **out) {
    noshi_tl_value *request, *join_as, *data;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || !params || params_len == 0 || params_len > NOSHI_GROUP_JOIN_PARAMS_MAX || memchr(params, 0, params_len) ||
        (invite_hash && (!invite_hash[0] || strlen(invite_hash) >= NOSHI_GROUP_INVITE_HASH_MAX))) return NOSHI_E_ARG;
    status = call_request(arena, call, "phone.joinGroupCall", &request);
    if (status != NOSHI_OK) return status;
    join_as = noshi_tl_new_obj(arena, "inputPeerSelf");
    data = noshi_tl_new_obj(arena, "dataJSON");
    if (!join_as || !data) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "join_as", join_as);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, data, "data", params, params_len);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "params", data);
    if (status == NOSHI_OK && muted) status = noshi_tl_set_flag(request, "muted");
    if (status == NOSHI_OK && invite_hash) status = noshi_tl_set_str(arena, request, "invite_hash", invite_hash);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_leave_request(noshi_arena *arena, const noshi_group_call_ref *call, uint32_t source, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!out) return NOSHI_E_ARG;
    status = call_request(arena, call, "phone.leaveGroupCall", &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "source", (int32_t)source);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_create_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t random_id, const char *title, noshi_tl_value **out) {
    noshi_tl_value *request, *input = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || peer->self || peer->kind < 2 || peer->kind > 3 || (title && strlen(title) >= NOSHI_GROUP_TITLE_MAX)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "phone.createGroupCall");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "random_id", random_id);
    if (status == NOSHI_OK && title && title[0]) status = noshi_tl_set_str(arena, request, "title", title);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_discard_request(noshi_arena *arena, const noshi_group_call_ref *call, noshi_tl_value **out) {
    if (out) *out = NULL;
    if (!out) return NOSHI_E_ARG;
    return call_request(arena, call, "phone.discardGroupCall", out);
}

noshi_status noshi_group_edit_request(noshi_arena *arena, const noshi_group_call_ref *call, const noshi_peer_ref *peer, int set_muted, int muted,
                                          int32_t volume, noshi_tl_value **out) {
    noshi_tl_value *request, *input = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || !peer || (!set_muted && volume == 0) || volume < 0 || volume > NOSHI_GROUP_VOLUME_MAX) return NOSHI_E_ARG;
    status = call_request(arena, call, "phone.editGroupCallParticipant", &request);
    if (status == NOSHI_OK) status = noshi_input_peer(arena, peer, &input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "participant", input);
    if (status == NOSHI_OK && set_muted) {
        noshi_tl_value *value = noshi_tl_new_obj(arena, muted ? "boolTrue" : "boolFalse");
        status = value ? noshi_tl_set(request, "muted", value) : NOSHI_E_NOMEM;
    }
    if (status == NOSHI_OK && volume) status = noshi_tl_set_i32(arena, request, "volume", volume);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_invite_link_request(noshi_arena *arena, const noshi_group_call_ref *call, int can_self_unmute, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!out) return NOSHI_E_ARG;
    status = call_request(arena, call, "phone.exportGroupCallInvite", &request);
    if (status == NOSHI_OK && can_self_unmute) status = noshi_tl_set_flag(request, "can_self_unmute");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_invite_link_parse(const noshi_tl_value *answer, char *link, size_t cap) {
    if (link && cap) link[0] = 0;
    if (!link || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_phone_exportedGroupCallInvite)) return NOSHI_E_MALFORMED;
    copy_text(link, cap, answer, "link");
    return link[0] ? NOSHI_OK : NOSHI_E_MALFORMED;
}

noshi_status noshi_group_check_request(noshi_arena *arena, const noshi_group_call_ref *call, const int32_t *sources, uint32_t count, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || !sources || count == 0 || count > NOSHI_GROUP_PARTICIPANTS_MAX) return NOSHI_E_ARG;
    status = call_request(arena, call, "phone.checkGroupCall", &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32_vec(arena, request, "sources", sources, count);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_check_parse(const noshi_tl_value *answer, int32_t source, int *present) {
    uint32_t i;
    if (present) *present = 0;
    if (!present) return NOSHI_E_ARG;
    if (!is_vec(answer)) return NOSHI_E_MALFORMED;
    for (i = 0; i < answer->u.vec.count; ++i) {
        const noshi_tl_value *item = answer->u.vec.items[i];
        if (item && item->kind == NOSHI_TL_V_I32 && item->u.i32 == source) *present = 1;
    }
    return NOSHI_OK;
}

noshi_status noshi_group_full_chat_request(noshi_arena *arena, const noshi_peer_ref *chat, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !chat || !out || chat->self || chat->id <= 0 || (chat->kind != 2 && chat->kind != 3) || (chat->kind == 3 && chat->access_hash == 0)) return NOSHI_E_ARG;
    if (chat->kind == 2) {
        request = noshi_tl_new_obj(arena, "messages.getFullChat");
        if (!request) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i64(arena, request, "chat_id", chat->id);
    } else {
        request = noshi_tl_new_obj(arena, "channels.getFullChannel");
        input = noshi_tl_new_obj(arena, "inputChannel");
        if (!request || !input) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i64(arena, input, "channel_id", chat->id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", chat->access_hash);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "channel", input);
    }
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_full_chat_call(const noshi_tl_value *answer, noshi_group_call_ref *out) {
    const noshi_tl_value *full;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chatFull)) return NOSHI_E_MALFORMED;
    full = noshi_tl_get(answer, "full_chat");
    if (!noshi_tl_is(full, NOSHI_TL_ID_chatFull) && !noshi_tl_is(full, NOSHI_TL_ID_channelFull)) return NOSHI_E_MALFORMED;
    if (!noshi_tl_has(full, "call")) return NOSHI_E_NOTFOUND;
    return noshi_group_call_ref_read(noshi_tl_get(full, "call"), out);
}

noshi_status noshi_group_updates_find_call(const noshi_tl_value *updates, noshi_group_call_info *out) {
    const noshi_tl_value *one, *list;
    uint32_t i;
    if (out) memset(out, 0, sizeof(*out));
    if (!out) return NOSHI_E_ARG;
    one = noshi_tl_get(updates, "update");
    if (noshi_tl_is(one, NOSHI_TL_ID_updateGroupCall)) return noshi_group_update_call(one, out);
    list = noshi_tl_get(updates, "updates");
    for (i = 0; is_vec(list) && i < list->u.vec.count; ++i) {
        if (noshi_tl_is(list->u.vec.items[i], NOSHI_TL_ID_updateGroupCall)) return noshi_group_update_call(list->u.vec.items[i], out);
    }
    return NOSHI_E_NOTFOUND;
}
