#include "test_util.h"
#include "noshi_sessions.h"
#include "noshi_tl_ids.h"

#include <string.h>

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void str(noshi_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, field, x), NOSHI_OK);
}
static void roundtrip(noshi_tl_value *request, uint32_t constructor) {
    noshi_writer writer;
    noshi_tl_value *decoded = NULL;
    noshi_writer_init(&writer, 65536);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, writer.data, writer.len, &decoded), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(decoded), constructor);
    noshi_writer_free(&writer);
}

static noshi_tl_value *auth(int64_t hash, int current, const char *model, const char *platform, const char *system, const char *app, const char *version) {
    noshi_tl_value *v = obj("authorization");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, "hash", hash), NOSHI_OK);
    if (current) CHECK_EQ_INT(noshi_tl_set_flag(v, "current"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "api_id", 4), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "date_created", 100 + (int32_t)hash), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "date_active", 200 + (int32_t)hash), NOSHI_OK);
    str(v, "device_model", model);
    str(v, "platform", platform);
    str(v, "system_version", system);
    str(v, "app_name", app);
    str(v, "app_version", version);
    str(v, "ip", "1.2.3.4");
    str(v, "country", "Germany");
    str(v, "region", "");
    return v;
}

static noshi_tl_value *answer(noshi_tl_value **items, uint32_t n, int32_t ttl) {
    noshi_tl_value *a = obj("account.authorizations"), *vec = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(vec, i, items[i]), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, a, "authorization_ttl_days", ttl), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(a, "authorizations", vec), NOSHI_OK);
    return a;
}

