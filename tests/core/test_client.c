#include "test_util.h"
#include "noshi_client.h"
#include "noshi_tl_ids.h"

typedef struct fixture {
    noshi_client client;
    noshi_mt_transport server;
    noshi_mt_session_state session;
    noshi_clock clock;
    uint64_t now;
    uint64_t reply_id;
    unsigned changes;
    unsigned errors;
    noshi_auth_state auth_state;
    noshi_status save_error;
    unsigned calls;
    unsigned folders;
    unsigned typings;
    noshi_typing last_typing;
    int64_t last_call;
} fixture;

static uint64_t time_now(void *ctx) { return ((fixture *)ctx)->now; }
static noshi_status send_bytes(void *ctx, int32_t dc, const uint8_t *bytes, size_t len) {
    fixture *f = ctx;
    CHECK_EQ_INT(dc, f->client.config.dc_id);
    return noshi_mt_transport_feed(&f->server, bytes, len);
}
static noshi_status load(void *ctx, int32_t dc, noshi_mt_session_state *session) {
    fixture *f = ctx;
    CHECK(dc > 0);
    *session = f->session;
    return NOSHI_OK;
}
static noshi_status save(void *ctx, int32_t dc, const noshi_mt_session_state *session) {
    fixture *f = ctx;
    CHECK(dc > 0);
    if (f->save_error) return f->save_error;
    f->session = *session;
    return NOSHI_OK;
}
static void changed(void *ctx) { ++((fixture *)ctx)->changes; }
static void error(void *ctx, noshi_status status, const char *boundary) {
    fixture *f = ctx;
    CHECK(status != NOSHI_OK && boundary != NULL);
    ++f->errors;
}
static void folders_changed(void *ctx) { ++((fixture *)ctx)->folders; }
static void on_typing(void *ctx, const noshi_typing *typing) {
    fixture *f = ctx;
    ++f->typings;
    f->last_typing = *typing;
}
static void on_call(void *ctx, const noshi_tl_value *call) {
    fixture *f = ctx;
    CHECK(noshi_tl_is(call, NOSHI_TL_ID_phoneCallRequested));
    noshi_tl_get_i64(call, "id", &f->last_call);
    ++f->calls;
}
static void auth(void *ctx, noshi_auth_state state, noshi_status status, const noshi_tl_value *value, const char *text) {
    fixture *f = ctx;
    (void)status; (void)value; (void)text;
    f->auth_state = state;
}
static void start(fixture *f, int first) {
    noshi_client_events events;
    noshi_mt_client_config config;
    unsigned i;
    if (first) {
        memset(f, 0, sizeof(*f));
        f->now = UINT64_C(1700000000000);
        for (i = 0; i < 256; ++i) f->session.auth_key[i] = (uint8_t)i;
        f->session.server_salt = 123;
    }
    f->reply_id = (f->now / 1000u << 32) | 1u;
    f->clock.realtime_ms = time_now; f->clock.monotonic_ms = time_now; f->clock.ctx = f;
    memset(&events, 0, sizeof(events)); memset(&config, 0, sizeof(config));
    events.ctx = f; events.send = send_bytes; events.load_session = load; events.save_session = save;
    events.auth = auth; events.changed = changed; events.error = error; events.phone_call = on_call; events.folders_changed = folders_changed;
    events.typing = on_typing;
    config.dc_id = 2; config.api_id = 12345; config.clock = &f->clock; config.transport = NOSHI_MT_INTERMEDIATE;
    noshi_mt_transport_init(&f->server);
    CHECK_EQ_INT(noshi_mt_transport_start_server(&f->server, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_init(&f->client, &config, "0123456789abcdef0123456789abcdef", &events), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_connect(&f->client), NOSHI_OK);
}
static void stop(fixture *f) {
    noshi_client_free(&f->client);
    noshi_mt_transport_free(&f->server);
}
static uint64_t pop(fixture *f, noshi_arena *arena, noshi_tl_value **request) {
    noshi_mt_frame frame;
    noshi_mt_header h;
    noshi_writer plain;
    const uint8_t *body;
    size_t len;
    CHECK_EQ_INT(noshi_mt_transport_next(&f->server, &frame), NOSHI_OK);
    noshi_writer_init(&plain, 2u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_mt_decrypt(&f->client.mt.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(arena, NULL, NOSHI_TL_REF_ANY, body, len, request), NOSHI_OK);
    while (noshi_tl_is(*request, NOSHI_TL_ID_invokeWithLayer) || noshi_tl_is(*request, NOSHI_TL_ID_initConnection))
        *request = (noshi_tl_value *)noshi_tl_get(*request, "query");
    noshi_writer_free(&plain);
    return h.msg_id;
}
static void reply(fixture *f, uint64_t msg_id, const noshi_tl_value *value) {
    noshi_mt_header h;
    noshi_writer body, enc, wire;
    noshi_writer_init(&body, 1u << 20); noshi_writer_init(&enc, 1u << 20); noshi_writer_init(&wire, 1u << 20);
    CHECK_EQ_INT(noshi_wr_u32le(&body, NOSHI_TL_ID_rpc_result), NOSHI_OK);
    CHECK_EQ_INT(noshi_wr_u64le(&body, msg_id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_encode(value, &body, NULL), NOSHI_OK);
    h.msg_id = f->reply_id; f->reply_id += 4;
    h.salt = f->client.mt.salt; h.session_id = f->client.mt.session_id; h.seq_no = 1;
    CHECK_EQ_INT(noshi_mt_encrypt(&f->client.mt.key, 0, &h, body.data, body.len, &enc), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_transport_wrap(&f->server, enc.data, enc.len, 0, &wire), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_feed(&f->client, wire.data, wire.len), NOSHI_OK);
    /* acknowledgements must not be mistaken for the next application request */
    { noshi_mt_frame frame; CHECK_EQ_INT(noshi_mt_transport_next(&f->server, &frame), NOSHI_OK); }
    noshi_writer_free(&body); noshi_writer_free(&enc); noshi_writer_free(&wire);
}
/* a message the server starts, such as an update, which is not the answer to a request */
static void push(fixture *f, const noshi_tl_value *value) {
    noshi_mt_header h;
    noshi_writer body, enc, wire;
    noshi_writer_init(&body, 1u << 20); noshi_writer_init(&enc, 1u << 20); noshi_writer_init(&wire, 1u << 20);
    CHECK_EQ_INT(noshi_tl_encode(value, &body, NULL), NOSHI_OK);
    h.msg_id = f->reply_id; f->reply_id += 4;
    h.salt = f->client.mt.salt; h.session_id = f->client.mt.session_id; h.seq_no = 1;
    CHECK_EQ_INT(noshi_mt_encrypt(&f->client.mt.key, 0, &h, body.data, body.len, &enc), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_transport_wrap(&f->server, enc.data, enc.len, 0, &wire), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_feed(&f->client, wire.data, wire.len), NOSHI_OK);
    { noshi_mt_frame frame; CHECK_EQ_INT(noshi_mt_transport_next(&f->server, &frame), NOSHI_OK); }
    noshi_writer_free(&body); noshi_writer_free(&enc); noshi_writer_free(&wire);
}
static noshi_tl_value *call_update(noshi_arena *a, int64_t id, int with_call) {
    noshi_tl_value *short_update = noshi_tl_new_obj(a, "updateShort"), *update = noshi_tl_new_obj(a, "updatePhoneCall");
    noshi_tl_value *call = noshi_tl_new_obj(a, with_call ? "phoneCallRequested" : "phoneCallEmpty");
    CHECK_EQ_INT(noshi_tl_set_i64(a, call, "id", id), NOSHI_OK);
    if (with_call) {
        noshi_tl_value *proto = noshi_tl_new_obj(a, "phoneCallProtocol");
        uint8_t hash[32] = {0};
        CHECK_EQ_INT(noshi_tl_set_i64(a, call, "access_hash", 5), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(a, call, "date", 100), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(a, call, "admin_id", 7), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(a, call, "participant_id", 1), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_bytes(a, call, "g_a_hash", hash, 32), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(a, proto, "min_layer", 65), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(a, proto, "max_layer", 92), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(proto, "library_versions", noshi_tl_new_vec(a, 0)), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(call, "protocol", proto), NOSHI_OK);
    }
    CHECK_EQ_INT(noshi_tl_set(update, "phone_call", call), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(short_update, "update", update), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, short_update, "date", 100), NOSHI_OK);
    return short_update;
}
static noshi_tl_value *send_request(noshi_arena *a, int64_t random_id) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "messages.sendMessage"), *peer = noshi_tl_new_obj(a, "inputPeerUser");
    CHECK_EQ_INT(noshi_tl_set_i64(a, peer, "user_id", 2), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(a, peer, "access_hash", INT64_MIN + 17), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "peer", peer), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(a, v, "random_id", random_id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(a, v, "message", "hello offline"), NOSHI_OK);
    return v;
}
static noshi_tl_value *sent(noshi_arena *a, int32_t id, int32_t pts) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "updateShortSentMessage");
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "pts", pts), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "pts_count", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "date", 101), NOSHI_OK);
    return v;
}

