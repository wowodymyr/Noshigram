#include "test_util.h"
#include "noshi_call_log.h"
#include "noshi_tl_ids.h"

#include <string.h>

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static noshi_tl_value *vec_of(noshi_tl_value **items, uint32_t n) {
    noshi_tl_value *vec = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(vec, i, items[i]), NOSHI_OK);
    return vec;
}

static noshi_tl_value *user(int64_t id, const char *name) {
    noshi_tl_value *v = obj("user");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, "access_hash", id * 3), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, "first_name", name), NOSHI_OK);
    return v;
}

/* a service message of a call with the person: out for a call the account made, duration and the reason as the server says them */
static noshi_tl_value *call(int32_t id, int64_t peer, int out, int video, int32_t duration, const char *reason, int32_t date) {
    noshi_tl_value *m = obj("messageService"), *action = obj("messageActionPhoneCall"), *to = obj("peerUser");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, m, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, m, "date", date), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, to, "user_id", peer), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(m, "peer_id", to), NOSHI_OK);
    if (out) CHECK_EQ_INT(noshi_tl_set_flag(m, "out"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, action, "call_id", id), NOSHI_OK);
    if (video) CHECK_EQ_INT(noshi_tl_set_flag(action, "video"), NOSHI_OK);
    if (duration) CHECK_EQ_INT(noshi_tl_set_i32(&arena, action, "duration", duration), NOSHI_OK);
    if (reason) CHECK_EQ_INT(noshi_tl_set(action, "reason", obj(reason)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(m, "action", action), NOSHI_OK);
    return m;
}

int main(void) {
    static noshi_call_log_row rows[8];
    size_t count = 99;
    noshi_tl_value *request, *messages[4], *users[2], *answer;

    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_call_log_request(&arena, 50, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_is(request, NOSHI_TL_ID_messages_search), 1);
    CHECK(noshi_tl_is(noshi_tl_get(request, "peer"), NOSHI_TL_ID_inputPeerEmpty));
    CHECK(noshi_tl_is(noshi_tl_get(request, "filter"), NOSHI_TL_ID_inputMessagesFilterPhoneCalls));
    noshi_writer encoded;
    noshi_writer_init(&encoded, 4096);
    CHECK_EQ_INT(noshi_tl_encode(request, &encoded, NULL), NOSHI_OK);
    noshi_writer_free(&encoded);
    CHECK_EQ_INT(noshi_call_log_request(&arena, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_call_log_request(&arena, NOSHI_CALL_LOG_MAX + 1, &request), NOSHI_E_ARG);

    messages[0] = call(10, 7, 1, 0, 65, NULL, 1000);
    messages[1] = call(9, 8, 0, 1, 0, "phoneCallDiscardReasonMissed", 900);
    messages[2] = call(8, 99, 0, 0, 0, "phoneCallDiscardReasonBusy", 800);       /* the person is not in the answer: skipped */
    messages[3] = call(7, 7, 1, 0, 0, "phoneCallDiscardReasonDisconnect", 700);
    users[0] = user(7, "Ann");
    users[1] = user(8, "Bob");
    answer = obj("messages.messages");
    CHECK_EQ_INT(noshi_tl_set(answer, "messages", vec_of(messages, 4)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "chats", vec_of(NULL, 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "users", vec_of(users, 2)), NOSHI_OK);
    CHECK_EQ_INT(noshi_call_log_parse(answer, rows, 8, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 3);
    CHECK_EQ_INT(rows[0].message_id, 10);
    CHECK_EQ_INT(rows[0].outgoing, 1);
    CHECK_EQ_INT(rows[0].duration, 65);
    CHECK_EQ_INT(rows[0].outcome, NOSHI_OUTCOME_ENDED);
    CHECK_EQ_INT((int)rows[0].user_id, 7);
    CHECK(strcmp(rows[0].name, "Ann") == 0);
    CHECK_EQ_INT(rows[1].outgoing, 0);
    CHECK_EQ_INT(rows[1].video, 1);
    CHECK_EQ_INT(rows[1].outcome, NOSHI_OUTCOME_MISSED);
    CHECK_EQ_INT((int)rows[1].user_id, 8);
    CHECK_EQ_INT(rows[2].outcome, NOSHI_OUTCOME_DISCONNECTED);

    CHECK_EQ_INT(noshi_call_log_parse(answer, rows, 2, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 2);
    CHECK_EQ_INT(noshi_call_log_parse(obj("messages.stickerSet"), rows, 8, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(noshi_call_log_parse(NULL, rows, 8, &count), NOSHI_E_ARG);
    noshi_arena_free(&arena);
    return test_finish("test_call_log");
}
