#include "test_util.h"

#include <zlib.h>

#include "noshi_mt_client.h"
#include "noshi_tl_ids.h"

#define CONTAINER_ID 0x73f1f8dcu

typedef struct client_fixture {
    noshi_mt_client client;
    noshi_mt_transport server;
    noshi_clock clock;
    uint64_t now;
    uint64_t server_id;
    unsigned results;
    unsigned updates;
    unsigned lost;
    unsigned sessions;
    uint64_t request_id;
    noshi_status result_status;
    noshi_status state_reason;
    uint32_t result_ctor;
    uint32_t vector_count;
    int32_t error_code;
    char error_text[64];
    int free_on_result;
} client_fixture;

static uint64_t fixture_time(void *ctx) {
    return ((client_fixture *)ctx)->now;
}

static void sent(void *ctx, const uint8_t *data, size_t len) {
    client_fixture *f = ctx;
    CHECK_EQ_INT(noshi_mt_transport_feed(&f->server, data, len), NOSHI_OK);
}

static void result(void *ctx, uint64_t request_id, const noshi_mt_rpc_result *r) {
    client_fixture *f = ctx;
    f->results++;
    f->request_id = request_id;
    f->result_status = r->status;
    f->result_ctor = noshi_tl_id(r->value);
    f->vector_count = r->value && r->value->kind == NOSHI_TL_V_VEC ? r->value->u.vec.count : UINT32_MAX;
    f->error_code = r->error_code;
    if (r->error_text) snprintf(f->error_text, sizeof(f->error_text), "%s", r->error_text);
    if (f->free_on_result) noshi_mt_client_free(&f->client);
}

static void update(void *ctx, const noshi_tl_value *v) {
    client_fixture *f = ctx;
    CHECK_EQ_INT(noshi_tl_id(v), NOSHI_TL_ID_updatesTooLong);
    f->updates++;
}

static void lost(void *ctx, noshi_status reason) {
    client_fixture *f = ctx;
    CHECK(reason != NOSHI_OK);
    f->lost++;
}

static void session(void *ctx) {
    ((client_fixture *)ctx)->sessions++;
}

static void state(void *ctx, noshi_mt_client_state st, noshi_status reason) {
    client_fixture *f = ctx;
    (void)st;
    f->state_reason = reason;
}

/* nonzero makes the client wrap its requests with initConnection */
static int32_t fixture_api_id;

static void fixture_init(client_fixture *f, size_t arena_limit) {
    noshi_mt_client_config config;
    noshi_mt_client_events events;
    noshi_mt_session_state restore;
    unsigned i;
    memset(f, 0, sizeof(*f));
    memset(&config, 0, sizeof(config));
    memset(&events, 0, sizeof(events));
    memset(&restore, 0, sizeof(restore));
    f->now = 1700000000123ull;
    f->server_id = (1700000000ull << 32) | 1u;
    f->clock.realtime_ms = fixture_time;
    f->clock.monotonic_ms = fixture_time;
    f->clock.ctx = f;
    for (i = 0; i < sizeof(restore.auth_key); ++i) restore.auth_key[i] = (uint8_t)i;
    restore.server_salt = 123456789;
    config.clock = &f->clock;
    config.restore = &restore;
    config.transport = NOSHI_MT_INTERMEDIATE;
    config.api_id = fixture_api_id;
    config.device_model = "iPhone4,1";
    config.system_version = "iPhone OS 6.1";
    config.app_version = "1.0";
    config.result_arena_limit = (uint32_t)arena_limit;
    events.ctx = f;
    events.send = sent;
    events.rpc_result = result;
    events.update = update;
    events.update_lost = lost;
    events.new_session = session;
    events.state = state;
    noshi_mt_transport_init(&f->server);
    CHECK_EQ_INT(noshi_mt_transport_start_server(&f->server, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_init(&f->client, &config, &events), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_connect(&f->client), NOSHI_OK);
}

static void fixture_free(client_fixture *f) {
    noshi_mt_client_free(&f->client);
    noshi_mt_transport_free(&f->server);
}

static uint64_t submit(client_fixture *f, uint64_t id, int vector, uint32_t timeout) {
    noshi_arena a;
    noshi_tl_value *request;
    noshi_mt_frame frame;
    noshi_mt_header h;
    noshi_writer plain;
    const uint8_t *body;
    size_t len;
    noshi_arena_init(&a, 16384);
    request = noshi_tl_new_obj(&a, vector ? "messages.receivedMessages" : "account.updateStatus");
    CHECK(request != NULL);
    if (vector) CHECK_EQ_INT(noshi_tl_set_i32(&a, request, "max_id", 1), NOSHI_OK);
    else CHECK_EQ_INT(noshi_tl_set(request, "offline", noshi_tl_new_obj(&a, "boolFalse")), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_submit(&f->client, id, request, timeout), NOSHI_OK);
    noshi_arena_free(&a);
    CHECK_EQ_INT(noshi_mt_transport_next(&f->server, &frame), NOSHI_OK);
    CHECK_EQ_INT(frame.kind, NOSHI_MT_FRAME_DATA);
    noshi_writer_init(&plain, 1 << 20);
    CHECK_EQ_INT(noshi_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), NOSHI_OK);
    CHECK_EQ_INT(h.session_id, f->client.session_id);
    CHECK_EQ_INT(h.seq_no & 1, 1);
    CHECK_EQ_INT(noshi_get_u32le(body), vector ? NOSHI_TL_ID_messages_receivedMessages : NOSHI_TL_ID_account_updateStatus);
    noshi_writer_free(&plain);
    return h.msg_id;
}