static noshi_tl_value *migrate_error(noshi_arena *a, const char *text) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "rpc_error");
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "error_code", 303), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(a, v, "error_message", text), NOSHI_OK);
    return v;
}

/* a phone that lives on another data center must resend the code request there, with that dc in the obfuscation header */
static void test_auth_migrate(void) {
    fixture f;
    noshi_arena a;
    noshi_tl_value *request;
    uint64_t msg_id;
    const char *phone;
    size_t phone_len;
    noshi_arena_init(&a, 8u * 1024u * 1024u);
    start(&f, 1);
    CHECK_EQ_INT(noshi_auth_phone(&f.client.auth, "+79991234567", NULL), NOSHI_OK);
    msg_id = pop(&f, &a, &request);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_auth_sendCode));
    reply(&f, msg_id, migrate_error(&a, "PHONE_MIGRATE_4"));
    CHECK_EQ_INT(f.auth_state, NOSHI_AUTH_MIGRATE);
    CHECK_EQ_INT(f.client.auth.migrate_dc, 4);
    CHECK_EQ_INT(noshi_client_migrate(&f.client, 3), NOSHI_E_STATE);

    f.client.config.obfuscation.enabled = 1;
    f.client.config.obfuscation.dc_id = 2;
    noshi_mt_transport_free(&f.server);
    noshi_mt_transport_init(&f.server);
    CHECK_EQ_INT(noshi_mt_transport_start_server(&f.server, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_migrate(&f.client, 4), NOSHI_OK);
    CHECK_EQ_INT(f.client.config.dc_id, 4);
    CHECK_EQ_INT(f.client.config.obfuscation.dc_id, 4);
    CHECK_EQ_INT(noshi_client_connect(&f.client), NOSHI_OK);
    CHECK_EQ_INT(f.server.obf.dc_id, 4);
    msg_id = pop(&f, &a, &request);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_auth_sendCode));
    CHECK_EQ_INT(noshi_tl_get_bytes(request, "phone_number", (const uint8_t **)&phone, &phone_len), NOSHI_OK);
    CHECK_EQ_INT(phone_len, 12);
    CHECK(memcmp(phone, "+79991234567", phone_len) == 0);
    (void)msg_id;
    CHECK_EQ_INT(f.errors, 0);
    stop(&f);
    noshi_wipe(&f.session, sizeof(f.session));
    noshi_arena_free(&a);
}

