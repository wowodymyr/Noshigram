#include "noshi_notify_prefs.h"

#include <string.h>

#include "noshi_dialogs.h"
#include "noshi_tl_ids.h"

#define YEAR_SECONDS (365 * 24 * 3600)

static int is_vec(const noshi_tl_value *v) {
    return v && v->kind == NOSHI_TL_V_VEC;
}

static void copy_text(char *dst, size_t cap, const noshi_tl_value *obj, const char *field) {
    const uint8_t *data = NULL;
    size_t len = 0, n;
    dst[0] = 0;
    if (noshi_tl_get_bytes(obj, field, &data, &len) != NOSHI_OK || !data) return;
    n = len < cap - 1 ? len : cap - 1;
    /* cut at a character boundary so a long title does not end in half a letter */
    while (n > 0 && n < len && (data[n] & 0xC0) == 0x80) --n;
    memcpy(dst, data, n);
    dst[n] = 0;
}

static int bool_value(const noshi_tl_value *v, uint8_t *out) {
    if (noshi_tl_is(v, NOSHI_TL_ID_boolTrue)) {
        *out = 1;
        return 1;
    }
    if (noshi_tl_is(v, NOSHI_TL_ID_boolFalse)) {
        *out = 0;
        return 1;
    }
    return 0;
}

static void sound_read(const noshi_tl_value *v, noshi_notify_sound *out, uint8_t *has) {
    memset(out, 0, sizeof(*out));
    *has = 0;
    if (!v) return;
    if (noshi_tl_is(v, NOSHI_TL_ID_notificationSoundDefault)) {
        out->kind = NOSHI_SOUND_DEFAULT;
        *has = 1;
    } else if (noshi_tl_is(v, NOSHI_TL_ID_notificationSoundNone)) {
        out->kind = NOSHI_SOUND_NONE;
        *has = 1;
    } else if (noshi_tl_is(v, NOSHI_TL_ID_notificationSoundLocal)) {
        out->kind = NOSHI_SOUND_LOCAL;
        copy_text(out->title, sizeof(out->title), v, "title");
        copy_text(out->data, sizeof(out->data), v, "data");
        *has = 1;
    } else if (noshi_tl_is(v, NOSHI_TL_ID_notificationSoundRingtone)) {
        out->kind = NOSHI_SOUND_RINGTONE;
        noshi_tl_get_i64(v, "id", &out->ringtone_id);
        *has = out->ringtone_id != 0;
    }
}

noshi_status noshi_peer_notify_read(const noshi_tl_value *settings, noshi_peer_notify *out) {
    int32_t value;
    uint8_t flag;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!settings) return NOSHI_OK;
    if (noshi_tl_get_i32(settings, "mute_until", &value) == NOSHI_OK) {
        out->has_mute = 1;
        out->mute_until = value;
    }
    if (bool_value(noshi_tl_get(settings, "show_previews"), &flag)) {
        out->has_previews = 1;
        out->previews = flag;
    }
    if (bool_value(noshi_tl_get(settings, "silent"), &flag)) {
        out->has_silent = 1;
        out->silent = flag;
    }
    sound_read(noshi_tl_get(settings, "ios_sound"), &out->sound, &out->has_sound);
    if (bool_value(noshi_tl_get(settings, "stories_muted"), &flag)) {
        out->has_stories_muted = 1;
        out->stories_muted = flag;
    }
    if (bool_value(noshi_tl_get(settings, "stories_hide_sender"), &flag)) {
        out->has_stories_hide_sender = 1;
        out->stories_hide_sender = flag;
    }
    sound_read(noshi_tl_get(settings, "stories_ios_sound"), &out->stories_sound, &out->has_stories_sound);
    return NOSHI_OK;
}

