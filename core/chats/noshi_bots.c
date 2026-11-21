#include "noshi_bots.h"

#include <ctype.h>
#include <string.h>

#include "noshi_srp.h"
#include "noshi_links.h"
#include "noshi_store.h"
#include "noshi_tl_ids.h"

#define PLATFORM "ios"
#define PRICES_MAX 16

static int is_vec(const noshi_tl_value *v) {
    return v && v->kind == NOSHI_TL_V_VEC;
}

/* a string field cut at a character boundary; line breaks stay only where the caller wants them */
static void copy_text(char *dst, size_t cap, const noshi_tl_value *object, const char *field, int keep_lines) {
    const uint8_t *data;
    size_t len, i;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    for (i = 0; i < len; ++i) {
        uint8_t c = data[i];
        dst[i] = (!keep_lines && (c == '\n' || c == '\r' || c == '\t')) ? ' ' : (char)c;
    }
    dst[len] = 0;
}

/* a C string cut at a character boundary; cap includes the terminator */
static void cut_into(char *dst, size_t cap, const char *src) {
    size_t len = strlen(src);
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && ((unsigned char)src[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, src, len);
    dst[len] = 0;
}

/* a string that is useless when cut, an address or a start parameter: false when it does not fit whole */
static int copy_whole(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK) return 0;
    if (len >= cap) return 0;
    memcpy(dst, data, len);
    dst[len] = 0;
    return 1;
}

static noshi_status input_user(noshi_arena *arena, const noshi_peer_ref *bot, noshi_tl_value **out) {
    noshi_tl_value *user;
    noshi_status status;
    *out = NULL;
    if (!bot || bot->kind != 1 || bot->id <= 0 || bot->access_hash == 0) return NOSHI_E_ARG;
    user = noshi_tl_new_obj(arena, "inputUser");
    if (!user) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, user, "user_id", bot->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, user, "access_hash", bot->access_hash);
    if (status == NOSHI_OK) *out = user;
    return status;
}

noshi_status noshi_contact_edit_request(noshi_arena *arena, const noshi_peer_ref *user, const char *first, const char *last, const char *phone,
                                            noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    size_t first_len = first ? strlen(first) : 0;
    if (out) *out = NULL;
    if (!arena || !out || !last || !phone || first_len == 0 || first_len >= NOSHI_CONTACT_NAME_MAX || strlen(last) >= NOSHI_CONTACT_NAME_MAX ||
        strlen(phone) > 32) return NOSHI_E_ARG;
    status = input_user(arena, user, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "contacts.addContact");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "id", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "first_name", first);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "last_name", last);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "phone", phone);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static int phone_valid(const char *phone) {
    size_t digits = 0;
    if (!phone) return 0;
    if (*phone == '+') ++phone;
    for (; *phone; ++phone) {
        if (*phone < '0' || *phone > '9') return 0;
        ++digits;
    }
    return digits >= 5 && digits <= 20;
}

noshi_status noshi_contact_import_request(noshi_arena *arena, const char *phone, const char *first, const char *last, noshi_tl_value **out) {
    noshi_tl_value *request, *contact, *list, *items[1];
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !phone_valid(phone) || !first || !last || !first[0] || strlen(first) >= NOSHI_CONTACT_NAME_MAX || strlen(last) >= NOSHI_CONTACT_NAME_MAX)
        return NOSHI_E_ARG;
    contact = noshi_tl_new_obj(arena, "inputPhoneContact");
    request = noshi_tl_new_obj(arena, "contacts.importContacts");
    if (!contact || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, contact, "client_id", 1);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, contact, "phone", phone);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, contact, "first_name", first);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, contact, "last_name", last);
    items[0] = contact;
    list = noshi_tl_new_vec(arena, 1);
    if (!list) return NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_vec_set(list, 0, items[0]);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "contacts", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_contact_import_parse(const noshi_tl_value *answer, size_t *imported) {
    const noshi_tl_value *list;
    if (imported) *imported = 0;
    if (!imported) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_contacts_importedContacts) || noshi_tl_get_vec(answer, "imported", &list) != NOSHI_OK) return NOSHI_E_MALFORMED;
    *imported = list->u.vec.count;
    return NOSHI_OK;
}

/* the characters the server accepts in a start parameter, a slug or a username */
static int word_char(char c, int dash) {
    return isalnum((unsigned char)c) || c == '_' || (dash && c == '-');
}

static int word_valid(const char *s, size_t min, size_t max, int dash) {
    size_t n = s ? strlen(s) : 0, i;
    if (n < min || n > max) return 0;
    for (i = 0; i < n; ++i) if (!word_char(s[i], dash)) return 0;
    return 1;
}

