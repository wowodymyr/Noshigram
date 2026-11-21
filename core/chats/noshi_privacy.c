#include "noshi_privacy.h"

#include <string.h>

#include "noshi_people.h"
#include "noshi_tl_ids.h"

#define ACCOUNT_TTL_MIN 30
#define ACCOUNT_TTL_MAX 730

static const char *const key_names[NOSHI_PRIVACY_KEY_COUNT] = {
    "inputPrivacyKeyPhoneNumber", "inputPrivacyKeyStatusTimestamp", "inputPrivacyKeyProfilePhoto", "inputPrivacyKeyForwards",
    "inputPrivacyKeyPhoneCall", "inputPrivacyKeyChatInvite", "inputPrivacyKeyVoiceMessages", "inputPrivacyKeyAbout",
    "inputPrivacyKeyBirthday", "inputPrivacyKeySavedMusic",
};

noshi_status noshi_privacy_get_request(noshi_arena *arena, noshi_privacy_key key, noshi_tl_value **out) {
    noshi_tl_value *request, *name;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || (unsigned)key >= NOSHI_PRIVACY_KEY_COUNT) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.getPrivacy");
    name = noshi_tl_new_obj(arena, key_names[key]);
    if (!request || !name) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "key", name);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* the text of a title field, cut at a whole character */
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

/* a name cut at a whole character to the room of the destination */
static void copy_cstr(char *dst, size_t cap, const char *src) {
    size_t len = strlen(src);
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && ((uint8_t)src[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, src, len);
    dst[len] = 0;
}

/* a person by id in a vector of User objects; the name and hash stay zero for one the answer does not carry */
static void find_user(const noshi_tl_value *users, int64_t id, noshi_privacy_user *out) {
    uint32_t i;
    out->id = id;
    out->access_hash = 0;
    out->name[0] = 0;
    if (!users || users->kind != NOSHI_TL_V_VEC) return;
    for (i = 0; i < users->u.vec.count; ++i) {
        noshi_person_row row;
        if (noshi_person_parse(users->u.vec.items[i], &row) != NOSHI_OK || row.id != id) continue;
        out->access_hash = row.access_hash;
        out->photo = row.photo;
        copy_cstr(out->name, sizeof(out->name), row.name);
        return;
    }
}

static void find_chat(const noshi_tl_value *chats, int64_t id, noshi_privacy_chat *out) {
    uint32_t i;
    out->id = id;
    out->title[0] = 0;
    if (!chats || chats->kind != NOSHI_TL_V_VEC) return;
    for (i = 0; i < chats->u.vec.count; ++i) {
        int64_t found;
        const noshi_tl_value *chat = chats->u.vec.items[i];
        if (noshi_tl_get_i64(chat, "id", &found) != NOSHI_OK || found != id) continue;
        copy_text(out->title, sizeof(out->title), chat, "title");
        noshi_photo_ref_read(chat, noshi_tl_is(chat, NOSHI_TL_ID_channel) ? 3 : 2, id, &out->photo);
        return;
    }
}

static noshi_status read_users(const noshi_tl_value *rule, const noshi_tl_value *users, noshi_privacy_user *rows, size_t *count) {
    const noshi_tl_value *ids;
    uint32_t i;
    if (noshi_tl_get_vec(rule, "users", &ids) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (i = 0; i < ids->u.vec.count; ++i) {
        int64_t id;
        const noshi_tl_value *item = ids->u.vec.items[i];
        if (!item || item->kind != NOSHI_TL_V_I64) return NOSHI_E_MALFORMED;
        id = item->u.i64;
        if (*count >= NOSHI_PRIVACY_EXCEPT_MAX) return NOSHI_E_LIMIT;
        find_user(users, id, &rows[(*count)++]);
    }
    return NOSHI_OK;
}

static noshi_status read_chats(const noshi_tl_value *rule, const noshi_tl_value *chats, noshi_privacy_chat *rows, size_t *count) {
    const noshi_tl_value *ids;
    uint32_t i;
    if (noshi_tl_get_vec(rule, "chats", &ids) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (i = 0; i < ids->u.vec.count; ++i) {
        const noshi_tl_value *item = ids->u.vec.items[i];
        if (!item || item->kind != NOSHI_TL_V_I64) return NOSHI_E_MALFORMED;
        if (*count >= NOSHI_PRIVACY_EXCEPT_MAX) return NOSHI_E_LIMIT;
        find_chat(chats, item->u.i64, &rows[(*count)++]);
    }
    return NOSHI_OK;
}

noshi_status noshi_privacy_parse(const noshi_tl_value *answer, noshi_privacy_rules *out) {
    const noshi_tl_value *rules, *users, *chats;
    uint32_t i;
    noshi_status status = NOSHI_OK;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_account_privacyRules)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "rules", &rules) != NOSHI_OK) return NOSHI_E_MALFORMED;
    users = noshi_tl_get(answer, "users");
    chats = noshi_tl_get(answer, "chats");
    for (i = 0; i < rules->u.vec.count && status == NOSHI_OK; ++i) {
        const noshi_tl_value *rule = rules->u.vec.items[i];
        uint32_t id = noshi_tl_id(rule);
        /* the rules are read in order, and the last of the three bases is the one that stands */
        if (id == NOSHI_TL_ID_privacyValueAllowAll) out->base = NOSHI_PRIVACY_EVERYBODY;
        else if (id == NOSHI_TL_ID_privacyValueAllowContacts) out->base = NOSHI_PRIVACY_CONTACTS;
        else if (id == NOSHI_TL_ID_privacyValueDisallowAll) out->base = NOSHI_PRIVACY_NOBODY;
        else if (id == NOSHI_TL_ID_privacyValueAllowUsers) status = read_users(rule, users, out->allow_users, &out->allow_users_count);
        else if (id == NOSHI_TL_ID_privacyValueDisallowUsers) status = read_users(rule, users, out->disallow_users, &out->disallow_users_count);
        else if (id == NOSHI_TL_ID_privacyValueAllowChatParticipants) status = read_chats(rule, chats, out->allow_chats, &out->allow_chats_count);
        else if (id == NOSHI_TL_ID_privacyValueDisallowChatParticipants) status = read_chats(rule, chats, out->disallow_chats, &out->disallow_chats_count);
        else if (id == NOSHI_TL_ID_privacyValueAllowPremium) out->allow_premium = 1;
        else if (id == NOSHI_TL_ID_privacyValueAllowCloseFriends) out->allow_close_friends = 1;
        else if (id == NOSHI_TL_ID_privacyValueAllowBots) out->allow_bots = 1;
        else if (id == NOSHI_TL_ID_privacyValueDisallowBots) out->disallow_bots = 1;
    }
    if (status != NOSHI_OK) memset(out, 0, sizeof(*out));
    return status;
}

