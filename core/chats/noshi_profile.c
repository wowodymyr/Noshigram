#include "noshi_profile.h"

#include <string.h>

#include "noshi_avatars.h"
#include "noshi_store.h"
#include "noshi_tl_ids.h"

noshi_status noshi_full_user_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request, *self;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "users.getFullUser");
    self = noshi_tl_new_obj(arena, "inputUserSelf");
    if (!request || !self) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "id", self);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_full_user_peer_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    noshi_tl_value *request, *user;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !peer) return NOSHI_E_ARG;
    if (peer->self) return noshi_full_user_request(arena, out);
    if (peer->kind != 1 || peer->id <= 0 || peer->access_hash == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "users.getFullUser");
    user = noshi_tl_new_obj(arena, "inputUser");
    if (!request || !user) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, user, "user_id", peer->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, user, "access_hash", peer->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", user);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static const noshi_tl_value *find_entity(const noshi_tl_value *list, int64_t id) {
    uint32_t i;
    for (i = 0; list && list->kind == NOSHI_TL_V_VEC && i < list->u.vec.count; ++i) {
        int64_t entity_id;
        if (noshi_tl_get_i64(list->u.vec.items[i], "id", &entity_id) == NOSHI_OK && entity_id == id) return list->u.vec.items[i];
    }
    return NULL;
}

