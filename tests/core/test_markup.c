#include "test_util.h"
#include "noshi_markup.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;
static noshi_markup markup;

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

static noshi_tl_value *inline_button(const char *text, noshi_tl_value *type) {
    noshi_tl_value *b = obj("keyboardInlineButton");
    str(b, "text", text);
    set(b, "type", type);
    return b;
}
static noshi_tl_value *key_button(const char *text, noshi_tl_value *type) {
    noshi_tl_value *b = obj("keyboardButton");
    str(b, "text", text);
    set(b, "type", type);
    return b;
}
static noshi_tl_value *row_of(const char *name, noshi_tl_value **buttons, uint32_t n) {
    noshi_tl_value *row = obj(name);
    set(row, "buttons", vec_of(buttons, n));
    return row;
}
static noshi_tl_value *inline_markup(noshi_tl_value **rows, uint32_t n) {
    noshi_tl_value *m = obj("replyInlineMarkup");
    set(m, "rows", vec_of(rows, n));
    return m;
}
static noshi_tl_value *url_type(const char *url) {
    noshi_tl_value *t = obj("inlineButtonTypeUrl");
    str(t, "url", url);
    return t;
}
static noshi_tl_value *callback_type(const void *data, size_t len, int password) {
    noshi_tl_value *t = obj("inlineButtonTypeCallback");
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, t, "data", data, len), NOSHI_OK);
    if (password) flag(t, "requires_password");
    return t;
}