static int utf8_valid(const char *s) {
    const unsigned char *p = (const unsigned char *)s;
    while (*p) {
        unsigned n, i;
        uint32_t cp;
        if (*p < 0x80u) { ++p; continue; }
        if (*p >= 0xc2u && *p <= 0xdfu) { n = 1; cp = *p & 0x1fu; }
        else if (*p >= 0xe0u && *p <= 0xefu) { n = 2; cp = *p & 0x0fu; }
        else if (*p >= 0xf0u && *p <= 0xf4u) { n = 3; cp = *p & 0x07u; }
        else return 0;
        for (i = 1; i <= n; ++i) {
            if ((p[i] & 0xc0u) != 0x80u) return 0;
            cp = (cp << 6) | (p[i] & 0x3fu);
        }
        if ((n == 2 && cp < 0x800u) || (n == 3 && cp < 0x10000u) || (cp >= 0xd800u && cp <= 0xdfffu) || cp > 0x10ffffu) return 0;
        p += n + 1;
    }
    return 1;
}

/* resolve */

noshi_status noshi_resolve_request(noshi_arena *arena, const char *username, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !word_valid(username, 1, NOSHI_USERNAME_LOOKUP_MAX, 0)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "contacts.resolveUsername");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "username", username);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static const noshi_tl_value *find_by_id(const noshi_tl_value *list, int64_t id) {
    uint32_t i;
    for (i = 0; is_vec(list) && i < list->u.vec.count; ++i) {
        int64_t found;
        if (noshi_tl_get_i64(list->u.vec.items[i], "id", &found) == NOSHI_OK && found == id) return list->u.vec.items[i];
    }
    return NULL;
}

noshi_status noshi_resolve_parse(const noshi_tl_value *answer, int64_t self_id, noshi_resolved *out) {
    noshi_peer peer;
    const noshi_tl_value *users, *chats;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_contacts_resolvedPeer)) return NOSHI_E_MALFORMED;
    if (noshi_peer_from_tl(noshi_tl_get(answer, "peer"), &peer) != NOSHI_OK) return NOSHI_E_MALFORMED;
    users = noshi_tl_get(answer, "users");
    chats = noshi_tl_get(answer, "chats");
    out->dialog.peer_kind = peer.kind;
    out->dialog.peer_id = peer.id;
    noshi_dialog_peer_read(&out->dialog, users, chats, self_id);
    if (!out->dialog.title[0] || out->dialog.deleted) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_NOTFOUND;
    }
    if (peer.kind == 1) {
        const noshi_tl_value *user = find_by_id(users, peer.id);
        if (user && noshi_person_parse(user, &out->person) == NOSHI_OK) out->is_user = 1;
    }
    return NOSHI_OK;
}

noshi_status noshi_top_inline_bots_request(noshi_arena *arena, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || limit < 1 || limit > NOSHI_TOP_BOTS_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "contacts.getTopPeers");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_flag(request, "bots_inline");
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    /* a zero hash always gets the list itself, never "not modified" */
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_top_inline_bots_parse(const noshi_tl_value *answer, noshi_person_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *categories, *users;
    uint32_t i, j;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || !cap) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_contacts_topPeersDisabled) || noshi_tl_is(answer, NOSHI_TL_ID_contacts_topPeersNotModified)) return NOSHI_OK;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_contacts_topPeers)) return NOSHI_E_MALFORMED;
    categories = noshi_tl_get(answer, "categories");
    users = noshi_tl_get(answer, "users");
    if (!is_vec(categories) || !is_vec(users)) return NOSHI_E_MALFORMED;
    if (categories->u.vec.count > 32 || users->u.vec.count > 1000) return NOSHI_E_LIMIT;
    for (i = 0; i < categories->u.vec.count; ++i) {
        const noshi_tl_value *category = categories->u.vec.items[i], *peers;
        if (!noshi_tl_is(category, NOSHI_TL_ID_topPeerCategoryPeers) || !noshi_tl_is(noshi_tl_get(category, "category"), NOSHI_TL_ID_topPeerCategoryBotsInline)) continue;
        peers = noshi_tl_get(category, "peers");
        if (!is_vec(peers)) return NOSHI_E_MALFORMED;
        for (j = 0; j < peers->u.vec.count && n < cap; ++j) {
            noshi_peer peer;
            const noshi_tl_value *user;
            noshi_person_row row;
            if (noshi_peer_from_tl(noshi_tl_get(peers->u.vec.items[j], "peer"), &peer) != NOSHI_OK || peer.kind != 1) continue;
            user = find_by_id(users, peer.id);
            if (!user || noshi_person_parse(user, &row) != NOSHI_OK || !row.bot || row.deleted || !row.username[0]) continue;
            rows[n++] = row;
        }
    }
    *count = n;
    return NOSHI_OK;
}

/* invite links */

#define INVITE_HASH_MAX 128

static noshi_status invite_request(noshi_arena *arena, const char *ctor, const char *hash, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !word_valid(hash, 1, INVITE_HASH_MAX, 1)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, ctor);
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "hash", hash);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_invite_check_request(noshi_arena *arena, const char *hash, noshi_tl_value **out) {
    return invite_request(arena, "messages.checkChatInvite", hash, out);
}

noshi_status noshi_invite_import_request(noshi_arena *arena, const char *hash, noshi_tl_value **out) {
    return invite_request(arena, "messages.importChatInvite", hash, out);
}

