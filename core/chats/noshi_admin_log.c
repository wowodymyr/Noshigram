#include "noshi_admin_log.h"

#include <stdio.h>
#include <string.h>

#include "noshi_tl_ids.h"

noshi_status noshi_admin_log_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *query, int64_t max_id, int32_t limit,
                                         noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || max_id < 0 || limit < 1 || limit > NOSHI_ADMIN_LOG_PAGE) return NOSHI_E_ARG;
    if (query && strnlen(query, NOSHI_ADMIN_LOG_QUERY_MAX + 1) > NOSHI_ADMIN_LOG_QUERY_MAX) return NOSHI_E_ARG;
    status = noshi_channel_input(arena, channel, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "channels.getAdminLog");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "channel", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "q", query ? query : "");
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "max_id", max_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "min_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* copies a text field whole characters at a time; empty when the field is missing */
static void copy_text(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (!object || noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static const noshi_tl_value *find_by_id(const noshi_tl_value *list, int64_t id) {
    uint32_t i;
    for (i = 0; list && list->kind == NOSHI_TL_V_VEC && i < list->u.vec.count; ++i) {
        int64_t found;
        const noshi_tl_value *item = list->u.vec.items[i];
        if (noshi_tl_get_i64(item, "id", &found) == NOSHI_OK && found == id) return item;
    }
    return NULL;
}

/* the name of a user, or of a channel when the id belongs to one the answer lists under chats */
static int name_of(const noshi_tl_value *answer, int64_t id, char *name, size_t name_cap, char *username, size_t username_cap) {
    noshi_person_row person;
    const noshi_tl_value *object = find_by_id(noshi_tl_get(answer, "users"), id);
    noshi_status status;
    if (name) name[0] = 0;
    if (username) username[0] = 0;
    if (object) {
        status = noshi_person_parse(object, &person);
    } else {
        object = find_by_id(noshi_tl_get(answer, "chats"), id);
        if (!object) return 0;
        status = noshi_channel_person_parse(object, &person);
    }
    if (status != NOSHI_OK) return 0;
    if (name) snprintf(name, name_cap, "%s", person.name);
    if (username) snprintf(username, username_cap, "%s", person.username);
    return 1;
}

/* the user a participant is about: user_id, or the peer of a banned one */
static int64_t participant_id(const noshi_tl_value *participant) {
    int64_t id = 0;
    const noshi_tl_value *peer;
    if (noshi_tl_get_i64(participant, "user_id", &id) == NOSHI_OK) return id;
    peer = noshi_tl_get(participant, "peer");
    if (noshi_tl_is(peer, NOSHI_TL_ID_peerUser) && noshi_tl_get_i64(peer, "user_id", &id) == NOSHI_OK) return id;
    if (noshi_tl_is(peer, NOSHI_TL_ID_peerChannel) && noshi_tl_get_i64(peer, "channel_id", &id) == NOSHI_OK) return id;
    return 0;
}

static int new_value_on(const noshi_tl_value *action) {
    return noshi_tl_is(noshi_tl_get(action, "new_value"), NOSHI_TL_ID_boolTrue);
}

static void set_flag_kind(noshi_admin_event *event, const noshi_tl_value *action, noshi_admin_event_kind kind) {
    event->kind = (uint8_t)kind;
    event->flag = new_value_on(action) ? 1 : 0;
}

static void set_target(noshi_admin_event *event, const noshi_tl_value *answer, int64_t id) {
    if (id <= 0) return;
    event->target_id = id;
    event->has_target = 1;
    name_of(answer, id, event->target_name, sizeof(event->target_name), NULL, 0);
}

/* the message an event is about: its text, whether it has media, its id, and whether it is pinned */
static void read_message(noshi_admin_event *event, const noshi_tl_value *message, char *text, size_t text_cap) {
    int32_t id = 0;
    text[0] = 0;
    if (!message) return;
    noshi_tl_get_i32(message, "id", &id);
    event->message_id = id;
    copy_text(text, text_cap, message, "message");
    if (noshi_tl_has(message, "media")) event->has_media = 1;
}

/* a ban of the account's view of the chat is a removal; one that leaves the person in the chat only takes some rights */
static void read_ban(noshi_admin_event *event, const noshi_tl_value *answer, const noshi_tl_value *action) {
    const noshi_tl_value *now = noshi_tl_get(action, "new_participant");
    const noshi_tl_value *before = noshi_tl_get(action, "prev_participant");
    int64_t id = participant_id(now ? now : before);
    set_target(event, answer, id);
    if (noshi_tl_is(now, NOSHI_TL_ID_channelParticipantBanned)) {
        const noshi_tl_value *rights = noshi_tl_get(now, "banned_rights");
        event->kind = (uint8_t)(rights && noshi_tl_has(rights, "view_messages") ? NOSHI_LOG_BAN : NOSHI_LOG_RESTRICT);
    } else {
        event->kind = NOSHI_LOG_UNBAN;
    }
}

static void read_admin(noshi_admin_event *event, const noshi_tl_value *answer, const noshi_tl_value *action) {
    const noshi_tl_value *now = noshi_tl_get(action, "new_participant");
    const noshi_tl_value *before = noshi_tl_get(action, "prev_participant");
    set_target(event, answer, participant_id(now ? now : before));
    if (noshi_tl_is(now, NOSHI_TL_ID_channelParticipantAdmin) || noshi_tl_is(now, NOSHI_TL_ID_channelParticipantCreator)) {
        event->kind = (uint8_t)(noshi_tl_is(before, NOSHI_TL_ID_channelParticipantAdmin) ? NOSHI_LOG_ADMIN_RIGHTS : NOSHI_LOG_PROMOTE);
        copy_text(event->new_text, sizeof(event->new_text), now, "rank");
    } else {
        event->kind = NOSHI_LOG_DEMOTE;
    }
}

static void read_action(noshi_admin_event *event, const noshi_tl_value *answer, const noshi_tl_value *action) {
    int32_t number = 0;
    int64_t id = 0;
    switch (noshi_tl_id(action)) {
    case NOSHI_TL_ID_channelAdminLogEventActionParticipantJoin: event->kind = NOSHI_LOG_JOIN; break;
    case NOSHI_TL_ID_channelAdminLogEventActionParticipantJoinByInvite: event->kind = NOSHI_LOG_JOIN_BY_INVITE; break;
    case NOSHI_TL_ID_channelAdminLogEventActionParticipantJoinByRequest:
        event->kind = NOSHI_LOG_JOIN_BY_REQUEST;
        if (noshi_tl_get_i64(action, "approved_by", &id) == NOSHI_OK) set_target(event, answer, id);
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionParticipantLeave: event->kind = NOSHI_LOG_LEAVE; break;
    case NOSHI_TL_ID_channelAdminLogEventActionParticipantInvite:
        event->kind = NOSHI_LOG_INVITE;
        set_target(event, answer, participant_id(noshi_tl_get(action, "participant")));
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionParticipantToggleBan: read_ban(event, answer, action); break;
    case NOSHI_TL_ID_channelAdminLogEventActionParticipantToggleAdmin: read_admin(event, answer, action); break;
    case NOSHI_TL_ID_channelAdminLogEventActionParticipantEditRank:
        event->kind = NOSHI_LOG_EDIT_RANK;
        if (noshi_tl_get_i64(action, "user_id", &id) == NOSHI_OK) set_target(event, answer, id);
        copy_text(event->old_text, sizeof(event->old_text), action, "prev_rank");
        copy_text(event->new_text, sizeof(event->new_text), action, "new_rank");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionChangeTitle:
        event->kind = NOSHI_LOG_TITLE;
        copy_text(event->old_text, sizeof(event->old_text), action, "prev_value");
        copy_text(event->new_text, sizeof(event->new_text), action, "new_value");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionChangeAbout:
        event->kind = NOSHI_LOG_ABOUT;
        copy_text(event->old_text, sizeof(event->old_text), action, "prev_value");
        copy_text(event->new_text, sizeof(event->new_text), action, "new_value");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionChangeUsername:
        event->kind = NOSHI_LOG_USERNAME;
        copy_text(event->old_text, sizeof(event->old_text), action, "prev_value");
        copy_text(event->new_text, sizeof(event->new_text), action, "new_value");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionChangePhoto: event->kind = NOSHI_LOG_PHOTO; break;
    case NOSHI_TL_ID_channelAdminLogEventActionToggleInvites: set_flag_kind(event, action, NOSHI_LOG_INVITES); break;
    case NOSHI_TL_ID_channelAdminLogEventActionToggleSignatures: set_flag_kind(event, action, NOSHI_LOG_SIGNATURES); break;
    case NOSHI_TL_ID_channelAdminLogEventActionToggleSignatureProfiles: set_flag_kind(event, action, NOSHI_LOG_SIGNATURE_PROFILES); break;
    case NOSHI_TL_ID_channelAdminLogEventActionTogglePreHistoryHidden: set_flag_kind(event, action, NOSHI_LOG_HISTORY_HIDDEN); break;
    case NOSHI_TL_ID_channelAdminLogEventActionToggleNoForwards: set_flag_kind(event, action, NOSHI_LOG_NO_FORWARDS); break;
    case NOSHI_TL_ID_channelAdminLogEventActionToggleForum: set_flag_kind(event, action, NOSHI_LOG_FORUM); break;
    case NOSHI_TL_ID_channelAdminLogEventActionToggleAntiSpam: set_flag_kind(event, action, NOSHI_LOG_ANTI_SPAM); break;
    case NOSHI_TL_ID_channelAdminLogEventActionToggleSlowMode:
        event->kind = NOSHI_LOG_SLOW_MODE;
        if (noshi_tl_get_i32(action, "new_value", &number) == NOSHI_OK) event->new_number = number;
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionChangeHistoryTTL:
        event->kind = NOSHI_LOG_HISTORY_TTL;
        if (noshi_tl_get_i32(action, "new_value", &number) == NOSHI_OK) event->new_number = number;
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionChangeLinkedChat:
        event->kind = NOSHI_LOG_LINKED_CHAT;
        if (noshi_tl_get_i64(action, "new_value", &id) == NOSHI_OK && id > 0) {
            event->flag = 1;
            set_target(event, answer, id);
        }
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionDefaultBannedRights: event->kind = NOSHI_LOG_DEFAULT_RIGHTS; break;
    case NOSHI_TL_ID_channelAdminLogEventActionUpdatePinned: {
        const noshi_tl_value *message = noshi_tl_get(action, "message");
        event->kind = (uint8_t)(message && noshi_tl_has(message, "pinned") ? NOSHI_LOG_PIN : NOSHI_LOG_UNPIN);
        read_message(event, message, event->new_text, sizeof(event->new_text));
        break;
    }
    case NOSHI_TL_ID_channelAdminLogEventActionEditMessage:
        event->kind = NOSHI_LOG_EDIT_MESSAGE;
        read_message(event, noshi_tl_get(action, "new_message"), event->new_text, sizeof(event->new_text));
        copy_text(event->old_text, sizeof(event->old_text), noshi_tl_get(action, "prev_message"), "message");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionDeleteMessage:
        event->kind = NOSHI_LOG_DELETE_MESSAGE;
        read_message(event, noshi_tl_get(action, "message"), event->old_text, sizeof(event->old_text));
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionSendMessage:
        event->kind = NOSHI_LOG_SEND_MESSAGE;
        read_message(event, noshi_tl_get(action, "message"), event->new_text, sizeof(event->new_text));
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionStopPoll:
        event->kind = NOSHI_LOG_STOP_POLL;
        read_message(event, noshi_tl_get(action, "message"), event->new_text, sizeof(event->new_text));
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionStartGroupCall: event->kind = NOSHI_LOG_CALL_START; break;
    case NOSHI_TL_ID_channelAdminLogEventActionDiscardGroupCall: event->kind = NOSHI_LOG_CALL_END; break;
    case NOSHI_TL_ID_channelAdminLogEventActionCreateTopic:
        event->kind = NOSHI_LOG_TOPIC_CREATE;
        copy_text(event->new_text, sizeof(event->new_text), noshi_tl_get(action, "topic"), "title");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionEditTopic:
        event->kind = NOSHI_LOG_TOPIC_EDIT;
        copy_text(event->old_text, sizeof(event->old_text), noshi_tl_get(action, "prev_topic"), "title");
        copy_text(event->new_text, sizeof(event->new_text), noshi_tl_get(action, "new_topic"), "title");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionDeleteTopic:
        event->kind = NOSHI_LOG_TOPIC_DELETE;
        copy_text(event->old_text, sizeof(event->old_text), noshi_tl_get(action, "topic"), "title");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionExportedInviteRevoke:
        event->kind = NOSHI_LOG_INVITE_REVOKE;
        copy_text(event->new_text, sizeof(event->new_text), noshi_tl_get(action, "invite"), "link");
        break;
    case NOSHI_TL_ID_channelAdminLogEventActionExportedInviteDelete:
        event->kind = NOSHI_LOG_INVITE_DELETE;
        copy_text(event->new_text, sizeof(event->new_text), noshi_tl_get(action, "invite"), "link");
        break;
    default: event->kind = NOSHI_LOG_OTHER; break;
    }
}

noshi_status noshi_admin_log_parse(const noshi_tl_value *answer, noshi_admin_event *rows, size_t cap, size_t *count) {
    const noshi_tl_value *events;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !rows || !cap || !count) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_channels_adminLogResults) || noshi_tl_get_vec(answer, "events", &events) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (events->u.vec.count > cap) return NOSHI_E_LIMIT;
    for (i = 0; i < events->u.vec.count; ++i) {
        const noshi_tl_value *item = events->u.vec.items[i];
        noshi_admin_event *row = &rows[i];
        int32_t date = 0;
        if (!noshi_tl_is(item, NOSHI_TL_ID_channelAdminLogEvent)) return NOSHI_E_MALFORMED;
        memset(row, 0, sizeof(*row));
        if (noshi_tl_get_i64(item, "id", &row->id) != NOSHI_OK || row->id <= 0 || noshi_tl_get_i64(item, "user_id", &row->actor_id) != NOSHI_OK ||
            !noshi_tl_get(item, "action")) return NOSHI_E_MALFORMED;
        noshi_tl_get_i32(item, "date", &date);
        row->date = date;
        name_of(answer, row->actor_id, row->actor_name, sizeof(row->actor_name), row->actor_username, sizeof(row->actor_username));
        read_action(row, answer, noshi_tl_get(item, "action"));
    }
    *count = events->u.vec.count;
    return NOSHI_OK;
}
