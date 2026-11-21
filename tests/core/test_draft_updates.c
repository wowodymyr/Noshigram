#include "test_util.h"
#include "noshi_drafts.h"
#include "noshi_tl_ids.h"
#include "noshi_updates.h"

#include <unistd.h>

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

static noshi_tl_value *draft_update(const char *text) {
    noshi_tl_value *update = obj("updateDraftMessage"), *peer = obj("peerUser"), *draft = obj("draftMessage"), *short_update = obj("updateShort");
    CHECK_EQ_INT(noshi_tl_set_i64(&a, peer, "user_id", 77), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(update, "peer", peer), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&a, draft, "message", text), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, draft, "date", 500), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(update, "draft", draft), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(short_update, "update", update), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, short_update, "date", 500), NOSHI_OK);
    return short_update;
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
    char path[] = "/tmp/noshigram-draft-updates-XXXXXX";
    int fd = mkstemp(path), count = 0;
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    noshi_arena_init(&a, 1u << 20);
    CHECK_EQ_INT(noshi_store_open(&store, path, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, store, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_state(&u, state(10, 5, 2)), NOSHI_OK);

    /* a draft typed on another phone is no part of the sequence: no gap, no difference, and nothing for the journal that nothing reads */
    for (int round = 0; round < 50; ++round) CHECK_EQ_INT(noshi_updates_apply(&u, draft_update("typed elsewhere")), NOSHI_OK);
    CHECK_EQ_INT(u.needs_difference, 0);
    CHECK_EQ_INT(u.global_gap, 0);
    CHECK_EQ_INT(noshi_store_journal_page(store, 0, 512, count_visit, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_updates_quiet(draft_update("x")), 1);

    /* and what the client hands to the app reads back from the same update */
    {
        const noshi_tl_value *update = noshi_tl_get(draft_update("hello"), "update"), *body = NULL;
        noshi_draft *row = malloc(sizeof(*row));
        int32_t kind = 0, top = 0;
        int64_t peer = 0;
        CHECK(row != NULL);
        CHECK_EQ_INT(noshi_draft_update_read(update, &kind, &peer, &top, &body), NOSHI_OK);
        CHECK_EQ_INT(noshi_draft_read(body, top, row), NOSHI_OK);
        CHECK(strcmp(row->text, "hello") == 0);
        CHECK_EQ_INT(row->date, 500);
        free(row);
    }
    noshi_arena_free(&a);
    noshi_store_close(store);
    unlink(path);
    return test_finish("test_draft_updates");
}