noshi_status noshi_invite_subscription_invoice(noshi_arena *arena, const char *hash, noshi_tl_value **out) {
    return invite_request(arena, "inputInvoiceChatInviteSubscription", hash, out);
}

/* a row for one chat object; the row reader looks the chat up by id in a list, so the chat is put in a list of one */
static noshi_status chat_row(const noshi_tl_value *chat, int64_t self_id, noshi_dialog_row *row) {
    noshi_tl_value *items[1];
    noshi_tl_value list;
    int64_t id;
    memset(row, 0, sizeof(*row));
    if (!chat || noshi_tl_get_i64(chat, "id", &id) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (noshi_tl_is(chat, NOSHI_TL_ID_channel) || noshi_tl_is(chat, NOSHI_TL_ID_channelForbidden)) row->peer_kind = 3;
    else if (noshi_tl_is(chat, NOSHI_TL_ID_chat)) row->peer_kind = 2;
    else return NOSHI_E_NOTFOUND;
    row->peer_id = id;
    items[0] = (noshi_tl_value *)chat;
    memset(&list, 0, sizeof(list));
    list.kind = NOSHI_TL_V_VEC;
    list.u.vec.count = 1;
    list.u.vec.items = items;
    noshi_dialog_peer_read(row, NULL, &list, self_id);
    return row->title[0] ? NOSHI_OK : NOSHI_E_NOTFOUND;
}

noshi_status noshi_invite_parse(const noshi_tl_value *answer, int64_t self_id, noshi_invite *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(answer, NOSHI_TL_ID_chatInviteAlready) || noshi_tl_is(answer, NOSHI_TL_ID_chatInvitePeek)) {
        noshi_status status = chat_row(noshi_tl_get(answer, "chat"), self_id, &out->dialog);
        if (status != NOSHI_OK) return status;
        out->member = 1;
        cut_into(out->title, sizeof(out->title), out->dialog.title);
        return NOSHI_OK;
    }
    if (!noshi_tl_is(answer, NOSHI_TL_ID_chatInvite)) return NOSHI_E_MALFORMED;
    copy_text(out->title, sizeof(out->title), answer, "title", 0);
    if (!out->title[0]) return NOSHI_E_MALFORMED;
    copy_text(out->about, sizeof(out->about), answer, "about", 1);
    {
        noshi_media_info photo;
        noshi_photo_read(noshi_tl_get(answer, "photo"), 180, &photo);
        out->photo = photo.ref;
    }
    noshi_tl_get_i32(answer, "participants_count", &out->participants);
    if (out->participants < 0) out->participants = 0;
    out->broadcast = noshi_tl_has(answer, "broadcast") ? 1 : 0;
    out->request_needed = noshi_tl_has(answer, "request_needed") ? 1 : 0;
    out->verified = noshi_tl_has(answer, "verified") ? 1 : 0;
    if (noshi_tl_has(answer, "subscription_pricing")) {
        const noshi_tl_value *pricing = noshi_tl_get(answer, "subscription_pricing");
        int64_t stars = 0;
        int32_t period = 0;
        /* a price that is not positive is no price, so the chat is offered as free and the server decides */
        if (noshi_tl_is(pricing, NOSHI_TL_ID_starsSubscriptionPricing) && noshi_tl_get_i64(pricing, "amount", &stars) == NOSHI_OK && stars > 0 &&
            noshi_tl_get_i32(pricing, "period", &period) == NOSHI_OK && period > 0) {
            out->subscription_stars = stars;
            out->subscription_period = period;
        }
    }
    return NOSHI_OK;
}

noshi_status noshi_invite_joined_parse(const noshi_tl_value *answer, int64_t self_id, noshi_dialog_row *out) {
    const noshi_tl_value *updates, *chats;
    uint32_t i;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_chatInviteJoinResultWebView)) return NOSHI_E_UNSUPPORTED;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chatInviteJoinResultOk)) return NOSHI_E_MALFORMED;
    updates = noshi_tl_get(answer, "updates");
    chats = noshi_tl_get(updates, "chats");
    if (!is_vec(chats)) return NOSHI_E_MALFORMED;
    for (i = 0; i < chats->u.vec.count; ++i) {
        if (chat_row(chats->u.vec.items[i], self_id, out) == NOSHI_OK) return NOSHI_OK;
    }
    memset(out, 0, sizeof(*out));
    return NOSHI_E_NOTFOUND;
}

/* bot info */

static void read_commands(const noshi_tl_value *list, noshi_bot_info *out) {
    uint32_t i;
    if (!is_vec(list)) return;
    for (i = 0; i < list->u.vec.count && out->command_count < NOSHI_BOT_COMMANDS_MAX; ++i) {
        const noshi_tl_value *c = list->u.vec.items[i];
        noshi_bot_command *row = &out->commands[out->command_count];
        if (!noshi_tl_is(c, NOSHI_TL_ID_botCommand) || noshi_tl_has(c, "ephemeral")) continue;
        /* a command that is cut would be sent as another command, so only whole names count */
        if (!copy_whole(row->name, sizeof(row->name), c, "command") || !word_valid(row->name, 1, 32, 0)) continue;
        copy_text(row->text, sizeof(row->text), c, "description", 0);
        ++out->command_count;
    }
}

