#include "test_util.h"
#include "noshi_call.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

#define MODP14 "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF"

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set_i32(noshi_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, f, x), NOSHI_OK); }
static void set_i64(noshi_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, f, x), NOSHI_OK); }
static void set_str(noshi_tl_value *v, const char *f, const char *x) { CHECK_EQ_INT(noshi_tl_set_str(&arena, v, f, x), NOSHI_OK); }
static void set_bytes(noshi_tl_value *v, const char *f, const void *x, size_t n) { CHECK_EQ_INT(noshi_tl_set_bytes(&arena, v, f, x, n), NOSHI_OK); }
static void set_flag(noshi_tl_value *v, const char *f) { CHECK_EQ_INT(noshi_tl_set_flag(v, f), NOSHI_OK); }
static void set(noshi_tl_value *v, const char *f, noshi_tl_value *x) { CHECK_EQ_INT(noshi_tl_set(v, f, x), NOSHI_OK); }

static noshi_tl_value *vec_of(noshi_tl_value **items, uint32_t n) {
    noshi_tl_value *v = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(v, i, items[i]), NOSHI_OK);
    return v;
}

static void unhex(const char *hex, uint8_t *out, size_t n) {
    size_t i;
    for (i = 0; i < n; ++i) {
        unsigned value;
        sscanf(hex + 2 * i, "%2x", &value);
        out[i] = (uint8_t)value;
    }
}

static noshi_call_dh modp14(void) {
    noshi_call_dh dh;
    memset(&dh, 0, sizeof(dh));
    unhex(MODP14, dh.p, NOSHI_CALL_KEY_LEN);
    dh.g = 2;
    dh.version = 7;
    return dh;
}

static void test_emoji_table(void) {
    size_t i;
    CHECK(!strcmp(noshi_call_emoji[0], "\xf0\x9f\x98\x89"));
    CHECK(!strcmp(noshi_call_emoji[NOSHI_CALL_EMOJI_COUNT - 1], "\xf0\x9f\x94\xb7"));
    for (i = 0; i < NOSHI_CALL_EMOJI_COUNT; ++i) CHECK(noshi_call_emoji[i] != NULL && noshi_call_emoji[i][0] != 0);
}