static void test_inline(void) {
    noshi_tl_value *r0[3], *r1[2], *rows[2], *auth, *sw, *copy, *profile, *game;
    static const uint8_t payload[] = {'v', ':', '1', 0, 0xff};
    noshi_tl_value *style = obj("keyboardButtonStyle");
    noshi_tl_value *styled;
    flag(style, "bg_danger");
    i64(style, "icon", 5000);
    styled = inline_button("Delete", callback_type(payload, sizeof(payload), 1));
    set(styled, "style", style);
    r0[0] = inline_button("Open", url_type("https://example.org/a?b=1&c=2"));
    r0[1] = styled;
    r0[2] = inline_button("Pay", obj("inlineButtonTypeBuy"));
    auth = obj("inlineButtonTypeUrlAuth");
    str(auth, "url", "https://login.example.org/");
    i32(auth, "button_id", 7);
    sw = obj("inlineButtonTypeSwitchInline");
    str(sw, "query", "cats");
    flag(sw, "same_peer");
    copy = obj("inlineButtonTypeCopy");
    str(copy, "copy_text", "CODE-123");
    profile = obj("inlineButtonTypeUserProfile");
    i64(profile, "user_id", 4242);
    game = obj("inlineButtonTypeGame");
    r1[0] = inline_button("Sign in", auth);
    r1[1] = inline_button("Share", sw);
    rows[0] = row_of("keyboardInlineButtonRow", r0, 3);
    rows[1] = row_of("keyboardInlineButtonRow", r1, 2);
    CHECK_EQ_INT(noshi_markup_read(inline_markup(rows, 2), &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.kind, NOSHI_MARKUP_INLINE);
    CHECK_EQ_INT(markup.row_count, 2);
    CHECK_EQ_INT(markup.row_size[0], 3);
    CHECK_EQ_INT(markup.row_size[1], 2);
    CHECK_EQ_INT(markup.button_count, 5);
    CHECK_EQ_INT(markup.buttons[0].kind, NOSHI_BUTTON_URL);
    CHECK(!strcmp(markup.buttons[0].text, "Open"));
    CHECK(!strcmp(noshi_markup_arg(&markup, &markup.buttons[0]), "https://example.org/a?b=1&c=2"));
    CHECK_EQ_INT(markup.buttons[1].kind, NOSHI_BUTTON_CALLBACK);
    CHECK_EQ_INT(markup.buttons[1].password, 1);
    CHECK_EQ_INT(markup.buttons[1].style, NOSHI_BUTTON_STYLE_DANGER);
    CHECK_EQ_INT(markup.buttons[1].icon, 5000);
    CHECK_EQ_INT(markup.buttons[1].data_len, sizeof(payload));
    CHECK_MEM(markup.buttons[1].data, payload, sizeof(payload));
    CHECK_EQ_INT(markup.buttons[2].kind, NOSHI_BUTTON_BUY);
    CHECK_EQ_INT(markup.buttons[3].kind, NOSHI_BUTTON_URL_AUTH);
    CHECK_EQ_INT(markup.buttons[3].button_id, 7);
    CHECK(!strcmp(noshi_markup_arg(&markup, &markup.buttons[3]), "https://login.example.org/"));
    CHECK_EQ_INT(markup.buttons[4].kind, NOSHI_BUTTON_SWITCH_INLINE);
    CHECK_EQ_INT(markup.buttons[4].same_peer, 1);
    CHECK(!strcmp(noshi_markup_arg(&markup, &markup.buttons[4]), "cats"));

    r0[0] = inline_button("Copy", copy);
    r0[1] = inline_button("Who", profile);
    r0[2] = inline_button("Play", game);
    rows[0] = row_of("keyboardInlineButtonRow", r0, 3);
    CHECK_EQ_INT(noshi_markup_read(inline_markup(rows, 1), &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.buttons[0].kind, NOSHI_BUTTON_COPY);
    CHECK(!strcmp(noshi_markup_arg(&markup, &markup.buttons[0]), "CODE-123"));
    CHECK_EQ_INT(markup.buttons[1].kind, NOSHI_BUTTON_USER_PROFILE);
    CHECK_EQ_INT(markup.buttons[1].user_id, 4242);
    CHECK_EQ_INT(markup.buttons[2].kind, NOSHI_BUTTON_GAME);
}

static void test_inline_bad_buttons(void) {
    noshi_tl_value *r[6], *rows[1], *profile = obj("inlineButtonTypeUserProfile"), *web = obj("inlineButtonTypeWebView");
    uint8_t big[NOSHI_MARKUP_DATA_MAX + 1];
    memset(big, 'x', sizeof(big));
    i64(profile, "user_id", 0);
    str(web, "url", "https://app.example.org/");
    r[0] = inline_button("Big", callback_type(big, sizeof(big), 0));
    r[1] = inline_button("Zero", callback_type(NULL, 0, 0));
    r[2] = inline_button("Nobody", profile);
    r[3] = inline_button("Off", obj("inlineButtonTypeDisabled"));
    r[4] = inline_button("App", web);
    r[5] = inline_button("Future", obj("inputInlineButtonTypeUserProfile"));
    rows[0] = row_of("keyboardInlineButtonRow", r, 6);
    CHECK_EQ_INT(noshi_markup_read(inline_markup(rows, 1), &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.button_count, 6);
    /* a button that cannot be read whole stays in its place and cannot be pressed */
    CHECK_EQ_INT(markup.buttons[0].kind, NOSHI_BUTTON_DISABLED);
    CHECK_EQ_INT(markup.buttons[1].kind, NOSHI_BUTTON_CALLBACK);
    CHECK_EQ_INT(markup.buttons[1].data_len, 0);
    CHECK_EQ_INT(markup.buttons[2].kind, NOSHI_BUTTON_DISABLED);
    CHECK_EQ_INT(markup.buttons[3].kind, NOSHI_BUTTON_DISABLED);
    /* a web app button is shown and cannot be pressed, this client has no way to open the app */
    CHECK_EQ_INT(markup.buttons[4].kind, NOSHI_BUTTON_DISABLED);
    CHECK_EQ_INT(markup.buttons[5].kind, NOSHI_BUTTON_DISABLED);
    CHECK(!strcmp(markup.buttons[5].text, "Future"));
}

static void test_keyboard(void) {
    noshi_tl_value *m = obj("replyKeyboardMarkup"), *r0[3], *r1[2], *rows[2], *poll = obj("buttonTypeRequestPoll");
    noshi_tl_value *peer = obj("buttonTypeRequestPeer"), *kind = obj("requestPeerTypeUser"), *web = obj("buttonTypeSimpleWebView");
    noshi_tl_value *chat = obj("buttonTypeRequestPeer"), *chat_kind = obj("requestPeerTypeChat");
    flag(m, "resize");
    flag(m, "single_use");
    flag(m, "persistent");
    str(m, "placeholder", "Pick one");
    set(poll, "quiz", obj("boolTrue"));
    set(kind, "bot", obj("boolFalse"));
    i32(peer, "button_id", 11);
    i32(peer, "max_quantity", 3);
    set(peer, "peer_type", kind);
    str(web, "url", "https://form.example.org/");
    i32(chat, "button_id", 12);
    i32(chat, "max_quantity", 99);
    flag(chat_kind, "creator");
    set(chat_kind, "has_username", obj("boolTrue"));
    set(chat, "peer_type", chat_kind);
    r0[0] = key_button("Yes", obj("buttonTypeDefault"));
    r0[1] = key_button("Phone", obj("buttonTypeRequestPhone"));
    r0[2] = key_button("Where", obj("buttonTypeRequestGeoLocation"));
    r1[0] = key_button("Quiz", poll);
    r1[1] = key_button("Friend", peer);
    rows[0] = row_of("keyboardButtonRow", r0, 3);
    rows[1] = row_of("keyboardButtonRow", r1, 2);
    set(m, "rows", vec_of(rows, 2));
    CHECK_EQ_INT(noshi_markup_read(m, &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.kind, NOSHI_MARKUP_KEYBOARD);
    CHECK_EQ_INT(markup.resize, 1);
    CHECK_EQ_INT(markup.single_use, 1);
    CHECK_EQ_INT(markup.persistent, 1);
    CHECK_EQ_INT(markup.selective, 0);
    CHECK(!strcmp(markup.placeholder, "Pick one"));
    CHECK_EQ_INT(markup.buttons[0].kind, NOSHI_BUTTON_TEXT);
    CHECK_EQ_INT(markup.buttons[1].kind, NOSHI_BUTTON_REQUEST_PHONE);
    CHECK_EQ_INT(markup.buttons[2].kind, NOSHI_BUTTON_REQUEST_GEO);
    CHECK_EQ_INT(markup.buttons[3].kind, NOSHI_BUTTON_REQUEST_POLL);
    CHECK_EQ_INT(markup.buttons[3].quiz, NOSHI_WANT_YES);
    CHECK_EQ_INT(markup.buttons[4].kind, NOSHI_BUTTON_REQUEST_PEER);
    CHECK_EQ_INT(markup.buttons[4].button_id, 11);
    CHECK_EQ_INT(markup.buttons[4].choice, NOSHI_CHOICE_USER);
    CHECK_EQ_INT(markup.buttons[4].want_bot, NOSHI_WANT_NO);
    CHECK_EQ_INT(markup.buttons[4].want_premium, NOSHI_WANT_ANY);
    CHECK_EQ_INT(markup.buttons[4].max_quantity, 3);

    r0[0] = key_button("Form", web);
    r0[1] = key_button("Group", chat);
    rows[0] = row_of("keyboardButtonRow", r0, 2);
    m = obj("replyKeyboardMarkup");
    set(m, "rows", vec_of(rows, 1));
    CHECK_EQ_INT(noshi_markup_read(m, &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.buttons[0].kind, NOSHI_BUTTON_DISABLED);
    CHECK(!strcmp(markup.buttons[0].text, "Form"));
    CHECK_EQ_INT(markup.buttons[1].choice, NOSHI_CHOICE_GROUP);
    CHECK_EQ_INT(markup.buttons[1].want_creator, NOSHI_WANT_YES);
    CHECK_EQ_INT(markup.buttons[1].want_username, NOSHI_WANT_YES);
    CHECK_EQ_INT(markup.buttons[1].want_forum, NOSHI_WANT_ANY);
    /* a count the server would refuse is held to the picker's own range */
    CHECK_EQ_INT(markup.buttons[1].max_quantity, 10);
}

static void test_other_kinds(void) {
    noshi_tl_value *m = obj("replyKeyboardHide");
    flag(m, "selective");
    CHECK_EQ_INT(noshi_markup_read(m, &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.kind, NOSHI_MARKUP_HIDE);
    CHECK_EQ_INT(markup.selective, 1);
    CHECK_EQ_INT(markup.button_count, 0);

    m = obj("replyKeyboardForceReply");
    flag(m, "single_use");
    str(m, "placeholder", "Your name");
    CHECK_EQ_INT(noshi_markup_read(m, &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.kind, NOSHI_MARKUP_FORCE_REPLY);
    CHECK_EQ_INT(markup.single_use, 1);
    CHECK(!strcmp(markup.placeholder, "Your name"));

    /* no markup at all is a clean none, and so is a keyboard with nothing in it */
    CHECK_EQ_INT(noshi_markup_read(NULL, &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.kind, NOSHI_MARKUP_NONE);
    m = obj("replyKeyboardMarkup");
    set(m, "rows", vec_of(NULL, 0));
    CHECK_EQ_INT(noshi_markup_read(m, &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.kind, NOSHI_MARKUP_NONE);
    m = inline_markup(NULL, 0);
    CHECK_EQ_INT(noshi_markup_read(m, &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.kind, NOSHI_MARKUP_NONE);

    CHECK_EQ_INT(noshi_markup_read(obj("boolTrue"), &markup), NOSHI_E_UNSUPPORTED);
    CHECK_EQ_INT(markup.kind, NOSHI_MARKUP_NONE);
    CHECK_EQ_INT(noshi_markup_read(noshi_tl_new_i32(&arena, 5), &markup), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_markup_read(m, NULL), NOSHI_E_ARG);
}

static void test_limits(void) {
    noshi_tl_value *rows[NOSHI_MARKUP_ROWS_MAX + 6];
    noshi_tl_value *cells[16];
    uint32_t r, c;
    size_t total;
    for (r = 0; r < NOSHI_MARKUP_ROWS_MAX + 6; ++r) {
        for (c = 0; c < 4; ++c) cells[c] = inline_button("b", url_type("https://x.example/"));
        rows[r] = row_of("keyboardInlineButtonRow", cells, 4);
    }
    CHECK_EQ_INT(noshi_markup_read(inline_markup(rows, NOSHI_MARKUP_ROWS_MAX + 6), &markup), NOSHI_OK);
    CHECK(markup.button_count <= NOSHI_MARKUP_BUTTONS_MAX);
    CHECK(markup.row_count <= NOSHI_MARKUP_ROWS_MAX);
    total = 0;
    for (r = 0; r < markup.row_count; ++r) total += markup.row_size[r];
    CHECK_EQ_INT(total, markup.button_count);

    /* a row longer than the cap is cut, and a row of nothing but unknown objects is dropped */
    for (c = 0; c < 16; ++c) cells[c] = inline_button("w", url_type("https://x.example/"));
    rows[0] = row_of("keyboardInlineButtonRow", cells, 16);
    cells[0] = obj("boolTrue");
    rows[1] = row_of("keyboardInlineButtonRow", cells, 1);
    CHECK_EQ_INT(noshi_markup_read(inline_markup(rows, 2), &markup), NOSHI_OK);
    CHECK_EQ_INT(markup.row_count, 1);
    CHECK_EQ_INT(markup.row_size[0], NOSHI_MARKUP_ROW_MAX);

    /* the address pool fills up: later buttons are disabled, never given half an address */
    {
        char long_url[1200];
        noshi_tl_value *many[12];
        memset(long_url, 'a', sizeof(long_url));
        memcpy(long_url, "https://", 8);
        long_url[sizeof(long_url) - 1] = 0;
        for (c = 0; c < 12; ++c) many[c] = inline_button("u", url_type(long_url));
        rows[0] = row_of("keyboardInlineButtonRow", many, 12);
        CHECK_EQ_INT(noshi_markup_read(inline_markup(rows, 1), &markup), NOSHI_OK);
        CHECK_EQ_INT(markup.button_count, 12);
        CHECK_EQ_INT(markup.buttons[0].kind, NOSHI_BUTTON_URL);
        CHECK_EQ_INT(markup.buttons[11].kind, NOSHI_BUTTON_DISABLED);
        CHECK_EQ_INT(strlen(noshi_markup_arg(&markup, &markup.buttons[0])), sizeof(long_url) - 1);
        CHECK(markup.pool_len <= NOSHI_MARKUP_POOL_MAX);
    }
    /* a label of any length is cut on a character boundary */
    {
        char label[300];
        noshi_tl_value *one[1];
        size_t i;
        for (i = 0; i + 2 < sizeof(label); i += 2) {
            label[i] = (char)0xd0;
            label[i + 1] = (char)0xb1;
        }
        label[i] = 0;
        one[0] = inline_button(label, obj("inlineButtonTypeGame"));
        rows[0] = row_of("keyboardInlineButtonRow", one, 1);
        CHECK_EQ_INT(noshi_markup_read(inline_markup(rows, 1), &markup), NOSHI_OK);
        CHECK(strlen(markup.buttons[0].text) < NOSHI_MARKUP_TEXT_MAX);
        CHECK_EQ_INT(strlen(markup.buttons[0].text) % 2, 0);
    }
}

static void test_layout(void) {
    noshi_tl_value *r0[3], *r1[1], *r2[2], *rows[3];
    noshi_rect frames[8];
    double height = -1;
    size_t i;
    r0[0] = inline_button("a", obj("inlineButtonTypeGame"));
    r0[1] = inline_button("b", obj("inlineButtonTypeGame"));
    r0[2] = inline_button("c", obj("inlineButtonTypeGame"));
    r1[0] = inline_button("d", obj("inlineButtonTypeGame"));
    r2[0] = inline_button("e", obj("inlineButtonTypeGame"));
    r2[1] = inline_button("f", obj("inlineButtonTypeGame"));
    rows[0] = row_of("keyboardInlineButtonRow", r0, 3);
    rows[1] = row_of("keyboardInlineButtonRow", r1, 1);
    rows[2] = row_of("keyboardInlineButtonRow", r2, 2);
    CHECK_EQ_INT(noshi_markup_read(inline_markup(rows, 3), &markup), NOSHI_OK);
    CHECK_EQ_INT(noshi_markup_layout(markup.row_size, markup.row_count, 200, 36, 4, frames, 8, &height), NOSHI_OK);
    CHECK(height == 3 * 36 + 2 * 4);
    /* each row is covered edge to edge with the gap between neighbours, whatever the width rounds to */
    CHECK(frames[0].x == 0 && frames[0].y == 0 && frames[0].height == 36);
    CHECK(frames[3].x == 0 && frames[3].width == 200 && frames[3].y == 40);
    CHECK(frames[4].x == 0 && frames[4].y == 80);
    CHECK(frames[5].x + frames[5].width == 200);
    CHECK(frames[4].x + frames[4].width + 4 == frames[5].x);
    for (i = 0; i < 6; ++i) CHECK(frames[i].width > 0);
    CHECK(frames[2].x + frames[2].width == 200);
    CHECK(frames[0].x + frames[0].width + 4 == frames[1].x);
    CHECK(frames[1].x + frames[1].width + 4 == frames[2].x);
    CHECK_EQ_INT(noshi_markup_layout(markup.row_size, markup.row_count, 201, 36, 4, frames, 8, &height), NOSHI_OK);
    CHECK(frames[2].x + frames[2].width == 201);
    CHECK_EQ_INT(noshi_markup_layout(markup.row_size, markup.row_count, 200, 36, 4, frames, 5, &height), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_markup_layout(markup.row_size, markup.row_count, 0, 36, 4, frames, 8, &height), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_markup_layout(markup.row_size, markup.row_count, 200, 0, 4, frames, 8, &height), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_markup_layout(markup.row_size, markup.row_count, 200, 36, -1, frames, 8, &height), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_markup_layout(markup.row_size, markup.row_count, 5, 36, 4, frames, 8, &height), NOSHI_E_LIMIT);
    CHECK(height == 0);
    CHECK_EQ_INT(noshi_markup_read(inline_markup(NULL, 0), &markup), NOSHI_OK);
    CHECK_EQ_INT(noshi_markup_layout(markup.row_size, markup.row_count, 200, 36, 4, frames, 0, &height), NOSHI_OK);
    CHECK(height == 0);
}

int main(void) {
    noshi_arena_init(&arena, 16u * 1024u * 1024u);
    test_inline();
    test_inline_bad_buttons();
    test_keyboard();
    test_other_kinds();
    test_limits();
    test_layout();
    noshi_arena_free(&arena);
    return test_finish("test_markup");
}