static void read_menu(const noshi_tl_value *button, noshi_bot_info *out) {
    /* a web app menu button stays the default menu, this client has no way to open the app */
    if (noshi_tl_is(button, NOSHI_TL_ID_botMenuButtonCommands)) out->menu_kind = NOSHI_BOT_MENU_COMMANDS;
}

#define BOT_PICTURE_TARGET 480

noshi_status noshi_bot_info_parse(const noshi_tl_value *answer, noshi_bot_info *out) {
    const noshi_tl_value *full, *info;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_users_userFull)) return NOSHI_E_MALFORMED;
    full = noshi_tl_get(answer, "full_user");
    if (!noshi_tl_is(full, NOSHI_TL_ID_userFull)) return NOSHI_E_MALFORMED;
    info = noshi_tl_get(full, "bot_info");
    if (!noshi_tl_is(info, NOSHI_TL_ID_botInfo)) return NOSHI_OK;
    out->present = 1;
    copy_text(out->description, sizeof(out->description), info, "description", 1);
    copy_whole(out->privacy_url, sizeof(out->privacy_url), info, "privacy_policy_url");
    read_commands(noshi_tl_get(info, "commands"), out);
    read_menu(noshi_tl_get(info, "menu_button"), out);
    if (noshi_tl_has(info, "description_document")) {
        noshi_document_read(noshi_tl_get(info, "description_document"), &out->picture);
        out->has_picture = out->picture.ref.source != NOSHI_MEDIA_SOURCE_NONE;
    }
    if (!out->has_picture && noshi_tl_has(info, "description_photo")) {
        noshi_photo_read(noshi_tl_get(info, "description_photo"), BOT_PICTURE_TARGET, &out->picture);
        out->has_picture = out->picture.ref.source != NOSHI_MEDIA_SOURCE_NONE;
    }
    if (!out->has_picture) memset(&out->picture, 0, sizeof(out->picture));
    return NOSHI_OK;
}

noshi_status noshi_start_bot_request(noshi_arena *arena, const noshi_peer_ref *bot, const noshi_peer_ref *peer,
                                         int64_t random_id, const char *param, noshi_tl_value **out) {
    noshi_tl_value *request, *user, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !peer || random_id == 0 || !param || !word_valid(param, 1, NOSHI_START_PARAM_MAX, 1)) return NOSHI_E_ARG;
    status = input_user(arena, bot, &user);
    if (status == NOSHI_OK) status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.startBot");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "bot", user);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "start_param", param);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* callbacks */

noshi_status noshi_callback_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, const uint8_t *data,
                                        size_t data_len, int game, noshi_tl_value *password, noshi_tl_value **out) {
    static const uint8_t none[1] = {0};
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || msg_id <= 0 || data_len > NOSHI_MARKUP_DATA_MAX || (data_len && !data)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.getBotCallbackAnswer");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", msg_id);
    if (status == NOSHI_OK && game) status = noshi_tl_set_flag(request, "game");
    else if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, request, "data", data_len ? data : none, data_len);
    if (status == NOSHI_OK && password) status = noshi_tl_set(request, "password", password);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_callback_parse(const noshi_tl_value *answer, noshi_callback_answer *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_botCallbackAnswer)) return NOSHI_E_MALFORMED;
    out->alert = noshi_tl_has(answer, "alert") ? 1 : 0;
    out->native_ui = noshi_tl_has(answer, "native_ui") ? 1 : 0;
    noshi_tl_get_i32(answer, "cache_time", &out->cache_time);
    copy_text(out->message, sizeof(out->message), answer, "message", 1);
    /* an address that does not fit whole is dropped: opening a cut address would open another page */
    if (noshi_tl_has(answer, "url") && copy_whole(out->url, sizeof(out->url), answer, "url") && out->url[0]) out->has_url = 1;
    else out->url[0] = 0;
    return NOSHI_OK;
}

noshi_status noshi_password_request(noshi_arena *arena, noshi_tl_value **out) {
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    *out = noshi_tl_new_obj(arena, "account.getPassword");
    return *out ? NOSHI_OK : NOSHI_E_NOMEM;
}

noshi_status noshi_password_input(noshi_arena *arena, const noshi_tl_value *account_password, const char *password,
                                      noshi_tl_value **out) {
    noshi_srp_proof proof;
    noshi_tl_value *check;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !password || !password[0] || !noshi_tl_is(account_password, NOSHI_TL_ID_account_password)) return NOSHI_E_ARG;
    if (!noshi_tl_has(account_password, "has_password")) return NOSHI_E_UNSUPPORTED;
    status = noshi_srp_check(account_password, (const uint8_t *)password, strlen(password), &proof);
    if (status != NOSHI_OK) return status;
    check = noshi_tl_new_obj(arena, "inputCheckPasswordSRP");
    if (!check) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, check, "srp_id", proof.id);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, check, "A", proof.A, sizeof(proof.A));
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, check, "M1", proof.M1, sizeof(proof.M1));
    if (status == NOSHI_OK) *out = check;
    return status;
}