static void test_dh_config(void) {
    noshi_call_dh dh = modp14(), parsed;
    uint8_t random[NOSHI_CALL_KEY_LEN], server[NOSHI_CALL_KEY_LEN];
    noshi_tl_value *answer = obj("messages.dhConfig"), *request = NULL;
    memset(server, 0x5a, sizeof(server));
    set_i32(answer, "g", 2);
    set_bytes(answer, "p", dh.p, NOSHI_CALL_KEY_LEN);
    set_i32(answer, "version", 7);
    set_bytes(answer, "random", server, sizeof(server));
    CHECK_EQ_INT(noshi_call_dh_parse(answer, NULL, &parsed, random), NOSHI_OK);
    CHECK_EQ_INT(parsed.g, 2);
    CHECK_EQ_INT(parsed.version, 7);
    CHECK(!memcmp(parsed.p, dh.p, NOSHI_CALL_KEY_LEN));
    CHECK(!memcmp(random, server, sizeof(server)));
    /* a prime that is not a safe prime is refused */
    {
        uint8_t composite[NOSHI_CALL_KEY_LEN];
        memcpy(composite, dh.p, sizeof(composite));
        composite[NOSHI_CALL_KEY_LEN - 1] ^= 2;
        set_bytes(answer, "p", composite, sizeof(composite));
        CHECK_EQ_INT(noshi_call_dh_parse(answer, NULL, &parsed, random), NOSHI_E_SECURITY);
        CHECK_EQ_INT(parsed.version, 0);
        set_bytes(answer, "p", dh.p, 255);
        CHECK_EQ_INT(noshi_call_dh_parse(answer, NULL, &parsed, random), NOSHI_E_SECURITY);
        set_bytes(answer, "p", dh.p, NOSHI_CALL_KEY_LEN);
    }
    set_i32(answer, "g", 9);
    CHECK_EQ_INT(noshi_call_dh_parse(answer, NULL, &parsed, random), NOSHI_E_SECURITY);
    /* not modified: only valid against the config the app holds */
    {
        noshi_tl_value *same = obj("messages.dhConfigNotModified");
        set_bytes(same, "random", server, sizeof(server));
        CHECK_EQ_INT(noshi_call_dh_parse(same, NULL, &parsed, random), NOSHI_E_STATE);
        CHECK_EQ_INT(noshi_call_dh_parse(same, &dh, &parsed, random), NOSHI_OK);
        CHECK_EQ_INT(parsed.version, 7);
        CHECK(!memcmp(random, server, sizeof(server)));
    }
    CHECK_EQ_INT(noshi_call_dh_parse(obj("boolTrue"), &dh, &parsed, random), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_call_dh_request(&arena, 7, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_getDhConfig);
    CHECK_EQ_INT(noshi_call_dh_request(&arena, -1, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
}

static void test_key_exchange(void) {
    noshi_call_dh dh = modp14();
    uint8_t seed_a[NOSHI_CALL_KEY_LEN], seed_b[NOSHI_CALL_KEY_LEN], server[NOSHI_CALL_KEY_LEN];
    uint8_t a[NOSHI_CALL_KEY_LEN], g_a[NOSHI_CALL_KEY_LEN], b[NOSHI_CALL_KEY_LEN], g_b[NOSHI_CALL_KEY_LEN];
    uint8_t key_a[NOSHI_CALL_KEY_LEN], key_b[NOSHI_CALL_KEY_LEN], hash[32], again[32];
    int64_t fp_a, fp_b;
    uint16_t emoji_a[4], emoji_b[4];
    size_t i;
    for (i = 0; i < sizeof(seed_a); ++i) {
        seed_a[i] = (uint8_t)(i * 7 + 3);
        seed_b[i] = (uint8_t)(i * 13 + 11);
        server[i] = (uint8_t)(255 - i);
    }
    CHECK_EQ_INT(noshi_call_make_secret_from(&dh, seed_a, server, a, g_a), NOSHI_OK);
    CHECK_EQ_INT(noshi_call_make_secret_from(&dh, seed_b, server, b, g_b), NOSHI_OK);
    CHECK(memcmp(g_a, g_b, sizeof(g_a)) != 0);
    CHECK_EQ_INT(a[0], seed_a[0] ^ server[0]);
    /* the two sides reach one key from each other's public value */
    CHECK_EQ_INT(noshi_call_make_key(&dh, g_b, a, key_a, &fp_a), NOSHI_OK);
    CHECK_EQ_INT(noshi_call_make_key(&dh, g_a, b, key_b, &fp_b), NOSHI_OK);
    CHECK(!memcmp(key_a, key_b, sizeof(key_a)));
    CHECK_EQ_INT(fp_a, fp_b);
    CHECK(fp_a != 0);
    /* and the same four emoji, which change with the key */
    CHECK_EQ_INT(noshi_call_emoji_indexes(key_a, g_a, emoji_a), NOSHI_OK);
    CHECK_EQ_INT(noshi_call_emoji_indexes(key_b, g_a, emoji_b), NOSHI_OK);
    for (i = 0; i < 4; ++i) {
        CHECK_EQ_INT(emoji_a[i], emoji_b[i]);
        CHECK(emoji_a[i] < NOSHI_CALL_EMOJI_COUNT);
    }
    CHECK_EQ_INT(noshi_call_emoji_indexes(key_a, g_b, emoji_b), NOSHI_OK);
    CHECK(memcmp(emoji_a, emoji_b, sizeof(emoji_a)) != 0);
    /* the commitment is the hash of the public value and nothing else */
    CHECK_EQ_INT(noshi_call_commit(g_a, hash), NOSHI_OK);
    CHECK_EQ_INT(noshi_call_commit(g_a, again), NOSHI_OK);
    CHECK(!memcmp(hash, again, 32));
    CHECK_EQ_INT(noshi_call_commit(g_b, again), NOSHI_OK);
    CHECK(memcmp(hash, again, 32) != 0);
    /* values that are 0, 1 or p - 1 would give a key anyone can guess */
    {
        uint8_t bad[NOSHI_CALL_KEY_LEN];
        memset(bad, 0, sizeof(bad));
        CHECK_EQ_INT(noshi_call_make_key(&dh, bad, a, key_a, &fp_a), NOSHI_E_SECURITY);
        CHECK_EQ_INT(fp_a, 0);
        bad[NOSHI_CALL_KEY_LEN - 1] = 1;
        CHECK_EQ_INT(noshi_call_make_key(&dh, bad, a, key_a, &fp_a), NOSHI_E_SECURITY);
        memcpy(bad, dh.p, sizeof(bad));
        bad[NOSHI_CALL_KEY_LEN - 1] -= 1;
        CHECK_EQ_INT(noshi_call_make_key(&dh, bad, a, key_a, &fp_a), NOSHI_E_SECURITY);
        CHECK_EQ_INT(key_a[0], 0);
    }
    CHECK_EQ_INT(noshi_call_make_secret_from(&dh, seed_a, server, NULL, g_a), NOSHI_E_ARG);
}

static void test_requests(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref user = {1, 77, 5, 0, 0}, nohash = {1, 77, 0, 0, 0}, channel = {3, 77, 5, 0, 0};
    uint8_t hash[32], pub[NOSHI_CALL_KEY_LEN];
    memset(hash, 1, sizeof(hash));
    memset(pub, 2, sizeof(pub));
    CHECK_EQ_INT(noshi_call_request_request(&arena, &user, 99, hash, 0, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_phone_requestCall);
    {
        const noshi_tl_value *proto = noshi_tl_get(request, "protocol"), *versions;
        int32_t min = 0, max = 0;
        const uint8_t *text;
        size_t len;
        CHECK_EQ_INT(noshi_tl_has(proto, "udp_p2p"), 1);
        CHECK_EQ_INT(noshi_tl_has(proto, "udp_reflector"), 1);
        CHECK_EQ_INT(noshi_tl_get_i32(proto, "min_layer", &min), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_get_i32(proto, "max_layer", &max), NOSHI_OK);
        CHECK_EQ_INT(min, NOSHI_CALL_MIN_LAYER);
        CHECK_EQ_INT(max, NOSHI_CALL_MAX_LAYER);
        versions = noshi_tl_get(proto, "library_versions");
        /* tgcalls first, so that two phones that know it settle on it, then libtgvoip for a phone that does not */
        CHECK_EQ_INT(versions->u.vec.count, 2);
        CHECK_EQ_INT(noshi_tl_get_bytes(proto, "library_versions", &text, &len) == NOSHI_OK, 0);
        CHECK_EQ_INT(versions->u.vec.items[0]->u.bytes.len, strlen(NOSHI_CALL_TGCALLS_VERSION));
        CHECK(memcmp(versions->u.vec.items[0]->u.bytes.data, NOSHI_CALL_TGCALLS_VERSION, strlen(NOSHI_CALL_TGCALLS_VERSION)) == 0);
        CHECK_EQ_INT(versions->u.vec.items[1]->u.bytes.len, strlen(NOSHI_CALL_LIBRARY_VERSION));
        CHECK_EQ_INT(noshi_tl_has(request, "video"), 0);
    }
    /* a call through the VPN does not offer a direct path: none of the three messages carries udp_p2p, and the relays are still asked for */
    CHECK_EQ_INT(noshi_call_request_request(&arena, &user, 99, hash, 0, 0, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(noshi_tl_get(request, "protocol"), "udp_p2p"), 0);
    CHECK_EQ_INT(noshi_tl_has(noshi_tl_get(request, "protocol"), "udp_reflector"), 1);
    CHECK_EQ_INT(noshi_call_accept_request(&arena, 5, 6, pub, 0, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(noshi_tl_get(request, "protocol"), "udp_p2p"), 0);
    CHECK_EQ_INT(noshi_call_confirm_request(&arena, 5, 6, pub, -12345, 0, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(noshi_tl_get(request, "protocol"), "udp_p2p"), 0);
    CHECK_EQ_INT(noshi_call_accept_request(&arena, 5, 6, pub, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(noshi_tl_get(request, "protocol"), "udp_p2p"), 1);
    /* a video call carries the flag */
    CHECK_EQ_INT(noshi_call_request_request(&arena, &user, 99, hash, 1, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "video"), 1);
    /* the signaling of a call: the call, the bytes, and refusals for none, too many, or no call */
    {
        static uint8_t big[16385];
        const uint8_t *got;
        size_t got_len;
        CHECK_EQ_INT(noshi_call_signaling_request(&arena, 5, 6, (const uint8_t *)"sealed", 6, &request), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_phone_sendSignalingData);
        CHECK_EQ_INT(noshi_tl_get_bytes(request, "data", &got, &got_len), NOSHI_OK);
        CHECK(got_len == 6 && memcmp(got, "sealed", 6) == 0);
        CHECK_EQ_INT(noshi_tl_id(noshi_tl_get(request, "peer")), NOSHI_TL_ID_inputPhoneCall);
        CHECK_EQ_INT(noshi_call_signaling_request(&arena, 5, 6, big, 16384, &request), NOSHI_OK);
        CHECK_EQ_INT(noshi_call_signaling_request(&arena, 5, 6, big, 16385, &request), NOSHI_E_LIMIT);
        CHECK_EQ_INT(noshi_call_signaling_request(&arena, 5, 6, big, 0, &request), NOSHI_E_LIMIT);
        CHECK(request == NULL);
        CHECK_EQ_INT(noshi_call_signaling_request(&arena, 0, 6, big, 4, &request), NOSHI_E_ARG);
        CHECK_EQ_INT(noshi_call_signaling_request(&arena, 5, 6, NULL, 4, &request), NOSHI_E_ARG);
    }
    CHECK_EQ_INT(noshi_call_request_request(&arena, &nohash, 99, hash, 0, 1, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_call_request_request(&arena, &channel, 99, hash, 0, 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_call_accept_request(&arena, 5, 6, pub, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_phone_acceptCall);
    CHECK_EQ_INT(noshi_call_confirm_request(&arena, 5, 6, pub, -12345, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_phone_confirmCall);
    CHECK_EQ_INT(noshi_call_received_request(&arena, 5, 6, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_phone_receivedCall);
    CHECK_EQ_INT(noshi_call_discard_request(&arena, 5, 6, 61, NOSHI_CALL_REASON_HANGUP, 3, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_phone_discardCall);
    CHECK_EQ_INT(noshi_tl_id(noshi_tl_get(request, "reason")), NOSHI_TL_ID_phoneCallDiscardReasonHangup);
    CHECK_EQ_INT(noshi_call_discard_request(&arena, 5, 6, -1, NOSHI_CALL_REASON_HANGUP, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_call_discard_request(&arena, 5, 6, 0, NOSHI_CALL_REASON_NONE, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_call_accept_request(&arena, 0, 6, pub, 1, &request), NOSHI_E_ARG);
}

static noshi_tl_value *protocol_object(void) {
    noshi_tl_value *p = obj("phoneCallProtocol"), *versions[2];
    versions[0] = noshi_tl_new_str(&arena, "2.4.4");
    versions[1] = noshi_tl_new_str(&arena, "5.0.0");
    set_flag(p, "udp_p2p");
    set_i32(p, "min_layer", 65);
    set_i32(p, "max_layer", 92);
    set(p, "library_versions", vec_of(versions, 2));
    return p;
}

static noshi_tl_value *call_base(const char *ctor) {
    noshi_tl_value *c = obj(ctor);
    set_i64(c, "id", 4001);
    set_i64(c, "access_hash", 9001);
    set_i32(c, "date", 1700);
    set_i64(c, "admin_id", 10);
    set_i64(c, "participant_id", 20);
    set(c, "protocol", protocol_object());
    return c;
}

static void test_parse(void) {
    noshi_phone_call call;
    uint8_t g[NOSHI_CALL_KEY_LEN], tag[16];
    noshi_tl_value *c, *conn, *conns[5], *answer;
    memset(g, 7, sizeof(g));
    memset(tag, 9, sizeof(tag));

    c = call_base("phoneCallWaiting");
    set_i32(c, "receive_date", 1710);
    CHECK_EQ_INT(noshi_phone_call_parse(c, &call), NOSHI_OK);
    CHECK_EQ_INT(call.kind, NOSHI_CALL_WAITING);
    CHECK_EQ_INT(call.id, 4001);
    CHECK_EQ_INT(call.receive_date, 1710);
    CHECK_EQ_INT(call.admin_id, 10);
    CHECK_EQ_INT(call.participant_id, 20);
    CHECK_EQ_INT(call.max_layer, 92);
    CHECK(!strcmp(call.version, "2.4.4"));

    c = call_base("phoneCallRequested");
    set_bytes(c, "g_a_hash", g, 32);
    CHECK_EQ_INT(noshi_phone_call_parse(c, &call), NOSHI_OK);
    CHECK_EQ_INT(call.kind, NOSHI_CALL_REQUESTED);
    CHECK_EQ_INT(call.has_hash, 1);
    CHECK_EQ_INT(call.g_hash[5], 7);
    /* a commitment of the wrong length cannot be checked later, so the call is refused now */
    set_bytes(c, "g_a_hash", g, 31);
    CHECK_EQ_INT(noshi_phone_call_parse(c, &call), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(call.id, 0);

    c = call_base("phoneCallAccepted");
    set_bytes(c, "g_b", g, NOSHI_CALL_KEY_LEN);
    CHECK_EQ_INT(noshi_phone_call_parse(c, &call), NOSHI_OK);
    CHECK_EQ_INT(call.kind, NOSHI_CALL_ACCEPTED);
    CHECK_EQ_INT(call.has_g, 1);
    CHECK_EQ_INT(call.g[100], 7);

    c = call_base("phoneCall");
    set_flag(c, "p2p_allowed");
    set_bytes(c, "g_a_or_b", g, NOSHI_CALL_KEY_LEN);
    set_i64(c, "key_fingerprint", -77);
    set_i32(c, "start_date", 1800);
    conn = obj("phoneConnection");
    set_i64(conn, "id", 31);
    set_str(conn, "ip", "149.154.167.1");
    set_str(conn, "ipv6", "");
    set_i32(conn, "port", 599);
    set_bytes(conn, "peer_tag", tag, 16);
    conns[0] = conn;
    conns[1] = obj("phoneConnectionWebrtc");
    set_i64(conns[1], "id", 32);
    set_str(conns[1], "ip", "1.2.3.4");
    set_str(conns[1], "ipv6", "");
    set_i32(conns[1], "port", 3478);
    set_str(conns[1], "username", "u");
    set_str(conns[1], "password", "p");
    conns[2] = obj("phoneConnection");
    set_i64(conns[2], "id", 33);
    set_str(conns[2], "ip", "149.154.167.2");
    set_str(conns[2], "ipv6", "2001:db8::1");
    set_i32(conns[2], "port", 599);
    set_bytes(conns[2], "peer_tag", tag, 15);
    /* a TURN server of the call (with the turn flag), and one that has the flag and no credentials */
    conns[3] = obj("phoneConnectionWebrtc");
    set_flag(conns[3], "turn");
    set_flag(conns[3], "stun");
    set_i64(conns[3], "id", 34);
    set_str(conns[3], "ip", "91.108.13.23");
    set_str(conns[3], "ipv6", "");
    set_i32(conns[3], "port", 598);
    set_str(conns[3], "username", "reflector");
    set_str(conns[3], "password", "p4ss-w0rd");
    conns[4] = obj("phoneConnectionWebrtc");
    set_flag(conns[4], "turn");
    set_i64(conns[4], "id", 35);
    set_str(conns[4], "ip", "91.108.13.24");
    set_str(conns[4], "ipv6", "");
    set_i32(conns[4], "port", 598);
    set_str(conns[4], "username", "");
    set_str(conns[4], "password", "x");
    set(c, "connections", vec_of(conns, 5));
    CHECK_EQ_INT(noshi_phone_call_parse(c, &call), NOSHI_OK);
    CHECK_EQ_INT(call.kind, NOSHI_CALL_ACTIVE);
    CHECK_EQ_INT(call.turn_count, 1);
    CHECK_EQ_INT(call.turns[0].id, 34);
    CHECK_EQ_INT(call.turns[0].port, 598);
    CHECK(!strcmp(call.turns[0].ip, "91.108.13.23"));
    CHECK(!strcmp(call.turns[0].username, "reflector"));
    CHECK(!strcmp(call.turns[0].password, "p4ss-w0rd"));
    CHECK_EQ_INT(call.p2p_allowed, 1);
    CHECK_EQ_INT(call.key_fingerprint, -77);
    /* the webrtc endpoint and the one with a short tag are left out, the reflector stays */
    CHECK_EQ_INT(call.connection_count, 1);
    CHECK_EQ_INT(call.connections[0].id, 31);
    CHECK_EQ_INT(call.connections[0].port, 599);
    CHECK(!strcmp(call.connections[0].ip, "149.154.167.1"));
    CHECK_EQ_INT(call.connections[0].peer_tag[3], 9);
    answer = obj("phone.phoneCall");
    set(answer, "phone_call", c);
    set(answer, "users", noshi_tl_new_vec(&arena, 0));
    CHECK_EQ_INT(noshi_phone_call_from_answer(answer, &call), NOSHI_OK);
    CHECK_EQ_INT(call.kind, NOSHI_CALL_ACTIVE);
    CHECK_EQ_INT(noshi_phone_call_from_answer(c, &call), NOSHI_E_MALFORMED);

    c = obj("phoneCallDiscarded");
    set_i64(c, "id", 4001);
    set_i32(c, "duration", 42);
    set(c, "reason", obj("phoneCallDiscardReasonBusy"));
    set_flag(c, "need_rating");
    CHECK_EQ_INT(noshi_phone_call_parse(c, &call), NOSHI_OK);
    CHECK_EQ_INT(call.kind, NOSHI_CALL_DISCARDED);
    CHECK_EQ_INT(call.reason, NOSHI_CALL_REASON_BUSY);
    CHECK_EQ_INT(call.duration, 42);
    CHECK_EQ_INT(call.need_rating, 1);

    c = obj("phoneCallEmpty");
    set_i64(c, "id", 5);
    CHECK_EQ_INT(noshi_phone_call_parse(c, &call), NOSHI_OK);
    CHECK_EQ_INT(call.kind, NOSHI_CALL_EMPTY);
    CHECK_EQ_INT(noshi_phone_call_parse(obj("boolTrue"), &call), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_phone_call_parse(NULL, &call), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_phone_call_parse(c, NULL), NOSHI_E_ARG);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_emoji_table();
    test_dh_config();
    test_key_exchange();
    test_requests();
    test_parse();
    noshi_arena_free(&arena);
    return test_finish("test_call");
}
