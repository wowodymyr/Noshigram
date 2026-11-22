#include "noshi_channel.h"

#include <string.h>

#include "noshi_store.h"
#include "noshi_tl_ids.h"

noshi_status noshi_channel_from_message_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t message_id,
                                                   int64_t channel_id, noshi_tl_value **out) {
    noshi_tl_value *input, *channel, *list, *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || message_id <= 0 || channel_id <= 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    channel = noshi_tl_new_obj(arena, "inputChannelFromMessage");
    list = noshi_tl_new_vec(arena, 1);
    request = noshi_tl_new_obj(arena, "channels.getChannels");
    if (!channel || !list || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(channel, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, channel, "msg_id", message_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "channel_id", channel_id);
    if (status == NOSHI_OK) status = noshi_tl_vec_set(list, 0, channel);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_by_id_request(noshi_arena *arena, int64_t channel_id, int64_t access_hash, noshi_tl_value **out) {
    noshi_tl_value *input, *list, *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || channel_id <= 0 || access_hash == 0) return NOSHI_E_ARG;
    input = noshi_tl_new_obj(arena, "inputChannel");
    list = noshi_tl_new_vec(arena, 1);
    request = noshi_tl_new_obj(arena, "channels.getChannels");
    if (!input || !list || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "channel_id", channel_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", access_hash);
    if (status == NOSHI_OK) status = noshi_tl_vec_set(list, 0, input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static void copy_text(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static const noshi_tl_value *find_channel(const noshi_tl_value *chats, int64_t id) {
    uint32_t i;
    for (i = 0; chats && chats->kind == NOSHI_TL_V_VEC && i < chats->u.vec.count; ++i) {
        int64_t found;
        const noshi_tl_value *chat = chats->u.vec.items[i];
        if (noshi_tl_is(chat, NOSHI_TL_ID_channel) && noshi_tl_get_i64(chat, "id", &found) == NOSHI_OK && found == id) return chat;
    }
    return NULL;
}

/* the public name: the username field, or the first active one of the usernames list a channel with several carries */
static void read_username(char *dst, size_t cap, const noshi_tl_value *channel) {
    const noshi_tl_value *names = noshi_tl_get(channel, "usernames");
    uint32_t i;
    copy_text(dst, cap, channel, "username");
    if (dst[0] || !names || names->kind != NOSHI_TL_V_VEC) return;
    for (i = 0; i < names->u.vec.count; ++i) {
        const noshi_tl_value *name = names->u.vec.items[i];
        if (noshi_tl_has(name, "active")) {
            copy_text(dst, cap, name, "username");
            if (dst[0]) return;
        }
    }
}

static void read_dialog(noshi_dialog_row *row, int64_t id, const noshi_tl_value *chats) {
    memset(row, 0, sizeof(*row));
    row->peer_kind = 3;
    row->peer_id = id;
    noshi_dialog_peer_read(row, NULL, chats, 0);
}

/* a request whose only argument is the channel */
static noshi_status channel_call(noshi_arena *arena, const noshi_peer_ref *channel, const char *method, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !channel || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return NOSHI_E_ARG;
    input = noshi_tl_new_obj(arena, "inputChannel");
    request = noshi_tl_new_obj(arena, method);
    if (!input || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "channel_id", channel->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", channel->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "channel", input);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_full_channel_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out) {
    return channel_call(arena, channel, "channels.getFullChannel", out);
}

noshi_status noshi_discussion_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t post_id, noshi_tl_value **out) {
    noshi_tl_value *input, *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !channel || !out || post_id <= 0 || channel->kind != 3) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, channel, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.getDiscussionMessage");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", post_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_discussion_parse(const noshi_tl_value *answer, int64_t channel_id, noshi_dialog_row *out) {
    const noshi_tl_value *messages, *chats;
    uint32_t i;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (channel_id <= 0 || !noshi_tl_is(answer, NOSHI_TL_ID_messages_discussionMessage)) return NOSHI_E_MALFORMED;
    messages = noshi_tl_get(answer, "messages");
    chats = noshi_tl_get(answer, "chats");
    if (!messages || messages->kind != NOSHI_TL_V_VEC) return NOSHI_E_MALFORMED;
    for (i = messages->u.vec.count; i > 0; --i) {
        const noshi_tl_value *message = messages->u.vec.items[i - 1];
        noshi_peer peer;
        int32_t id = 0;
        if (noshi_peer_from_tl(noshi_tl_get(message, "peer_id"), &peer) != NOSHI_OK || peer.kind != 3 || peer.id == channel_id ||
            noshi_tl_get_i32(message, "id", &id) != NOSHI_OK || id <= 0 || !find_channel(chats, peer.id)) continue;
        read_dialog(out, peer.id, chats);
        if (!out->peer_hash) { memset(out, 0, sizeof(*out)); return NOSHI_E_MALFORMED; }
        out->topic_id = id;
        return NOSHI_OK;
    }
    return NOSHI_E_NOTFOUND;
}

noshi_status noshi_channel_join_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out) {
    return channel_call(arena, channel, "channels.joinChannel", out);
}

noshi_status noshi_channel_join_parse(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_chatInviteJoinResultOk)) return NOSHI_OK;
    /* the channel wants a bot to verify the newcomer in a web view, which this client does not open */
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_chatInviteJoinResultWebView)) return NOSHI_E_UNSUPPORTED;
    return NOSHI_E_MALFORMED;
}