static noshi_tl_value *sound_build(noshi_arena *arena, const noshi_notify_sound *sound, noshi_status *status) {
    noshi_tl_value *v;
    switch (sound->kind) {
    case NOSHI_SOUND_NONE:
        return noshi_tl_new_obj(arena, "notificationSoundNone");
    case NOSHI_SOUND_LOCAL:
        v = noshi_tl_new_obj(arena, "notificationSoundLocal");
        if (!v) return NULL;
        *status = noshi_tl_set_str(arena, v, "title", sound->title);
        if (*status == NOSHI_OK) *status = noshi_tl_set_str(arena, v, "data", sound->data);
        return v;
    case NOSHI_SOUND_RINGTONE:
        v = noshi_tl_new_obj(arena, "notificationSoundRingtone");
        if (!v) return NULL;
        *status = noshi_tl_set_i64(arena, v, "id", sound->ringtone_id);
        return v;
    default:
        return noshi_tl_new_obj(arena, "notificationSoundDefault");
    }
}

static noshi_status set_sound(noshi_arena *arena, noshi_tl_value *obj, const char *field, const noshi_notify_sound *sound) {
    noshi_status status = NOSHI_OK;
    noshi_tl_value *v = sound_build(arena, sound, &status);
    if (!v) return NOSHI_E_NOMEM;
    if (status != NOSHI_OK) return status;
    return noshi_tl_set(obj, field, v);
}

static noshi_status set_bool(noshi_arena *arena, noshi_tl_value *obj, const char *field, int value) {
    noshi_tl_value *v = noshi_tl_new_obj(arena, value ? "boolTrue" : "boolFalse");
    if (!v) return NOSHI_E_NOMEM;
    return noshi_tl_set(obj, field, v);
}

noshi_status noshi_peer_notify_build(noshi_arena *arena, const noshi_peer_notify *settings, noshi_tl_value **out) {
    noshi_tl_value *v;
    noshi_status status = NOSHI_OK;
    if (out) *out = NULL;
    if (!arena || !settings || !out) return NOSHI_E_ARG;
    v = noshi_tl_new_obj(arena, "inputPeerNotifySettings");
    if (!v) return NOSHI_E_NOMEM;
    if (settings->has_previews) status = set_bool(arena, v, "show_previews", settings->previews);
    if (status == NOSHI_OK && settings->has_silent) status = set_bool(arena, v, "silent", settings->silent);
    if (status == NOSHI_OK && settings->has_mute) status = noshi_tl_set_i32(arena, v, "mute_until", settings->mute_until);
    if (status == NOSHI_OK && settings->has_sound) status = set_sound(arena, v, "sound", &settings->sound);
    if (status == NOSHI_OK && settings->has_stories_muted) status = set_bool(arena, v, "stories_muted", settings->stories_muted);
    if (status == NOSHI_OK && settings->has_stories_hide_sender) status = set_bool(arena, v, "stories_hide_sender", settings->stories_hide_sender);
    if (status == NOSHI_OK && settings->has_stories_sound) status = set_sound(arena, v, "stories_sound", &settings->stories_sound);
    if (status != NOSHI_OK) return status;
    *out = v;
    return NOSHI_OK;
}

static const char *scope_ctor(noshi_notify_scope scope) {
    switch (scope) {
    case NOSHI_SCOPE_USERS: return "inputNotifyUsers";
    case NOSHI_SCOPE_CHATS: return "inputNotifyChats";
    default: return "inputNotifyBroadcasts";
    }
}

noshi_status noshi_notify_scope_request(noshi_arena *arena, noshi_notify_scope scope, noshi_tl_value **out) {
    noshi_tl_value *request, *target;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || (int)scope < 0 || scope >= NOSHI_SCOPE_COUNT) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.getNotifySettings");
    target = noshi_tl_new_obj(arena, scope_ctor(scope));
    if (!request || !target) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", target);
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

/* the InputNotifyPeer that names one chat, or one topic of a forum */
static noshi_status chat_target(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **target) {
    noshi_tl_value *chat = NULL;
    noshi_status status = noshi_input_peer(arena, peer, &chat);
    if (status != NOSHI_OK) return status;
    if (peer->topic_id > 0) {
        *target = noshi_tl_new_obj(arena, "inputNotifyForumTopic");
        if (!*target) return NOSHI_E_NOMEM;
        status = noshi_tl_set(*target, "peer", chat);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, *target, "top_msg_id", peer->topic_id);
        return status;
    }
    *target = noshi_tl_new_obj(arena, "inputNotifyPeer");
    if (!*target) return NOSHI_E_NOMEM;
    return noshi_tl_set(*target, "peer", chat);
}

