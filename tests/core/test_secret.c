#include "test_util.h"
#include "noshi_secret.h"
#include "noshi_tl_ids.h"
#include "srp_vectors.h"

static noshi_tl_value *message(noshi_arena *arena, int64_t id) {
    noshi_tl_value *v = noshi_tl_new_obj(arena, "decryptedMessage");
    CHECK_EQ_INT(noshi_tl_set_i64(arena, v, "random_id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(arena, v, "ttl", 10), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(arena, v, "message", "secret text"), NOSHI_OK);
    return v;
}
static noshi_tl_value *service(noshi_arena *a, const noshi_tl_value *action, int64_t random_id) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "decryptedMessageService");
    CHECK_EQ_INT(noshi_tl_set_i64(a, v, "random_id", random_id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "action", (noshi_tl_value *)action), NOSHI_OK);
    return v;
}
static void exchange(noshi_secret_state *sender, noshi_secret_state *receiver, const noshi_tl_value *v,
                     noshi_arena *arena, noshi_tl_value **received) {
    noshi_writer packet;
    noshi_secret_state next;
    noshi_writer_init(&packet, 2u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_secret_seal(sender, v, &packet, &next), NOSHI_OK);
    *sender = next;
    CHECK_EQ_INT(noshi_secret_open(receiver, packet.data, packet.len, arena, received, &next), NOSHI_OK);
    *receiver = next;
    noshi_writer_free(&packet);
    noshi_secret_free(&next);
}

