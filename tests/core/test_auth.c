#include "test_util.h"
#include "noshi_auth.h"
#include "noshi_tl_ids.h"

typedef struct fixture {
    noshi_auth auth;
    noshi_clock clock;
    uint64_t time;
    uint64_t wall_time;
    uint64_t id;
    uint32_t method;
    unsigned submits;
    unsigned cancels;
    unsigned changes;
    noshi_status send_status;
} fixture;

static uint64_t clock_now(void *ctx) { return ((fixture *)ctx)->time; }
static uint64_t clock_wall(void *ctx) {
    fixture *f = ctx;
    return f->wall_time ? f->wall_time : f->time;
}
static noshi_status submit(void *ctx, uint64_t id, const noshi_tl_value *v) {
    fixture *f = ctx;
    noshi_writer w;
    f->id = id;
    f->method = noshi_tl_id(v);
    ++f->submits;
    noshi_writer_init(&w, 256u * 1024u);
    CHECK_EQ_INT(noshi_tl_encode(v, &w, NULL), NOSHI_OK);
    noshi_writer_free(&w);
    return f->send_status;
}
static void cancel(void *ctx, uint64_t id) {
    fixture *f = ctx;
    CHECK(id > 0);
    ++f->cancels;
}
static void change(void *ctx, noshi_auth_state s, noshi_status status, const noshi_tl_value *v, const char *e) {
    fixture *f = ctx;
    (void)status; (void)v; (void)e;
    CHECK_EQ_INT(f->auth.state, s);
    ++f->changes;
}
static void init(fixture *f) {
    noshi_auth_events events;
    memset(f, 0, sizeof(*f));
    f->time = 100000;
    f->clock.realtime_ms = clock_wall;
    f->clock.monotonic_ms = clock_now;
    f->clock.ctx = f;
    events.ctx = f; events.submit = submit; events.cancel = cancel; events.changed = change;
    CHECK_EQ_INT(noshi_auth_init(&f->auth, 12345, "0123456789abcdef0123456789abcdef", &f->clock, &events), NOSHI_OK);
}
static noshi_status result(fixture *f, const noshi_tl_value *v, const char *error) {
    noshi_mt_rpc_result r;
    memset(&r, 0, sizeof(r));
    r.value = v;
    r.status = error ? NOSHI_E_RPC : NOSHI_OK;
    r.error_code = error ? 400 : 0;
    r.error_text = error;
    return noshi_auth_result(&f->auth, f->id, &r);
}
static noshi_tl_value *sent(noshi_arena *a, const char *delivery) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "auth.sentCode");
    noshi_tl_value *type = noshi_tl_new_obj(a, delivery);
    CHECK_EQ_INT(noshi_tl_set_i32(a, type, "length", 5), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "type", type), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(a, v, "phone_code_hash", "opaque-hash"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "next_type", noshi_tl_new_obj(a, "auth.codeTypeSms")), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "timeout", 30), NOSHI_OK);
    return v;
}