noshi_status noshi_notify_peer_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    noshi_tl_value *request, *target = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.getNotifySettings");
    if (!request) return NOSHI_E_NOMEM;
    status = chat_target(arena, peer, &target);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", target);
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

noshi_status noshi_notify_update_request(noshi_arena *arena, int has_scope, noshi_notify_scope scope, const noshi_peer_ref *peer,
                                             const noshi_peer_notify *settings, noshi_tl_value **out) {
    noshi_tl_value *request, *target = NULL, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !settings || !out) return NOSHI_E_ARG;
    if (has_scope ? ((int)scope < 0 || scope >= NOSHI_SCOPE_COUNT) : !peer) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.updateNotifySettings");
    if (!request) return NOSHI_E_NOMEM;
    if (has_scope) {
        target = noshi_tl_new_obj(arena, scope_ctor(scope));
        if (!target) return NOSHI_E_NOMEM;
    } else {
        status = chat_target(arena, peer, &target);
        if (status != NOSHI_OK) return status;
    }
    status = noshi_peer_notify_build(arena, settings, &input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", target);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "settings", input);
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

noshi_status noshi_notify_bool_result(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolTrue)) return NOSHI_OK;
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolFalse)) return NOSHI_E_STATE;
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_notify_exceptions_request(noshi_arena *arena, int compare_sound, int compare_stories, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status = NOSHI_OK;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.getNotifyExceptions");
    if (!request) return NOSHI_E_NOMEM;
    if (compare_sound) status = noshi_tl_set_flag(request, "compare_sound");
    if (status == NOSHI_OK && compare_stories) status = noshi_tl_set_flag(request, "compare_stories");
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

static const noshi_tl_value *update_list(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_updates) || noshi_tl_is(answer, NOSHI_TL_ID_updatesCombined)) return noshi_tl_get(answer, "updates");
    return NULL;
}

