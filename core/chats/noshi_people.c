#include "noshi_people.h"

#include <string.h>

#include "noshi_store.h"
#include "noshi_tl_ids.h"

/* the same text rule as the chat list: UTF-8 cut at a character boundary, no line breaks */
static void copy_text(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len, out = 0;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    for (; out < len; ++out) dst[out] = (data[out] == '\n' || data[out] == '\r' || data[out] == '\t') ? ' ' : (char)data[out];
    dst[out] = 0;
}

/* the public name: the username field, or the first active one of the usernames list that a user with several of them (a bot with a collectible one) carries in its place;
   without it "via @bot" had no name to show */
static void read_username(char *dst, size_t cap, const noshi_tl_value *user) {
    const noshi_tl_value *names = noshi_tl_get(user, "usernames");
    uint32_t i;
    copy_text(dst, cap, user, "username");
    if (dst[0] || !names || names->kind != NOSHI_TL_V_VEC) return;
    for (i = 0; i < names->u.vec.count; ++i) {
        const noshi_tl_value *name = names->u.vec.items[i];
        if (noshi_tl_has(name, "active")) {
            copy_text(dst, cap, name, "username");
            if (dst[0]) return;
        }
    }
}

static void join_name(char *dst, size_t cap, const noshi_tl_value *user) {
    char first[NOSHI_PERSON_NAME_MAX], last[NOSHI_PERSON_NAME_MAX];
    size_t a, b;
    copy_text(first, sizeof(first), user, "first_name");
    copy_text(last, sizeof(last), user, "last_name");
    a = strlen(first);
    b = strlen(last);
    if (a + b + 2 > cap) {
        last[0] = 0;
        b = 0;
    }
    if (a && b) {
        memcpy(dst, first, a);
        dst[a] = ' ';
        memcpy(dst + a + 1, last, b + 1);
    } else if (a || b) {
        memcpy(dst, a ? first : last, (a ? a : b) + 1);
    } else {
        copy_text(dst, cap, user, "username");
    }
}

void noshi_presence_read(const noshi_tl_value *status, noshi_presence *presence, int32_t *seen) {
    int32_t value;
    *presence = NOSHI_PRESENCE_UNKNOWN;
    *seen = 0;
    if (noshi_tl_is(status, NOSHI_TL_ID_userStatusOnline)) {
        *presence = NOSHI_PRESENCE_ONLINE;
    } else if (noshi_tl_is(status, NOSHI_TL_ID_userStatusOffline)) {
        *presence = NOSHI_PRESENCE_OFFLINE;
        if (noshi_tl_get_i32(status, "was_online", &value) == NOSHI_OK) *seen = value;
    } else if (noshi_tl_is(status, NOSHI_TL_ID_userStatusRecently)) {
        *presence = NOSHI_PRESENCE_RECENTLY;
    } else if (noshi_tl_is(status, NOSHI_TL_ID_userStatusLastWeek)) {
        *presence = NOSHI_PRESENCE_LAST_WEEK;
    } else if (noshi_tl_is(status, NOSHI_TL_ID_userStatusLastMonth)) {
        *presence = NOSHI_PRESENCE_LAST_MONTH;
    }
}

void noshi_emoji_status_read(const noshi_tl_value *user, int64_t *document, int32_t *until) {
    const noshi_tl_value *status = noshi_tl_get(user, "emoji_status");
    int64_t id = 0;
    int32_t end = 0;
    if (status && (noshi_tl_is(status, NOSHI_TL_ID_emojiStatus) || noshi_tl_is(status, NOSHI_TL_ID_emojiStatusCollectible)) &&
        noshi_tl_get_i64(status, "document_id", &id) == NOSHI_OK && id > 0) {
        if (noshi_tl_get_i32(status, "until", &end) != NOSHI_OK || end < 0) end = 0;
    } else {
        id = 0;
    }
    if (document) *document = id;
    if (until) *until = id ? end : 0;
}

int64_t noshi_emoji_status_collectible(const noshi_tl_value *user) {
    const noshi_tl_value *status = noshi_tl_get(user, "emoji_status");
    int64_t id = 0;
    if (!noshi_tl_is(status, NOSHI_TL_ID_emojiStatusCollectible) || noshi_tl_get_i64(status, "collectible_id", &id) != NOSHI_OK || id <= 0) return 0;
    return id;
}

static int vec_i32(const noshi_tl_value *vec, uint32_t index, int32_t *out) {
    if (!vec || vec->kind != NOSHI_TL_V_VEC || index >= vec->u.vec.count) return 0;
    if (!vec->u.vec.items[index] || vec->u.vec.items[index]->kind != NOSHI_TL_V_I32) return 0;
    *out = vec->u.vec.items[index]->u.i32;
    return 1;
}