/* a frame from the server built with any key, salt and session id, and with one byte of the ciphertext flipped when tamper is set */
static noshi_status receive_as(client_fixture *f, const noshi_mt_auth_key *key, uint64_t salt, uint64_t session_id,
                                 const uint8_t *body, size_t len, uint64_t msg_id, int32_t seq_no, int fragmented, int tamper) {
    noshi_mt_header h;
    noshi_writer enc, wire;
    noshi_status s;
    size_t pos;
    h.salt = salt;
    h.session_id = session_id;
    h.msg_id = msg_id;
    h.seq_no = seq_no;
    noshi_writer_init(&enc, 1 << 20);
    noshi_writer_init(&wire, 1 << 20);
    CHECK_EQ_INT(noshi_mt_encrypt(key, 0, &h, body, len, &enc), NOSHI_OK);
    if (tamper) enc.data[40] ^= 1;
    CHECK_EQ_INT(noshi_mt_transport_wrap(&f->server, enc.data, enc.len, 0, &wire), NOSHI_OK);
    s = NOSHI_OK;
    if (fragmented) {
        for (pos = 0; pos < wire.len && s == NOSHI_OK; ++pos) {
            s = noshi_mt_client_feed(&f->client, wire.data + pos, 1);
        }
    } else s = noshi_mt_client_feed(&f->client, wire.data, wire.len);
    noshi_writer_free(&enc);
    noshi_writer_free(&wire);
    return s;
}

static noshi_status receive(client_fixture *f, const uint8_t *body, size_t len,
                               uint64_t msg_id, int32_t seq_no, int fragmented) {
    return receive_as(f, &f->client.key, f->client.salt, f->client.session_id, body, len, msg_id, seq_no, fragmented, 0);
}

static void drain_acks(client_fixture *f, unsigned expected) {
    noshi_mt_frame frame;
    unsigned got = 0;
    noshi_status s;
    while ((s = noshi_mt_transport_next(&f->server, &frame)) == NOSHI_OK) {
        noshi_writer plain;
        noshi_mt_header h;
        const uint8_t *body;
        size_t len;
        noshi_tl_value *v;
        const noshi_tl_value *ids;
        noshi_arena a;
        noshi_writer_init(&plain, 1 << 20);
        noshi_arena_init(&a, 1 << 20);
        CHECK_EQ_INT(noshi_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), NOSHI_OK);
        CHECK_EQ_INT(h.seq_no & 1, 0);
        CHECK_EQ_INT(noshi_tl_decode_all(&a, NULL, NOSHI_TL_REF_ANY, body, len, &v), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_id(v), NOSHI_TL_ID_msgs_ack);
        CHECK_EQ_INT(noshi_tl_get_vec(v, "msg_ids", &ids), NOSHI_OK);
        got += ids->u.vec.count;
        noshi_arena_free(&a);
        noshi_writer_free(&plain);
    }
    CHECK_EQ_INT(s, NOSHI_E_TRUNCATED);
    CHECK_EQ_INT(got, expected);
}

static void gzip_body(const uint8_t *data, size_t len, int trailing, noshi_writer *out) {
    uint8_t packed[8192];
    z_stream z;
    noshi_arena a;
    noshi_tl_value *v;
    size_t n;
    memset(&z, 0, sizeof(z));
    CHECK_EQ_INT(deflateInit2(&z, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY), Z_OK);
    z.next_in = (Bytef *)(uintptr_t)data;
    z.avail_in = (uInt)len;
    z.next_out = packed;
    z.avail_out = sizeof(packed) - 1;
    CHECK_EQ_INT(deflate(&z, Z_FINISH), Z_STREAM_END);
    n = sizeof(packed) - 1 - z.avail_out;
    CHECK_EQ_INT(deflateEnd(&z), Z_OK);
    if (trailing) packed[n++] = 0xff;
    noshi_arena_init(&a, 1 << 20);
    v = noshi_tl_new_obj(&a, "gzip_packed");
    CHECK_EQ_INT(noshi_tl_set_bytes(&a, v, "packed_data", packed, n), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_encode(v, out, NULL), NOSHI_OK);
    noshi_arena_free(&a);
}

static void test_rpc_gzip(void) {
    unsigned mode;
    for (mode = 0; mode < 4; ++mode) {
        client_fixture f;
        uint64_t request_id;
        noshi_writer rpc, packed, value;
        uint8_t raw[8];
        int vector = (int)(mode & 1u);
        fixture_init(&f, 0);
        request_id = submit(&f, 41, vector, 5000);
        noshi_writer_init(&rpc, 1 << 20);
        noshi_writer_init(&packed, 1 << 20);
        noshi_writer_init(&value, 1 << 20);
        noshi_put_u32le(raw, vector ? 0x1cb5c415u : NOSHI_TL_ID_boolTrue);
        noshi_put_u32le(raw + 4, 0);
        CHECK_EQ_INT(noshi_wr_u32le(&rpc, NOSHI_TL_ID_rpc_result), NOSHI_OK);
        CHECK_EQ_INT(noshi_wr_u64le(&rpc, request_id), NOSHI_OK);
        if (mode < 2) {
            CHECK_EQ_INT(noshi_wr_bytes(&rpc, raw, vector ? 8 : 4), NOSHI_OK);
            gzip_body(rpc.data, rpc.len, 0, &packed);
            CHECK_EQ_INT(receive(&f, packed.data, packed.len, f.server_id, 0, 1), NOSHI_OK);
        } else {
            gzip_body(raw, vector ? 8 : 4, 0, &value);
            CHECK_EQ_INT(noshi_wr_bytes(&rpc, value.data, value.len), NOSHI_OK);
            CHECK_EQ_INT(receive(&f, rpc.data, rpc.len, f.server_id, 1, 1), NOSHI_OK);
            drain_acks(&f, 1);
        }
        CHECK_EQ_INT(f.results, 1);
        CHECK_EQ_INT(f.request_id, 41);
        CHECK_EQ_INT(f.result_status, NOSHI_OK);
        CHECK_EQ_INT(vector ? f.vector_count : f.result_ctor, vector ? 0 : NOSHI_TL_ID_boolTrue);
        CHECK_EQ_INT(noshi_mt_client_pending_count(&f.client), 0);
        noshi_writer_free(&rpc);
        noshi_writer_free(&packed);
        noshi_writer_free(&value);
        fixture_free(&f);
    }
}

