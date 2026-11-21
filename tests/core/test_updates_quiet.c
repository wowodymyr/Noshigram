#include "test_util.h"
#include "noshi_updates.h"

/* a presence or typing update must not wake the notifier's look at the chat list, and anything else must */

static noshi_tl_value *obj(noshi_arena *a, const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(a, name);
    CHECK(v != NULL);
    return v;
}

static noshi_tl_value *container(noshi_arena *a, const char *name, const char *const *items, uint32_t count) {
    noshi_tl_value *v = obj(a, name), *vec = noshi_tl_new_vec(a, count);
    uint32_t i;
    for (i = 0; i < count; ++i) vec->u.vec.items[i] = obj(a, items[i]);
    CHECK_EQ_INT(noshi_tl_set(v, "updates", vec), NOSHI_OK);
    return v;
}

int main(void) {
    noshi_arena a;
    noshi_tl_value *v;
    const char *status[] = {"updateUserStatus"};
    const char *typing[] = {"updateUserTyping", "updateChatUserTyping", "updateReadHistoryOutbox"};
    const char *mixed[] = {"updateUserStatus", "updateNewMessage"};
    const char *message[] = {"updateNewChannelMessage"};
    const char *read[] = {"updateReadHistoryInbox"};
    noshi_arena_init(&a, 262144);

    v = obj(&a, "updateShort");
    CHECK_EQ_INT(noshi_tl_set(v, "update", obj(&a, "updateUserStatus")), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_quiet(v), 1);
    v = obj(&a, "updateShort");
    CHECK_EQ_INT(noshi_tl_set(v, "update", obj(&a, "updateNewMessage")), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_quiet(v), 0);
    v = obj(&a, "updateShort");
    CHECK_EQ_INT(noshi_tl_set(v, "update", obj(&a, "updateReadHistoryInbox")), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_quiet(v), 0);

    CHECK_EQ_INT(noshi_updates_quiet(container(&a, "updates", status, 1)), 1);
    CHECK_EQ_INT(noshi_updates_quiet(container(&a, "updatesCombined", typing, 3)), 1);
    CHECK_EQ_INT(noshi_updates_quiet(container(&a, "updates", mixed, 2)), 0);
    CHECK_EQ_INT(noshi_updates_quiet(container(&a, "updates", message, 1)), 0);
    CHECK_EQ_INT(noshi_updates_quiet(container(&a, "updates", read, 1)), 0);
    /* an empty container says nothing, so it is looked at */
    CHECK_EQ_INT(noshi_updates_quiet(container(&a, "updates", status, 0)), 0);

    /* a short message and a gap marker are never quiet */
    CHECK_EQ_INT(noshi_updates_quiet(obj(&a, "updateShortMessage")), 0);
    CHECK_EQ_INT(noshi_updates_quiet(obj(&a, "updatesTooLong")), 0);
    CHECK_EQ_INT(noshi_updates_quiet(NULL), 0);

    noshi_arena_free(&a);
    return test_finish("test_updates_quiet");
}