static noshi_status push_rule(noshi_arena *arena, noshi_tl_value *list, uint32_t *at, const char *ctor, noshi_tl_value **made) {
    noshi_tl_value *rule = noshi_tl_new_obj(arena, ctor);
    if (!rule) return NOSHI_E_NOMEM;
    if (made) *made = rule;
    return noshi_tl_vec_set(list, (*at)++, rule);
}

static noshi_status user_rule(noshi_arena *arena, noshi_tl_value *list, uint32_t *at, const char *ctor, const noshi_privacy_user *users, size_t count) {
    noshi_tl_value *rule, *vec;
    noshi_status status;
    size_t i;
    if (!count) return NOSHI_OK;
    status = push_rule(arena, list, at, ctor, &rule);
    if (status != NOSHI_OK) return status;
    vec = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!vec) return NOSHI_E_NOMEM;
    for (i = 0; i < count; ++i) {
        noshi_tl_value *input = noshi_tl_new_obj(arena, "inputUser");
        if (!input) return NOSHI_E_NOMEM;
        /* a person the server did not give a hash for cannot be named, and sending a zero hash would be refused as a whole */
        if (users[i].access_hash == 0) return NOSHI_E_ARG;
        status = noshi_tl_set_i64(arena, input, "user_id", users[i].id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", users[i].access_hash);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(vec, (uint32_t)i, input);
        if (status != NOSHI_OK) return status;
    }
    return noshi_tl_set(rule, "users", vec);
}

static noshi_status chat_rule(noshi_arena *arena, noshi_tl_value *list, uint32_t *at, const char *ctor, const noshi_privacy_chat *chats, size_t count) {
    noshi_tl_value *rule;
    noshi_status status;
    int64_t ids[NOSHI_PRIVACY_EXCEPT_MAX];
    size_t i;
    if (!count) return NOSHI_OK;
    status = push_rule(arena, list, at, ctor, &rule);
    if (status != NOSHI_OK) return status;
    for (i = 0; i < count; ++i) ids[i] = chats[i].id;
    return noshi_tl_set_i64_vec(arena, rule, "chats", ids, (uint32_t)count);
}