static void test_rpc_error(void) {
    client_fixture f;
    noshi_arena a;
    noshi_tl_value *v;
    noshi_writer rpc, error, packed;
    uint64_t request;
    fixture_init(&f, 0);
    request = submit(&f, 42, 0, 5000);
    noshi_arena_init(&a, 16384);
    noshi_writer_init(&rpc, 16384);
    noshi_writer_init(&error, 16384);
    noshi_writer_init(&packed, 16384);
    v = noshi_tl_new_obj(&a, "rpc_error");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "error_code", 303), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&a, v, "error_message", "PHONE_MIGRATE_4"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_encode(v, &error, NULL), NOSHI_OK);
    gzip_body(error.data, error.len, 0, &packed);
    CHECK_EQ_INT(noshi_wr_u32le(&rpc, NOSHI_TL_ID_rpc_result), NOSHI_OK);
    CHECK_EQ_INT(noshi_wr_u64le(&rpc, request), NOSHI_OK);
    CHECK_EQ_INT(noshi_wr_bytes(&rpc, packed.data, packed.len), NOSHI_OK);
    CHECK_EQ_INT(receive(&f, rpc.data, rpc.len, f.server_id, 1, 0), NOSHI_OK);
    CHECK_EQ_INT(f.results, 1);
    CHECK_EQ_INT(f.result_status, NOSHI_E_RPC);
    CHECK_EQ_INT(f.error_code, 303);
    CHECK(strcmp(f.error_text, "PHONE_MIGRATE_4") == 0);
    noshi_writer_free(&rpc);
    noshi_writer_free(&error);
    noshi_writer_free(&packed);
    noshi_arena_free(&a);
    fixture_free(&f);
}

static void container_begin(noshi_writer *w, uint32_t count) {
    noshi_writer_init(w, 1 << 20);
    CHECK_EQ_INT(noshi_wr_u32le(w, CONTAINER_ID), NOSHI_OK);
    CHECK_EQ_INT(noshi_wr_u32le(w, count), NOSHI_OK);
}

static void container_item(noshi_writer *w, uint64_t id, int32_t seq, const uint8_t *body, size_t len) {
    CHECK_EQ_INT(noshi_wr_u64le(w, id), NOSHI_OK);
    CHECK_EQ_INT(noshi_wr_u32le(w, (uint32_t)seq), NOSHI_OK);
    CHECK_EQ_INT(noshi_wr_u32le(w, (uint32_t)len), NOSHI_OK);
    CHECK_EQ_INT(noshi_wr_bytes(w, body, len), NOSHI_OK);
}

static void test_container(void) {
    client_fixture f;
    noshi_writer w;
    uint8_t body[4];
    uint64_t outer;
    unsigned i;
    fixture_init(&f, 0);
    noshi_put_u32le(body, NOSHI_TL_ID_updatesTooLong);
    container_begin(&w, 1024);
    for (i = 0; i < 1024; ++i) container_item(&w, f.server_id + i * 4u, 1, body, sizeof(body));
    outer = f.server_id + 1024u * 4u;
    CHECK_EQ_INT(receive(&f, w.data, w.len, outer, 0, 0), NOSHI_OK);
    CHECK_EQ_INT(f.updates, 1024);
    drain_acks(&f, 1024);
    CHECK_EQ_INT(receive(&f, w.data, w.len, outer, 0, 0), NOSHI_OK);
    CHECK_EQ_INT(f.updates, 1024);
    CHECK_EQ_INT(receive(&f, body, sizeof(body), f.server_id, 1, 0), NOSHI_OK);
    CHECK_EQ_INT(f.updates, 1024);
    noshi_writer_free(&w);
    fixture_free(&f);
}

static void test_bad_container(void) {
    unsigned mode;
    for (mode = 0; mode < 9; ++mode) {
        client_fixture f;
        noshi_writer w;
        uint8_t body[8];
        uint64_t outer;
        fixture_init(&f, 0);
        outer = f.server_id + 20;
        noshi_put_u32le(body, NOSHI_TL_ID_updatesTooLong);
        noshi_put_u32le(body + 4, 0);
        container_begin(&w, mode == 0 ? 1025 : 1);
        container_item(&w, f.server_id, 1, body, 4);
        if (mode == 1) CHECK_EQ_INT(noshi_wr_u32le(&w, 0), NOSHI_OK);
        if (mode == 2) noshi_put_u64le(w.data + 8, outer);
        if (mode == 3) noshi_put_u64le(w.data + 8, f.server_id & ~3ull);
        if (mode == 4) noshi_put_u32le(w.data + 16, UINT32_MAX);
        if (mode == 5) noshi_put_u32le(w.data + 20, 8);
        if (mode == 6) noshi_put_u32le(w.data + 24, CONTAINER_ID);
        if (mode == 7) {
            noshi_put_u32le(w.data + 4, 2);
            container_item(&w, outer, 1, body, 4);
        }
        CHECK_EQ_INT(receive(&f, w.data, w.len, outer, mode == 8 ? 1 : 0, 0), NOSHI_E_MALFORMED);
        CHECK_EQ_INT(f.client.state, NOSHI_MT_CLIENT_DEAD);
        CHECK_EQ_INT(f.updates, 0);
        noshi_writer_free(&w);
        fixture_free(&f);
    }
}

