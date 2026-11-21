#include "test_util.h"
#include "noshi_updates.h"
#include "noshi_tl_ids.h"

#include <string.h>
#include <unistd.h>

static noshi_arena arena;

static noshi_tl_value *state(int32_t pts) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, "updates.state");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "pts", pts), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "qts", 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "seq", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "date", 100), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "unread_count", 0), NOSHI_OK);
    return v;
}

static noshi_tl_value *message(int32_t id, int64_t user, const char *text, int32_t edit_date) {
    noshi_tl_value *m = noshi_tl_new_obj(&arena, "message"), *peer = noshi_tl_new_obj(&arena, "peerUser");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, m, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, m, "date", 1000 + id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, peer, "user_id", user), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(m, "peer_id", peer), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, m, "message", text), NOSHI_OK);
    if (edit_date) CHECK_EQ_INT(noshi_tl_set_i32(&arena, m, "edit_date", edit_date), NOSHI_OK);
    return m;
}

static noshi_tl_value *deletion(int32_t pts, int32_t id) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, "updateDeleteMessages");
    int32_t ids[1];
    ids[0] = id;
    CHECK_EQ_INT(noshi_tl_set_i32_vec(&arena, v, "messages", ids, 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "pts", pts), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "pts_count", 1), NOSHI_OK);
    {
        noshi_tl_value *wrapper = noshi_tl_new_obj(&arena, "updateShort");
        CHECK_EQ_INT(noshi_tl_set(wrapper, "update", v), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, wrapper, "date", 200), NOSHI_OK);
        return wrapper;
    }
}

static const char *text_of(noshi_store *s, noshi_record_kind kind, noshi_peer peer, int64_t id, noshi_arena *read) {
    noshi_tl_value *got = NULL;
    const uint8_t *bytes = NULL;
    size_t len = 0;
    if (noshi_store_get(s, kind, peer, id, read, &got) != NOSHI_OK) return NULL;
    if (noshi_tl_get_bytes(got, "message", &bytes, &len) != NOSHI_OK) return NULL;
    return (const char *)bytes;
}