noshi_status noshi_privacy_set_request(noshi_arena *arena, noshi_privacy_key key, const noshi_privacy_rules *rules, noshi_tl_value **out) {
    noshi_tl_value *request, *name, *list;
    noshi_status status;
    uint32_t at = 0;
    const char *base;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !rules || (unsigned)key >= NOSHI_PRIVACY_KEY_COUNT) return NOSHI_E_ARG;
    if (rules->allow_users_count > NOSHI_PRIVACY_EXCEPT_MAX || rules->disallow_users_count > NOSHI_PRIVACY_EXCEPT_MAX ||
        rules->allow_chats_count > NOSHI_PRIVACY_EXCEPT_MAX || rules->disallow_chats_count > NOSHI_PRIVACY_EXCEPT_MAX) return NOSHI_E_ARG;
    switch (rules->base) {
    case NOSHI_PRIVACY_EVERYBODY: base = "inputPrivacyValueAllowAll"; break;
    case NOSHI_PRIVACY_CONTACTS: base = "inputPrivacyValueAllowContacts"; break;
    case NOSHI_PRIVACY_NOBODY: base = "inputPrivacyValueDisallowAll"; break;
    default: return NOSHI_E_ARG;
    }
    request = noshi_tl_new_obj(arena, "account.setPrivacy");
    name = noshi_tl_new_obj(arena, key_names[key]);
    /* at most the four exception rules, four extras and the base */
    list = noshi_tl_new_vec(arena, 9);
    if (!request || !name || !list) return NOSHI_E_NOMEM;
    status = user_rule(arena, list, &at, "inputPrivacyValueAllowUsers", rules->allow_users, rules->allow_users_count);
    if (status == NOSHI_OK) status = user_rule(arena, list, &at, "inputPrivacyValueDisallowUsers", rules->disallow_users, rules->disallow_users_count);
    if (status == NOSHI_OK) status = chat_rule(arena, list, &at, "inputPrivacyValueAllowChatParticipants", rules->allow_chats, rules->allow_chats_count);
    if (status == NOSHI_OK) status = chat_rule(arena, list, &at, "inputPrivacyValueDisallowChatParticipants", rules->disallow_chats, rules->disallow_chats_count);
    if (status == NOSHI_OK && rules->allow_premium) status = push_rule(arena, list, &at, "inputPrivacyValueAllowPremium", NULL);
    if (status == NOSHI_OK && rules->allow_close_friends) status = push_rule(arena, list, &at, "inputPrivacyValueAllowCloseFriends", NULL);
    if (status == NOSHI_OK && rules->allow_bots) status = push_rule(arena, list, &at, "inputPrivacyValueAllowBots", NULL);
    if (status == NOSHI_OK && rules->disallow_bots) status = push_rule(arena, list, &at, "inputPrivacyValueDisallowBots", NULL);
    if (status == NOSHI_OK) status = push_rule(arena, list, &at, base, NULL);
    if (status != NOSHI_OK) return status;
    /* the vector was made for nine and holds what was pushed */
    list->u.vec.count = at;
    status = noshi_tl_set(request, "key", name);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "rules", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_blocked_request(noshi_arena *arena, int32_t offset, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || offset < 0 || limit < 1 || limit > NOSHI_BLOCKED_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "contacts.getBlocked");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, request, "offset", offset);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static const noshi_tl_value *find_object(const noshi_tl_value *vec, int64_t id) {
    uint32_t i;
    if (!vec || vec->kind != NOSHI_TL_V_VEC) return NULL;
    for (i = 0; i < vec->u.vec.count; ++i) {
        int64_t found;
        if (noshi_tl_get_i64(vec->u.vec.items[i], "id", &found) == NOSHI_OK && found == id) return vec->u.vec.items[i];
    }
    return NULL;
}

static int read_blocked(const noshi_tl_value *item, const noshi_tl_value *users, const noshi_tl_value *chats, noshi_blocked_row *out) {
    const noshi_tl_value *peer = NULL, *object;
    const char *field = NULL;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(item, NOSHI_TL_ID_peerBlocked) || noshi_tl_get_obj(item, "peer_id", &peer) != NOSHI_OK) return 0;
    if (noshi_tl_is(peer, NOSHI_TL_ID_peerUser)) { out->kind = 1; field = "user_id"; }
    else if (noshi_tl_is(peer, NOSHI_TL_ID_peerChat)) { out->kind = 2; field = "chat_id"; }
    else if (noshi_tl_is(peer, NOSHI_TL_ID_peerChannel)) { out->kind = 3; field = "channel_id"; }
    else return 0;
    if (noshi_tl_get_i64(peer, field, &out->id) != NOSHI_OK) return 0;
    noshi_tl_get_i32(item, "date", &out->date);
    if (out->kind == 1) {
        noshi_person_row row;
        object = find_object(users, out->id);
        if (object && noshi_person_parse(object, &row) == NOSHI_OK) {
            out->access_hash = row.access_hash;
            out->photo = row.photo;
            copy_cstr(out->name, sizeof(out->name), row.name);
        }
    } else {
        object = find_object(chats, out->id);
        if (object) {
            copy_text(out->name, sizeof(out->name), object, "title");
            noshi_tl_get_i64(object, "access_hash", &out->access_hash);
            noshi_photo_ref_read(object, out->kind, out->id, &out->photo);
        }
    }
    return 1;
}