static void test_gzip_limits(void) {
    unsigned mode;
    for (mode = 0; mode < 5; ++mode) {
        client_fixture f;
        noshi_writer packed, twice;
        uint8_t body[8192];
        fixture_init(&f, mode == 3 ? 64 : 0);
        memset(body, 0, sizeof(body));
        noshi_put_u32le(body, NOSHI_TL_ID_updatesTooLong);
        noshi_writer_init(&packed, 1 << 20);
        noshi_writer_init(&twice, 1 << 20);
        gzip_body(body, mode == 3 ? sizeof(body) : 4, mode == 1, &packed);
        if (mode == 2) {
            gzip_body(packed.data, packed.len, 0, &twice);
            CHECK_EQ_INT(receive(&f, twice.data, twice.len, f.server_id, 0, 0), NOSHI_E_MALFORMED);
        } else {
            if (mode == 4) packed.data[packed.len - 5] ^= 0xff;
            CHECK_EQ_INT(receive(&f, packed.data, packed.len, f.server_id, 0, 0),
                         mode == 0 ? NOSHI_OK : mode == 3 ? NOSHI_E_LIMIT : NOSHI_E_MALFORMED);
        }
        CHECK_EQ_INT(f.updates, mode == 0 ? 1 : 0);
        noshi_writer_free(&packed);
        noshi_writer_free(&twice);
        fixture_free(&f);
    }
}

/* the server sends large updates gzipped as content messages, which carry an odd seq_no and need an ack */
static void test_gzip_content_message(void) {
    client_fixture f;
    noshi_writer packed;
    uint8_t body[4];
    fixture_init(&f, 0);
    noshi_put_u32le(body, NOSHI_TL_ID_updatesTooLong);
    noshi_writer_init(&packed, 1 << 20);
    gzip_body(body, sizeof(body), 0, &packed);
    CHECK_EQ_INT(receive(&f, packed.data, packed.len, f.server_id, 1, 0), NOSHI_OK);
    CHECK_EQ_INT(f.updates, 1);
    CHECK(f.client.state != NOSHI_MT_CLIENT_DEAD);
    drain_acks(&f, 1);
    noshi_writer_free(&packed);
    fixture_free(&f);
}

static void test_replay_window(void) {
    client_fixture f;
    uint8_t body[4];
    unsigned i;
    fixture_init(&f, 0);
    noshi_put_u32le(body, NOSHI_TL_ID_updatesTooLong);
    for (i = 0; i < NOSHI_MT_SEEN_MAX + 2; ++i) {
        CHECK_EQ_INT(receive(&f, body, sizeof(body), f.server_id + 4u * i, 0, 0), NOSHI_OK);
    }
    CHECK_EQ_INT(f.updates, NOSHI_MT_SEEN_MAX + 2);
    CHECK_EQ_INT(receive(&f, body, sizeof(body), f.server_id, 0, 0), NOSHI_OK);
    CHECK_EQ_INT(f.updates, NOSHI_MT_SEEN_MAX + 2);
    fixture_free(&f);
}

static void test_timeout_cancel(void) {
    client_fixture f;
    fixture_init(&f, 0);
    (void)submit(&f, 43, 0, 100);
    f.now += 99;
    CHECK_EQ_INT(noshi_mt_client_tick(&f.client), 1);
    CHECK_EQ_INT(f.results, 0);
    f.now++;
    (void)noshi_mt_client_tick(&f.client);
    CHECK_EQ_INT(f.result_status, NOSHI_E_TIMEOUT);
    CHECK_EQ_INT(f.results, 1);
    (void)submit(&f, 44, 0, 100);
    CHECK_EQ_INT(noshi_mt_client_cancel(&f.client, 44), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_cancel(&f.client, 44), NOSHI_E_NOTFOUND);
    f.now += 100;
    (void)noshi_mt_client_tick(&f.client);
    CHECK_EQ_INT(f.results, 1);
    fixture_free(&f);
}

/* the ping a quiet link sends names a disconnect delay of the interval plus 45 seconds, so a longer background interval does not get the link dropped */
static int32_t next_ping_delay(client_fixture *f) {
    noshi_mt_frame frame;
    noshi_mt_header h;
    noshi_writer plain;
    const uint8_t *body;
    size_t len;
    noshi_arena a;
    noshi_tl_value *v;
    int32_t delay = -1;
    if (noshi_mt_transport_next(&f->server, &frame) != NOSHI_OK) return -1;
    noshi_writer_init(&plain, 1 << 20);
    noshi_arena_init(&a, 1 << 20);
    CHECK_EQ_INT(noshi_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(&a, NULL, NOSHI_TL_REF_ANY, body, len, &v), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(v), NOSHI_TL_ID_ping_delay_disconnect);
    CHECK_EQ_INT(noshi_tl_get_i32(v, "disconnect_delay", &delay), NOSHI_OK);
    noshi_arena_free(&a);
    noshi_writer_free(&plain);
    return delay;
}

static void test_ping_interval(void) {
    client_fixture f;
    noshi_mt_frame frame;
    uint32_t wait;
    fixture_init(&f, 0);
    CHECK_EQ_INT(noshi_mt_client_ping_interval(&f.client), 30000);
    noshi_mt_client_set_ping_interval(&f.client, 5);
    CHECK_EQ_INT(noshi_mt_client_ping_interval(&f.client), 10000);
    noshi_mt_client_set_ping_interval(&f.client, 4000000);
    CHECK_EQ_INT(noshi_mt_client_ping_interval(&f.client), 300000);
    noshi_mt_client_set_ping_interval(&f.client, 60000);
    wait = noshi_mt_client_tick(&f.client);
    CHECK(wait > 30000 && wait <= 60000);
    CHECK_EQ_INT(noshi_mt_transport_next(&f.server, &frame), NOSHI_E_TRUNCATED);
    f.now += wait;
    (void)noshi_mt_client_tick(&f.client);
    CHECK_EQ_INT(next_ping_delay(&f), 60 + 45);
    noshi_mt_client_set_ping_interval(&f.client, 30000);
    fixture_free(&f);
    noshi_mt_client_set_ping_interval(NULL, 60000);
    CHECK_EQ_INT(noshi_mt_client_ping_interval(NULL), 0);
}