static void test_deleted(void) {
    noshi_store *s = NULL;
    noshi_updates u;
    noshi_arena read;
    noshi_peer peer = {1, 77}, found;
    int64_t count = -1;
    char path[] = "/tmp/noshigram-keep-XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    noshi_arena_init(&read, 4u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&s, path, 5), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, s, 5), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_state(&u, state(10)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(7, 77, "hello", 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(8, 77, "again", 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_find_common_message(s, 7, &found), NOSHI_OK);
    CHECK_EQ_INT(found.kind, 1);
    CHECK_EQ_INT((int)found.id, 77);

    /* with nothing asked for, a deleted message is gone */
    CHECK_EQ_INT(noshi_updates_apply(&u, deletion(11, 7)), NOSHI_OK);
    CHECK(text_of(s, NOSHI_RECORD_MESSAGE, peer, 7, &read) == NULL);
    CHECK(text_of(s, NOSHI_RECORD_DELETED_MESSAGE, peer, 7, &read) == NULL);

    /* the private switch alone keeps it, under the kind of the deleted ones, and the chat no longer has it */
    u.keep = NOSHI_KEEP_DELETED | NOSHI_KEEP_PRIVATE;
    CHECK_EQ_INT(noshi_updates_apply(&u, deletion(12, 8)), NOSHI_OK);
    CHECK(text_of(s, NOSHI_RECORD_MESSAGE, peer, 8, &read) == NULL);
    CHECK(text_of(s, NOSHI_RECORD_DELETED_MESSAGE, peer, 8, &read) != NULL);
    CHECK(strcmp(text_of(s, NOSHI_RECORD_DELETED_MESSAGE, peer, 8, &read), "again") == 0);
    CHECK_EQ_INT(noshi_store_count(s, NOSHI_RECORD_DELETED_MESSAGE, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 1);

    /* a switch for other chats keeps nothing here */
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(9, 77, "third", 0)), NOSHI_OK);
    u.keep = NOSHI_KEEP_DELETED | NOSHI_KEEP_GROUPS;
    CHECK_EQ_INT(noshi_updates_apply(&u, deletion(13, 9)), NOSHI_OK);
    CHECK(text_of(s, NOSHI_RECORD_DELETED_MESSAGE, peer, 9, &read) == NULL);

    /* a message the store never held is nothing to keep or remove */
    u.keep = NOSHI_KEEP_DELETED | NOSHI_KEEP_PRIVATE;
    CHECK_EQ_INT(noshi_updates_apply(&u, deletion(14, 99)), NOSHI_OK);

    CHECK_EQ_INT(noshi_store_delete(s, NOSHI_RECORD_DELETED_MESSAGE, peer, 8), NOSHI_OK);
    CHECK(text_of(s, NOSHI_RECORD_DELETED_MESSAGE, peer, 8, &read) == NULL);
    CHECK_EQ_INT(noshi_store_count(s, NOSHI_RECORD_DELETED_MESSAGE, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(noshi_store_clear(s, NOSHI_RECORD_DELETED_MESSAGE), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_count(s, NOSHI_RECORD_DELETED_MESSAGE, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(noshi_store_move(s, NOSHI_RECORD_MESSAGE, NOSHI_RECORD_DELETED_MESSAGE, peer, 12345), NOSHI_E_NOTFOUND);
    noshi_arena_free(&read);
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    unlink(path);
}

static void test_edits(void) {
    noshi_store *s = NULL;
    noshi_updates u;
    noshi_arena read;
    noshi_peer peer = {1, 88};
    int64_t count = -1;
    char path[] = "/tmp/noshigram-edit-XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    noshi_arena_init(&read, 4u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&s, path, 6), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, s, 6), NOSHI_OK);
    u.keep = NOSHI_KEEP_EDITS;
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(3, 88, "one", 0)), NOSHI_OK);
    /* the same message from a page of history is not an edit */
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(3, 88, "one", 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_count(s, NOSHI_RECORD_MESSAGE_EDIT, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(3, 88, "two", 2000)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(3, 88, "three", 3000)), NOSHI_OK);
    /* an edit that changed nothing in the text, and an older copy that arrives late, add no version */
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(3, 88, "three", 3500)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(3, 88, "stale", 2500)), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_count(s, NOSHI_RECORD_MESSAGE_EDIT, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 2);
    CHECK(strcmp(text_of(s, NOSHI_RECORD_MESSAGE_EDIT, peer, 3 * NOSHI_EDIT_VERSIONS + 1, &read), "one") == 0);
    CHECK(strcmp(text_of(s, NOSHI_RECORD_MESSAGE_EDIT, peer, 3 * NOSHI_EDIT_VERSIONS + 2, &read), "two") == 0);
    /* the neighbour message numbers its versions from one again */
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(4, 88, "a", 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(4, 88, "b", 4000)), NOSHI_OK);
    CHECK(strcmp(text_of(s, NOSHI_RECORD_MESSAGE_EDIT, peer, 4 * NOSHI_EDIT_VERSIONS + 1, &read), "a") == 0);
    /* with the switch off nothing is kept */
    u.keep = 0;
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(5, 88, "x", 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache_message(&u, message(5, 88, "y", 5000)), NOSHI_OK);
    CHECK(text_of(s, NOSHI_RECORD_MESSAGE_EDIT, peer, 5 * NOSHI_EDIT_VERSIONS + 1, &read) == NULL);
    noshi_arena_free(&read);
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    unlink(path);
}

int main(void) {
    noshi_arena_init(&arena, 8u * 1024u * 1024u);
    test_deleted();
    test_edits();
    noshi_arena_free(&arena);
    return test_finish("test_keep_deleted");
}