/* a profile color picked from the list names only its id and the emoji; the colors come from the list */
static void profile_color_read(const noshi_tl_value *user, noshi_person_row *out) {
    const noshi_tl_value *color = noshi_tl_get(user, "profile_color");
    int32_t id = 0;
    int64_t emoji = 0;
    out->has_profile_color = 0;
    if (!noshi_tl_is(color, NOSHI_TL_ID_peerColor) || noshi_tl_get_i32(color, "color", &id) != NOSHI_OK || id < 0) return;
    noshi_tl_get_i64(color, "background_emoji_id", &emoji);
    out->has_profile_color = 1;
    out->profile_color_id = id;
    out->profile_color_emoji = emoji > 0 ? emoji : 0;
}

/* a collectible profile color wins over a collectible emoji status; a plain color index has no colors of its own here and leaves the profile as it is */
static void backdrop_read(const noshi_tl_value *user, noshi_person_row *out) {
    const noshi_tl_value *color = noshi_tl_get(user, "profile_color"), *status = noshi_tl_get(user, "emoji_status");
    int32_t center = 0, edge = 0, pattern = 0, text = 0xFFFFFF;
    int64_t pattern_document = 0;
    out->has_backdrop = 0;
    if (noshi_tl_is(color, NOSHI_TL_ID_peerColorCollectible)) {
        const noshi_tl_value *colors = noshi_tl_get(color, "colors");
        if (!vec_i32(colors, 0, &center)) return;
        if (!vec_i32(colors, 1, &edge)) edge = center;
        if (noshi_tl_get_i32(color, "accent_color", &pattern) != NOSHI_OK) pattern = 0xFFFFFF;
        noshi_tl_get_i64(color, "background_emoji_id", &pattern_document);
    } else if (noshi_tl_is(status, NOSHI_TL_ID_emojiStatusCollectible)) {
        const uint8_t *slug = NULL;
        size_t slug_len = 0, at;
        if (noshi_tl_get_i32(status, "center_color", &center) != NOSHI_OK || noshi_tl_get_i32(status, "edge_color", &edge) != NOSHI_OK) return;
        if (noshi_tl_get_i32(status, "pattern_color", &pattern) != NOSHI_OK) pattern = 0xFFFFFF;
        if (noshi_tl_get_i32(status, "text_color", &text) != NOSHI_OK) text = 0xFFFFFF;
        noshi_tl_get_i64(status, "pattern_document_id", &pattern_document);
        copy_text(out->backdrop_title, sizeof(out->backdrop_title), status, "title");
        /* the number of the collectible is what follows the last dash of its slug */
        if (noshi_tl_get_bytes(status, "slug", &slug, &slug_len) == NOSHI_OK && slug_len > 0) {
            for (at = slug_len; at > 0 && slug[at - 1] != '-'; --at) {}
            if (at > 0 && at < slug_len) {
                size_t used = strlen(out->backdrop_title), digits = 0;
                while (at + digits < slug_len && slug[at + digits] >= '0' && slug[at + digits] <= '9') ++digits;
                if (digits && at + digits == slug_len && used + 2 + digits < sizeof(out->backdrop_title)) {
                    out->backdrop_title[used++] = ' ';
                    out->backdrop_title[used++] = '#';
                    memcpy(out->backdrop_title + used, slug + at, digits);
                    out->backdrop_title[used + digits] = 0;
                }
            }
        }
    } else {
        return;
    }
    out->has_backdrop = 1;
    out->backdrop_center = (uint32_t)center & 0xFFFFFFu;
    out->backdrop_edge = (uint32_t)edge & 0xFFFFFFu;
    out->backdrop_pattern = (uint32_t)pattern & 0xFFFFFFu;
    out->backdrop_text = (uint32_t)text & 0xFFFFFFu;
    out->backdrop_pattern_document = pattern_document > 0 ? pattern_document : 0;
}