static void test_state_request(void) {
    const unsigned counts[] = { 0, 257, 8192, 8193 };
    unsigned k;
    for (k = 0; k < sizeof(counts) / sizeof(counts[0]); ++k) {
        client_fixture f;
        noshi_arena a;
        noshi_writer w, plain;
        noshi_tl_value *req, *reply;
        noshi_mt_frame frame;
        noshi_mt_header h;
        int64_t ids[8193];
        const uint8_t *body, *info;
        size_t len, info_len;
        unsigned i;
        fixture_init(&f, 0);
        noshi_arena_init(&a, 1 << 20);
        noshi_writer_init(&w, 1 << 20);
        noshi_writer_init(&plain, 1 << 20);
        req = noshi_tl_new_obj(&a, "msgs_state_req");
        for (i = 0; i < counts[k]; ++i) ids[i] = (int64_t)(f.server_id + i * 4u);
        CHECK_EQ_INT(noshi_tl_set_i64_vec(&a, req, "msg_ids", ids, counts[k]), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_encode(req, &w, NULL), NOSHI_OK);
        CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + 40000, 0, 0),
                     counts[k] > 8192 ? NOSHI_E_LIMIT : NOSHI_OK);
        if (counts[k] <= 8192) {
            CHECK_EQ_INT(noshi_mt_transport_next(&f.server, &frame), NOSHI_OK);
            CHECK_EQ_INT(noshi_mt_decrypt(&f.client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_decode_all(&a, NULL, NOSHI_TL_REF_ANY, body, len, &reply), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_id(reply), NOSHI_TL_ID_msgs_state_info);
            CHECK_EQ_INT(noshi_tl_get_bytes(reply, "info", &info, &info_len), NOSHI_OK);
            CHECK_EQ_INT(info_len, counts[k]);
            for (i = 0; i < info_len; ++i) CHECK_EQ_INT(info[i], 1);
        }
        noshi_writer_free(&w);
        noshi_writer_free(&plain);
        noshi_arena_free(&a);
        fixture_free(&f);
    }
}

static void test_receive_errors(void) {
    unsigned mode;
    for (mode = 0; mode < 5; ++mode) {
        client_fixture f;
        uint8_t body[12];
        fixture_init(&f, 0);
        memset(body, 0, sizeof(body));
        noshi_put_u32le(body, mode == 0 ? NOSHI_TL_ID_rpc_result :
                              mode == 1 ? NOSHI_TL_ID_pong :
                              mode == 2 ? 0xdeadbeefu : NOSHI_TL_ID_updatesTooLong);
        CHECK_EQ_INT(receive(&f, body, mode == 0 ? 12 : 4,
                            mode == 3 ? f.server_id & ~3ull : f.server_id,
                            mode == 4 ? -1 : 0, 0), mode == 2 ? NOSHI_OK : NOSHI_E_MALFORMED);
        CHECK_EQ_INT(f.lost, mode == 2 ? 1 : 0);
        CHECK_EQ_INT(f.updates, 0);
        CHECK_EQ_INT(f.state_reason, mode == 2 ? NOSHI_OK : NOSHI_E_MALFORMED);
        fixture_free(&f);
    }
}

static void test_unpack_limits(void) {
    uint8_t body[4096];
    unsigned mode;
    for (mode = 0; mode < 4; ++mode) {
        noshi_writer packed, plain;
        memset(body, 0x42, sizeof(body));
        noshi_writer_init(&packed, 16384);
        noshi_writer_init(&plain, mode == 1 ? sizeof(body) + 3 : sizeof(body) + 4);
        CHECK_EQ_INT(noshi_wr_u32le(&plain, 0x12345678), NOSHI_OK);
        gzip_body(body, sizeof(body), mode == 2, &packed);
        if (mode == 3) CHECK_EQ_INT(noshi_wr_u32le(&packed, 0), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_unpack_gzip(packed.data, packed.len, &plain), mode == 0 ? NOSHI_OK : mode == 1 ? NOSHI_E_LIMIT : NOSHI_E_MALFORMED);
        CHECK_EQ_INT(plain.len, mode == 0 ? sizeof(body) + 4 : 4);
        CHECK_EQ_INT(noshi_get_u32le(plain.data), 0x12345678);
        if (mode == 0) CHECK_MEM(plain.data + 4, body, sizeof(body));
        noshi_writer_free(&packed);
        noshi_writer_free(&plain);
    }
}

static uint64_t outgoing_id(client_fixture *f, uint64_t *session_id) {
    noshi_mt_frame frame;
    noshi_mt_header h;
    noshi_writer plain;
    const uint8_t *body;
    size_t len;
    CHECK_EQ_INT(noshi_mt_transport_next(&f->server, &frame), NOSHI_OK);
    noshi_writer_init(&plain, 1u << 20);
    CHECK_EQ_INT(noshi_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), NOSHI_OK);
    if (session_id) *session_id = h.session_id;
    noshi_writer_free(&plain);
    return h.msg_id;
}