/* inline mode */

int noshi_inline_address_parse(const char *text, char *name, size_t capacity, const char **query) {
    if (name && capacity) name[0] = 0;
    if (query) *query = NULL;
    if (!text || text[0] != '@' || !name || !capacity || !query) return 0;
    const char *space = strchr(text, ' ');
    if (!space || space == text + 1) return 0;
    size_t length = (size_t)(space - text - 1);
    if (length >= capacity || length >= NOSHI_LINK_NAME_MAX) return 0;
    char candidate[NOSHI_LINK_NAME_MAX];
    memcpy(candidate, text + 1, length);
    candidate[length] = 0;
    if (candidate[0] == '@' || noshi_mention_name(candidate, name, capacity) != NOSHI_OK) return 0;
    *query = space + 1;
    return 1;
}

noshi_status noshi_inline_query_request(noshi_arena *arena, const noshi_peer_ref *bot, const noshi_peer_ref *peer,
                                            const char *query, const char *offset, noshi_tl_value **out) {
    noshi_tl_value *request, *user, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !query || !offset || strlen(query) > NOSHI_INLINE_QUERY_MAX || strlen(offset) >= NOSHI_INLINE_OFFSET_MAX ||
        !utf8_valid(query)) return NOSHI_E_ARG;
    status = input_user(arena, bot, &user);
    if (status == NOSHI_OK) status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.getInlineBotResults");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "bot", user);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "query", query);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "offset", offset);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_inline_query_set_location(noshi_arena *arena, noshi_tl_value *request, const noshi_geo_point *point) {
    noshi_tl_value *geo = NULL;
    if (!arena || !noshi_tl_is(request, NOSHI_TL_ID_messages_getInlineBotResults) || !point) return NOSHI_E_ARG;
    if (!point->valid) return NOSHI_OK;
    noshi_status status = noshi_geo_input(arena, point, &geo);
    return status == NOSHI_OK ? noshi_tl_set(request, "geo_point", geo) : status;
}

static void read_web_ref(const noshi_tl_value *document, noshi_web_ref *out, int32_t *width, int32_t *height, int32_t *duration) {
    const noshi_tl_value *attributes;
    uint32_t i;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(document, NOSHI_TL_ID_webDocument)) {
        out->proxied = 1;
        if (noshi_tl_get_i64(document, "access_hash", &out->access_hash) != NOSHI_OK) return;
    } else if (!noshi_tl_is(document, NOSHI_TL_ID_webDocumentNoProxy)) {
        return;
    }
    if (!copy_whole(out->url, sizeof(out->url), document, "url") || !out->url[0]) {
        memset(out, 0, sizeof(*out));
        return;
    }
    noshi_tl_get_i32(document, "size", &out->size);
    copy_text(out->mime, sizeof(out->mime), document, "mime_type", 0);
    out->present = 1;
    attributes = noshi_tl_get(document, "attributes");
    for (i = 0; is_vec(attributes) && i < attributes->u.vec.count; ++i) {
        const noshi_tl_value *a = attributes->u.vec.items[i];
        double seconds = 0;
        if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeImageSize)) {
            noshi_tl_get_i32(a, "w", width);
            noshi_tl_get_i32(a, "h", height);
        } else if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeVideo)) {
            noshi_tl_get_i32(a, "w", width);
            noshi_tl_get_i32(a, "h", height);
            if (noshi_tl_get_f64(a, "duration", &seconds) == NOSHI_OK && seconds > 0 && seconds < 2147483647.0) *duration = (int32_t)seconds;
        } else if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeAudio)) {
            noshi_tl_get_i32(a, "duration", duration);
        }
    }
}

static noshi_inline_kind inline_kind(const noshi_tl_value *result) {
    const uint8_t *type;
    size_t len;
    static const struct { const char *name; noshi_inline_kind kind; } table[] = {
        {"article", NOSHI_INLINE_ARTICLE}, {"photo", NOSHI_INLINE_PHOTO}, {"gif", NOSHI_INLINE_GIF}, {"mpeg4_gif", NOSHI_INLINE_GIF},
        {"video", NOSHI_INLINE_VIDEO}, {"audio", NOSHI_INLINE_AUDIO}, {"voice", NOSHI_INLINE_VOICE},
        {"document", NOSHI_INLINE_FILE}, {"sticker", NOSHI_INLINE_STICKER}, {"geo", NOSHI_INLINE_LOCATION},
        {"venue", NOSHI_INLINE_LOCATION}, {"contact", NOSHI_INLINE_CONTACT}, {"game", NOSHI_INLINE_GAME}
    };
    size_t i;
    if (noshi_tl_get_bytes(result, "type", &type, &len) != NOSHI_OK) return NOSHI_INLINE_OTHER;
    for (i = 0; i < sizeof(table) / sizeof(table[0]); ++i) {
        if (strlen(table[i].name) == len && memcmp(table[i].name, type, len) == 0) return table[i].kind;
    }
    return NOSHI_INLINE_OTHER;
}

