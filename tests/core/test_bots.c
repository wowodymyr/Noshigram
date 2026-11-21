#include "test_util.h"
#include "noshi_bots.h"
#include "noshi_links.h"
#include "noshi_tl_ids.h"
#include "srp_vectors.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set(noshi_tl_value *v, const char *field, noshi_tl_value *x) {
    CHECK_EQ_INT(noshi_tl_set(v, field, x), NOSHI_OK);
}
static void i32(noshi_tl_value *v, const char *field, int32_t x) {
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, field, x), NOSHI_OK);
}
static void i64(noshi_tl_value *v, const char *field, int64_t x) {
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, field, x), NOSHI_OK);
}
static void str(noshi_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, field, x), NOSHI_OK);
}
static void flag(noshi_tl_value *v, const char *field) {
    CHECK_EQ_INT(noshi_tl_set_flag(v, field), NOSHI_OK);
}
static noshi_tl_value *vec_of(noshi_tl_value **items, uint32_t n) {
    noshi_tl_value *vec = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(vec, i, items[i]), NOSHI_OK);
    return vec;
}

/* a request has to encode with the schema's own rules, which catches a misspelled field or a missing flag */
static void roundtrip(noshi_tl_value *request, uint32_t constructor) {
    noshi_writer writer;
    noshi_tl_value *decoded = NULL;
    CHECK(request != NULL);
    noshi_writer_init(&writer, 65536);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, writer.data, writer.len, &decoded), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(decoded), constructor);
    noshi_writer_free(&writer);
}

static noshi_tl_value *user(int64_t id, const char *name, int bot) {
    noshi_tl_value *v = obj("user");
    i64(v, "id", id);
    i64(v, "access_hash", id * 10);
    str(v, "first_name", name);
    str(v, "username", name);
    if (bot) {
        flag(v, "bot");
        flag(v, "bot_inline_geo");
        str(v, "bot_inline_placeholder", "search cats");
    }
    return v;
}

static noshi_tl_value *peer_user(int64_t id) {
    noshi_tl_value *p = obj("peerUser");
    i64(p, "user_id", id);
    return p;
}

static const noshi_peer_ref bot = {1, 77, 770, 0, 0};
static const noshi_peer_ref chat = {1, 5, 50, 0, 0};
static const noshi_peer_ref group = {2, 9, 0, 0, 0};
static const noshi_peer_ref forum = {3, 12, 120, 0, 44};