static void test_reconnect_services(void) {
    client_fixture f;
    noshi_arena a;
    noshi_tl_value *v;
    noshi_writer w;
    uint64_t id, new_id, session_id, old_session;
    unsigned i;
    fixture_init(&f, 1u << 20);
    noshi_arena_init(&a, 1u << 20);
    noshi_writer_init(&w, 1u << 20);
    id = submit(&f, 80, 0, 0);
    v = noshi_tl_new_obj(&a, "msg_resend_req");
    { int64_t requested = (int64_t)id; CHECK_EQ_INT(noshi_tl_set_i64_vec(&a, v, "msg_ids", &requested, 1), NOSHI_OK); }
    CHECK_EQ_INT(noshi_tl_encode(v, &w, NULL), NOSHI_OK);
    for (i = 0; i < 7; ++i) {
        CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + i * 4u, 0, 0), NOSHI_OK);
        CHECK_EQ_INT(outgoing_id(&f, NULL), id);
    }
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + i * 4u, 0, 0), NOSHI_OK);
    CHECK_EQ_INT(f.result_status, NOSHI_E_LIMIT);
    CHECK_EQ_INT(f.client.pending_count, 0);
    id = submit(&f, 81, 0, 10000);
    old_session = f.client.session_id;
    w.len = 0;
    v = noshi_tl_new_obj(&a, "bad_msg_notification");
    CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "bad_msg_id", (int64_t)id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "bad_msg_seqno", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "error_code", 17), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_encode(v, &w, NULL), NOSHI_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id - (3600ull << 32), 0, 0), NOSHI_OK);
    new_id = outgoing_id(&f, &session_id);
    CHECK(session_id != old_session);
    CHECK(new_id < id);
    CHECK_EQ_INT(new_id >> 32, (id >> 32) - 3600u);
    w.len = 0;
    v = noshi_tl_new_obj(&a, "bad_server_salt");
    CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "bad_msg_id", (int64_t)new_id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "bad_msg_seqno", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "error_code", 48), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "new_server_salt", 987654321), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_encode(v, &w, NULL), NOSHI_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id - (3600ull << 32) + 4, 0, 0), NOSHI_OK);
    CHECK_EQ_INT(outgoing_id(&f, NULL), new_id);
    CHECK_EQ_INT(f.client.salt, 987654321);
    noshi_mt_client_disconnected(&f.client);
    noshi_mt_transport_free(&f.server);
    noshi_mt_transport_init(&f.server);
    CHECK_EQ_INT(noshi_mt_transport_start_server(&f.server, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_connect(&f.client), NOSHI_OK);
    (void)outgoing_id(&f, &session_id);
    CHECK(session_id != old_session);
    noshi_writer_free(&w);
    noshi_arena_free(&a);
    fixture_free(&f);
}

/* a frame the client refuses says which check it failed, so a link that connects and fails at once can be told from the log */
static void test_refusals(void) {
    unsigned mode;
    static const char *const expected[] = {"auth key id", "session id", "message time", "message time", "server salt", "message key"};
    for (mode = 0; mode < 6; ++mode) {
        client_fixture f;
        noshi_mt_auth_key other;
        uint8_t other_bytes[NOSHI_MT_AUTH_KEY_LEN], body[4];
        const noshi_mt_auth_key *key = &f.client.key;
        uint64_t salt, session_id, msg_id;
        int64_t value = 7;
        const char *note;
        unsigned i;
        fixture_init(&f, 0);
        salt = f.client.salt;
        session_id = f.client.session_id;
        msg_id = f.server_id;
        for (i = 0; i < sizeof(other_bytes); ++i) other_bytes[i] = (uint8_t)(i * 3u + 1u);
        CHECK_EQ_INT(noshi_mt_auth_key_set(&other, other_bytes), NOSHI_OK);
        noshi_put_u32le(body, NOSHI_TL_ID_updatesTooLong);
        CHECK(noshi_mt_client_security_note(&f.client, &value) == NULL);
        CHECK_EQ_INT(value, 0);
        if (mode == 0) key = &other;
        if (mode == 1) session_id ^= 1;
        if (mode == 2) msg_id += 3600ull << 32;
        if (mode == 3) msg_id -= 3600ull << 32;
        if (mode == 4) salt ^= 0x55;
        CHECK_EQ_INT(receive_as(&f, key, salt, session_id, body, sizeof(body), msg_id, 1, 0, mode == 5), NOSHI_E_SECURITY);
        note = noshi_mt_client_security_note(&f.client, &value);
        CHECK(note != NULL && strcmp(note, expected[mode]) == 0);
        /* the gap to the server's clock is kept in milliseconds with its sign; a wrong key or session carries none */
        if (mode == 2) CHECK(value > 3500000 && value < 3700000);
        if (mode == 3) CHECK(value < -3500000 && value > -3700000);
        if (mode == 0 || mode == 1 || mode == 5) CHECK_EQ_INT(value, 0);
        CHECK_EQ_INT(noshi_mt_client_heard(&f.client), 0);
        fixture_free(&f);
    }
}

/* after a pause the stored salt is stale, and the server answers in one container whose salt is the new one, as
   the real one does */
static void test_container_with_new_salt(void) {
    unsigned mode;
    for (mode = 0; mode < 3; ++mode) {
        client_fixture f;
        noshi_arena a;
        noshi_tl_value *v;
        noshi_writer item, w;
        uint8_t other[4];
        int64_t value = 0;
        noshi_status s;
        fixture_init(&f, 0);
        noshi_arena_init(&a, 16384);
        noshi_writer_init(&item, 16384);
        noshi_put_u32le(other, NOSHI_TL_ID_updatesTooLong);
        if (mode == 0) {
            v = noshi_tl_new_obj(&a, "new_session_created");
            CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "first_msg_id", 1), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "unique_id", 2), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "server_salt", 987654321), NOSHI_OK);
        } else {
            v = noshi_tl_new_obj(&a, "bad_server_salt");
            CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "bad_msg_id", 1), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "bad_msg_seqno", 1), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "error_code", 48), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "new_server_salt", 987654321), NOSHI_OK);
        }
        CHECK_EQ_INT(noshi_tl_encode(v, &item, NULL), NOSHI_OK);
        container_begin(&w, 2);
        container_item(&w, f.server_id, 1, other, sizeof(other));
        if (mode == 2) container_item(&w, f.server_id + 4, 1, other, sizeof(other));
        else container_item(&w, f.server_id + 4, 0, item.data, item.len);
        s = receive_as(&f, &f.client.key, f.client.salt ^ 0x55, f.client.session_id, w.data, w.len, f.server_id + 8, 0, 0, 0);
        if (mode == 2) {
            CHECK_EQ_INT(s, NOSHI_E_SECURITY);
            CHECK(noshi_mt_client_security_note(&f.client, &value) != NULL);
            CHECK_EQ_INT(noshi_mt_client_heard(&f.client), 0);
        } else {
            CHECK_EQ_INT(s, NOSHI_OK);
            CHECK_EQ_INT(noshi_mt_client_heard(&f.client), 1);
        }
        noshi_writer_free(&w);
        noshi_writer_free(&item);
        noshi_arena_free(&a);
        fixture_free(&f);
    }
}

