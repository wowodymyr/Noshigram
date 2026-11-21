#include "test_util.h"
#include "noshi_messages.h"
#include "noshi_poll.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void set(noshi_tl_value *v, const char *f, noshi_tl_value *x) { CHECK_EQ_INT(noshi_tl_set(v, f, x), NOSHI_OK); }
static void set_i32(noshi_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, f, x), NOSHI_OK); }
static void set_i64(noshi_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, f, x), NOSHI_OK); }
static void set_flag(noshi_tl_value *v, const char *f) { CHECK_EQ_INT(noshi_tl_set_flag(v, f), NOSHI_OK); }

static noshi_tl_value *words(const char *text) {
    noshi_tl_value *w = obj("textWithEntities");
    CHECK_EQ_INT(noshi_tl_set_str(&arena, w, "text", text), NOSHI_OK);
    set(w, "entities", noshi_tl_new_vec(&arena, 0));
    return w;
}

static noshi_tl_value *answer(const char *text, uint8_t token) {
    noshi_tl_value *a = obj("pollAnswer");
    set(a, "text", words(text));
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, a, "option", &token, 1), NOSHI_OK);
    return a;
}

static noshi_tl_value *voters(uint8_t token, int32_t count, int chosen, int correct) {
    noshi_tl_value *v = obj("pollAnswerVoters");
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, v, "option", &token, 1), NOSHI_OK);
    set_i32(v, "voters", count);
    if (chosen) set_flag(v, "chosen");
    if (correct) set_flag(v, "correct");
    return v;
}

static noshi_tl_value *vec2(noshi_tl_value *a, noshi_tl_value *b) {
    noshi_tl_value *v = noshi_tl_new_vec(&arena, 2);
    CHECK(v != NULL);
    CHECK_EQ_INT(noshi_tl_vec_set(v, 0, a), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(v, 1, b), NOSHI_OK);
    return v;
}

static noshi_tl_value *media_poll(noshi_tl_value *answers, noshi_tl_value *results) {
    noshi_tl_value *poll = obj("poll"), *media = obj("messageMediaPoll");
    set_i64(poll, "id", 99);
    set(poll, "question", words("Tea or coffee?"));
    set(poll, "answers", answers);
    set(media, "poll", poll);
    if (results) set(media, "results", results);
    return media;
}

static noshi_tl_value *peer_user(int64_t id) {
    noshi_tl_value *peer = obj("peerUser");
    set_i64(peer, "user_id", id);
    return peer;
}