static noshi_status rating_parse(const noshi_tl_value *value, noshi_star_rating *rating) {
    if (!noshi_tl_is(value, NOSHI_TL_ID_starsRating) ||
        noshi_tl_get_i32(value, "level", &rating->level) != NOSHI_OK ||
        noshi_tl_get_i64(value, "current_level_stars", &rating->current_level_stars) != NOSHI_OK ||
        noshi_tl_get_i64(value, "stars", &rating->stars) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (noshi_tl_has(value, "next_level_stars")) {
        if (noshi_tl_get_i64(value, "next_level_stars", &rating->next_level_stars) != NOSHI_OK ||
            rating->next_level_stars <= rating->current_level_stars) return NOSHI_E_MALFORMED;
        rating->has_next = 1;
    }
    return NOSHI_OK;
}

/* a text field copied whole into a buffer, cut at a character boundary */
static void copy_field(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
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

noshi_status noshi_full_user_parse(const noshi_tl_value *answer, noshi_full_user *out) {
    const noshi_tl_value *full, *users, *chats, *entity, *birthday;
    const uint8_t *data;
    size_t len;
    int64_t id = 0, channel_id = 0;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_users_userFull)) return NOSHI_E_MALFORMED;
    full = noshi_tl_get(answer, "full_user");
    if (!noshi_tl_is(full, NOSHI_TL_ID_userFull)) return NOSHI_E_MALFORMED;
    if (noshi_tl_has(full, "stars_rating")) {
        if (rating_parse(noshi_tl_get(full, "stars_rating"), &out->rating) != NOSHI_OK) return NOSHI_E_MALFORMED;
        out->has_rating = 1;
    }
    if (noshi_tl_has(full, "stars_my_pending_rating")) {
        if (rating_parse(noshi_tl_get(full, "stars_my_pending_rating"), &out->pending_rating) != NOSHI_OK ||
            noshi_tl_get_i32(full, "stars_my_pending_rating_date", &out->pending_rating_date) != NOSHI_OK || out->pending_rating_date <= 0)
            return NOSHI_E_MALFORMED;
        out->has_pending_rating = 1;
    }
    if (noshi_tl_has(full, "about") && noshi_tl_get_bytes(full, "about", &data, &len) == NOSHI_OK && data) {
        if (len >= sizeof(out->about)) {
            len = sizeof(out->about) - 1;
            while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
        }
        memcpy(out->about, data, len);
        out->about[len] = 0;
    }
    if (noshi_tl_has(full, "note")) {
        const noshi_tl_value *note = noshi_tl_get(full, "note");
        if (noshi_tl_is(note, NOSHI_TL_ID_textWithEntities)) copy_field(out->note, sizeof(out->note), note, "text");
    }
    out->has_personal_photo = noshi_tl_has(full, "personal_photo") ? 1 : 0;
    if (noshi_tl_has(full, "fallback_photo")) {
        noshi_photo_read(noshi_tl_get(full, "fallback_photo"), NOSHI_AVATAR_TARGET, &out->public_photo);
        out->has_public_photo = out->public_photo.ref.source == NOSHI_MEDIA_SOURCE_PHOTO && out->public_photo.ref.id != 0;
    }
    if (noshi_tl_get_i32(full, "common_chats_count", &out->common_chats) != NOSHI_OK || out->common_chats < 0) out->common_chats = 0;
    out->require_premium = noshi_tl_has(full, "contact_require_premium") ? 1 : 0;
    out->blocked = noshi_tl_has(full, "blocked") ? 1 : 0;
    out->sharing_restricted = noshi_tl_has(full, "noforwards_my_enabled") || noshi_tl_has(full, "noforwards_peer_enabled");
    users = noshi_tl_get(answer, "users");
    chats = noshi_tl_get(answer, "chats");
    if (noshi_tl_get_i64(full, "id", &id) == NOSHI_OK && id > 0) {
        entity = find_entity(users, id);
        if (entity && noshi_person_parse(entity, &out->person) == NOSHI_OK) out->has_person = 1;
    }
    birthday = noshi_tl_get(full, "birthday");
    if (birthday && noshi_tl_get_i32(birthday, "day", &out->birthday_day) == NOSHI_OK &&
        noshi_tl_get_i32(birthday, "month", &out->birthday_month) == NOSHI_OK && out->birthday_day >= 1 && out->birthday_day <= 31 &&
        out->birthday_month >= 1 && out->birthday_month <= 12) {
        out->has_birthday = 1;
        if (noshi_tl_has(birthday, "year")) noshi_tl_get_i32(birthday, "year", &out->birthday_year);
    }
    if (noshi_tl_has(full, "personal_channel_id") && noshi_tl_get_i64(full, "personal_channel_id", &channel_id) == NOSHI_OK && channel_id > 0) {
        entity = find_entity(chats, channel_id);
        if (entity && noshi_tl_is(entity, NOSHI_TL_ID_channel)) {
            out->channel.peer_kind = 3;
            out->channel.peer_id = channel_id;
            noshi_dialog_peer_read(&out->channel, users, chats, 0);
            if (out->channel.title[0]) {
                out->has_channel = 1;
                noshi_tl_get_i32(entity, "participants_count", &out->channel_participants);
                if (noshi_tl_has(full, "personal_channel_message")) noshi_tl_get_i32(full, "personal_channel_message", &out->channel_message);
            } else {
                memset(&out->channel, 0, sizeof(out->channel));
            }
        }
    }
    if (noshi_tl_has(full, "business_intro")) {
        const noshi_tl_value *intro = noshi_tl_get(full, "business_intro");
        if (noshi_tl_is(intro, NOSHI_TL_ID_businessIntro)) {
            copy_field(out->intro_title, sizeof(out->intro_title), intro, "title");
            copy_field(out->intro_text, sizeof(out->intro_text), intro, "description");
            if (noshi_tl_has(intro, "sticker") && noshi_sticker_read(noshi_tl_get(intro, "sticker"), &out->intro_sticker) == NOSHI_OK)
                out->has_intro_sticker = 1;
            out->has_intro = out->intro_title[0] || out->intro_text[0] || out->has_intro_sticker;
        }
    }
    if (noshi_tl_has(full, "saved_music")) {
        noshi_document_read(noshi_tl_get(full, "saved_music"), &out->music);
        out->has_music = out->music.ref.source != NOSHI_MEDIA_SOURCE_NONE;
        if (!out->has_music) memset(&out->music, 0, sizeof(out->music));
    }
    return NOSHI_OK;
}