/* a link counts as heard once a frame was accepted, and the count starts again with the next connection */
static void test_heard(void) {
    client_fixture f;
    uint8_t body[4];
    fixture_init(&f, 0);
    noshi_put_u32le(body, NOSHI_TL_ID_updatesTooLong);
    CHECK_EQ_INT(noshi_mt_client_heard(&f.client), 0);
    CHECK_EQ_INT(receive(&f, body, sizeof(body), f.server_id, 1, 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_heard(&f.client), 1);
    CHECK_EQ_INT(noshi_mt_client_heard(NULL), 0);
    CHECK(noshi_mt_client_security_note(NULL, NULL) == NULL);
    noshi_mt_client_disconnected(&f.client);
    noshi_mt_transport_free(&f.server);
    noshi_mt_transport_init(&f.server);
    CHECK_EQ_INT(noshi_mt_transport_start_server(&f.server, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_connect(&f.client), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_heard(&f.client), 0);
    fixture_free(&f);
}

/* the server's clock differs from the one the client has, as when the phone's clock moved after the offset was
   stored */
static void test_clock_correction(void) {
    client_fixture f;
    noshi_arena a;
    noshi_writer w;
    noshi_tl_value *v;
    uint64_t first, container, session_id;
    int64_t offset;
    fixture_init(&f, 1u << 20);
    noshi_arena_init(&a, 1u << 20);
    noshi_writer_init(&w, 1u << 20);
    first = submit(&f, 95, 0, 0);
    (void)submit(&f, 96, 0, 0);

    /* an hour of difference, named for a message that waits for its answer */
    v = noshi_tl_new_obj(&a, "bad_msg_notification");
    CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "bad_msg_id", (int64_t)first), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "bad_msg_seqno", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "error_code", 16), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_encode(v, &w, NULL), NOSHI_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + (3600ull << 32), 0, 0), NOSHI_OK);
    offset = f.client.time_offset_ms;
    CHECK(offset > 3599000 && offset < 3601000);

    /* both requests go out again in one container, and that is the id the server then complains about */
    container = outgoing_id(&f, &session_id);
    CHECK(container != first);
    w.len = 0;
    v = noshi_tl_new_obj(&a, "bad_msg_notification");
    CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "bad_msg_id", (int64_t)container), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "bad_msg_seqno", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "error_code", 16), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_encode(v, &w, NULL), NOSHI_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + (7200ull << 32), 0, 0), NOSHI_OK);
    CHECK(f.client.time_offset_ms > 7199000 && f.client.time_offset_ms < 7201000);

    /* the same complaint about an id that was never sent is refused */
    w.len = 0;
    v = noshi_tl_new_obj(&a, "bad_msg_notification");
    CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "bad_msg_id", (int64_t)(first + 8)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "bad_msg_seqno", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "error_code", 16), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_encode(v, &w, NULL), NOSHI_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + (14400ull << 32), 0, 0), NOSHI_E_SECURITY);
    CHECK(noshi_mt_client_security_note(&f.client, NULL) != NULL);
    noshi_writer_free(&w);
    noshi_arena_free(&a);
    fixture_free(&f);
}

static noshi_status failed_send(void *ctx, const uint8_t *data, size_t len) {
    (void)ctx; (void)data; (void)len;
    return NOSHI_E_IO;
}

static void test_teardown_and_send_error(void) {
    client_fixture f;
    noshi_arena a;
    noshi_tl_value *request;
    uint8_t rpc[16];
    uint64_t id;
    fixture_init(&f, 1u << 20);
    id = submit(&f, 90, 0, 10000);
    f.free_on_result = 1;
    noshi_put_u32le(rpc, NOSHI_TL_ID_rpc_result);
    noshi_put_u64le(rpc + 4, id);
    noshi_put_u32le(rpc + 12, NOSHI_TL_ID_boolTrue);
    CHECK_EQ_INT(receive(&f, rpc, sizeof(rpc), f.server_id, 1, 0), NOSHI_E_STATE);
    CHECK_EQ_INT(f.results, 1);
    CHECK_EQ_INT(f.client.pending_count, 0);
    fixture_free(&f);
    fixture_init(&f, 1u << 20);
    f.client.events.send_checked = failed_send;
    noshi_arena_init(&a, 65536);
    request = noshi_tl_new_obj(&a, "account.updateStatus");
    CHECK_EQ_INT(noshi_tl_set(request, "offline", noshi_tl_new_obj(&a, "boolFalse")), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_submit(&f.client, 92, request, 1000), NOSHI_E_IO);
    CHECK_EQ_INT(f.client.state, NOSHI_MT_CLIENT_DEAD);
    CHECK_EQ_INT(f.state_reason, NOSHI_E_IO);
    CHECK_EQ_INT(noshi_mt_client_submit(&f.client, 93, request, 1000), NOSHI_E_STATE);
    noshi_arena_free(&a);
    fixture_free(&f);
    fixture_init(&f, 1u << 20);
    { uint8_t body[4]; noshi_put_u32le(body, NOSHI_TL_ID_updatesTooLong);
      CHECK_EQ_INT(receive(&f, body, 4, f.server_id - (301ull << 32), 0, 0), NOSHI_E_SECURITY); }
    fixture_free(&f);
}