int noshi_channel_already_left(int peer_kind, const char *error_name) {
    return peer_kind == 3 && error_name && strcmp(error_name, "USER_NOT_PARTICIPANT") == 0;
}

noshi_status noshi_channel_member_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out) {
    noshi_tl_value *input, *me, *request;
    noshi_peer_ref self;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !channel || !out || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return NOSHI_E_ARG;
    memset(&self, 0, sizeof(self));
    self.kind = 1;
    self.self = 1;
    input = noshi_tl_new_obj(arena, "inputChannel");
    request = noshi_tl_new_obj(arena, "channels.getParticipant");
    if (!input || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "channel_id", channel->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", channel->access_hash);
    if (status == NOSHI_OK) status = noshi_input_peer(arena, &self, &me);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "channel", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "participant", me);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_member_parse(const noshi_tl_value *answer, int *member) {
    const noshi_tl_value *participant;
    if (member) *member = 0;
    if (!member || !noshi_tl_is(answer, NOSHI_TL_ID_channels_channelParticipant)) return NOSHI_E_MALFORMED;
    participant = noshi_tl_get(answer, "participant");
    if (noshi_tl_is(participant, NOSHI_TL_ID_channelParticipantLeft) || noshi_tl_is(participant, NOSHI_TL_ID_channelParticipantBanned)) return NOSHI_OK;
    if (noshi_tl_is(participant, NOSHI_TL_ID_channelParticipant) || noshi_tl_is(participant, NOSHI_TL_ID_channelParticipantSelf) ||
        noshi_tl_is(participant, NOSHI_TL_ID_channelParticipantCreator) || noshi_tl_is(participant, NOSHI_TL_ID_channelParticipantAdmin)) {
        *member = 1;
        return NOSHI_OK;
    }
    return NOSHI_E_MALFORMED;
}

static const struct {
    uint32_t bit;
    const char *field;
} admin_rights_table[] = {
    {NOSHI_ADMIN_CHANGE_INFO, "change_info"},
    {NOSHI_ADMIN_POST_MESSAGES, "post_messages"},
    {NOSHI_ADMIN_EDIT_MESSAGES, "edit_messages"},
    {NOSHI_ADMIN_DELETE_MESSAGES, "delete_messages"},
    {NOSHI_ADMIN_BAN_USERS, "ban_users"},
    {NOSHI_ADMIN_INVITE_USERS, "invite_users"},
    {NOSHI_ADMIN_PIN_MESSAGES, "pin_messages"},
    {NOSHI_ADMIN_ADD_ADMINS, "add_admins"},
    {NOSHI_ADMIN_MANAGE_CALL, "manage_call"},
    {NOSHI_ADMIN_ANONYMOUS, "anonymous"},
    {NOSHI_ADMIN_MANAGE_TOPICS, "manage_topics"},
};

uint32_t noshi_admin_rights_read(const noshi_tl_value *rights) {
    uint32_t bits = 0;
    size_t i;
    if (!noshi_tl_is(rights, NOSHI_TL_ID_chatAdminRights)) return 0;
    for (i = 0; i < sizeof(admin_rights_table) / sizeof(admin_rights_table[0]); ++i) {
        if (noshi_tl_has(rights, admin_rights_table[i].field)) bits |= admin_rights_table[i].bit;
    }
    return bits;
}

void noshi_chat_wallpaper_read(const noshi_tl_value *wallpaper, noshi_chat_wallpaper *out) {
    static const char *const names[4] = {"background_color", "second_background_color", "third_background_color", "fourth_background_color"};
    const noshi_tl_value *settings;
    size_t i;
    if (!out) return;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(wallpaper, NOSHI_TL_ID_wallPaper) && !noshi_tl_is(wallpaper, NOSHI_TL_ID_wallPaperNoFile)) return;
    out->present = 1;
    settings = noshi_tl_get(wallpaper, "settings");
    if (noshi_tl_is(settings, NOSHI_TL_ID_wallPaperSettings)) {
        int32_t value = 0;
        out->blur = noshi_tl_has(settings, "blur") ? 1 : 0;
        for (i = 0; i < 4; ++i) {
            if (!noshi_tl_has(settings, names[i]) || noshi_tl_get_i32(settings, names[i], &value) != NOSHI_OK) break;
            out->colors[out->color_count++] = (uint32_t)value & 0xFFFFFFu;
        }
        if (noshi_tl_get_i32(settings, "rotation", &value) == NOSHI_OK) out->rotation = value;
        if (noshi_tl_get_i32(settings, "intensity", &value) == NOSHI_OK) out->intensity = value < 0 ? -value : value;
        if (out->intensity > 100) out->intensity = 100;
    }
    if (noshi_tl_is(wallpaper, NOSHI_TL_ID_wallPaper)) {
        noshi_media_info info;
        out->pattern = noshi_tl_has(wallpaper, "pattern") ? 1 : 0;
        noshi_document_read(noshi_tl_get(wallpaper, "document"), &info);
        if (info.ref.source != NOSHI_MEDIA_SOURCE_NONE && info.size > 0) {
            out->has_file = 1;
            out->file = info.ref;
            out->file_size = info.size;
        }
    }
    /* nothing to paint: no colors and no file */
    if (!out->color_count && !out->has_file) memset(out, 0, sizeof(*out));
}