/* what an article says when the bot gave it no description: the first words of the message it will send */
static void message_preview(const noshi_tl_value *result, char *dst, size_t cap) {
    const noshi_tl_value *message = noshi_tl_get(result, "send_message");
    dst[0] = 0;
    if (noshi_tl_is(message, NOSHI_TL_ID_botInlineMessageText) || noshi_tl_is(message, NOSHI_TL_ID_botInlineMessageMediaAuto))
        copy_text(dst, cap, message, "message", 0);
}

static int read_inline_result(const noshi_tl_value *r, noshi_inline_result *out) {
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(r, NOSHI_TL_ID_botInlineResult)) {
        const noshi_tl_value *thumb = noshi_tl_get(r, "thumb"), *content = noshi_tl_get(r, "content");
        int32_t w = 0, h = 0, d = 0;
        if (!copy_whole(out->id, sizeof(out->id), r, "id") || !out->id[0]) return 0;
        out->kind = (uint8_t)inline_kind(r);
        copy_text(out->title, sizeof(out->title), r, "title", 0);
        copy_text(out->description, sizeof(out->description), r, "description", 0);
        noshi_web_ref whole;
        read_web_ref(thumb, &out->thumb, &w, &h, &d);
        read_web_ref(content, &whole, &out->width, &out->height, &out->duration);
        /* a picture or an animation that has no thumbnail is its own thumbnail */
        if (!out->thumb.present && (out->kind == NOSHI_INLINE_PHOTO || out->kind == NOSHI_INLINE_GIF) && whole.present &&
            !strncmp(whole.mime, "image/", 6)) out->thumb = whole;
        if (!out->width) out->width = w;
        if (!out->height) out->height = h;
        if (!out->duration) out->duration = d;
    } else if (noshi_tl_is(r, NOSHI_TL_ID_botInlineMediaResult)) {
        if (!copy_whole(out->id, sizeof(out->id), r, "id") || !out->id[0]) return 0;
        out->kind = (uint8_t)inline_kind(r);
        copy_text(out->title, sizeof(out->title), r, "title", 0);
        copy_text(out->description, sizeof(out->description), r, "description", 0);
        if (noshi_tl_has(r, "document")) noshi_document_read(noshi_tl_get(r, "document"), &out->media);
        else if (noshi_tl_has(r, "photo")) noshi_photo_read(noshi_tl_get(r, "photo"), 320, &out->media);
        if (out->media.ref.source == NOSHI_MEDIA_SOURCE_NONE && out->media.preview.source == NOSHI_MEDIA_SOURCE_NONE)
            memset(&out->media, 0, sizeof(out->media));
        out->width = out->media.width;
        out->height = out->media.height;
        out->duration = out->media.duration;
    } else {
        return 0;
    }
    if (out->kind == NOSHI_INLINE_LOCATION) {
        const noshi_tl_value *message = noshi_tl_get(r, "send_message");
        if (noshi_geo_read(noshi_tl_get(message, "geo"),
            noshi_tl_is(message, NOSHI_TL_ID_botInlineMessageMediaVenue) ? message : NULL, &out->media.location) != NOSHI_OK) return 0;
        out->media.kind = NOSHI_PREVIEW_LOCATION;
        out->media.width = 320;
        out->media.height = 180;
    }
    if (!out->description[0]) message_preview(r, out->description, sizeof(out->description));
    return 1;
}