noshi_status noshi_notify_exceptions_parse(const noshi_tl_value *answer, int64_t self_id, noshi_notify_exception *out, size_t cap, size_t *count) {
    const noshi_tl_value *updates, *users, *chats;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!out || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_updatesTooLong)) return NOSHI_OK;
    updates = update_list(answer);
    if (!is_vec(updates)) return NOSHI_E_MALFORMED;
    users = noshi_tl_get(answer, "users");
    chats = noshi_tl_get(answer, "chats");
    for (i = 0; i < updates->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *update = updates->u.vec.items[i], *notify, *peer;
        noshi_notify_exception *entry;
        noshi_dialog_row row;
        int32_t topic = 0;
        if (!noshi_tl_is(update, NOSHI_TL_ID_updateNotifySettings)) continue;
        notify = noshi_tl_get(update, "peer");
        if (noshi_tl_is(notify, NOSHI_TL_ID_notifyForumTopic)) {
            noshi_tl_get_i32(notify, "top_msg_id", &topic);
        } else if (!noshi_tl_is(notify, NOSHI_TL_ID_notifyPeer)) {
            continue;
        }
        peer = noshi_tl_get(notify, "peer");
        entry = &out[n];
        memset(entry, 0, sizeof(*entry));
        memset(&row, 0, sizeof(row));
        if (noshi_tl_is(peer, NOSHI_TL_ID_peerUser) && noshi_tl_get_i64(peer, "user_id", &row.peer_id) == NOSHI_OK) row.peer_kind = 1;
        else if (noshi_tl_is(peer, NOSHI_TL_ID_peerChat) && noshi_tl_get_i64(peer, "chat_id", &row.peer_id) == NOSHI_OK) row.peer_kind = 2;
        else if (noshi_tl_is(peer, NOSHI_TL_ID_peerChannel) && noshi_tl_get_i64(peer, "channel_id", &row.peer_id) == NOSHI_OK) row.peer_kind = 3;
        else continue;
        noshi_dialog_peer_read(&row, users, chats, self_id);
        entry->peer_kind = row.peer_kind;
        entry->peer_id = row.peer_id;
        entry->peer_hash = row.peer_hash;
        entry->deleted = row.deleted;
        entry->broadcast = row.kind == NOSHI_DIALOG_CHANNEL;
        entry->forum_topic = topic > 0;
        memcpy(entry->title, row.title, sizeof(entry->title) < sizeof(row.title) ? sizeof(entry->title) : sizeof(row.title));
        entry->title[sizeof(entry->title) - 1] = 0;
        noshi_peer_notify_read(noshi_tl_get(update, "notify_settings"), &entry->settings);
        ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_notify_reset_request(noshi_arena *arena, noshi_tl_value **out) {
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    *out = noshi_tl_new_obj(arena, "account.resetNotifySettings");
    return *out ? NOSHI_OK : NOSHI_E_NOMEM;
}

noshi_status noshi_notify_signup_request(noshi_arena *arena, int silent, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.setContactSignUpNotification");
    if (!request) return NOSHI_E_NOMEM;
    status = set_bool(arena, request, "silent", silent);
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

noshi_status noshi_reaction_notify_request(noshi_arena *arena, noshi_tl_value **out) {
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    *out = noshi_tl_new_obj(arena, "account.getReactionsNotifySettings");
    return *out ? NOSHI_OK : NOSHI_E_NOMEM;
}

static int32_t reaction_from(const noshi_tl_value *v) {
    if (noshi_tl_is(v, NOSHI_TL_ID_reactionNotificationsFromContacts)) return NOSHI_REACTION_FROM_CONTACTS;
    if (noshi_tl_is(v, NOSHI_TL_ID_reactionNotificationsFromAll)) return NOSHI_REACTION_FROM_EVERYONE;
    return NOSHI_REACTION_FROM_NOBODY;
}

noshi_status noshi_reaction_notify_read(const noshi_tl_value *answer, noshi_reaction_notify *out) {
    uint8_t flag, has;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    out->previews = 1;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_reactionsNotifySettings)) return NOSHI_E_MALFORMED;
    out->messages_from = reaction_from(noshi_tl_get(answer, "messages_notify_from"));
    out->stories_from = reaction_from(noshi_tl_get(answer, "stories_notify_from"));
    if (bool_value(noshi_tl_get(answer, "show_previews"), &flag)) out->previews = flag;
    sound_read(noshi_tl_get(answer, "sound"), &out->sound, &has);
    return NOSHI_OK;
}

static noshi_status set_from(noshi_arena *arena, noshi_tl_value *obj, const char *field, int32_t from) {
    noshi_tl_value *v;
    if (from == NOSHI_REACTION_FROM_NOBODY) return NOSHI_OK;
    v = noshi_tl_new_obj(arena, from == NOSHI_REACTION_FROM_CONTACTS ? "reactionNotificationsFromContacts" : "reactionNotificationsFromAll");
    if (!v) return NOSHI_E_NOMEM;
    return noshi_tl_set(obj, field, v);
}

noshi_status noshi_reaction_notify_set_request(noshi_arena *arena, const noshi_reaction_notify *settings, noshi_tl_value **out) {
    noshi_tl_value *request, *body;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !settings || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.setReactionsNotifySettings");
    body = noshi_tl_new_obj(arena, "reactionsNotifySettings");
    if (!request || !body) return NOSHI_E_NOMEM;
    status = set_from(arena, body, "messages_notify_from", settings->messages_from);
    if (status == NOSHI_OK) status = set_from(arena, body, "stories_notify_from", settings->stories_from);
    if (status == NOSHI_OK) status = set_sound(arena, body, "sound", &settings->sound);
    if (status == NOSHI_OK) status = set_bool(arena, body, "show_previews", settings->previews);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "settings", body);
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

noshi_status noshi_ringtones_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.getSavedRingtones");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