/* what a channelFull and a chatFull both carry: the description, the invite link the account sees, the mute and the pinned message */
static void read_full_common(const noshi_tl_value *full, int32_t now, noshi_full_channel *out) {
    const noshi_tl_value *invite = noshi_tl_get(full, "exported_invite"), *notify = noshi_tl_get(full, "notify_settings");
    int32_t mute_until = 0;
    copy_text(out->about, sizeof(out->about), full, "about");
    if (noshi_tl_is(invite, NOSHI_TL_ID_chatInviteExported)) copy_text(out->link, sizeof(out->link), invite, "link");
    if (notify && noshi_tl_get_i32(notify, "mute_until", &mute_until) == NOSHI_OK && mute_until > now) out->muted = 1;
    noshi_tl_get_i32(full, "pinned_msg_id", &out->pinned_message);
}

noshi_status noshi_full_channel_parse(const noshi_tl_value *answer, int64_t channel_id, int32_t now, noshi_full_channel *out) {
    const noshi_tl_value *full, *chats, *entity;
    int64_t linked = 0;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chatFull) || channel_id <= 0) return NOSHI_E_MALFORMED;
    full = noshi_tl_get(answer, "full_chat");
    chats = noshi_tl_get(answer, "chats");
    entity = find_channel(chats, channel_id);
    if (!noshi_tl_is(full, NOSHI_TL_ID_channelFull) || !entity) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    read_dialog(&out->dialog, channel_id, chats);
    out->membership_known = noshi_tl_has(entity, "min") ? 0 : 1;
    out->megagroup = noshi_tl_has(entity, "megagroup") ? 1 : 0;
    out->creator = noshi_tl_has(entity, "creator") ? 1 : 0;
    out->signatures = noshi_tl_has(entity, "signatures") ? 1 : 0;
    out->admin_rights = out->creator ? NOSHI_ADMIN_ALL : noshi_admin_rights_read(noshi_tl_get(entity, "admin_rights"));
    out->verified = noshi_tl_has(entity, "verified") ? 1 : 0;
    read_username(out->username, sizeof(out->username), entity);
    read_full_common(full, now, out);
    noshi_tl_get_i32(full, "participants_count", &out->participants);
    noshi_tl_get_i32(full, "admins_count", &out->admins);
    noshi_tl_get_i32(full, "banned_count", &out->banned);
    noshi_tl_get_i32(full, "stargifts_count", &out->gifts);
    out->can_view_stats = noshi_tl_has(full, "can_view_stats") ? 1 : 0;
    out->gifts_available = noshi_tl_has(full, "stargifts_available") ? 1 : 0;
    {
        noshi_peer chosen;
        if (noshi_peer_from_tl(noshi_tl_get(full, "default_send_as"), &chosen) == NOSHI_OK && (chosen.kind == 1 || chosen.kind == 3) && chosen.id > 0) {
            out->send_as_kind = chosen.kind;
            out->send_as_id = chosen.id;
        }
    }
    noshi_chat_wallpaper_read(noshi_tl_get(full, "wallpaper"), &out->wallpaper);
    if (noshi_tl_get_i64(full, "linked_chat_id", &linked) == NOSHI_OK && linked > 0 && find_channel(chats, linked)) {
        read_dialog(&out->linked, linked, chats);
        out->has_linked = out->linked.title[0] != 0;
    }
    return NOSHI_OK;
}