noshi_status noshi_inline_results_parse(const noshi_tl_value *answer, noshi_inline_page *page, noshi_inline_result *rows,
                                            size_t cap, size_t *count) {
    const noshi_tl_value *results, *pm;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!page) return NOSHI_E_ARG;
    memset(page, 0, sizeof(*page));
    if (!rows || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_botResults) || noshi_tl_get_vec(answer, "results", &results) != NOSHI_OK ||
        noshi_tl_get_i64(answer, "query_id", &page->query_id) != NOSHI_OK) return NOSHI_E_MALFORMED;
    page->gallery = noshi_tl_has(answer, "gallery") ? 1 : 0;
    noshi_tl_get_i32(answer, "cache_time", &page->cache_time);
    /* a cut offset would fetch another page, so a long one ends the paging instead */
    if (!copy_whole(page->next_offset, sizeof(page->next_offset), answer, "next_offset")) page->next_offset[0] = 0;
    pm = noshi_tl_get(answer, "switch_pm");
    if (noshi_tl_is(pm, NOSHI_TL_ID_inlineBotSwitchPM)) {
        copy_text(page->switch_text, sizeof(page->switch_text), pm, "text", 0);
        if (!copy_whole(page->switch_param, sizeof(page->switch_param), pm, "start_param") ||
            (page->switch_param[0] && !word_valid(page->switch_param, 1, NOSHI_START_PARAM_MAX, 1))) {
            page->switch_text[0] = 0;
            page->switch_param[0] = 0;
        }
    }
    const noshi_tl_value *web = noshi_tl_get(answer, "switch_webview");
    if (noshi_tl_is(web, NOSHI_TL_ID_inlineBotWebView))
        copy_text(page->web_text, sizeof(page->web_text), web, "text", 0);
    for (i = 0; i < results->u.vec.count && n < cap; ++i) {
        if (read_inline_result(results->u.vec.items[i], &rows[n])) {
            rows[n].query_id = page->query_id;
            ++n;
        }
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_inline_send_request(noshi_arena *arena, const noshi_peer_ref *peer, int64_t random_id, int64_t query_id,
                                           const char *result_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !peer || random_id == 0 || !result_id || !result_id[0] || strlen(result_id) >= NOSHI_INLINE_ID_MAX) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.sendInlineBotResult");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_topic_reply(arena, request, peer);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "query_id", query_id);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "id", result_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_user_from_message_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, int64_t user_id, noshi_tl_value **out) {
    noshi_tl_value *request, *list, *user, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || msg_id <= 0 || user_id <= 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "users.getUsers");
    list = noshi_tl_new_vec(arena, 1);
    user = noshi_tl_new_obj(arena, "inputUserFromMessage");
    if (!request || !list || !user) return NOSHI_E_NOMEM;
    status = noshi_tl_set(user, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, user, "msg_id", msg_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, user, "user_id", user_id);
    if (status == NOSHI_OK) status = noshi_tl_vec_set(list, 0, user);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_user_from_message_parse(const noshi_tl_value *answer, int64_t user_id, noshi_person_row *out) {
    uint32_t i;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!is_vec(answer)) return NOSHI_E_MALFORMED;
    for (i = 0; i < answer->u.vec.count; ++i) {
        noshi_person_row row;
        if (noshi_person_parse(answer->u.vec.items[i], &row) == NOSHI_OK && row.id == user_id) {
            *out = row;
            return NOSHI_OK;
        }
    }
    return NOSHI_E_NOTFOUND;
}

/* signing in on a site */

static noshi_status set_button_target(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *peer, int32_t msg_id,
                                        int32_t button_id, const char *url) {
    noshi_tl_value *input;
    noshi_status status = NOSHI_OK;
    if (peer) {
        status = noshi_input_peer(arena, peer, &input);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", msg_id);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "button_id", button_id);
    }
    if (status == NOSHI_OK && url) status = noshi_tl_set_str(arena, request, "url", url);
    return status;
}

static int url_auth_target_valid(const noshi_peer_ref *peer, int32_t msg_id, const char *url) {
    if (peer) return msg_id > 0;
    return url && url[0] && strlen(url) < NOSHI_BOT_URL_MAX && utf8_valid(url);
}

noshi_status noshi_url_auth_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, int32_t button_id,
                                        const char *url, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !url_auth_target_valid(peer, msg_id, url)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.requestUrlAuth");
    if (!request) return NOSHI_E_NOMEM;
    status = set_button_target(arena, request, peer, msg_id, button_id, peer ? NULL : url);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_url_auth_accept_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, int32_t button_id,
                                               const char *url, int write_allowed, int share_phone, const char *code, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !url_auth_target_valid(peer, msg_id, url) || (code && (!code[0] || strlen(code) >= 16))) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.acceptUrlAuth");
    if (!request) return NOSHI_E_NOMEM;
    status = NOSHI_OK;
    if (write_allowed) status = noshi_tl_set_flag(request, "write_allowed");
    if (status == NOSHI_OK && share_phone) status = noshi_tl_set_flag(request, "share_phone_number");
    if (status == NOSHI_OK) status = set_button_target(arena, request, peer, msg_id, button_id, peer ? NULL : url);
    if (status == NOSHI_OK && code) status = noshi_tl_set_str(arena, request, "match_code", code);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_url_auth_parse(const noshi_tl_value *answer, noshi_url_auth *out) {
    const noshi_tl_value *bot, *codes;
    uint32_t i;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(answer, NOSHI_TL_ID_urlAuthResultDefault)) {
        out->kind = NOSHI_URL_AUTH_OPEN;
        return NOSHI_OK;
    }
    if (noshi_tl_is(answer, NOSHI_TL_ID_urlAuthResultAccepted)) {
        out->kind = NOSHI_URL_AUTH_DONE;
        /* an accepted login without an address leaves the person on the page they were on */
        if (noshi_tl_has(answer, "url") && !copy_whole(out->url, sizeof(out->url), answer, "url")) out->url[0] = 0;
        return NOSHI_OK;
    }
    if (!noshi_tl_is(answer, NOSHI_TL_ID_urlAuthResultRequest)) return NOSHI_E_MALFORMED;
    out->kind = NOSHI_URL_AUTH_ASK;
    out->request_write = noshi_tl_has(answer, "request_write_access") ? 1 : 0;
    out->request_phone = noshi_tl_has(answer, "request_phone_number") ? 1 : 0;
    if (!copy_whole(out->domain, sizeof(out->domain), answer, "domain") || !out->domain[0]) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    bot = noshi_tl_get(answer, "bot");
    if (noshi_tl_is(bot, NOSHI_TL_ID_user)) {
        noshi_person_row person;
        if (noshi_person_parse(bot, &person) == NOSHI_OK) cut_into(out->bot, sizeof(out->bot), person.name);
    }
    codes = noshi_tl_get(answer, "match_codes");
    for (i = 0; is_vec(codes) && i < codes->u.vec.count && out->code_count < NOSHI_URL_AUTH_CODES_MAX; ++i) {
        const uint8_t *data;
        size_t len;
        if (codes->u.vec.items[i]->kind != NOSHI_TL_V_BYTES) continue;
        data = codes->u.vec.items[i]->u.bytes.data;
        len = codes->u.vec.items[i]->u.bytes.len;
        if (!len || len >= sizeof(out->codes[0])) continue;
        memcpy(out->codes[out->code_count], data, len);
        out->codes[out->code_count][len] = 0;
        ++out->code_count;
    }
    return NOSHI_OK;
}