noshi_status noshi_ringtones_parse(const noshi_tl_value *answer, noshi_ringtone_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *list;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_account_savedRingtonesNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_account_savedRingtones)) return NOSHI_E_MALFORMED;
    list = noshi_tl_get(answer, "ringtones");
    if (!is_vec(list)) return NOSHI_E_MALFORMED;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *document = list->u.vec.items[i], *attributes;
        const uint8_t *reference = NULL;
        size_t length = 0;
        noshi_ringtone_row *row = &rows[n];
        uint32_t a;
        memset(row, 0, sizeof(*row));
        if (!noshi_tl_is(document, NOSHI_TL_ID_document)) continue;
        if (noshi_tl_get_i64(document, "id", &row->id) != NOSHI_OK || row->id == 0 || noshi_tl_get_i64(document, "access_hash", &row->access_hash) != NOSHI_OK) continue;
        if (noshi_tl_get_bytes(document, "file_reference", &reference, &length) != NOSHI_OK || !reference || length > sizeof(row->file_reference)) continue;
        noshi_tl_get_i32(document, "dc_id", &row->dc);
        memcpy(row->file_reference, reference, length);
        row->file_reference_len = (uint8_t)length;
        {
            int64_t size = 0;
            if (noshi_tl_get_i64(document, "size", &size) == NOSHI_OK && size > 0 && size < INT32_MAX) row->size = (int32_t)size;
        }
        copy_text(row->mime, sizeof(row->mime), document, "mime_type");
        attributes = noshi_tl_get(document, "attributes");
        if (is_vec(attributes)) {
            for (a = 0; a < attributes->u.vec.count; ++a) {
                const noshi_tl_value *attribute = attributes->u.vec.items[a];
                if (noshi_tl_is(attribute, NOSHI_TL_ID_documentAttributeAudio)) {
                    noshi_tl_get_i32(attribute, "duration", &row->duration);
                    copy_text(row->title, sizeof(row->title), attribute, "title");
                } else if (noshi_tl_is(attribute, NOSHI_TL_ID_documentAttributeFilename)) {
                    copy_text(row->file_name, sizeof(row->file_name), attribute, "file_name");
                }
            }
        }
        ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_ringtone_unsave_request(noshi_arena *arena, const noshi_ringtone_row *row, noshi_tl_value **out) {
    noshi_tl_value *request, *document;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !row || !out || row->id == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.saveRingtone");
    document = noshi_tl_new_obj(arena, "inputDocument");
    if (!request || !document) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, document, "id", row->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, document, "access_hash", row->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, document, "file_reference", row->file_reference, row->file_reference_len);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", document);
    if (status == NOSHI_OK) status = set_bool(arena, request, "unsave", 1);
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

void noshi_notify_rules_init(noshi_notify_rules *rules) {
    if (!rules) return;
    memset(rules, 0, sizeof(*rules));
    rules->contact_joined = 1;
    rules->pinned_messages = 1;
}

noshi_notify_scope noshi_notify_scope_of(int32_t peer_kind, int is_broadcast) {
    if (peer_kind == 1) return NOSHI_SCOPE_USERS;
    return is_broadcast ? NOSHI_SCOPE_BROADCASTS : NOSHI_SCOPE_CHATS;
}

void noshi_notify_decide(const noshi_notify_rules *rules, noshi_notify_scope scope, const noshi_peer_notify *chat, int32_t now, noshi_notify_decision *out) {
    const noshi_peer_notify *kind;
    int32_t mute_until;
    int silent;
    if (!out) return;
    memset(out, 0, sizeof(*out));
    out->previews = 1;
    if (!rules || (int)scope < 0 || scope >= NOSHI_SCOPE_COUNT) return;
    kind = &rules->scope[scope];
    mute_until = kind->has_mute ? kind->mute_until : 0;
    if (chat && chat->has_mute) mute_until = chat->mute_until;
    out->notify = mute_until <= now;
    out->previews = chat && chat->has_previews ? chat->previews : (kind->has_previews ? kind->previews : 1);
    silent = chat && chat->has_silent ? chat->silent : (kind->has_silent ? kind->silent : 0);
    if (chat && chat->has_sound) out->sound = chat->sound;
    else if (kind->has_sound) out->sound = kind->sound;
    if (silent) {
        memset(&out->sound, 0, sizeof(out->sound));
        out->sound.kind = NOSHI_SOUND_NONE;
    }
}

int noshi_notify_mute_state(int32_t mute_until, int32_t now) {
    if (mute_until <= now) return 0;
    if (mute_until - YEAR_SECONDS >= now) return 1;
    return 2;
}