/* the metadata of the next request: the strings of its initConnection, or empty when the request goes out bare */
static void next_metadata(client_fixture *f, char *model, char *system, char *app, size_t cap, int *wrapped) {
    noshi_arena a;
    noshi_tl_value *request, *init;
    noshi_mt_frame frame;
    noshi_mt_header h;
    noshi_writer plain;
    const uint8_t *body, *text;
    size_t len, n;
    static uint64_t next_id = 1000;
    model[0] = system[0] = app[0] = 0;
    noshi_arena_init(&a, 16384);
    request = noshi_tl_new_obj(&a, "account.updateStatus");
    CHECK(request != NULL);
    CHECK_EQ_INT(noshi_tl_set(request, "offline", noshi_tl_new_obj(&a, "boolFalse")), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_client_submit(&f->client, next_id++, request, 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_mt_transport_next(&f->server, &frame), NOSHI_OK);
    noshi_writer_init(&plain, 1 << 20);
    CHECK_EQ_INT(noshi_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), NOSHI_OK);
    *wrapped = noshi_get_u32le(body) == NOSHI_TL_ID_invokeWithLayer;
    if (*wrapped) {
        noshi_tl_value *whole = NULL;
        CHECK_EQ_INT(noshi_tl_decode_all(&a, NULL, NOSHI_TL_REF_ANY, body, len, &whole), NOSHI_OK);
        init = (noshi_tl_value *)noshi_tl_get(whole, "query");
        CHECK(noshi_tl_is(init, NOSHI_TL_ID_initConnection));
        CHECK_EQ_INT(noshi_tl_get_bytes(init, "device_model", &text, &n), NOSHI_OK);
        snprintf(model, cap, "%.*s", (int)n, (const char *)text);
        CHECK_EQ_INT(noshi_tl_get_bytes(init, "system_version", &text, &n), NOSHI_OK);
        snprintf(system, cap, "%.*s", (int)n, (const char *)text);
        CHECK_EQ_INT(noshi_tl_get_bytes(init, "app_version", &text, &n), NOSHI_OK);
        snprintf(app, cap, "%.*s", (int)n, (const char *)text);
    }
    noshi_writer_free(&plain);
    noshi_arena_free(&a);
}

static void test_set_device(void) {
    client_fixture f;
    char model[160], system[160], app[160], long_text[NOSHI_MT_DEVICE_TEXT_MAX + 2];
    int wrapped = 0;
    fixture_api_id = 777;
    fixture_init(&f, 0);
    next_metadata(&f, model, system, app, sizeof(model), &wrapped);
    CHECK(wrapped);
    CHECK(!strcmp(model, "iPhone4,1") && !strcmp(system, "iPhone OS 6.1") && !strcmp(app, "1.0"));
    /* once the server has taken the metadata the requests go out bare */
    f.client.init_confirmed = 1;
    next_metadata(&f, model, system, app, sizeof(model), &wrapped);
    CHECK(!wrapped);
    /* another device brings the metadata back, with the new strings, on the next request */
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, "samsungSM-S928B", "SDK 34", "12.1.1"), NOSHI_OK);
    CHECK_EQ_INT(f.client.init_confirmed, 0);
    next_metadata(&f, model, system, app, sizeof(model), &wrapped);
    CHECK(wrapped);
    CHECK(!strcmp(model, "samsungSM-S928B") && !strcmp(system, "SDK 34") && !strcmp(app, "12.1.1"));
    /* an empty app version is allowed, an empty model or system version, a missing string and a text that is too long are refused and change nothing */
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, "Pixel 8", "SDK 35", ""), NOSHI_OK);
    memset(long_text, 'x', sizeof(long_text) - 1);
    long_text[sizeof(long_text) - 1] = 0;
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, "", "SDK 34", "1"), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, "Pixel", "", "1"), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, NULL, "SDK 34", "1"), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, "Pixel", "SDK 34", NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, long_text, "SDK 34", "1"), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, "Pixel", "SDK 34", long_text), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_mt_client_set_device(NULL, "Pixel", "SDK 34", "1"), NOSHI_E_ARG);
    next_metadata(&f, model, system, app, sizeof(model), &wrapped);
    CHECK(wrapped);
    CHECK(!strcmp(model, "Pixel 8") && !strcmp(system, "SDK 35") && !strcmp(app, ""));
    fixture_free(&f);
    fixture_api_id = 0;
    /* a client without an api_id sends no metadata, and keeps sending none */
    fixture_init(&f, 0);
    CHECK_EQ_INT(noshi_mt_client_set_device(&f.client, "Pixel 8", "SDK 35", "1"), NOSHI_OK);
    next_metadata(&f, model, system, app, sizeof(model), &wrapped);
    CHECK(!wrapped);
    fixture_free(&f);
}

int main(void) {
    test_set_device();
    test_reconnect_services();
    test_teardown_and_send_error();
    test_rpc_gzip();
    test_rpc_error();
    test_container();
    test_bad_container();
    test_refusals();
    test_container_with_new_salt();
    test_heard();
    test_clock_correction();
    test_gzip_limits();
    test_gzip_content_message();
    test_replay_window();
    test_timeout_cancel();
    test_ping_interval();
    test_state_request();
    test_receive_errors();
    test_unpack_limits();
    return test_finish("test_mt_client");
}