static void test_parse(void) {
    noshi_session_info rows[4];
    noshi_tl_value *items[5];
    size_t count = 99;
    int32_t ttl = -1;
    items[0] = auth(1, 0, "Galaxy", "Android", "14", "Telegram Android", "13.1.0");
    items[1] = auth(2, 1, "iPhone4,1", "iOS", "6.1.6", "noshigram", "0.1.0");
    items[2] = auth(0, 0, "no hash", "", "", "", "");
    items[3] = auth(4, 0, "Firefox 154", "Web", "", "Telegram Web", "2.2 K");
    items[4] = obj("boolTrue");
    CHECK_EQ_INT(noshi_sessions_parse(answer(items, 4, 180), rows, 4, &count, &ttl), NOSHI_OK);
    /* this session leads, a session without a hash is left out, the server's order holds for the rest */
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(ttl, 180);
    CHECK_EQ_INT(rows[0].hash, 2);
    CHECK_EQ_INT(rows[0].current, 1);
    CHECK_EQ_INT(rows[1].hash, 1);
    CHECK_EQ_INT(rows[2].hash, 4);
    CHECK(!strcmp(rows[0].device_model, "iPhone4,1"));
    CHECK(!strcmp(rows[1].app_version, "13.1.0"));
    CHECK_EQ_INT(rows[0].secret_chats_off, 0);
    /* cap cuts the list short and keeps the current one in front */
    CHECK_EQ_INT(noshi_sessions_parse(answer(items, 4, 7), rows, 2, &count, NULL), NOSHI_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(noshi_sessions_parse(answer(items, 4, 7), NULL, 0, &count, NULL), NOSHI_OK);
    CHECK_EQ_INT(count, 0);
    /* the current session of the server has the hash zero and must still be listed, first */
    {
        noshi_tl_value *zero[2];
        zero[0] = auth(7, 0, "Pixel", "Android", "14", "Telegram Android", "12.5.1");
        zero[1] = auth(0, 1, "iPhone4,1", "iOS", "6.1.6", "noshigram", "0.1.0");
        CHECK_EQ_INT(noshi_sessions_parse(answer(zero, 2, 7), rows, 4, &count, NULL), NOSHI_OK);
        CHECK_EQ_INT(count, 2);
        CHECK_EQ_INT(rows[0].current, 1);
        CHECK_EQ_INT(rows[0].hash, 0);
        CHECK_EQ_INT(rows[1].hash, 7);
    }
    CHECK_EQ_INT(noshi_sessions_parse(items[4], rows, 4, &count, &ttl), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(ttl, 0);
    CHECK_EQ_INT(noshi_sessions_parse(answer(items, 1, 7), NULL, 4, &count, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_sessions_parse(answer(items, 1, 7), rows, 4, NULL, NULL), NOSHI_E_ARG);
    /* a flag on the session reads as the switch off */
    CHECK_EQ_INT(noshi_tl_set_flag(items[0], "encrypted_requests_disabled"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_flag(items[0], "call_requests_disabled"), NOSHI_OK);
    CHECK_EQ_INT(noshi_sessions_parse(answer(items, 1, 7), rows, 4, &count, NULL), NOSHI_OK);
    CHECK_EQ_INT(rows[0].secret_chats_off, 1);
    CHECK_EQ_INT(rows[0].calls_off, 1);
}

static noshi_session_kind kind(const char *model, const char *platform, const char *system, const char *app) {
    noshi_session_info s;
    memset(&s, 0, sizeof(s));
    strcpy(s.device_model, model);
    strcpy(s.platform, platform);
    strcpy(s.system_version, system);
    strcpy(s.app_name, app);
    return noshi_session_kind_of(&s);
}

static void test_kind_and_titles(void) {
    noshi_session_info s;
    char text[64];
    CHECK_EQ_INT(kind("iPhone 4S", "iOS", "", "noshigram"), NOSHI_SESSION_IPHONE);
    CHECK_EQ_INT(kind("iPad Air", "iOS", "", "Telegram"), NOSHI_SESSION_IPAD);
    CHECK_EQ_INT(kind("MacBook Air M2", "macOS", "", "Telegram macOS"), NOSHI_SESSION_MAC);
    CHECK_EQ_INT(kind("PC 64bit", "Windows", "", "Telegram Desktop"), NOSHI_SESSION_WINDOWS);
    CHECK_EQ_INT(kind("Galaxy S25", "Android", "", "Telegram Android"), NOSHI_SESSION_ANDROID);
    CHECK_EQ_INT(kind("Galaxy Tab S9", "Android", "", "Telegram Android"), NOSHI_SESSION_ANDROID_TABLET);
    CHECK_EQ_INT(kind("Firefox 154", "Web", "", "Telegram Web"), NOSHI_SESSION_FIREFOX);
    CHECK_EQ_INT(kind("Chrome 120", "Windows", "", "Telegram Web"), NOSHI_SESSION_CHROME);
    CHECK_EQ_INT(kind("Safari 17", "macOS", "", "Telegram Web"), NOSHI_SESSION_SAFARI);
    CHECK_EQ_INT(kind("Vivaldi", "Web", "", "Telegram Web"), NOSHI_SESSION_WEB);
    CHECK_EQ_INT(kind("PC", "Ubuntu 22.04", "", "Telegram Desktop"), NOSHI_SESSION_UBUNTU);
    CHECK_EQ_INT(kind("PC", "Linux", "", "Telegram Desktop"), NOSHI_SESSION_LINUX);
    CHECK_EQ_INT(kind("Box", "", "", "Some Desktop"), NOSHI_SESSION_DESKTOP);
    CHECK_EQ_INT(kind("", "", "", ""), NOSHI_SESSION_OTHER);
    /* the platform names the system when it is empty */
    CHECK_EQ_INT(kind("x", "", "iOS 6", "y"), NOSHI_SESSION_IPHONE);

    memset(&s, 0, sizeof(s));
    strcpy(s.platform, "Android");
    strcpy(s.system_version, "14");
    noshi_session_title(&s, text, sizeof(text));
    CHECK(!strcmp(text, "Android 14"));
    strcpy(s.device_model, "Pixel 9");
    noshi_session_title(&s, text, sizeof(text));
    CHECK(!strcmp(text, "Pixel 9"));
    noshi_session_title(&s, text, 4);
    CHECK(!strcmp(text, "Pix"));
    strcpy(s.app_name, "Telegram Android");
    strcpy(s.app_version, "12.5.1");
    noshi_session_app_line(&s, text, sizeof(text));
    CHECK(!strcmp(text, "Telegram Android 12.5.1"));
    s.app_version[0] = 0;
    noshi_session_app_line(&s, text, sizeof(text));
    CHECK(!strcmp(text, "Telegram Android"));
}

static void test_requests(void) {
    noshi_tl_value *request = NULL;
    const noshi_tl_value *flag;
    CHECK_EQ_INT(noshi_sessions_request(&arena, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_account_getAuthorizations);
    CHECK_EQ_INT(noshi_session_end_request(&arena, 77, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_account_resetAuthorization);
    CHECK_EQ_INT(noshi_session_end_request(&arena, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_sessions_end_others_request(&arena, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_auth_resetAuthorizations);

    /* a switch turned off sends the field as true, since the field says what is disabled */
    CHECK_EQ_INT(noshi_session_settings_request(&arena, 9, 0, -1, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_account_changeAuthorizationSettings);
    flag = noshi_tl_get(request, "encrypted_requests_disabled");
    CHECK(noshi_tl_is(flag, NOSHI_TL_ID_boolTrue));
    CHECK_EQ_INT(noshi_tl_has(request, "call_requests_disabled"), 0);
    CHECK_EQ_INT(noshi_session_settings_request(&arena, 9, -1, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "encrypted_requests_disabled"), 0);
    CHECK(noshi_tl_is(noshi_tl_get(request, "call_requests_disabled"), NOSHI_TL_ID_boolFalse));
    CHECK_EQ_INT(noshi_session_settings_request(&arena, 9, -1, -1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_session_settings_request(&arena, 0, 1, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_session_settings_request(&arena, 9, 2, 1, &request), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_sessions_ttl_request(&arena, 180, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_account_setAuthorizationTTL);
    CHECK_EQ_INT(noshi_sessions_ttl_request(&arena, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_sessions_ttl_request(&arena, 366, &request), NOSHI_E_ARG);
}

static void test_login_token(void) {
    uint8_t token[NOSHI_LOGIN_TOKEN_MAX];
    size_t len = 99;
    noshi_tl_value *request = NULL;
    /* 24 bytes 0x00..0x17 in url-safe base64 */
    CHECK_EQ_INT(noshi_login_token_from_link("tg://login?token=AAECAwQFBgcICQoLDA0ODxAREhMUFRYX", token, sizeof(token), &len), NOSHI_OK);
    CHECK_EQ_INT(len, 24);
    CHECK_EQ_INT(token[0], 0);
    CHECK_EQ_INT(token[23], 0x17);
    /* the url-safe letters stand for 62 and 63: "--__" is the bytes 0xFB 0xEF 0xFF */
    CHECK_EQ_INT(noshi_login_token_from_link("tg://login?token=--__AAECAwQFBgcICQoLDA0ODxAREg", token, sizeof(token), &len), NOSHI_OK);
    CHECK_EQ_INT(token[0], 0xFB);
    CHECK_EQ_INT(token[1], 0xEF);
    CHECK_EQ_INT(token[2], 0xFF);
    CHECK_EQ_INT(noshi_login_token_from_link("https://t.me/x", token, sizeof(token), &len), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(noshi_login_token_from_link("tg://login?token=AAEC", token, sizeof(token), &len), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_login_token_from_link("tg://login?token=AA!ECAwQFBgcICQoLDA0ODxAREhMUFRYX", token, sizeof(token), &len), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_login_token_from_link("tg://login?token=AAECAwQFBgcICQoLDA0ODxAREhMUFRYX", token, 8, &len), NOSHI_E_LIMIT);
    CHECK_EQ_INT(noshi_login_token_from_link(NULL, token, sizeof(token), &len), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_login_token_accept_request(&arena, token, 24, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_auth_acceptLoginToken);
    CHECK_EQ_INT(noshi_login_token_accept_request(&arena, token, 8, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_parse();
    test_kind_and_titles();
    test_requests();
    test_login_token();
    noshi_arena_free(&arena);
    return test_finish("test_sessions");
}