static void test_phone(void) {
    fixture f;
    noshi_arena a;
    noshi_tl_value *v;
    noshi_mt_rpc_result stale;
    uint64_t old;
    init(&f);
    noshi_arena_init(&a, 1024u * 1024u);
    CHECK_EQ_INT(noshi_auth_phone(&f.auth, "+79991234567", NULL), NOSHI_OK);
    CHECK_EQ_INT(f.method, NOSHI_TL_ID_auth_sendCode);
    CHECK_EQ_INT(result(&f, NULL, "PHONE_MIGRATE_4"), NOSHI_OK);
    CHECK_EQ_INT(f.auth.state, NOSHI_AUTH_MIGRATE);
    CHECK_EQ_INT(f.auth.migrate_dc, 4);
    CHECK_EQ_INT(noshi_auth_resume(&f.auth), NOSHI_OK);
    CHECK_EQ_INT(result(&f, sent(&a, "auth.sentCodeTypeSms"), NULL), NOSHI_OK);
    CHECK_EQ_INT(f.auth.state, NOSHI_AUTH_CODE);
    CHECK_EQ_INT(noshi_auth_resend(&f.auth, NULL), NOSHI_E_STATE);
    f.time += 30000;
    CHECK_EQ_INT(noshi_auth_resend(&f.auth, "SMS"), NOSHI_OK);
    CHECK_EQ_INT(result(&f, sent(&a, "auth.sentCodeTypeApp"), NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_auth_code(&f.auth, "12345", NULL), NOSHI_OK);
    CHECK_EQ_INT(result(&f, NULL, "PHONE_CODE_INVALID"), NOSHI_E_RPC);
    CHECK_EQ_INT(f.auth.state, NOSHI_AUTH_CODE);
    CHECK_EQ_INT(noshi_auth_code(&f.auth, "54321", NULL), NOSHI_OK);
    CHECK_EQ_INT(result(&f, NULL, "FLOOD_WAIT_17"), NOSHI_OK);
    CHECK_EQ_INT(noshi_auth_resume(&f.auth), NOSHI_E_RETRY);
    f.time += 17000;
    CHECK_EQ_INT(noshi_auth_resume(&f.auth), NOSHI_OK);
    v = noshi_tl_new_obj(&a, "auth.authorizationSignUpRequired");
    CHECK_EQ_INT(result(&f, v, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_auth_signup(&f.auth, "Name", "Last"), NOSHI_OK);
    CHECK_EQ_INT(f.method, NOSHI_TL_ID_auth_signUp);
    old = f.id;
    noshi_auth_cancel(&f.auth);
    memset(&stale, 0, sizeof(stale));
    stale.value = noshi_tl_new_obj(&a, "auth.authorization");
    CHECK_EQ_INT(noshi_auth_result(&f.auth, old, &stale), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(f.auth.state, NOSHI_AUTH_IDLE);
    CHECK_EQ_INT(noshi_auth_phone(&f.auth, "+79991234568", NULL), NOSHI_OK);
    f.time += 60000;
    CHECK_EQ_INT(noshi_auth_tick(&f.auth), NOSHI_E_TIMEOUT);
    CHECK_EQ_INT(f.auth.state, NOSHI_AUTH_IDLE);
    CHECK_EQ_INT(noshi_auth_phone(&f.auth, "+7999;1234", NULL), NOSHI_E_ARG);
    f.send_status = NOSHI_E_IO;
    CHECK_EQ_INT(noshi_auth_phone(&f.auth, "+79991234568", NULL), NOSHI_E_IO);
    CHECK_EQ_INT(f.auth.pending, 0);
    noshi_auth_free(&f.auth);
    noshi_arena_free(&a);
}

static void test_qr(void) {
    fixture f;
    noshi_arena a;
    noshi_tl_value *v;
    char url[128];
    const uint8_t token[] = {0xff, 0xef, 0x11, 0xaa, 0x55};
    init(&f);
    noshi_arena_init(&a, 1024u * 1024u);
    CHECK_EQ_INT(noshi_auth_next_ms(&f.auth), UINT32_MAX);
    CHECK_EQ_INT(noshi_auth_qr(&f.auth, NULL, 0), NOSHI_OK);
    /* the request waits sixty seconds for its answer */
    CHECK_EQ_INT(noshi_auth_next_ms(&f.auth), 60000);
    v = noshi_tl_new_obj(&a, "auth.loginToken");
    CHECK_EQ_INT(noshi_tl_set_bytes(&a, v, "token", token, sizeof(token)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "expires", 130), NOSHI_OK);
    CHECK_EQ_INT(result(&f, v, NULL), NOSHI_OK);
    /* the token ends at 130 s of a clock that stands at 100 s */
    CHECK_EQ_INT(noshi_auth_next_ms(&f.auth), 30000);
    CHECK_EQ_INT(noshi_auth_qr_url(v, url, sizeof(url)), NOSHI_OK);
    CHECK(!strcmp(url, "tg://login?token=_-8RqlU"));
    CHECK_EQ_INT(noshi_auth_qr_url(v, url, 20), NOSHI_E_LIMIT);
    CHECK_EQ_INT(url[0], 0);
    f.time = 130000;
    CHECK_EQ_INT(noshi_auth_next_ms(&f.auth), 0);
    CHECK_EQ_INT(noshi_auth_tick(&f.auth), NOSHI_OK);
    CHECK_EQ_INT(f.method, NOSHI_TL_ID_auth_exportLoginToken);
    v = noshi_tl_new_obj(&a, "auth.loginTokenMigrateTo");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "dc_id", 2), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_bytes(&a, v, "token", token, sizeof(token)), NOSHI_OK);
    CHECK_EQ_INT(result(&f, v, NULL), NOSHI_OK);
    CHECK_EQ_INT(f.auth.state, NOSHI_AUTH_MIGRATE);
    CHECK_EQ_INT(noshi_auth_resume(&f.auth), NOSHI_OK);
    CHECK_EQ_INT(f.method, NOSHI_TL_ID_auth_importLoginToken);
    CHECK_EQ_INT(result(&f, NULL, "SESSION_PASSWORD_NEEDED"), NOSHI_OK);
    CHECK_EQ_INT(f.method, NOSHI_TL_ID_account_getPassword);
    CHECK_EQ_INT(result(&f, NULL, "FLOOD_WAIT_1"), NOSHI_OK);
    f.time += 1000;
    CHECK_EQ_INT(noshi_auth_resume(&f.auth), NOSHI_OK);
    noshi_auth_free(&f.auth);
    noshi_arena_free(&a);
}

static void test_qr_clock_and_pending(void) {
    fixture f;
    noshi_arena a;
    init(&f);
    f.wall_time = 3700000;
    f.auth.server_time_offset_ms = -3600000;
    noshi_arena_init(&a, 1024u * 1024u);
    noshi_tl_value *v = noshi_tl_new_obj(&a, "auth.loginToken");
    const uint8_t token[] = {1, 2, 3};
    CHECK_EQ_INT(noshi_tl_set_bytes(&a, v, "token", token, sizeof(token)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "expires", 130), NOSHI_OK);
    CHECK_EQ_INT(noshi_auth_qr(&f.auth, NULL, 0), NOSHI_OK);
    CHECK_EQ_INT(result(&f, v, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_auth_next_ms(&f.auth), 30000);
    f.wall_time += 7200000;
    CHECK_EQ_INT(noshi_auth_next_ms(&f.auth), 30000);
    f.time += 30000;
    CHECK_EQ_INT(noshi_auth_tick(&f.auth), NOSHI_OK);
    unsigned submitted = f.submits;
    CHECK_EQ_INT(noshi_auth_next_ms(&f.auth), 60000);
    for (int i = 0; i < 20; ++i) CHECK_EQ_INT(noshi_auth_tick(&f.auth), NOSHI_OK);
    CHECK_EQ_INT(f.submits, submitted);
    CHECK_EQ_INT(f.auth.qr_refresh, 0);
    CHECK_EQ_INT(result(&f, v, NULL), NOSHI_OK);
    CHECK_EQ_INT(f.submits, submitted);
    CHECK_EQ_INT(noshi_auth_next_ms(&f.auth), 1000);
    noshi_arena_free(&a);
    noshi_auth_free(&f.auth);
}

int main(void) {
    test_phone();
    test_qr();
    test_qr_clock_and_pending();
    return test_finish("test_auth");
}