noshi_status noshi_person_parse(const noshi_tl_value *user, noshi_person_row *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(user, NOSHI_TL_ID_user) || noshi_tl_get_i64(user, "id", &out->id) != NOSHI_OK || out->id <= 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    /* a min object comes from a mention and carries no hash that works for this account */
    if (!noshi_tl_has(user, "min")) noshi_tl_get_i64(user, "access_hash", &out->access_hash);
    out->bot = noshi_tl_has(user, "bot") ? 1 : 0;
    if (out->bot) {
        out->bot_inline = noshi_tl_has(user, "bot_inline_placeholder") ? 1 : 0;
        out->bot_inline_geo = noshi_tl_has(user, "bot_inline_geo") ? 1 : 0;
        out->bot_no_chats = noshi_tl_has(user, "bot_nochats") ? 1 : 0;
        out->bot_reads_all = noshi_tl_has(user, "bot_chat_history") ? 1 : 0;
        copy_text(out->bot_placeholder, sizeof(out->bot_placeholder), user, "bot_inline_placeholder");
    }
    out->verified = noshi_tl_has(user, "verified") ? 1 : 0;
    out->contact = noshi_tl_has(user, "contact") ? 1 : 0;
    out->mutual = noshi_tl_has(user, "mutual_contact") ? 1 : 0;
    out->premium = noshi_tl_has(user, "premium") ? 1 : 0;
    noshi_emoji_status_read(user, &out->emoji_status, &out->emoji_status_until);
    out->emoji_status_collectible = noshi_emoji_status_collectible(user);
    backdrop_read(user, out);
    profile_color_read(user, out);
    out->deleted = noshi_tl_has(user, "deleted") ? 1 : 0;
    {
        /* a collectible color has no id of its own and leaves the name to the default */
        const noshi_tl_value *color = noshi_tl_get(user, "color");
        int32_t id = 0;
        if (noshi_tl_is(color, NOSHI_TL_ID_peerColor) && noshi_tl_get_i32(color, "color", &id) == NOSHI_OK && id >= 0) {
            out->has_name_color = 1;
            out->name_color = id;
        }
    }
    join_name(out->name, sizeof(out->name), user);
    read_username(out->username, sizeof(out->username), user);
    copy_text(out->phone, sizeof(out->phone), user, "phone");
    noshi_photo_ref_read(user, 1, out->id, &out->photo);
    noshi_presence_read(noshi_tl_get(user, "status"), &out->presence, &out->seen);
    if (out->id == NOSHI_TELEGRAM_SERVICE_USER_ID) { out->presence = NOSHI_PRESENCE_UNKNOWN; out->seen = 0; }
    if (out->deleted) {
        out->presence = NOSHI_PRESENCE_DELETED;
        out->seen = 0;
    }
    return NOSHI_OK;
}