noshi_status noshi_saved_music_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request, *user;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !peer || offset < 0 || limit < 1 || limit > NOSHI_MUSIC_PAGE) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "users.getSavedMusic");
    if (!request) return NOSHI_E_NOMEM;
    if (peer->self) {
        user = noshi_tl_new_obj(arena, "inputUserSelf");
        if (!user) return NOSHI_E_NOMEM;
        status = NOSHI_OK;
    } else {
        if (peer->kind != 1 || peer->id <= 0 || peer->access_hash == 0) return NOSHI_E_ARG;
        user = noshi_tl_new_obj(arena, "inputUser");
        if (!user) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i64(arena, user, "user_id", peer->id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, user, "access_hash", peer->access_hash);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", user);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset", offset);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    /* a hash of zero asks for the full page; the list is not kept between runs, so there is nothing to compare against */
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_save_music_request(noshi_arena *arena, const noshi_media_ref *song, int unsave, noshi_tl_value **out) {
    noshi_tl_value *request, *document;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !song || song->source != NOSHI_MEDIA_SOURCE_DOCUMENT || song->id == 0 || song->ref_len == 0 || song->thumb[0]) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.saveMusic");
    document = noshi_tl_new_obj(arena, "inputDocument");
    if (!request || !document) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, document, "id", song->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, document, "access_hash", song->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, document, "file_reference", song->file_ref, song->ref_len);
    if (status == NOSHI_OK && unsave) status = noshi_tl_set_flag(request, "unsave");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", document);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_saved_music_parse(const noshi_tl_value *answer, noshi_media_info *tracks, size_t cap, size_t *count, int32_t *total) {
    const noshi_tl_value *documents;
    uint32_t i;
    if (!tracks || !count || !total) return NOSHI_E_ARG;
    *count = 0;
    *total = 0;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_users_savedMusic)) return NOSHI_E_MALFORMED;
    documents = noshi_tl_get(answer, "documents");
    if (!documents || documents->kind != NOSHI_TL_V_VEC || noshi_tl_get_i32(answer, "count", total) != NOSHI_OK || *total < 0) {
        *total = 0;
        return NOSHI_E_MALFORMED;
    }
    for (i = 0; i < documents->u.vec.count && *count < cap; ++i) {
        noshi_media_info *track = &tracks[*count];
        noshi_document_read(documents->u.vec.items[i], track);
        if (track->ref.source == NOSHI_MEDIA_SOURCE_NONE) continue;
        ++*count;
    }
    return NOSHI_OK;
}

noshi_status noshi_birthday_request(noshi_arena *arena, int32_t day, int32_t month, int32_t year, noshi_tl_value **out) {
    static const int32_t days[12] = {31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    noshi_tl_value *request, *birthday;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || month < 1 || month > 12 || day < 1 || day > days[month - 1] || (year != 0 && (year < 1900 || year > 2100))) return NOSHI_E_ARG;
    /* a day that only a leap year has needs a year that is one, when the year is given */
    if (year && month == 2 && day == 29 && !((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.updateBirthday");
    birthday = noshi_tl_new_obj(arena, "birthday");
    if (!request || !birthday) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, birthday, "day", day);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, birthday, "month", month);
    if (status == NOSHI_OK && year) status = noshi_tl_set_i32(arena, birthday, "year", year);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "birthday", birthday);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_birthday_clear_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.updateBirthday");
    if (!request) return NOSHI_E_NOMEM;
    *out = request;
    return NOSHI_OK;
}

static noshi_status input_channel(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out) {
    noshi_tl_value *v;
    noshi_status status;
    *out = NULL;
    if (!channel || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return NOSHI_E_ARG;
    v = noshi_tl_new_obj(arena, "inputChannel");
    if (!v) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, v, "channel_id", channel->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, v, "access_hash", channel->access_hash);
    if (status == NOSHI_OK) *out = v;
    return status;
}