int main(void) {
    noshi_secret_dh da, db;
    noshi_mt_auth_key ka, kb;
    noshi_secret_state a, b, next;
    noshi_arena arena, received;
    noshi_tl_value *v, *got, *request, *accept, *commit, *noop;
    noshi_writer packet, packet2, short_output;
    uint8_t invalid[256] = {0};
    uint64_t old_key;
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    noshi_arena_init(&received, 4u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_secret_dh_begin(&da, srp_prime, 3, NULL, 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_secret_dh_begin(&db, srp_prime, 3, srp_b, 256), NOSHI_OK);
    CHECK_EQ_INT(noshi_secret_dh_finish(&da, db.public_value, 256, &ka), NOSHI_OK);
    CHECK_EQ_INT(noshi_secret_dh_finish(&db, da.public_value, 256, &kb), NOSHI_OK);
    CHECK_MEM(ka.key, kb.key, 256);
    CHECK_EQ_INT(ka.id, kb.id);
    CHECK_EQ_INT(noshi_secret_init(&a, 1, &da, &ka, 1000), NOSHI_OK);
    CHECK_EQ_INT(noshi_secret_init(&b, 0, &db, &kb, 1000), NOSHI_OK);
    v = noshi_tl_new_obj(&arena, "decryptedMessageActionNotifyLayer");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "layer", NOSHI_SECRET_LAYER), NOSHI_OK);
    exchange(&a, &b, service(&arena, v, 10), &received, &got);
    CHECK_EQ_INT(noshi_secret_action(&b, noshi_tl_get(got, "action"), 1000, &arena, &noop, &next), NOSHI_OK);
    b = next;
    exchange(&b, &a, service(&arena, v, 11), &received, &got);
    CHECK_EQ_INT(noshi_secret_action(&a, noshi_tl_get(got, "action"), 1000, &arena, &noop, &next), NOSHI_OK);
    a = next;
    CHECK_EQ_INT(a.remote_layer, NOSHI_SECRET_LAYER);
    CHECK_EQ_INT(b.remote_layer, NOSHI_SECRET_LAYER);
    noshi_writer_init(&packet, 2u * 1024u * 1024u);
    noshi_writer_init(&packet2, 2u * 1024u * 1024u);
    noshi_writer_init(&short_output, 10);
    v = message(&arena, 12);
    CHECK_EQ_INT(noshi_secret_seal(&a, v, &short_output, &next), NOSHI_E_LIMIT);
    CHECK_EQ_INT(next.out_count, a.out_count);
    CHECK_EQ_INT(short_output.len, 0);
    CHECK_EQ_INT(noshi_secret_seal(&a, v, &packet, &next), NOSHI_OK);
    a = next;
    CHECK_EQ_INT(noshi_secret_seal(&a, message(&arena, 13), &packet2, &next), NOSHI_OK);
    a = next;
    CHECK_EQ_INT(noshi_secret_open(&b, packet2.data, packet2.len, &received, &got, &next), NOSHI_E_RETRY);
    CHECK_EQ_INT(next.in_count, b.in_count);
    CHECK_EQ_INT(noshi_secret_open(&b, packet.data, packet.len, &received, &got, &next), NOSHI_OK);
    b = next;
    CHECK_EQ_INT(noshi_secret_open(&b, packet.data, packet.len, &received, &got, &next), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_secret_open(&b, packet2.data, packet2.len, &received, &got, &next), NOSHI_OK);
    b = next;
    CHECK_EQ_INT(noshi_secret_open(&a, packet.data, packet.len, &received, &got, &next), NOSHI_E_SECURITY);
    packet.data[packet.len - 1] ^= 1;
    CHECK_EQ_INT(noshi_secret_open(&b, packet.data, packet.len, &received, &got, &next), NOSHI_E_SECURITY);
    CHECK(next.discarded);
    packet.data[packet.len - 1] ^= 1;
    CHECK(noshi_secret_rekey_due(&a, 1000 + 604800));
    CHECK_EQ_INT(noshi_secret_rekey_start(&a, &arena, &request, &next), NOSHI_OK);
    a = next;
    CHECK(!noshi_secret_rekey_due(&a, 1000 + 604800));
    exchange(&a, &b, service(&arena, request, 14), &received, &got);
    CHECK_EQ_INT(noshi_secret_action(&b, noshi_tl_get(got, "action"), 2000, &arena, &accept, &next), NOSHI_OK);
    b = next;
    CHECK(accept != NULL);
    exchange(&b, &a, service(&arena, accept, 15), &received, &got);
    CHECK_EQ_INT(noshi_secret_action(&a, noshi_tl_get(got, "action"), 2000, &arena, &commit, &next), NOSHI_OK);
    a = next;
    old_key = a.key.id;
    exchange(&a, &b, service(&arena, commit, 16), &received, &got);
    CHECK(a.key.id != old_key);
    CHECK_EQ_INT(noshi_secret_action(&b, noshi_tl_get(got, "action"), 2000, &arena, &noop, &next), NOSHI_OK);
    b = next;
    CHECK_EQ_INT(a.key.id, b.key.id);
    CHECK_EQ_INT(b.previous.id, 0);
    exchange(&b, &a, service(&arena, noop, 17), &received, &got);
    CHECK_EQ_INT(a.previous.id, 0);
    CHECK_EQ_INT(a.rekey_state, 0);
    CHECK_MEM(a.visualization, b.visualization, sizeof(a.visualization));
    CHECK_EQ_INT(noshi_secret_dh_finish(&da, invalid, 256, &ka), NOSHI_E_SECURITY);
    CHECK_EQ_INT(ka.id, 0);
    CHECK_EQ_INT(noshi_secret_expiry(10, 100, 30), 131);
    CHECK_EQ_INT(noshi_secret_expiry(0, 100, 30), 0);
    CHECK_EQ_INT(noshi_secret_expiry(10, UINT64_MAX - 2, 0), UINT64_MAX);
    noshi_secret_free(&a); noshi_secret_free(&b); noshi_secret_free(&next);
    noshi_wipe(&da, sizeof(da)); noshi_wipe(&db, sizeof(db)); noshi_wipe(&ka, sizeof(ka)); noshi_wipe(&kb, sizeof(kb));
    noshi_writer_free(&packet); noshi_writer_free(&packet2); noshi_writer_free(&short_output);
    noshi_arena_free(&arena); noshi_arena_free(&received);
    return test_finish("test_secret");
}