int main(void) {
    fixture f;
    noshi_arena a;
    noshi_store *s;
    noshi_tl_value *request, *v;
    noshi_peer peer = {1, 2};
    noshi_cursor cursor;
    uint32_t ms;
    uint64_t msg_id;
    int64_t random_id;
    noshi_arena_init(&a, 8u * 1024u * 1024u);
    start(&f, 1);
    CHECK_EQ_INT(noshi_store_open(&s, ":memory:", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_attach_store(&f.client, s, 1), NOSHI_OK);
    /* a full transport queue must not leave update recovery suspended forever */
    {
        uint32_t limit = f.client.mt.config.max_pending;
        f.client.mt.config.max_pending = 0;
        CHECK_EQ_INT(noshi_client_tick(&f.client, &ms), NOSHI_E_LIMIT);
        CHECK(f.client.sync_suspended && f.client.sync_retry);
        f.client.mt.config.max_pending = limit;
        noshi_client_resume_sync(&f.client);
        CHECK(!f.client.sync_suspended && !f.client.sync_retry);
        CHECK_EQ_INT(f.errors, 1);
        f.errors = 0;
    }
    CHECK_EQ_INT(noshi_client_tick(&f.client, &ms), NOSHI_OK);
    msg_id = pop(&f, &a, &request);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_updates_getState));
    v = noshi_tl_new_obj(&a, "updates.state");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "pts", 10), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "qts", 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "seq", 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "date", 100), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "unread_count", 0), NOSHI_OK);
    reply(&f, msg_id, v);
    {
        noshi_tl_value *short_update = noshi_tl_new_obj(&a, "updateShort");
        noshi_tl_value *typing = noshi_tl_new_obj(&a, "updateUserTyping");
        CHECK_EQ_INT(noshi_tl_set_i64(&a, typing, "user_id", 2), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(typing, "action", noshi_tl_new_obj(&a, "sendMessageTypingAction")), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(short_update, "update", typing), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&a, short_update, "date", 100), NOSHI_OK);
        push(&f, short_update);
        CHECK_EQ_INT(f.typings, 1);
        CHECK_EQ_INT(f.last_typing.peer_kind, 1);
        CHECK_EQ_INT(f.last_typing.peer_id, 2);
        CHECK_EQ_INT(f.last_typing.action, NOSHI_TYPING_TEXT);
    }
    CHECK_EQ_INT(noshi_client_send(&f.client, peer, send_request(&a, INT64_MIN + 90)), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_tick(&f.client, &ms), NOSHI_OK);
    msg_id = pop(&f, &a, &request);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_messages_sendMessage));
    CHECK_EQ_INT(noshi_tl_get_i64(request, "random_id", &random_id), NOSHI_OK);
    CHECK_EQ_INT(random_id, INT64_MIN + 90);
    reply(&f, msg_id, sent(&a, 42, 11));
    CHECK_EQ_INT(noshi_store_cursor_get(s, 0, &cursor), NOSHI_OK);
    CHECK_EQ_INT(cursor.pts, 11);
    /* a call that rings reaches the app as it came; the update does not move the cursor */
    push(&f, call_update(&a, 4001, 1));
    CHECK_EQ_INT(f.calls, 1);
    CHECK_EQ_INT(f.last_call, 4001);
    CHECK_EQ_INT(noshi_store_cursor_get(s, 0, &cursor), NOSHI_OK);
    CHECK_EQ_INT(cursor.pts, 11);
    {
        noshi_tl_value *update = noshi_tl_new_obj(&a, "updateShort");
        noshi_tl_value *filters = noshi_tl_new_obj(&a, "updateDialogFilters");
        CHECK_EQ_INT(noshi_tl_set(update, "update", filters), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&a, update, "date", 100), NOSHI_OK);
        push(&f, update);
        CHECK_EQ_INT(f.folders, 1);
        f.client.events.folders_changed = NULL;
        push(&f, update);
        CHECK_EQ_INT(f.folders, 1);
    }
    CHECK_EQ_INT(noshi_client_send(&f.client, peer, send_request(&a, INT64_MIN + 91)), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_tick(&f.client, &ms), NOSHI_OK);
    msg_id = pop(&f, &a, &request);
    CHECK_EQ_INT(noshi_tl_get_i64(request, "random_id", &random_id), NOSHI_OK);
    CHECK_EQ_INT(random_id, INT64_MIN + 91);
    stop(&f);
    start(&f, 0);
    CHECK_EQ_INT(noshi_client_attach_store(&f.client, s, 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_client_tick(&f.client, &ms), NOSHI_OK);
    msg_id = pop(&f, &a, &request);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_updates_getDifference));
    v = noshi_tl_new_obj(&a, "updates.differenceEmpty");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "date", 101), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "seq", 1), NOSHI_OK);
    { uint64_t out_msg = pop(&f, &a, &request);
      CHECK_EQ_INT(noshi_tl_get_i64(request, "random_id", &random_id), NOSHI_OK);
      CHECK_EQ_INT(random_id, INT64_MIN + 91);
      reply(&f, msg_id, v);
      reply(&f, out_msg, sent(&a, 43, 12)); }
    CHECK_EQ_INT(noshi_store_cursor_get(s, 0, &cursor), NOSHI_OK);
    CHECK_EQ_INT(cursor.pts, 12);
    CHECK_EQ_INT(f.errors, 0);
    stop(&f);
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    noshi_arena_free(&a);
    noshi_wipe(&f.session, sizeof(f.session));
    test_auth_migrate();
    return test_finish("test_client");
}