noshi_status noshi_personal_channel_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    if (channel) {
        status = input_channel(arena, channel, &input);
    } else {
        input = noshi_tl_new_obj(arena, "inputChannelEmpty");
        status = input ? NOSHI_OK : NOSHI_E_NOMEM;
    }
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "account.updatePersonalChannel");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "channel", input);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_admined_channels_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "channels.getAdminedPublicChannels");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_flag(request, "for_personal");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_admined_channels_parse(const noshi_tl_value *answer, noshi_dialog_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *chats;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || !cap) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chats) || noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (chats->u.vec.count > 1000) return NOSHI_E_LIMIT;
    for (i = 0; i < chats->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *chat = chats->u.vec.items[i];
        int64_t id;
        noshi_dialog_row row;
        if (!noshi_tl_is(chat, NOSHI_TL_ID_channel) || noshi_tl_get_i64(chat, "id", &id) != NOSHI_OK || id <= 0) continue;
        memset(&row, 0, sizeof(row));
        row.peer_kind = 3;
        row.peer_id = id;
        noshi_dialog_peer_read(&row, chats, chats, 0);
        /* a channel seen only in part has no usable hash, so it cannot be named in a request */
        if (!row.title[0] || row.peer_hash == 0) continue;
        rows[n++] = row;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_channel_message_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t id, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *ids, *message;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || id <= 0) return NOSHI_E_ARG;
    status = input_channel(arena, channel, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "channels.getMessages");
    ids = noshi_tl_new_vec(arena, 1);
    message = noshi_tl_new_obj(arena, "inputMessageID");
    if (!request || !ids || !message) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, message, "id", id);
    if (status == NOSHI_OK) status = noshi_tl_vec_set(ids, 0, message);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "channel", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", ids);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_profile_update_request(noshi_arena *arena, const char *first_name, const char *last_name, const char *about,
                                              noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status = NOSHI_OK;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || (!first_name && !last_name && !about)) return NOSHI_E_ARG;
    if (first_name && (!first_name[0] || strlen(first_name) > NOSHI_NAME_PART_MAX)) return NOSHI_E_ARG;
    if (last_name && strlen(last_name) > NOSHI_NAME_PART_MAX) return NOSHI_E_ARG;
    if (about && strlen(about) >= NOSHI_ABOUT_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.updateProfile");
    if (!request) return NOSHI_E_NOMEM;
    if (first_name) status = noshi_tl_set_str(arena, request, "first_name", first_name);
    if (status == NOSHI_OK && last_name) status = noshi_tl_set_str(arena, request, "last_name", last_name);
    if (status == NOSHI_OK && about) status = noshi_tl_set_str(arena, request, "about", about);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_username_check(const char *name) {
    size_t len, i;
    if (!name) return NOSHI_E_ARG;
    len = strlen(name);
    if (len == 0) return NOSHI_OK;
    if (len < NOSHI_USERNAME_MIN || len > NOSHI_USERNAME_MAX) return NOSHI_E_ARG;
    for (i = 0; i < len; ++i) {
        char c = name[i];
        int letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        int digit = c >= '0' && c <= '9';
        if (!letter && !digit && c != '_') return NOSHI_E_ARG;
        if (i == 0 && !letter) return NOSHI_E_ARG;
    }
    if (name[len - 1] == '_') return NOSHI_E_ARG;
    return NOSHI_OK;
}

noshi_status noshi_username_request(noshi_arena *arena, const char *name, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || noshi_username_check(name) != NOSHI_OK) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.updateUsername");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "username", name);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_profile_video_request(noshi_arena *arena, noshi_tl_value *video, double start_seconds, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    /* a second out of the clip, and a clip is of ten seconds at most: a value outside it is a mistake of the caller */
    if (!arena || !video || !(start_seconds >= 0) || start_seconds > 10) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "photos.uploadProfilePhoto");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "video", video);
    if (status == NOSHI_OK) status = noshi_tl_set_f64(arena, request, "video_start_ts", start_seconds);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_profile_photo_request(noshi_arena *arena, noshi_tl_value *file, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !file) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "photos.uploadProfilePhoto");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "file", file);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_profile_public_photo_request(noshi_arena *arena, noshi_tl_value *file, noshi_tl_value **out) {
    noshi_tl_value *request = NULL;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    status = noshi_profile_photo_request(arena, file, &request);
    if (status == NOSHI_OK) status = noshi_tl_set_flag(request, "fallback");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_profile_photo_delete_request(noshi_arena *arena, const noshi_media_ref *photo, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *list;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !photo || photo->source != NOSHI_MEDIA_SOURCE_PHOTO || photo->id == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "photos.deletePhotos");
    input = noshi_tl_new_obj(arena, "inputPhoto");
    list = noshi_tl_new_vec(arena, 1);
    if (!request || !input || !list) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "id", photo->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", photo->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, input, "file_reference", photo->file_ref, photo->ref_len);
    if (status == NOSHI_OK) status = noshi_tl_vec_set(list, 0, input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static noshi_status contact_input_user(noshi_arena *arena, const noshi_peer_ref *user, noshi_tl_value **out) {
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

noshi_status noshi_common_chats_request(noshi_arena *arena, const noshi_peer_ref *user, int64_t max_id, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || max_id < 0 || limit < 1 || limit > NOSHI_COMMON_CHATS_PAGE) return NOSHI_E_ARG;
    status = contact_input_user(arena, user, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.getCommonChats");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "user_id", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "max_id", max_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_common_chats_parse(const noshi_tl_value *answer, noshi_dialog_row *rows, size_t cap, size_t *count, int64_t *last_id, size_t *raw) {
    const noshi_tl_value *chats;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (last_id) *last_id = 0;
    if (raw) *raw = 0;
    if (!rows || !count || !last_id || !raw || !cap) return NOSHI_E_ARG;
    if ((!noshi_tl_is(answer, NOSHI_TL_ID_messages_chats) && !noshi_tl_is(answer, NOSHI_TL_ID_messages_chatsSlice)) ||
        noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (chats->u.vec.count > 1000) return NOSHI_E_LIMIT;
    for (i = 0; i < chats->u.vec.count; ++i) {
        const noshi_tl_value *chat = chats->u.vec.items[i];
        int64_t id;
        noshi_dialog_row row;
        if (noshi_tl_get_i64(chat, "id", &id) != NOSHI_OK || id <= 0) continue;
        *last_id = id;
        *raw += 1;
        if (n >= cap) continue;
        if (!noshi_tl_is(chat, NOSHI_TL_ID_chat) && !noshi_tl_is(chat, NOSHI_TL_ID_channel)) continue;
        memset(&row, 0, sizeof(row));
        row.peer_kind = noshi_tl_is(chat, NOSHI_TL_ID_channel) ? 3 : 2;
        row.peer_id = id;
        noshi_dialog_peer_read(&row, chats, chats, 0);
        /* a channel seen only in part has no usable hash, so it cannot be opened */
        if (!row.title[0] || (row.peer_kind == 3 && row.peer_hash == 0)) continue;
        rows[n++] = row;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_contact_note_request(noshi_arena *arena, const noshi_peer_ref *user, const char *note, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *text;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!note || strlen(note) >= NOSHI_CONTACT_NOTE_MAX) return NOSHI_E_ARG;
    status = contact_input_user(arena, user, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "contacts.updateContactNote");
    text = noshi_tl_new_obj(arena, "textWithEntities");
    if (!request || !text) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, text, "text", note);
    if (status == NOSHI_OK) status = noshi_tl_set(text, "entities", noshi_tl_new_vec(arena, 0));
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "note", text);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_contact_photo_request(noshi_arena *arena, const noshi_peer_ref *user, noshi_tl_value *file, int suggest, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!file) return NOSHI_E_ARG;
    status = contact_input_user(arena, user, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "photos.uploadContactProfilePhoto");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "user_id", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "file", file);
    if (status == NOSHI_OK && suggest) status = noshi_tl_set_flag(request, "suggest");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_contact_photo_reset_request(noshi_arena *arena, const noshi_peer_ref *user, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    status = contact_input_user(arena, user, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "photos.uploadContactProfilePhoto");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "user_id", input);
    /* the save flag without a file is how the server is told to take the personal photo away */
    if (status == NOSHI_OK) status = noshi_tl_set_flag(request, "save");
    if (status == NOSHI_OK) *out = request;
    return status;
}