static void test_resolve(void) {
    noshi_tl_value *request = NULL, *answer, *users[1];
    noshi_resolved resolved;
    CHECK_EQ_INT(noshi_resolve_request(&arena, "durov_bot", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_contacts_resolveUsername);
    CHECK_EQ_INT(noshi_resolve_request(&arena, "", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_resolve_request(&arena, "a b", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_resolve_request(&arena, "a/b", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_resolve_request(&arena, "@bot", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_resolve_request(&arena, "012345678901234567890123456789012", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_resolve_request(&arena, NULL, &request), NOSHI_E_ARG);

    answer = obj("contacts.resolvedPeer");
    set(answer, "peer", peer_user(77));
    users[0] = user(77, "helper_bot", 1);
    set(answer, "users", vec_of(users, 1));
    set(answer, "chats", vec_of(NULL, 0));
    CHECK_EQ_INT(noshi_resolve_parse(answer, 1, &resolved), NOSHI_OK);
    CHECK_EQ_INT(resolved.is_user, 1);
    CHECK_EQ_INT(resolved.dialog.peer_kind, 1);
    CHECK_EQ_INT(resolved.dialog.peer_id, 77);
    CHECK_EQ_INT(resolved.dialog.peer_hash, 770);
    CHECK_EQ_INT(resolved.dialog.kind, NOSHI_DIALOG_BOT);
    CHECK_EQ_INT(resolved.person.bot, 1);
    CHECK_EQ_INT(resolved.person.bot_inline, 1);
    CHECK_EQ_INT(resolved.person.bot_inline_geo, 1);
    CHECK_EQ_INT(resolved.person.bot_no_chats, 0);
    CHECK(!strcmp(resolved.person.bot_placeholder, "search cats"));

    /* a person has none of the bot flags even when the answer carried the fields */
    users[0] = user(78, "friend", 0);
    set(answer, "peer", peer_user(78));
    set(answer, "users", vec_of(users, 1));
    CHECK_EQ_INT(noshi_resolve_parse(answer, 1, &resolved), NOSHI_OK);
    CHECK_EQ_INT(resolved.person.bot, 0);
    CHECK_EQ_INT(resolved.person.bot_inline, 0);
    CHECK_EQ_INT(resolved.dialog.kind, NOSHI_DIALOG_USER);

    /* the peer is not among the users */
    set(answer, "peer", peer_user(99));
    CHECK_EQ_INT(noshi_resolve_parse(answer, 1, &resolved), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(resolved.dialog.peer_id, 0);
    CHECK_EQ_INT(noshi_resolve_parse(obj("boolTrue"), 1, &resolved), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_resolve_parse(answer, 1, NULL), NOSHI_E_ARG);
}

static noshi_tl_value *channel_obj(int64_t id, const char *title) {
    noshi_tl_value *c = obj("channel");
    i64(c, "id", id);
    str(c, "title", title);
    flag(c, "broadcast");
    i64(c, "access_hash", id * 10);
    return c;
}

static void test_invite(void) {
    noshi_tl_value *request = NULL, *answer, *items[2], *updates, *joined;
    noshi_invite invite;
    noshi_dialog_row row;
    CHECK_EQ_INT(noshi_invite_check_request(&arena, "AbC-d_1", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_checkChatInvite);
    CHECK_EQ_INT(noshi_invite_import_request(&arena, "AbC-d_1", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_importChatInvite);
    CHECK_EQ_INT(noshi_invite_check_request(&arena, "", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_invite_import_request(&arena, "a b", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_invite_check_request(&arena, NULL, &request), NOSHI_E_ARG);

    answer = obj("chatInvite");
    flag(answer, "channel");
    flag(answer, "broadcast");
    flag(answer, "request_needed");
    str(answer, "title", "Secret\nclub");
    str(answer, "about", "line one\nline two");
    i32(answer, "participants_count", 4200);
    CHECK_EQ_INT(noshi_invite_parse(answer, 1, &invite), NOSHI_OK);
    CHECK_EQ_INT(invite.member, 0);
    CHECK_EQ_INT(invite.broadcast, 1);
    CHECK_EQ_INT(invite.request_needed, 1);
    CHECK_EQ_INT(invite.participants, 4200);
    CHECK(!strcmp(invite.title, "Secret club"));
    CHECK(!strcmp(invite.about, "line one\nline two"));
    CHECK_EQ_INT(invite.photo.source, NOSHI_MEDIA_SOURCE_NONE);
    CHECK_EQ_INT(invite.subscription_stars, 0);
    {
        noshi_tl_value *pricing = obj("starsSubscriptionPricing"), *invoice = NULL;
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, pricing, "period", 2592000), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, pricing, "amount", 50), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(answer, "subscription_pricing", pricing), NOSHI_OK);
        CHECK_EQ_INT(noshi_invite_parse(answer, 1, &invite), NOSHI_OK);
        CHECK_EQ_INT(invite.subscription_stars, 50);
        CHECK_EQ_INT(invite.subscription_period, 2592000);
        /* a price of zero is no subscription */
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, pricing, "amount", 0), NOSHI_OK);
        CHECK_EQ_INT(noshi_invite_parse(answer, 1, &invite), NOSHI_OK);
        CHECK_EQ_INT(invite.subscription_stars, 0);
        CHECK_EQ_INT(noshi_invite_subscription_invoice(&arena, "abc_DEF-1", &invoice), NOSHI_OK);
        CHECK(noshi_tl_is(invoice, NOSHI_TL_ID_inputInvoiceChatInviteSubscription));
        CHECK_EQ_INT(noshi_invite_subscription_invoice(&arena, "a b", &invoice), NOSHI_E_ARG);
    }
    {
        noshi_tl_value *photo = obj("photo"), *small = obj("photoSize"), *large = obj("photoSize");
        noshi_tl_value *sizes[2] = {small, large};
        i64(photo, "id", 31);
        i64(photo, "access_hash", 32);
        CHECK_EQ_INT(noshi_tl_set_bytes(&arena, photo, "file_reference", "abc", 3), NOSHI_OK);
        i32(photo, "dc_id", 4);
        str(small, "type", "s"); i32(small, "w", 90); i32(small, "h", 90); i32(small, "size", 1000);
        str(large, "type", "m"); i32(large, "w", 180); i32(large, "h", 180); i32(large, "size", 5000);
        set(photo, "sizes", vec_of(sizes, 2));
        set(answer, "photo", photo);
        CHECK_EQ_INT(noshi_invite_parse(answer, 1, &invite), NOSHI_OK);
        CHECK_EQ_INT(invite.photo.source, NOSHI_MEDIA_SOURCE_PHOTO);
        CHECK_EQ_INT(invite.photo.id, 31);
        CHECK_EQ_INT(invite.photo.dc, 4);
        CHECK(!strcmp(invite.photo.thumb, "m"));
        set(answer, "photo", obj("photoEmpty"));
        CHECK_EQ_INT(noshi_invite_parse(answer, 1, &invite), NOSHI_OK);
        CHECK_EQ_INT(invite.photo.source, NOSHI_MEDIA_SOURCE_NONE);
    }

    answer = obj("chatInvite");
    str(answer, "title", "");
    CHECK_EQ_INT(noshi_invite_parse(answer, 1, &invite), NOSHI_E_MALFORMED);

    answer = obj("chatInviteAlready");
    set(answer, "chat", channel_obj(500, "Known"));
    CHECK_EQ_INT(noshi_invite_parse(answer, 1, &invite), NOSHI_OK);
    CHECK_EQ_INT(invite.member, 1);
    CHECK_EQ_INT(invite.dialog.peer_kind, 3);
    CHECK_EQ_INT(invite.dialog.peer_id, 500);
    CHECK_EQ_INT(invite.dialog.peer_hash, 5000);
    CHECK(!strcmp(invite.title, "Known"));
    CHECK_EQ_INT(noshi_invite_parse(obj("boolTrue"), 1, &invite), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_invite_parse(answer, 1, NULL), NOSHI_E_ARG);

    joined = obj("messages.chatInviteJoinResultOk");
    updates = obj("updates");
    items[0] = channel_obj(600, "Joined");
    set(updates, "chats", vec_of(items, 1));
    set(updates, "users", vec_of(NULL, 0));
    set(updates, "updates", vec_of(NULL, 0));
    i32(updates, "date", 1);
    i32(updates, "seq", 1);
    set(joined, "updates", updates);
    CHECK_EQ_INT(noshi_invite_joined_parse(joined, 1, &row), NOSHI_OK);
    CHECK_EQ_INT(row.peer_kind, 3);
    CHECK_EQ_INT(row.peer_id, 600);
    CHECK(!strcmp(row.title, "Joined"));

    set(updates, "chats", vec_of(NULL, 0));
    CHECK_EQ_INT(noshi_invite_joined_parse(joined, 1, &row), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_invite_joined_parse(obj("messages.chatInviteJoinResultWebView"), 1, &row), NOSHI_E_UNSUPPORTED);
    CHECK_EQ_INT(noshi_invite_joined_parse(obj("boolTrue"), 1, &row), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_invite_joined_parse(joined, 1, NULL), NOSHI_E_ARG);
}

static noshi_tl_value *command(const char *name, const char *text) {
    noshi_tl_value *c = obj("botCommand");
    str(c, "command", name);
    str(c, "description", text);
    return c;
}

static noshi_tl_value *full_user(noshi_tl_value *bot_info) {
    noshi_tl_value *full = obj("userFull"), *answer = obj("users.userFull");
    i64(full, "id", 77);
    str(full, "about", "about me");
    if (bot_info) set(full, "bot_info", bot_info);
    set(answer, "full_user", full);
    set(answer, "users", vec_of(NULL, 0));
    set(answer, "chats", vec_of(NULL, 0));
    return answer;
}

static void test_bot_info(void) {
    static noshi_bot_info info;
    noshi_tl_value *b = obj("botInfo"), *commands[5], *menu = obj("botMenuButton"), *answer;
    noshi_tl_value *ephemeral = command("hidden", "temporary");
    flag(ephemeral, "ephemeral");
    str(b, "description", "I search cats.\nSend a name.");
    str(b, "privacy_policy_url", "https://example.org/privacy");
    commands[0] = command("start", "Begin");
    commands[1] = command("help", "What I can do");
    commands[2] = ephemeral;
    commands[3] = command("bad name", "has a space");
    commands[4] = command("long_command_", "x");
    set(b, "commands", vec_of(commands, 5));
    str(menu, "text", "Open");
    str(menu, "url", "https://app.example.org/");
    set(b, "menu_button", menu);
    answer = full_user(b);
    CHECK_EQ_INT(noshi_bot_info_parse(answer, &info), NOSHI_OK);
    CHECK_EQ_INT(info.present, 1);
    CHECK(!strcmp(info.description, "I search cats.\nSend a name."));
    CHECK(!strcmp(info.privacy_url, "https://example.org/privacy"));
    /* a web app menu button is not opened here, so the bot keeps the default menu */
    CHECK_EQ_INT(info.menu_kind, NOSHI_BOT_MENU_DEFAULT);
    CHECK_EQ_INT(info.has_picture, 0);
    /* the temporary command and the one with a space in its name are not offered */
    CHECK_EQ_INT(info.command_count, 3);
    CHECK(!strcmp(info.commands[0].name, "start"));
    CHECK(!strcmp(info.commands[1].text, "What I can do"));
    CHECK(!strcmp(info.commands[2].name, "long_command_"));

    b = obj("botInfo");
    set(b, "menu_button", obj("botMenuButtonCommands"));
    CHECK_EQ_INT(noshi_bot_info_parse(full_user(b), &info), NOSHI_OK);
    CHECK_EQ_INT(info.menu_kind, NOSHI_BOT_MENU_COMMANDS);
    CHECK_EQ_INT(info.command_count, 0);
    b = obj("botInfo");
    set(b, "menu_button", obj("botMenuButtonDefault"));
    CHECK_EQ_INT(noshi_bot_info_parse(full_user(b), &info), NOSHI_OK);
    CHECK_EQ_INT(info.menu_kind, NOSHI_BOT_MENU_DEFAULT);

    CHECK_EQ_INT(noshi_bot_info_parse(full_user(NULL), &info), NOSHI_OK);
    CHECK_EQ_INT(info.present, 0);
    CHECK_EQ_INT(noshi_bot_info_parse(obj("boolTrue"), &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_bot_info_parse(answer, NULL), NOSHI_E_ARG);
}

static void test_start(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref no_hash = {1, 77, 0, 0, 0};
    /* the server answers START_PARAM_EMPTY to an empty parameter, so none is built: a start without one is the text "/start" */
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &bot, &chat, 5, "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &bot, &chat, 5, "go", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_startBot);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &bot, &group, 5, "ref_1-a", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_startBot);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &bot, &chat, 0, "", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &bot, &chat, 5, "a b", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &bot, &chat, 5, "x/y", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &bot, &chat, 5, "0123456789012345678901234567890123456789012345678901234567890123x", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &no_hash, &chat, 5, "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &group, &chat, 5, "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_start_bot_request(&arena, &bot, &chat, 5, NULL, &request), NOSHI_E_ARG);
}

/* the number a contact is added by, and what the server says of it */
static void test_contact_import(void) {
    noshi_tl_value *request = NULL, *answer, *none;
    size_t count = 9;
    CHECK_EQ_INT(noshi_contact_import_request(&arena, "+79001112233", "Ann", "", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_contacts_importContacts);
    CHECK_EQ_INT(noshi_contact_import_request(&arena, "79001112233", "Ann", "Lee", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_contact_import_request(&arena, "7900", "Ann", "", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_contact_import_request(&arena, "+7 900 111", "Ann", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_import_request(&arena, "+790011122334455667788", "Ann", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_import_request(&arena, NULL, "Ann", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_import_request(&arena, "79001112233", "", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_import_request(&arena, "79001112233", "Ann", NULL, &request), NOSHI_E_ARG);
    answer = obj("contacts.importedContacts");
    none = noshi_tl_new_vec(&arena, 0);
    CHECK_EQ_INT(noshi_tl_set(answer, "imported", none), NOSHI_OK);
    CHECK_EQ_INT(noshi_contact_import_parse(answer, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(noshi_contact_import_parse(obj("boolTrue"), &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_contact_import_parse(answer, NULL), NOSHI_E_ARG);
}

/* the name the person gives a contact */
static void test_contact_edit(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref no_hash = {1, 77, 0, 0, 0};
    char big[NOSHI_CONTACT_NAME_MAX + 1];
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &bot, "Ann", "Lee", "79001112233", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_contacts_addContact);
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &bot, "Ann", "", "", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &bot, "", "Lee", "", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &bot, NULL, "Lee", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &bot, "Ann", NULL, "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &no_hash, "Ann", "", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &group, "Ann", "", "", &request), NOSHI_E_ARG);
    memset(big, 'a', sizeof(big));
    big[NOSHI_CONTACT_NAME_MAX] = 0;
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &bot, big, "", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_edit_request(&arena, &bot, "Ann", big, "", &request), NOSHI_E_ARG);
}

static noshi_tl_value *account_password(void) {
    noshi_tl_value *algo = obj("passwordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow"), *info = obj("account.password");
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, algo, "salt1", srp_salt1, sizeof(srp_salt1)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, algo, "salt2", srp_salt2, sizeof(srp_salt2)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, algo, "p", srp_prime, sizeof(srp_prime)), NOSHI_OK);
    i32(algo, "g", 3);
    flag(info, "has_password");
    set(info, "current_algo", algo);
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, info, "srp_B", srp_B, sizeof(srp_B)), NOSHI_OK);
    i64(info, "srp_id", 35);
    return info;
}

static void test_callback(void) {
    noshi_tl_value *request = NULL, *answer, *check = NULL;
    static const uint8_t data[] = {'a', 0, 'b'};
    static noshi_callback_answer reply;
    uint8_t big[NOSHI_MARKUP_DATA_MAX + 1];
    memset(big, 'x', sizeof(big));
    CHECK_EQ_INT(noshi_callback_request(&arena, &chat, 12, data, sizeof(data), 0, NULL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "data"), 1);
    CHECK_EQ_INT(noshi_tl_has(request, "game"), 0);
    roundtrip(request, NOSHI_TL_ID_messages_getBotCallbackAnswer);
    /* a press with an empty payload still carries the field, otherwise the server takes it for another button */
    CHECK_EQ_INT(noshi_callback_request(&arena, &chat, 12, NULL, 0, 0, NULL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "data"), 1);
    roundtrip(request, NOSHI_TL_ID_messages_getBotCallbackAnswer);
    CHECK_EQ_INT(noshi_callback_request(&arena, &group, 12, NULL, 0, 1, NULL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "data"), 0);
    CHECK_EQ_INT(noshi_tl_has(request, "game"), 1);
    roundtrip(request, NOSHI_TL_ID_messages_getBotCallbackAnswer);
    CHECK_EQ_INT(noshi_callback_request(&arena, &chat, 0, data, sizeof(data), 0, NULL, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_callback_request(&arena, &chat, 12, big, sizeof(big), 0, NULL, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_callback_request(&arena, &chat, 12, NULL, 3, 0, NULL, &request), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_password_input(&arena, account_password(), "hunter2", &check), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(check), NOSHI_TL_ID_inputCheckPasswordSRP);
    CHECK_EQ_INT(noshi_callback_request(&arena, &chat, 12, data, sizeof(data), 0, check, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "password"), 1);
    roundtrip(request, NOSHI_TL_ID_messages_getBotCallbackAnswer);
    {
        noshi_tl_value *none = obj("account.password");
        CHECK_EQ_INT(noshi_password_input(&arena, none, "x", &check), NOSHI_E_UNSUPPORTED);
        CHECK(check == NULL);
    }
    CHECK_EQ_INT(noshi_password_input(&arena, account_password(), "", &check), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_password_input(&arena, obj("boolTrue"), "x", &check), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_password_request(&arena, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_account_getPassword);

    answer = obj("messages.botCallbackAnswer");
    flag(answer, "alert");
    str(answer, "message", "Done\nfor now");
    i32(answer, "cache_time", 30);
    CHECK_EQ_INT(noshi_callback_parse(answer, &reply), NOSHI_OK);
    CHECK_EQ_INT(reply.alert, 1);
    CHECK_EQ_INT(reply.has_url, 0);
    CHECK_EQ_INT(reply.cache_time, 30);
    CHECK(!strcmp(reply.message, "Done\nfor now"));

    answer = obj("messages.botCallbackAnswer");
    flag(answer, "has_url");
    str(answer, "url", "https://t.me/game?x=1");
    i32(answer, "cache_time", 0);
    CHECK_EQ_INT(noshi_callback_parse(answer, &reply), NOSHI_OK);
    CHECK_EQ_INT(reply.has_url, 1);
    CHECK_EQ_INT(reply.message[0], 0);
    CHECK(!strcmp(reply.url, "https://t.me/game?x=1"));

    {
        char long_url[NOSHI_CALLBACK_URL_MAX + 40];
        memset(long_url, 'a', sizeof(long_url));
        long_url[sizeof(long_url) - 1] = 0;
        answer = obj("messages.botCallbackAnswer");
        str(answer, "url", long_url);
        i32(answer, "cache_time", 0);
        CHECK_EQ_INT(noshi_callback_parse(answer, &reply), NOSHI_OK);
        /* an address that does not fit is not opened at all */
        CHECK_EQ_INT(reply.has_url, 0);
        CHECK_EQ_INT(reply.url[0], 0);
    }
    CHECK_EQ_INT(noshi_callback_parse(obj("boolTrue"), &reply), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_callback_parse(answer, NULL), NOSHI_E_ARG);
}

static noshi_tl_value *web_document(const char *url, int proxied, const char *mime, int w, int h) {
    noshi_tl_value *d = obj(proxied ? "webDocument" : "webDocumentNoProxy"), *a = obj("documentAttributeImageSize"), *attrs[1];
    str(d, "url", url);
    if (proxied) i64(d, "access_hash", 4444);
    i32(d, "size", 1000);
    str(d, "mime_type", mime);
    i32(a, "w", w);
    i32(a, "h", h);
    attrs[0] = a;
    set(d, "attributes", vec_of(attrs, 1));
    return d;
}

static noshi_tl_value *text_message(const char *text) {
    noshi_tl_value *m = obj("botInlineMessageText");
    str(m, "message", text);
    return m;
}

static void test_inline(void) {
    static noshi_inline_result rows[8];
    static noshi_inline_page page;
    noshi_tl_value *request = NULL, *answer, *results[6], *article = obj("botInlineResult"), *photo = obj("botInlineResult");
    noshi_tl_value *gif = obj("botInlineResult"), *media = obj("botInlineMediaResult"), *broken = obj("botInlineResult"), *pm = obj("inlineBotSwitchPM");
    noshi_tl_value *web = obj("inlineBotWebView"), *sticker = obj("document");
    size_t count = 0;
    char query[NOSHI_INLINE_QUERY_MAX + 2];

    CHECK_EQ_INT(noshi_inline_query_request(&arena, &bot, &chat, "cats", "", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_getInlineBotResults);
    noshi_geo_point inline_location;
    memset(&inline_location, 0, sizeof(inline_location));
    CHECK_EQ_INT(noshi_inline_query_set_location(&arena, request, &inline_location), NOSHI_OK);
    CHECK(!noshi_tl_has(request, "geo_point"));
    inline_location.valid = 1; inline_location.latitude = 55.03; inline_location.longitude = 82.92;
    CHECK_EQ_INT(noshi_inline_query_set_location(&arena, request, &inline_location), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "geo_point"), NOSHI_TL_ID_inputGeoPoint));
    roundtrip(request, NOSHI_TL_ID_messages_getInlineBotResults);
    inline_location.latitude = 100;
    CHECK_EQ_INT(noshi_inline_query_set_location(&arena, request, &inline_location), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_inline_query_request(&arena, &bot, &forum, "", "next:2", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_getInlineBotResults);
    memset(query, 'q', sizeof(query));
    query[NOSHI_INLINE_QUERY_MAX + 1] = 0;
    CHECK_EQ_INT(noshi_inline_query_request(&arena, &bot, &chat, query, "", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_inline_query_request(&arena, &bot, &chat, "\xff", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_inline_query_request(&arena, &bot, &chat, "q", NULL, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_inline_query_request(&arena, &group, &chat, "q", "", &request), NOSHI_E_ARG);

    str(article, "id", "a1");
    str(article, "type", "article");
    str(article, "title", "Cat facts");
    set(article, "send_message", text_message("Cats sleep 16 hours a day."));
    str(photo, "id", "p1");
    str(photo, "type", "photo");
    set(photo, "content", web_document("https://img.example.org/cat.jpg", 0, "image/jpeg", 800, 600));
    set(photo, "send_message", obj("botInlineMessageMediaAuto"));
    str(gif, "id", "g1");
    str(gif, "type", "mpeg4_gif");
    set(gif, "thumb", web_document("https://img.example.org/t.jpg", 1, "image/jpeg", 90, 60));
    set(gif, "content", web_document("https://img.example.org/c.mp4", 0, "video/mp4", 480, 320));
    set(gif, "send_message", obj("botInlineMessageMediaAuto"));
    str(media, "id", "m1");
    str(media, "type", "sticker");
    sticker = obj("document");
    i64(sticker, "id", 31);
    i64(sticker, "access_hash", 32);
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, sticker, "file_reference", "ref", 3), NOSHI_OK);
    i32(sticker, "dc_id", 2);
    set(media, "document", sticker);
    set(media, "send_message", obj("botInlineMessageMediaAuto"));
    str(broken, "type", "article");
    results[0] = article;
    results[1] = photo;
    results[2] = gif;
    results[3] = media;
    results[4] = broken;
    results[5] = obj("boolTrue");
    answer = obj("messages.botResults");
    flag(answer, "gallery");
    i64(answer, "query_id", 987654321);
    str(answer, "next_offset", "page2");
    str(pm, "text", "Connect");
    str(pm, "start_param", "login_1");
    set(answer, "switch_pm", pm);
    str(web, "text", "Open app");
    str(web, "url", "https://app.example.org/inline");
    set(answer, "switch_webview", web);
    set(answer, "results", vec_of(results, 6));
    i32(answer, "cache_time", 300);
    set(answer, "users", vec_of(NULL, 0));
    CHECK_EQ_INT(noshi_inline_results_parse(answer, &page, rows, 8, &count), NOSHI_OK);
    CHECK(rows[0].query_id == 987654321);
    CHECK_EQ_INT(page.query_id, 987654321);
    CHECK_EQ_INT(page.gallery, 1);
    CHECK_EQ_INT(page.cache_time, 300);
    CHECK(!strcmp(page.next_offset, "page2"));
    CHECK(!strcmp(page.switch_text, "Connect"));
    CHECK(!strcmp(page.switch_param, "login_1"));
    CHECK(!strcmp(page.web_text, "Open app"));
    /* the result without an id and the stray object are skipped */
    CHECK_EQ_INT(count, 4);
    CHECK_EQ_INT(rows[0].kind, NOSHI_INLINE_ARTICLE);
    CHECK(!strcmp(rows[0].id, "a1"));
    CHECK(!strcmp(rows[0].title, "Cat facts"));
    CHECK(!strcmp(rows[0].description, "Cats sleep 16 hours a day."));
    CHECK_EQ_INT(rows[0].thumb.present, 0);
    CHECK_EQ_INT(rows[1].kind, NOSHI_INLINE_PHOTO);
    /* a photo the bot hosts without a thumbnail uses itself */
    CHECK_EQ_INT(rows[1].thumb.present, 1);
    CHECK_EQ_INT(rows[1].thumb.proxied, 0);
    CHECK(!strcmp(rows[1].thumb.url, "https://img.example.org/cat.jpg"));
    CHECK_EQ_INT(rows[1].width, 800);
    CHECK_EQ_INT(rows[1].height, 600);
    CHECK_EQ_INT(rows[2].kind, NOSHI_INLINE_GIF);
    CHECK_EQ_INT(rows[2].thumb.proxied, 1);
    CHECK_EQ_INT(rows[2].thumb.access_hash, 4444);
    i64(answer, "query_id", 123456789);
    CHECK_EQ_INT(noshi_inline_results_parse(answer, &page, rows, 8, &count), NOSHI_OK);
    CHECK(rows[0].query_id == 123456789 && rows[2].query_id == 123456789);
    i64(answer, "query_id", 987654321);
    CHECK(!strcmp(rows[2].thumb.url, "https://img.example.org/t.jpg"));
    CHECK_EQ_INT(rows[2].width, 480);
    CHECK_EQ_INT(rows[3].kind, NOSHI_INLINE_STICKER);
    CHECK_EQ_INT(rows[3].media.ref.source, NOSHI_MEDIA_SOURCE_DOCUMENT);

    /* a bad start parameter takes the connect button away rather than sending the person to a wrong deep link */
    str(pm, "start_param", "bad param!");
    set(answer, "switch_pm", pm);
    CHECK_EQ_INT(noshi_inline_results_parse(answer, &page, rows, 8, &count), NOSHI_OK);
    CHECK_EQ_INT(page.switch_text[0], 0);
    CHECK_EQ_INT(noshi_inline_results_parse(answer, &page, rows, 2, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(noshi_inline_results_parse(obj("boolTrue"), &page, rows, 8, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_inline_results_parse(answer, &page, NULL, 8, &count), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_inline_send_request(&arena, &chat, 9, 987654321, "a1", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_sendInlineBotResult);
    CHECK_EQ_INT(noshi_inline_send_request(&arena, &forum, 9, 987654321, "a1", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "reply_to"), 1);
    roundtrip(request, NOSHI_TL_ID_messages_sendInlineBotResult);
    CHECK_EQ_INT(noshi_inline_send_request(&arena, &chat, 0, 1, "a1", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_inline_send_request(&arena, &chat, 9, 1, "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_inline_send_request(&arena, &chat, 9, 1, NULL, &request), NOSHI_E_ARG);
}

static void test_url_auth(void) {
    static noshi_url_auth auth;
    noshi_tl_value *request = NULL, *answer, *codes[3];
    CHECK_EQ_INT(noshi_url_auth_request(&arena, &chat, 12, 3, NULL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "peer"), 1);
    CHECK_EQ_INT(noshi_tl_has(request, "url"), 0);
    roundtrip(request, NOSHI_TL_ID_messages_requestUrlAuth);
    CHECK_EQ_INT(noshi_url_auth_request(&arena, NULL, 0, 0, "https://site.example.org/login", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "peer"), 0);
    CHECK_EQ_INT(noshi_tl_has(request, "url"), 1);
    roundtrip(request, NOSHI_TL_ID_messages_requestUrlAuth);
    CHECK_EQ_INT(noshi_url_auth_request(&arena, NULL, 0, 0, NULL, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_url_auth_request(&arena, NULL, 0, 0, "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_url_auth_request(&arena, &chat, 0, 3, NULL, &request), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_url_auth_accept_request(&arena, &chat, 12, 3, NULL, 1, 0, NULL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "write_allowed"), 1);
    roundtrip(request, NOSHI_TL_ID_messages_acceptUrlAuth);
    CHECK_EQ_INT(noshi_url_auth_accept_request(&arena, NULL, 0, 0, "https://site.example.org/login", 0, 1, "42", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "share_phone_number"), 1);
    CHECK_EQ_INT(noshi_tl_has(request, "match_code"), 1);
    roundtrip(request, NOSHI_TL_ID_messages_acceptUrlAuth);
    CHECK_EQ_INT(noshi_url_auth_accept_request(&arena, &chat, 12, 3, NULL, 0, 0, "", &request), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_url_auth_parse(obj("urlAuthResultDefault"), &auth), NOSHI_OK);
    CHECK_EQ_INT(auth.kind, NOSHI_URL_AUTH_OPEN);
    answer = obj("urlAuthResultAccepted");
    str(answer, "url", "https://site.example.org/in?token=1");
    CHECK_EQ_INT(noshi_url_auth_parse(answer, &auth), NOSHI_OK);
    CHECK_EQ_INT(auth.kind, NOSHI_URL_AUTH_DONE);
    CHECK(!strcmp(auth.url, "https://site.example.org/in?token=1"));
    CHECK_EQ_INT(noshi_url_auth_parse(obj("urlAuthResultAccepted"), &auth), NOSHI_OK);
    CHECK_EQ_INT(auth.url[0], 0);

    answer = obj("urlAuthResultRequest");
    flag(answer, "request_write_access");
    set(answer, "bot", user(77, "login_bot", 1));
    str(answer, "domain", "site.example.org");
    codes[0] = noshi_tl_new_str(&arena, "17");
    codes[1] = noshi_tl_new_str(&arena, "");
    codes[2] = noshi_tl_new_str(&arena, "93");
    set(answer, "match_codes", vec_of(codes, 3));
    flag(answer, "match_codes_first");
    CHECK_EQ_INT(noshi_url_auth_parse(answer, &auth), NOSHI_OK);
    CHECK_EQ_INT(auth.kind, NOSHI_URL_AUTH_ASK);
    CHECK_EQ_INT(auth.request_write, 1);
    CHECK_EQ_INT(auth.request_phone, 0);
    CHECK(!strcmp(auth.domain, "site.example.org"));
    CHECK(!strcmp(auth.bot, "login_bot"));
    CHECK_EQ_INT(auth.code_count, 2);
    CHECK(!strcmp(auth.codes[0], "17"));
    CHECK(!strcmp(auth.codes[1], "93"));
    answer = obj("urlAuthResultRequest");
    set(answer, "bot", user(77, "login_bot", 1));
    CHECK_EQ_INT(noshi_url_auth_parse(answer, &auth), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_url_auth_parse(obj("boolTrue"), &auth), NOSHI_E_MALFORMED);
}

static noshi_tl_value *price(const char *label, int64_t amount) {
    noshi_tl_value *p = obj("labeledPrice");
    str(p, "label", label);
    i64(p, "amount", amount);
    return p;
}

static noshi_tl_value *stars_form(const char *currency, int64_t a, int64_t b) {
    noshi_tl_value *form = obj("payments.paymentFormStars"), *invoice = obj("invoice"), *prices[2];
    i64(form, "form_id", 600);
    i64(form, "bot_id", 77);
    str(form, "title", "Sticker pack");
    str(form, "description", "Ten stickers\nand a pin");
    str(invoice, "currency", currency);
    prices[0] = price("pack", a);
    prices[1] = price("tax", b);
    set(invoice, "prices", vec_of(prices, 2));
    set(form, "invoice", invoice);
    set(form, "users", vec_of(NULL, 0));
    return form;
}

static void test_invoice(void) {
    static noshi_stars_form form;
    noshi_tl_value *input = NULL;
    CHECK_EQ_INT(noshi_invoice_message_input(&arena, &chat, 12, &input), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(input), NOSHI_TL_ID_inputInvoiceMessage);
    CHECK_EQ_INT(noshi_invoice_slug_input(&arena, "abc_DEF-123", &input), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(input), NOSHI_TL_ID_inputInvoiceSlug);
    CHECK_EQ_INT(noshi_invoice_slug_input(&arena, "a b", &input), NOSHI_E_ARG);
    CHECK(input == NULL);
    CHECK_EQ_INT(noshi_invoice_slug_input(&arena, "", &input), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_invoice_message_input(&arena, &chat, 0, &input), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_stars_form_parse(stars_form("XTR", 90, 10), &form), NOSHI_OK);
    CHECK_EQ_INT(form.form_id, 600);
    CHECK_EQ_INT(form.bot_id, 77);
    CHECK_EQ_INT(form.stars, 100);
    CHECK(!strcmp(form.title, "Sticker pack"));
    CHECK(!strcmp(form.description, "Ten stickers\nand a pin"));
    CHECK_EQ_INT(noshi_stars_form_parse(stars_form("USD", 90, 10), &form), NOSHI_E_UNSUPPORTED);
    CHECK_EQ_INT(form.form_id, 0);
    CHECK_EQ_INT(noshi_stars_form_parse(stars_form("XTR", -1, 10), &form), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_stars_form_parse(stars_form("XTR", INT64_MAX, 1), &form), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_stars_form_parse(obj("payments.paymentForm"), &form), NOSHI_E_UNSUPPORTED);
    CHECK_EQ_INT(noshi_stars_form_parse(obj("boolTrue"), &form), NOSHI_E_MALFORMED);
}

static void test_user_from_message(void) {
    noshi_tl_value *request = NULL, *list[2];
    noshi_person_row row;
    CHECK_EQ_INT(noshi_user_from_message_request(&arena, &chat, 12, 4242, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_users_getUsers);
    CHECK_EQ_INT(noshi_user_from_message_request(&arena, &group, 12, 4242, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_user_from_message_request(&arena, &chat, 0, 4242, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_user_from_message_request(&arena, &chat, 12, 0, &request), NOSHI_E_ARG);
    list[0] = user(3, "other", 0);
    list[1] = user(4242, "wanted", 0);
    CHECK_EQ_INT(noshi_user_from_message_parse(vec_of(list, 2), 4242, &row), NOSHI_OK);
    CHECK_EQ_INT(row.id, 4242);
    CHECK_EQ_INT(row.access_hash, 42420);
    CHECK_EQ_INT(noshi_user_from_message_parse(vec_of(list, 2), 9, &row), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(row.id, 0);
    CHECK_EQ_INT(noshi_user_from_message_parse(obj("boolTrue"), 9, &row), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_user_from_message_parse(vec_of(NULL, 0), 9, &row), NOSHI_E_NOTFOUND);
}

static void test_answers(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref picked[2] = {{1, 5, 50, 0, 0}, {3, 12, 120, 0, 0}};
    CHECK_EQ_INT(noshi_send_contact_request(&arena, &chat, "+15550100", "Ann", "Lee", 4, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_sendMedia);
    CHECK_EQ_INT(noshi_send_contact_request(&arena, &forum, "+15550100", "Ann", "", 4, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "reply_to"), 1);
    CHECK_EQ_INT(noshi_send_contact_request(&arena, &chat, "", "Ann", "", 4, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_send_contact_request(&arena, &chat, "+1", "Ann", "", 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_send_contact_request(&arena, &chat, "+1", "\xff", "", 4, &request), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_requested_peers_request(&arena, &chat, 12, 3, picked, 2, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_sendBotRequestedPeer);
    CHECK_EQ_INT(noshi_requested_peers_request(&arena, &chat, 12, 3, picked, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_requested_peers_request(&arena, &chat, 12, 3, picked, 11, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_requested_peers_request(&arena, &chat, 0, 3, picked, 2, &request), NOSHI_E_ARG);
    picked[1].access_hash = 0;
    CHECK_EQ_INT(noshi_requested_peers_request(&arena, &chat, 12, 3, picked, 2, &request), NOSHI_E_ARG);
}

/* the inline bots of the most used list: only bots with a public name, in the order of the rating, from the inline category alone */
static void test_top_inline_bots(void) {
    noshi_tl_value *request = NULL, *answer = obj("contacts.topPeers"), *users[4], *categories[2], *pics[3], *others[1];
    noshi_tl_value *inline_category = obj("topPeerCategoryPeers"), *pm_category = obj("topPeerCategoryPeers");
    noshi_person_row rows[4];
    size_t count = 9, i;
    CHECK_EQ_INT(noshi_top_inline_bots_request(&arena, 20, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "bots_inline"), 1);
    roundtrip(request, NOSHI_TL_ID_contacts_getTopPeers);
    CHECK_EQ_INT(noshi_top_inline_bots_request(&arena, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_top_inline_bots_request(&arena, NOSHI_TOP_BOTS_MAX + 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_top_inline_bots_request(NULL, 5, &request), NOSHI_E_ARG);
    users[0] = user(11, "pic", 1);
    users[1] = user(12, "loadit", 1);
    users[2] = user(13, "human", 0);
    users[3] = user(14, "gone", 1);
    flag(users[3], "deleted");
    for (i = 0; i < 3; ++i) {
        pics[i] = obj("topPeer");
        set(pics[i], "peer", obj("peerUser"));
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, (noshi_tl_value *)noshi_tl_get(pics[i], "peer"), "user_id", i == 0 ? 12 : (i == 1 ? 13 : 14)), NOSHI_OK);
    }
    /* the order of the list is the order of the rows: loadit, then the person who is no bot, then the deleted bot, and pic only in the other category */
    set(inline_category, "category", obj("topPeerCategoryBotsInline"));
    i32(inline_category, "count", 3);
    set(inline_category, "peers", vec_of(pics, 3));
    others[0] = obj("topPeer");
    set(others[0], "peer", obj("peerUser"));
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, (noshi_tl_value *)noshi_tl_get(others[0], "peer"), "user_id", 11), NOSHI_OK);
    set(pm_category, "category", obj("topPeerCategoryBotsPM"));
    i32(pm_category, "count", 1);
    set(pm_category, "peers", vec_of(others, 1));
    categories[0] = pm_category;
    categories[1] = inline_category;
    set(answer, "categories", vec_of(categories, 2));
    set(answer, "chats", vec_of(users, 0));
    set(answer, "users", vec_of(users, 4));
    CHECK_EQ_INT(noshi_top_inline_bots_parse(answer, rows, 4, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].id, 12);
    CHECK(!strcmp(rows[0].username, "loadit"));
    CHECK_EQ_INT(noshi_top_inline_bots_parse(answer, rows, 4, &count), NOSHI_OK);
    CHECK_EQ_INT(noshi_top_inline_bots_parse(obj("contacts.topPeersDisabled"), rows, 4, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_top_inline_bots_parse(obj("contacts.topPeersNotModified"), rows, 4, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_top_inline_bots_parse(obj("boolTrue"), rows, 4, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_top_inline_bots_parse(answer, NULL, 4, &count), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_top_inline_bots_parse(answer, rows, 0, &count), NOSHI_E_ARG);
}

int main(void) {
    char inline_name[NOSHI_LINK_NAME_MAX];
    const char *inline_query = NULL;
    CHECK(noshi_inline_address_parse("@pic cats", inline_name, sizeof(inline_name), &inline_query));
    CHECK(!strcmp(inline_name, "pic") && !strcmp(inline_query, "cats"));
    CHECK(noshi_inline_address_parse("@loaditgay ", inline_name, sizeof(inline_name), &inline_query));
    CHECK(!strcmp(inline_name, "loaditgay") && !strcmp(inline_query, ""));
    CHECK(!noshi_inline_address_parse("@pic", inline_name, sizeof(inline_name), &inline_query));
    CHECK(!noshi_inline_address_parse("@@pic x", inline_name, sizeof(inline_name), &inline_query));
    CHECK(!noshi_inline_address_parse("@bad-name x", inline_name, sizeof(inline_name), &inline_query));
    noshi_arena_init(&arena, 64u * 1024u * 1024u);
    test_resolve();
    test_top_inline_bots();
    test_invite();
    test_bot_info();
    test_start();
    test_contact_edit();
    test_contact_import();
    test_callback();
    test_inline();
    test_url_auth();
    test_invoice();
    test_user_from_message();
    test_answers();
    noshi_arena_free(&arena);
    return test_finish("test_bots");
}