/* invoices */

noshi_status noshi_invoice_message_input(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, noshi_tl_value **out) {
    noshi_tl_value *invoice, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || msg_id <= 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    invoice = noshi_tl_new_obj(arena, "inputInvoiceMessage");
    if (!invoice) return NOSHI_E_NOMEM;
    status = noshi_tl_set(invoice, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, invoice, "msg_id", msg_id);
    if (status == NOSHI_OK) *out = invoice;
    return status;
}

noshi_status noshi_invoice_slug_input(noshi_arena *arena, const char *slug, noshi_tl_value **out) {
    noshi_tl_value *invoice;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !word_valid(slug, 1, 128, 1)) return NOSHI_E_ARG;
    invoice = noshi_tl_new_obj(arena, "inputInvoiceSlug");
    if (!invoice) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, invoice, "slug", slug);
    if (status == NOSHI_OK) *out = invoice;
    return status;
}

noshi_status noshi_stars_form_parse(const noshi_tl_value *answer, noshi_stars_form *out) {
    const noshi_tl_value *invoice, *prices;
    const uint8_t *currency;
    size_t currency_len, i;
    int64_t total = 0;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(answer, NOSHI_TL_ID_payments_paymentForm)) return NOSHI_E_UNSUPPORTED;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_payments_paymentFormStars)) return NOSHI_E_MALFORMED;
    invoice = noshi_tl_get(answer, "invoice");
    if (noshi_tl_get_i64(answer, "form_id", &out->form_id) != NOSHI_OK || !noshi_tl_is(invoice, NOSHI_TL_ID_invoice) ||
        noshi_tl_get_bytes(invoice, "currency", &currency, &currency_len) != NOSHI_OK ||
        noshi_tl_get_vec(invoice, "prices", &prices) != NOSHI_OK || prices->u.vec.count == 0 || prices->u.vec.count > PRICES_MAX) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    if (currency_len != 3 || memcmp(currency, "XTR", 3) != 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_UNSUPPORTED;
    }
    for (i = 0; i < prices->u.vec.count; ++i) {
        int64_t amount;
        if (noshi_tl_get_i64(prices->u.vec.items[i], "amount", &amount) != NOSHI_OK || amount < 0 || amount > INT64_MAX - total) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        total += amount;
    }
    out->stars = total;
    noshi_tl_get_i64(answer, "bot_id", &out->bot_id);
    copy_text(out->title, sizeof(out->title), answer, "title", 0);
    copy_text(out->description, sizeof(out->description), answer, "description", 1);
    return NOSHI_OK;
}

/* answers to a keyboard */

noshi_status noshi_send_contact_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *phone, const char *first_name,
                                            const char *last_name, int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *media;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || random_id == 0 || !phone || !phone[0] || !first_name || !last_name || strlen(phone) > 32 || strlen(first_name) > 128 ||
        strlen(last_name) > 128 || !utf8_valid(first_name) || !utf8_valid(last_name)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.sendMedia");
    media = noshi_tl_new_obj(arena, "inputMediaContact");
    if (!request || !media) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, media, "phone_number", phone);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "first_name", first_name);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "last_name", last_name);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "vcard", "");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_topic_reply(arena, request, peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", "");
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_requested_peers_request(noshi_arena *arena, const noshi_peer_ref *bot_chat, int32_t msg_id, int32_t button_id,
                                               const noshi_peer_ref *peers, size_t count, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *list;
    noshi_status status;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !out || !peers || count == 0 || count > 10 || msg_id <= 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, bot_chat, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.sendBotRequestedPeer");
    list = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!request || !list) return NOSHI_E_NOMEM;
    for (i = 0; i < count && status == NOSHI_OK; ++i) {
        noshi_tl_value *picked;
        status = noshi_input_peer(arena, &peers[i], &picked);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(list, (uint32_t)i, picked);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", msg_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "button_id", button_id);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "requested_peers", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}