noshi_status noshi_blocked_parse(const noshi_tl_value *answer, noshi_blocked_row *rows, size_t cap, size_t *count, int32_t *total) {
    const noshi_tl_value *list;
    uint32_t i;
    size_t found = 0;
    if (!count) return NOSHI_E_ARG;
    *count = 0;
    if (total) *total = 0;
    if (!rows && cap) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_contacts_blocked) && !noshi_tl_is(answer, NOSHI_TL_ID_contacts_blockedSlice)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "blocked", &list) != NOSHI_OK || list->u.vec.count > NOSHI_BLOCKED_MAX * 5u) return NOSHI_E_MALFORMED;
    for (i = 0; i < list->u.vec.count && found < cap; ++i) {
        if (read_blocked(list->u.vec.items[i], noshi_tl_get(answer, "users"), noshi_tl_get(answer, "chats"), &rows[found])) ++found;
    }
    *count = found;
    if (total) {
        int32_t all = 0;
        if (!noshi_tl_has(answer, "count") || noshi_tl_get_i32(answer, "count", &all) != NOSHI_OK) all = (int32_t)list->u.vec.count;
        *total = all;
    }
    return NOSHI_OK;
}

noshi_status noshi_block_request(noshi_arena *arena, const noshi_peer_ref *peer, int block, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !peer) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, block ? "contacts.block" : "contacts.unblock");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_input_peer(arena, peer, &input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", input);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static noshi_status plain_request(noshi_arena *arena, const char *method, noshi_tl_value **out) {
    noshi_tl_value *request;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, method);
    if (!request) return NOSHI_E_NOMEM;
    *out = request;
    return NOSHI_OK;
}

noshi_status noshi_account_ttl_request(noshi_arena *arena, noshi_tl_value **out) {
    return plain_request(arena, "account.getAccountTTL", out);
}

noshi_status noshi_account_ttl_parse(const noshi_tl_value *answer, int32_t *days) {
    if (!days) return NOSHI_E_ARG;
    *days = 0;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_accountDaysTTL)) return NOSHI_E_MALFORMED;
    return noshi_tl_get_i32(answer, "days", days) == NOSHI_OK ? NOSHI_OK : NOSHI_E_MALFORMED;
}

noshi_status noshi_account_ttl_set_request(noshi_arena *arena, int32_t days, noshi_tl_value **out) {
    noshi_tl_value *request, *ttl;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || days < ACCOUNT_TTL_MIN || days > ACCOUNT_TTL_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.setAccountTTL");
    ttl = noshi_tl_new_obj(arena, "accountDaysTTL");
    if (!request || !ttl) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, ttl, "days", days);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "ttl", ttl);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_history_ttl_request(noshi_arena *arena, noshi_tl_value **out) {
    return plain_request(arena, "messages.getDefaultHistoryTTL", out);
}

noshi_status noshi_history_ttl_parse(const noshi_tl_value *answer, int32_t *seconds) {
    if (!seconds) return NOSHI_E_ARG;
    *seconds = 0;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_defaultHistoryTTL)) return NOSHI_E_MALFORMED;
    return noshi_tl_get_i32(answer, "period", seconds) == NOSHI_OK ? NOSHI_OK : NOSHI_E_MALFORMED;
}

noshi_status noshi_history_ttl_set_request(noshi_arena *arena, int32_t seconds, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || seconds < 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.setDefaultHistoryTTL");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, request, "period", seconds);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_clear_payments_request(noshi_arena *arena, int credentials, int info, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status = NOSHI_OK;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || (!credentials && !info)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "payments.clearSavedInfo");
    if (!request) return NOSHI_E_NOMEM;
    if (credentials) status = noshi_tl_set_flag(request, "credentials");
    if (status == NOSHI_OK && info) status = noshi_tl_set_flag(request, "info");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_reset_saved_contacts_request(noshi_arena *arena, noshi_tl_value **out) {
    return plain_request(arena, "contacts.resetSaved", out);
}
