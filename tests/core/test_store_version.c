#include "test_util.h"
#include "noshi_store.h"

/* a watcher skips its read while the version of its chat stands; a write to the chat, to a user or chat record, or a sweep must move it */

static noshi_tl_value *record(noshi_arena *a, int32_t id) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "updates.state");
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "pts", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "qts", 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "seq", 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "date", 100), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "unread_count", 0), NOSHI_OK);
    return v;
}

int main(void) {
    noshi_store *s = NULL;
    noshi_arena a;
    noshi_tl_value *v;
    noshi_peer chat = {2, 1001}, other = {2, 1002}, user = {1, 77};
    uint64_t before, after;
    noshi_arena_init(&a, 65536);
    v = record(&a, 5);
    CHECK_EQ_INT(noshi_store_open(&s, ":memory:", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_peer_version(NULL, chat), 0);

    before = noshi_store_peer_version(s, chat);
    CHECK_EQ_INT(noshi_store_put(s, NOSHI_RECORD_MESSAGE, chat, 10, v), NOSHI_OK);
    after = noshi_store_peer_version(s, chat);
    CHECK(after > before);

    /* a read changes nothing */
    CHECK_EQ_INT(noshi_store_peer_version(s, chat), after);

    /* another chat in another bucket leaves this one alone */
    before = after;
    CHECK_EQ_INT(noshi_store_put(s, NOSHI_RECORD_MESSAGE, other, 11, v), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_peer_version(s, chat), before);

    /* a user record changes names in every chat */
    CHECK_EQ_INT(noshi_store_put(s, NOSHI_RECORD_USER, user, 77, v), NOSHI_OK);
    after = noshi_store_peer_version(s, chat);
    CHECK(after > before);

    before = after;
    CHECK_EQ_INT(noshi_store_delete(s, NOSHI_RECORD_MESSAGE, chat, 10), NOSHI_OK);
    after = noshi_store_peer_version(s, chat);
    CHECK(after > before);

    /* a failed write keeps the number */
    before = after;
    CHECK_EQ_INT(noshi_store_put(s, NOSHI_RECORD_MESSAGE, chat, 12, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_store_peer_version(s, chat), before);

    /* the sweep over every chat moves them all */
    CHECK_EQ_INT(noshi_store_delete_common_message(s, 11), NOSHI_OK);
    after = noshi_store_peer_version(s, chat);
    CHECK(after > before);
    CHECK(noshi_store_peer_version(s, other) > 0);

    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    noshi_arena_free(&a);
    return test_finish("test_store_version");
}