noshi_status noshi_full_chat_request(noshi_arena *arena, int64_t chat_id, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || chat_id <= 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getFullChat");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, request, "chat_id", chat_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static const noshi_tl_value *find_basic_chat(const noshi_tl_value *chats, int64_t id) {
    uint32_t i;
    for (i = 0; chats && chats->kind == NOSHI_TL_V_VEC && i < chats->u.vec.count; ++i) {
        int64_t found;
        const noshi_tl_value *chat = chats->u.vec.items[i];
        if (noshi_tl_is(chat, NOSHI_TL_ID_chat) && noshi_tl_get_i64(chat, "id", &found) == NOSHI_OK && found == id) return chat;
    }
    return NULL;
}

noshi_status noshi_full_chat_parse(const noshi_tl_value *answer, int64_t chat_id, int32_t now, noshi_full_channel *out) {
    const noshi_tl_value *full, *chats, *entity, *list, *people;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chatFull) || chat_id <= 0) return NOSHI_E_MALFORMED;
    full = noshi_tl_get(answer, "full_chat");
    chats = noshi_tl_get(answer, "chats");
    entity = find_basic_chat(chats, chat_id);
    if (!noshi_tl_is(full, NOSHI_TL_ID_chatFull) || !entity) return NOSHI_E_MALFORMED;
    out->dialog.peer_kind = 2;
    out->dialog.peer_id = chat_id;
    noshi_dialog_peer_read(&out->dialog, NULL, chats, 0);
    out->basic = 1;
    out->membership_known = 1;
    out->creator = noshi_tl_has(entity, "creator") ? 1 : 0;
    out->admin_rights = out->creator ? NOSHI_ADMIN_ALL : noshi_admin_rights_read(noshi_tl_get(entity, "admin_rights"));
    read_full_common(full, now, out);
    /* the members are listed whole in a chatParticipants; a chat the account has left gets chatParticipantsForbidden, and the chat's own count stands in */
    list = noshi_tl_get(full, "participants");
    people = noshi_tl_is(list, NOSHI_TL_ID_chatParticipants) ? noshi_tl_get(list, "participants") : NULL;
    if (people && people->kind == NOSHI_TL_V_VEC) {
        uint32_t i;
        out->participants = (int32_t)people->u.vec.count;
        for (i = 0; i < people->u.vec.count; ++i) {
            const noshi_tl_value *person = people->u.vec.items[i];
            if (noshi_tl_is(person, NOSHI_TL_ID_chatParticipantAdmin) || noshi_tl_is(person, NOSHI_TL_ID_chatParticipantCreator)) ++out->admins;
        }
    } else {
        noshi_tl_get_i32(entity, "participants_count", &out->participants);
    }
    return NOSHI_OK;
}