noshi_status noshi_channel_person_parse(const noshi_tl_value *channel, noshi_person_row *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if ((!noshi_tl_is(channel, NOSHI_TL_ID_channel) && !noshi_tl_is(channel, NOSHI_TL_ID_channelForbidden) &&
         !noshi_tl_is(channel, NOSHI_TL_ID_community) && !noshi_tl_is(channel, NOSHI_TL_ID_communityForbidden)) ||
        noshi_tl_get_i64(channel, "id", &out->id) != NOSHI_OK || out->id <= 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    if (!noshi_tl_has(channel, "min")) noshi_tl_get_i64(channel, "access_hash", &out->access_hash);
    out->verified = noshi_tl_has(channel, "verified") ? 1 : 0;
    copy_text(out->name, sizeof(out->name), channel, "title");
    copy_text(out->username, sizeof(out->username), channel, "username");
    noshi_photo_ref_read(channel, 3, out->id, &out->photo);
    return NOSHI_OK;
}

noshi_status noshi_group_roles_request(noshi_arena *arena, int32_t kind, int64_t id, int64_t hash, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || id <= 0 || (kind != 2 && kind != 3)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, kind == 2 ? "messages.getFullChat" : "channels.getParticipants");
    if (!request) return NOSHI_E_NOMEM;
    if (kind == 2) status = noshi_tl_set_i64(arena, request, "chat_id", id);
    else {
        noshi_tl_value *channel = noshi_tl_new_obj(arena, "inputChannel");
        if (!channel) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i64(arena, channel, "channel_id", id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", hash);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "channel", channel);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "filter", noshi_tl_new_obj(arena, "channelParticipantsAdmins"));
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset", 0);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", NOSHI_GROUP_ROLES_MAX);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    }
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_group_roles_parse(const noshi_tl_value *answer, int64_t id, noshi_group_role *rows, size_t cap, size_t *count) {
    const noshi_tl_value *participants = NULL;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !cap || !count || id <= 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_channels_channelParticipants)) {
        int32_t total = 0;
        if (noshi_tl_get_vec(answer, "participants", &participants) != NOSHI_OK ||
            noshi_tl_get_i32(answer, "count", &total) != NOSHI_OK || total < 0) return NOSHI_E_MALFORMED;
        if ((uint32_t)total > participants->u.vec.count) return NOSHI_E_LIMIT;
    } else if (noshi_tl_is(answer, NOSHI_TL_ID_messages_chatFull)) {
        const noshi_tl_value *full = noshi_tl_get(answer, "full_chat");
        const noshi_tl_value *group = noshi_tl_get(full, "participants");
        int64_t full_id = 0, group_id = 0;
        if (!noshi_tl_is(full, NOSHI_TL_ID_chatFull) || noshi_tl_get_i64(full, "id", &full_id) != NOSHI_OK || full_id != id ||
            !noshi_tl_is(group, NOSHI_TL_ID_chatParticipants) || noshi_tl_get_i64(group, "chat_id", &group_id) != NOSHI_OK || group_id != id ||
            noshi_tl_get_vec(group, "participants", &participants) != NOSHI_OK) return NOSHI_E_MALFORMED;
    } else return NOSHI_E_MALFORMED;
    if (participants->u.vec.count > NOSHI_PEOPLE_MAX) return NOSHI_E_LIMIT;
    for (uint32_t i = 0; i < participants->u.vec.count; ++i) {
        const noshi_tl_value *p = participants->u.vec.items[i];
        noshi_group_role row;
        memset(&row, 0, sizeof(row));
        row.owner = noshi_tl_is(p, NOSHI_TL_ID_channelParticipantCreator) || noshi_tl_is(p, NOSHI_TL_ID_chatParticipantCreator);
        row.admin = row.owner || noshi_tl_is(p, NOSHI_TL_ID_channelParticipantAdmin) || noshi_tl_is(p, NOSHI_TL_ID_chatParticipantAdmin);
        if (!row.admin && !noshi_tl_is(p, NOSHI_TL_ID_channelParticipant) && !noshi_tl_is(p, NOSHI_TL_ID_channelParticipantSelf) &&
            !noshi_tl_is(p, NOSHI_TL_ID_chatParticipant)) return NOSHI_E_MALFORMED;
        if (noshi_tl_get_i64(p, "user_id", &row.user_id) != NOSHI_OK || row.user_id <= 0) return NOSHI_E_MALFORMED;
        copy_text(row.rank, sizeof(row.rank), p, "rank");
        if (!row.admin && !row.rank[0]) continue;
        if (n == cap) return NOSHI_E_LIMIT;
        rows[n++] = row;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_contacts_parse(const noshi_tl_value *answer, noshi_person_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *users;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_contacts_contacts) || noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    for (i = 0; i < users->u.vec.count && n < cap; ++i) {
        /* an empty user in the list is skipped, one bad entry does not hide the rest */
        if (noshi_person_parse(users->u.vec.items[i], &rows[n]) == NOSHI_OK) ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_profile_colors_request(noshi_arena *arena, int32_t hash, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "help.getPeerProfileColors");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, request, "hash", hash);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* the one or two background colors of a help.peerColorProfileSet; zero colors is no set */
static int profile_set_read(const noshi_tl_value *set, uint32_t bg[2]) {
    const noshi_tl_value *colors;
    int32_t first = 0, second = 0;
    if (!noshi_tl_is(set, NOSHI_TL_ID_help_peerColorProfileSet)) return 0;
    colors = noshi_tl_get(set, "bg_colors");
    if (!vec_i32(colors, 0, &first)) return 0;
    if (!vec_i32(colors, 1, &second)) second = first;
    bg[0] = (uint32_t)first & 0xFFFFFFu;
    bg[1] = (uint32_t)second & 0xFFFFFFu;
    return 1;
}

noshi_status noshi_profile_colors_parse(const noshi_tl_value *answer, noshi_profile_color *rows, size_t cap, size_t *count, int32_t *hash) {
    const noshi_tl_value *options;
    uint32_t i;
    if (count) *count = 0;
    if (hash) *hash = 0;
    if (!answer || !rows || !count || !cap) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_help_peerColorsNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_help_peerColors)) return NOSHI_E_MALFORMED;
    if (hash && noshi_tl_get_i32(answer, "hash", hash) != NOSHI_OK) *hash = 0;
    options = noshi_tl_get(answer, "colors");
    if (!options || options->kind != NOSHI_TL_V_VEC) return NOSHI_E_MALFORMED;
    for (i = 0; i < options->u.vec.count && *count < cap; ++i) {
        const noshi_tl_value *option = options->u.vec.items[i];
        noshi_profile_color row;
        int32_t id = 0;
        memset(&row, 0, sizeof(row));
        if (!noshi_tl_is(option, NOSHI_TL_ID_help_peerColorOption) || noshi_tl_get_i32(option, "color_id", &id) != NOSHI_OK || id < 0) continue;
        if (!profile_set_read(noshi_tl_get(option, "colors"), row.bg)) continue;
        row.id = id;
        row.has_dark = (uint8_t)profile_set_read(noshi_tl_get(option, "dark_colors"), row.dark_bg);
        rows[(*count)++] = row;
    }
    return NOSHI_OK;
}
