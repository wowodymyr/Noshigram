#include "test_util.h"
#include "noshi_notify_prefs.h"
#include "noshi_tl_ids.h"
#include "noshi_updates.h"

#include <string.h>
#include <unistd.h>

#define EXCEPTIONS 300

static noshi_arena a;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&a, name);
    CHECK(v != NULL);
    return v;
}

static noshi_tl_value *state(int32_t pts, int32_t qts, int32_t seq) {
    noshi_tl_value *v = obj("updates.state");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "pts", pts), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "qts", qts), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "seq", seq), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "date", 100), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "unread_count", 0), NOSHI_OK);
    return v;
}

/* the answer of account.getNotifyExceptions: an Updates whose entries are settings of chats, with the channels and users they name */
static noshi_tl_value *exceptions_answer(int with_chats) {
    noshi_tl_value *answer = obj("updates"), *list = noshi_tl_new_vec(&a, EXCEPTIONS), *chats = noshi_tl_new_vec(&a, EXCEPTIONS);
    for (uint32_t i = 0; i < EXCEPTIONS; ++i) {
        noshi_tl_value *update = obj("updateNotifySettings"), *notify = obj("notifyPeer"), *peer = obj("peerChannel"), *settings = obj("peerNotifySettings");
        noshi_tl_value *channel = obj("channelForbidden");
        CHECK_EQ_INT(noshi_tl_set_i64(&a, peer, "channel_id", 1000 + i), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(notify, "peer", peer), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&a, settings, "mute_until", 2147483647), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(update, "peer", notify), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(update, "notify_settings", settings), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_vec_set(list, i, update), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(&a, channel, "id", 1000 + i), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(&a, channel, "access_hash", 7), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_str(&a, channel, "title", "c"), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_vec_set(chats, i, channel), NOSHI_OK);
    }
    CHECK_EQ_INT(noshi_tl_set(answer, "updates", list), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "users", noshi_tl_new_vec(&a, 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "chats", with_chats ? chats : noshi_tl_new_vec(&a, 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, answer, "date", 1000), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, answer, "seq", 0), NOSHI_OK);
    return answer;
}

static noshi_status count_visit(void *ctx, int64_t id, const noshi_tl_value *v) {
    (void)id;
    (void)v;
    ++*(int *)ctx;
    return NOSHI_OK;
}

int main(void) {
    noshi_store *store = NULL;
    noshi_updates u;
    char path[] = "/tmp/noshigram-notify-updates-XXXXXX";
    int fd = mkstemp(path);
    noshi_status status;
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    noshi_arena_init(&a, 16u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&store, path, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, store, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_state(&u, state(10, 5, 2)), NOSHI_OK);
    status = noshi_updates_apply(&u, exceptions_answer(0));
    fprintf(stderr, "without chats: %d\n", (int)status);
    status = noshi_updates_apply(&u, exceptions_answer(1));
    fprintf(stderr, "apply status %d, needs_difference %d, global_gap %d, channels %u\n", (int)status, u.needs_difference, u.global_gap, (unsigned)u.channel_count);
    /* a list of settings is no part of the sequence of updates: it must not open a gap or fail */
    CHECK_EQ_INT(status, NOSHI_OK);
    CHECK_EQ_INT(u.needs_difference, 0);
    CHECK_EQ_INT((int)u.channel_count, 0);
    /* the list is asked for again and again, and none of it is kept in the journal that nothing reads */
    for (int round = 0; round < 40; ++round) CHECK_EQ_INT(noshi_updates_apply(&u, exceptions_answer(1)), NOSHI_OK);
    {
        /* a full journal makes room instead of refusing the next update */
        int count = 0;
        CHECK_EQ_INT(noshi_store_begin(store), NOSHI_OK);
        for (int i = 0; i < 8400; ++i) CHECK_EQ_INT(noshi_store_journal_add(store, obj("boolTrue")), NOSHI_OK);
        CHECK_EQ_INT(noshi_store_commit(store), NOSHI_OK);
        CHECK_EQ_INT(noshi_store_journal_page(store, 0, 512, count_visit, &count), NOSHI_OK);
        CHECK_EQ_INT(noshi_store_begin(store), NOSHI_OK);
        CHECK_EQ_INT(noshi_store_journal_add(store, obj("boolTrue")), NOSHI_OK);
        CHECK_EQ_INT(noshi_store_commit(store), NOSHI_OK);
        CHECK(count > 0);
    }
    noshi_arena_free(&a);
    noshi_store_close(store);
    unlink(path);
    return test_finish("test_notify_updates");
}