/* the channel, as the input channel of a request and its peer form; the access hash is required, as an unusable one is rejected by the server */
static noshi_status input_channel(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out) {
    noshi_tl_value *input;
    noshi_status status;
    *out = NULL;
    if (!arena || !channel || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return NOSHI_E_ARG;
    input = noshi_tl_new_obj(arena, "inputChannel");
    if (!input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "channel_id", channel->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", channel->access_hash);
    if (status == NOSHI_OK) *out = input;
    return status;
}

noshi_status noshi_channel_input(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out) {
    if (!out) return NOSHI_E_ARG;
    return input_channel(arena, channel, out);
}

static noshi_status input_user(noshi_arena *arena, const noshi_peer_ref *user, noshi_tl_value **out) {
    noshi_tl_value *input;
    noshi_status status;
    *out = NULL;
    if (!arena || !user || user->kind != 1 || user->id <= 0 || user->access_hash == 0) return NOSHI_E_ARG;
    input = noshi_tl_new_obj(arena, "inputUser");
    if (!input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "user_id", user->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", user->access_hash);
    if (status == NOSHI_OK) *out = input;
    return status;
}

/* a request that starts from the channel: the request object with its channel set, ready for the other arguments */
static noshi_status channel_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *method, noshi_tl_value **request) {
    noshi_tl_value *input;
    noshi_status status = input_channel(arena, channel, &input);
    *request = NULL;
    if (status != NOSHI_OK) return status;
    *request = noshi_tl_new_obj(arena, method);
    if (!*request) return NOSHI_E_NOMEM;
    return noshi_tl_set(*request, "channel", input);
}

static size_t text_length(const char *text, size_t max) {
    size_t len = 0;
    if (!text) return 0;
    while (len <= max && text[len]) ++len;
    return len;
}

noshi_status noshi_channel_members_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_member_list list, const char *query,
                                              int32_t offset, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request = NULL, *filter;
    noshi_status status;
    int has_query = query && query[0];
    if (out) *out = NULL;
    if (!out || offset < 0 || limit < 1 || limit > NOSHI_MEMBERS_MAX || text_length(query, NOSHI_MEMBERS_QUERY_MAX) > NOSHI_MEMBERS_QUERY_MAX) return NOSHI_E_ARG;
    if (list != NOSHI_MEMBERS_RECENT && list != NOSHI_MEMBERS_ADMINS && list != NOSHI_MEMBERS_KICKED) return NOSHI_E_ARG;
    status = channel_request(arena, channel, "channels.getParticipants", &request);
    if (status != NOSHI_OK) return status;
    if (list == NOSHI_MEMBERS_ADMINS) filter = noshi_tl_new_obj(arena, "channelParticipantsAdmins");
    else if (list == NOSHI_MEMBERS_KICKED) filter = noshi_tl_new_obj(arena, "channelParticipantsKicked");
    else filter = noshi_tl_new_obj(arena, has_query ? "channelParticipantsSearch" : "channelParticipantsRecent");
    if (!filter) return NOSHI_E_NOMEM;
    if (list == NOSHI_MEMBERS_KICKED || (list == NOSHI_MEMBERS_RECENT && has_query)) {
        status = noshi_tl_set_str(arena, filter, "q", has_query ? query : "");
        if (status != NOSHI_OK) return status;
    }
    status = noshi_tl_set(request, "filter", filter);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset", offset);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static const noshi_tl_value *find_user(const noshi_tl_value *users, int64_t id) {
    uint32_t i;
    for (i = 0; users && users->kind == NOSHI_TL_V_VEC && i < users->u.vec.count; ++i) {
        int64_t found;
        const noshi_tl_value *user = users->u.vec.items[i];
        if (noshi_tl_get_i64(user, "id", &found) == NOSHI_OK && found == id) return user;
    }
    return NULL;
}

/* the user a participant is about: the user_id field, or the peer of a banned one; zero for a participant that is not a user */
static int64_t participant_user(const noshi_tl_value *participant) {
    int64_t id = 0;
    const noshi_tl_value *peer;
    if (noshi_tl_get_i64(participant, "user_id", &id) == NOSHI_OK) return id;
    peer = noshi_tl_get(participant, "peer");
    if (noshi_tl_is(peer, NOSHI_TL_ID_peerUser) && noshi_tl_get_i64(peer, "user_id", &id) == NOSHI_OK) return id;
    return 0;
}

noshi_status noshi_channel_members_parse(const noshi_tl_value *answer, noshi_channel_member *rows, size_t cap, size_t *count, int32_t *total) {
    const noshi_tl_value *participants = NULL, *users;
    int32_t all = 0;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (total) *total = 0;
    if (!answer || !rows || !cap || !count || !total) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_channels_channelParticipantsNotModified)) return NOSHI_OK;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_channels_channelParticipants) || noshi_tl_get_i32(answer, "count", &all) != NOSHI_OK || all < 0 ||
        noshi_tl_get_vec(answer, "participants", &participants) != NOSHI_OK) return NOSHI_E_MALFORMED;
    users = noshi_tl_get(answer, "users");
    if (participants->u.vec.count > cap) return NOSHI_E_LIMIT;
    for (i = 0; i < participants->u.vec.count; ++i) {
        const noshi_tl_value *p = participants->u.vec.items[i], *user;
        noshi_channel_member *row = &rows[n];
        int64_t id;
        memset(row, 0, sizeof(*row));
        if (noshi_tl_is(p, NOSHI_TL_ID_channelParticipantCreator)) {
            row->role = NOSHI_MEMBER_CREATOR;
            row->rights = NOSHI_ADMIN_ALL;
        } else if (noshi_tl_is(p, NOSHI_TL_ID_channelParticipantAdmin)) {
            row->role = NOSHI_MEMBER_ADMIN;
            row->can_edit = noshi_tl_has(p, "can_edit") ? 1 : 0;
            row->rights = noshi_admin_rights_read(noshi_tl_get(p, "admin_rights"));
        } else if (noshi_tl_is(p, NOSHI_TL_ID_channelParticipantBanned)) {
            row->role = NOSHI_MEMBER_BANNED;
        } else if (noshi_tl_is(p, NOSHI_TL_ID_channelParticipant) || noshi_tl_is(p, NOSHI_TL_ID_channelParticipantSelf)) {
            row->role = NOSHI_MEMBER_PLAIN;
        } else if (noshi_tl_is(p, NOSHI_TL_ID_channelParticipantLeft)) {
            continue;
        } else {
            *count = 0;
            return NOSHI_E_MALFORMED;
        }
        row->self = noshi_tl_is(p, NOSHI_TL_ID_channelParticipantSelf) || noshi_tl_has(p, "self") ? 1 : 0;
        id = participant_user(p);
        user = id > 0 ? find_user(users, id) : NULL;
        if (!user || noshi_person_parse(user, &row->person) != NOSHI_OK) continue;
        noshi_tl_get_i32(p, "date", &row->date);
        copy_text(row->rank, sizeof(row->rank), p, "rank");
        ++n;
    }
    *count = n;
    *total = all;
    return NOSHI_OK;
}