static void test_recent_voters(void) {
    noshi_poll p;
    noshi_tl_value *results = obj("pollResults");
    noshi_tl_value *media = media_poll(vec2(answer("Tea", '0'), answer("Coffee", '1')), results);
    noshi_tl_value *recent = noshi_tl_new_vec(&arena, 5);
    noshi_tl_value *channel = obj("peerChannel");
    CHECK(recent != NULL);
    set_i64(channel, "channel_id", 5);
    /* the order is kept, what is not a user is left out, and no more than three are read */
    CHECK_EQ_INT(noshi_tl_vec_set(recent, 0, peer_user(11)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(recent, 1, channel), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(recent, 2, peer_user(12)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(recent, 3, peer_user(13)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(recent, 4, peer_user(14)), NOSHI_OK);
    set(results, "results", vec2(voters('0', 1, 0, 0), voters('1', 3, 0, 0)));
    set(results, "recent_voters", recent);
    set_i32(results, "total_voters", 4);
    CHECK_EQ_INT(noshi_poll_read(media, &p), 1);
    CHECK_EQ_INT(p.recent_voter_count, 3);
    CHECK_EQ_INT(p.recent_voters[0], 11);
    CHECK_EQ_INT(p.recent_voters[1], 12);
    CHECK_EQ_INT(p.recent_voters[2], 13);
}

static void test_read(void) {
    noshi_poll p;
    noshi_tl_value *results = obj("pollResults");
    noshi_tl_value *media = media_poll(vec2(answer("Tea", '0'), answer("Coffee", '1')), results);
    set(results, "results", vec2(voters('0', 3, 0, 0), voters('1', 7, 1, 0)));
    set_i32(results, "total_voters", 10);
    CHECK_EQ_INT(noshi_poll_read(media, &p), 1);
    CHECK_EQ_INT(p.present, 1);
    CHECK_EQ_INT(p.id, 99);
    CHECK(strcmp(p.question, "Tea or coffee?") == 0);
    CHECK_EQ_INT(p.answer_count, 2);
    CHECK(strcmp(p.answers[1].text, "Coffee") == 0);
    CHECK_EQ_INT(p.answers[0].option_len, 1);
    CHECK_EQ_INT(p.answers[0].option[0], '0');
    CHECK_EQ_INT(p.total_voters, 10);
    CHECK_EQ_INT(p.has_counts, 1);
    CHECK_EQ_INT(p.answers[0].voters, 3);
    CHECK_EQ_INT(p.answers[1].voters, 7);
    CHECK_EQ_INT(p.answers[1].chosen, 1);
    CHECK_EQ_INT(p.answers[0].chosen, 0);
    CHECK_EQ_INT(p.closed + p.multiple + p.quiz + p.public_voters, 0);
}

static void test_flags_and_no_results(void) {
    noshi_poll p;
    noshi_tl_value *media = media_poll(vec2(answer("A", 'a'), answer("B", 'b')), NULL);
    set_flag(noshi_tl_get(media, "poll") == NULL ? media : (noshi_tl_value *)noshi_tl_get(media, "poll"), "closed");
    set_flag((noshi_tl_value *)noshi_tl_get(media, "poll"), "multiple_choice");
    set_flag((noshi_tl_value *)noshi_tl_get(media, "poll"), "quiz");
    set_flag((noshi_tl_value *)noshi_tl_get(media, "poll"), "public_voters");
    CHECK_EQ_INT(noshi_poll_read(media, &p), 1);
    CHECK_EQ_INT(p.closed, 1);
    CHECK_EQ_INT(p.multiple, 1);
    CHECK_EQ_INT(p.quiz, 1);
    CHECK_EQ_INT(p.public_voters, 1);
    /* no results: no counts, nobody chosen */
    CHECK_EQ_INT(p.has_counts, 0);
    CHECK_EQ_INT(p.total_voters, 0);
    CHECK_EQ_INT(p.answers[0].chosen + p.answers[1].chosen, 0);
}

static void test_results_edge(void) {
    noshi_poll p;
    noshi_tl_value *results = obj("pollResults");
    noshi_tl_value *media = media_poll(vec2(answer("A", 'a'), answer("B", 'b')), results);
    /* an answer the poll does not have is ignored, and a result with no voters counted keeps the flags only */
    set(results, "results", vec2(voters('z', 5, 1, 0), voters('b', 0, 1, 1)));
    CHECK_EQ_INT(noshi_poll_read(media, &p), 1);
    CHECK_EQ_INT(p.has_counts, 0);
    CHECK_EQ_INT(p.answers[0].chosen, 0);
    CHECK_EQ_INT(p.answers[1].chosen, 1);
    CHECK_EQ_INT(p.answers[1].correct, 1);
}

static void test_malformed(void) {
    noshi_poll p;
    noshi_tl_value *empty = noshi_tl_new_vec(&arena, 0);
    noshi_tl_value *bad = media_poll(vec2(answer("", 'a'), answer("B", 'b')), NULL);
    CHECK_EQ_INT(noshi_poll_read(obj("messageMediaEmpty"), &p), 0);
    CHECK_EQ_INT(p.present, 0);
    CHECK_EQ_INT(noshi_poll_read(NULL, &p), 0);
    CHECK_EQ_INT(noshi_poll_read(media_poll(empty, NULL), &p), 0);
    CHECK_EQ_INT(p.answer_count, 0);
    /* an answer without words is dropped and the other stays */
    CHECK_EQ_INT(noshi_poll_read(bad, &p), 1);
    CHECK_EQ_INT(p.answer_count, 1);
    CHECK(strcmp(p.answers[0].text, "B") == 0);
    CHECK_EQ_INT(noshi_poll_read(bad, NULL), 0);
}

static void test_vote(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref group = {2, 600, 0, 0, 0}, channel = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    noshi_poll_choice choice[2];
    const noshi_tl_value *list;
    noshi_writer wire;
    memset(choice, 0, sizeof(choice));
    choice[0].option[0] = '1';
    choice[0].option_len = 1;
    choice[1].option[0] = '2';
    choice[1].option_len = 1;
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, &channel, 12, choice, 2, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_sendVote);
    CHECK_EQ_INT(noshi_tl_get_vec(request, "options", &list), NOSHI_OK);
    CHECK_EQ_INT(list->u.vec.count, 2);
    noshi_writer_init(&wire, 1024);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    /* no choices takes the vote back */
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, &group, 12, NULL, 0, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_get_vec(request, "options", &list), NOSHI_OK);
    CHECK_EQ_INT(list->u.vec.count, 0);
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, &channel, 0, choice, 1, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, &nohash, 12, choice, 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, NULL, 12, choice, 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, &channel, 12, NULL, 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, &channel, 12, choice, NOSHI_POLL_ANSWERS_MAX + 1, &request), NOSHI_E_ARG);
    choice[1].option_len = 0;
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, &channel, 12, choice, 2, &request), NOSHI_E_ARG);
    choice[1].option_len = NOSHI_POLL_OPTION_MAX + 1;
    CHECK_EQ_INT(noshi_poll_vote_request(&arena, &channel, 12, choice, 2, &request), NOSHI_E_ARG);
}

static void test_by_id(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref group = {2, 600, 0, 0, 0}, channel = {3, 500, 7, 0, 0}, user = {1, 5, 9, 0, 0}, nohash = {3, 500, 0, 0, 0}, self = {1, 1, 0, 1, 0};
    int32_t ids[2] = {10, 11}, bad[2] = {10, 0};
    const noshi_tl_value *list;
    noshi_writer wire;
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &channel, ids, 2, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_channels_getMessages);
    CHECK(noshi_tl_is(noshi_tl_get(request, "channel"), NOSHI_TL_ID_inputChannel));
    CHECK_EQ_INT(noshi_tl_get_vec(request, "id", &list), NOSHI_OK);
    CHECK_EQ_INT(list->u.vec.count, 2);
    noshi_writer_init(&wire, 1024);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &group, ids, 2, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_getMessages);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &user, ids, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &channel, bad, 2, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &nohash, ids, 2, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &self, ids, 2, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &channel, ids, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &channel, ids, NOSHI_MESSAGES_MAX + 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &channel, NULL, 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, NULL, ids, 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_messages_by_id_request(&arena, &channel, ids, 1, NULL), NOSHI_E_ARG);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_read();
    test_recent_voters();
    test_flags_and_no_results();
    test_results_edge();
    test_malformed();
    test_vote();
    test_by_id();
    noshi_arena_free(&arena);
    return test_finish("test_poll");
}