noshi_status noshi_channel_admin_request(noshi_arena *arena, const noshi_peer_ref *channel, const noshi_peer_ref *user, uint32_t rights,
                                            const char *rank, noshi_tl_value **out) {
    noshi_tl_value *request = NULL, *input = NULL, *bits;
    noshi_status status;
    size_t i;
    if (out) *out = NULL;
    if (!out || (rights & ~NOSHI_ADMIN_ALL) || text_length(rank, NOSHI_MEMBER_RANK_MAX) >= NOSHI_MEMBER_RANK_MAX) return NOSHI_E_ARG;
    status = input_user(arena, user, &input);
    if (status != NOSHI_OK) return status;
    status = channel_request(arena, channel, "channels.editAdmin", &request);
    if (status != NOSHI_OK) return status;
    bits = noshi_tl_new_obj(arena, "chatAdminRights");
    if (!bits) return NOSHI_E_NOMEM;
    for (i = 0; i < sizeof(admin_rights_table) / sizeof(admin_rights_table[0]) && status == NOSHI_OK; ++i) {
        if (rights & admin_rights_table[i].bit) status = noshi_tl_set_flag(bits, admin_rights_table[i].field);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "user_id", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "admin_rights", bits);
    if (status == NOSHI_OK && rank && rank[0]) status = noshi_tl_set_str(arena, request, "rank", rank);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_ban_request(noshi_arena *arena, const noshi_peer_ref *channel, const noshi_peer_ref *user, int banned,
                                          noshi_tl_value **out) {
    noshi_tl_value *request = NULL, *participant = NULL, *rights;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || !user || user->kind != 1 || user->id <= 0 || user->access_hash == 0) return NOSHI_E_ARG;
    status = channel_request(arena, channel, "channels.editBanned", &request);
    if (status != NOSHI_OK) return status;
    status = noshi_input_peer(arena, user, &participant);
    if (status != NOSHI_OK) return status;
    rights = noshi_tl_new_obj(arena, "chatBannedRights");
    if (!rights) return NOSHI_E_NOMEM;
    /* until_date zero is forever; no flags at all lifts the ban */
    status = noshi_tl_set_i32(arena, rights, "until_date", 0);
    if (status == NOSHI_OK && banned) status = noshi_tl_set_flag(rights, "view_messages");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "participant", participant);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "banned_rights", rights);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_invite_request(noshi_arena *arena, const noshi_peer_ref *channel, const noshi_peer_ref *users, size_t count,
                                             noshi_tl_value **out) {
    noshi_tl_value *request = NULL, *list;
    noshi_status status;
    size_t i;
    if (out) *out = NULL;
    if (!out || !users || count == 0 || count > NOSHI_INVITE_MAX || !channel || channel->kind != 3) return NOSHI_E_ARG;
    status = channel_request(arena, channel, "channels.inviteToChannel", &request);
    if (status != NOSHI_OK) return status;
    list = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!list) return NOSHI_E_NOMEM;
    for (i = 0; i < count; ++i) {
        noshi_tl_value *input;
        status = input_user(arena, &users[i], &input);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(list, (uint32_t)i, input);
        if (status != NOSHI_OK) return status;
    }
    status = noshi_tl_set(request, "users", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_invite_missing(const noshi_tl_value *answer, size_t *missing) {
    const noshi_tl_value *list = NULL;
    if (missing) *missing = 0;
    if (!answer || !missing || !noshi_tl_is(answer, NOSHI_TL_ID_messages_invitedUsers)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "missing_invitees", &list) != NOSHI_OK) return NOSHI_E_MALFORMED;
    *missing = list->u.vec.count;
    return NOSHI_OK;
}

noshi_status noshi_channel_title_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *title, noshi_tl_value **out) {
    noshi_tl_value *request = NULL;
    noshi_status status;
    if (out) *out = NULL;
    /* the server takes 1 to 128 characters; the byte bound is the same number of ascii characters and four times as many of the widest */
    if (!out || !title || !title[0] || text_length(title, NOSHI_CHANNEL_TITLE_MAX * 4) > NOSHI_CHANNEL_TITLE_MAX * 4) return NOSHI_E_ARG;
    status = channel_request(arena, channel, "channels.editTitle", &request);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "title", title);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_about_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *about, noshi_tl_value **out) {
    noshi_tl_value *request, *peer = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || !about || !channel || channel->kind != 3 || text_length(about, NOSHI_ABOUT_MAX) >= NOSHI_ABOUT_MAX) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, channel, &peer);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.editChatAbout");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", peer);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "about", about);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_username_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *username, int check,
                                               noshi_tl_value **out) {
    noshi_tl_value *request = NULL;
    noshi_status status;
    size_t i;
    if (out) *out = NULL;
    if (!out || !username || text_length(username, NOSHI_CHANNEL_USERNAME_MAX) >= NOSHI_CHANNEL_USERNAME_MAX) return NOSHI_E_ARG;
    /* a public name is letters, digits and underscores; the server's own rules (length, a letter first) are its to apply and report */
    for (i = 0; username[i]; ++i) {
        char c = username[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) return NOSHI_E_ARG;
    }
    if (check && !username[0]) return NOSHI_E_ARG;
    status = channel_request(arena, channel, check ? "channels.checkUsername" : "channels.updateUsername", &request);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "username", username);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_signatures_request(noshi_arena *arena, const noshi_peer_ref *channel, int enabled, noshi_tl_value **out) {
    noshi_tl_value *request = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!out) return NOSHI_E_ARG;
    status = channel_request(arena, channel, "channels.toggleSignatures", &request);
    if (status == NOSHI_OK && enabled) status = noshi_tl_set_flag(request, "signatures_enabled");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_channel_bool_parse(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolTrue)) return NOSHI_OK;
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolFalse)) return NOSHI_E_STATE;
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_channel_dialog_parse(const noshi_tl_value *answer, int64_t channel_id, noshi_dialog_row *out) {
    const noshi_tl_value *chats;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chats) && !noshi_tl_is(answer, NOSHI_TL_ID_messages_chatsSlice)) return NOSHI_E_MALFORMED;
    chats = noshi_tl_get(answer, "chats");
    if (channel_id <= 0 || !find_channel(chats, channel_id)) return NOSHI_E_NOTFOUND;
    read_dialog(out, channel_id, chats);
    return NOSHI_OK;
}
