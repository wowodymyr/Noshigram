#include "test_util.h"
#include "noshi_send_as.h"
#include "noshi_tl_ids.h"

#define SELF 100

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void set_i64(noshi_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, f, x), NOSHI_OK); }
static void set_str(noshi_tl_value *v, const char *f, const char *x) { CHECK_EQ_INT(noshi_tl_set_str(&arena, v, f, x), NOSHI_OK); }
static void set(noshi_tl_value *v, const char *f, noshi_tl_value *x) { CHECK_EQ_INT(noshi_tl_set(v, f, x), NOSHI_OK); }

static noshi_tl_value *vec_of(noshi_tl_value **items, uint32_t n) {
    noshi_tl_value *v = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(v != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(v, i, items[i]), NOSHI_OK);
    return v;
}

static noshi_tl_value *as_peer(const char *ctor, const char *field, int64_t id, int premium) {
    noshi_tl_value *p = obj(ctor), *item = obj("sendAsPeer");
    set_i64(p, field, id);
    set(item, "peer", p);
    if (premium) CHECK_EQ_INT(noshi_tl_set_flag(item, "premium_required"), NOSHI_OK);
    return item;
}

static void test_request(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref channel = {3, 500, 7, 0, 0}, group = {2, 600, 0, 0, 0}, user = {1, 5, 9, 0, 0}, nohash = {3, 500, 0, 0, 0};
    noshi_writer wire;
    CHECK_EQ_INT(noshi_send_as_request(&arena, &channel, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_channels_getSendAs);
    CHECK(noshi_tl_is(noshi_tl_get(request, "peer"), NOSHI_TL_ID_inputPeerChannel));
    noshi_writer_init(&wire, 1024);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_send_as_request(&arena, &group, &request), NOSHI_OK);
    /* a private chat has no identities, and a channel without its hash cannot be named */
    CHECK_EQ_INT(noshi_send_as_request(&arena, &user, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_send_as_request(&arena, &nohash, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_send_as_request(&arena, NULL, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_send_as_request(&arena, &channel, NULL), NOSHI_E_ARG);
}

static void test_parse(void) {
    noshi_dialog_row rows[4];
    uint8_t premium[4];
    size_t count;
    noshi_tl_value *peers[5], *chats[2], *users[2], *answer_value, *me, *news, *gone;
    me = obj("user");
    set_i64(me, "id", SELF);
    set_i64(me, "access_hash", 321);
    set_str(me, "first_name", "Me");
    users[0] = me;
    news = obj("channel");
    set_i64(news, "id", 77);
    set_i64(news, "access_hash", 5555);
    set_str(news, "title", "News");
    gone = obj("channel");
    set_i64(gone, "id", 88);
    set_i64(gone, "access_hash", 6666);
    chats[0] = news;
    chats[1] = gone;
    peers[0] = as_peer("peerUser", "user_id", SELF, 0);
    peers[1] = as_peer("peerChannel", "channel_id", 77, 0);
    /* a channel with no title in the answer, a chat and a channel the answer does not carry are all skipped */
    peers[2] = as_peer("peerChannel", "channel_id", 88, 1);
    peers[3] = as_peer("peerChannel", "channel_id", 99, 0);
    peers[4] = as_peer("peerChat", "chat_id", 12, 0);
    answer_value = obj("channels.sendAsPeers");
    set(answer_value, "peers", vec_of(peers, 5));
    set(answer_value, "chats", vec_of(chats, 2));
    set(answer_value, "users", vec_of(users, 1));
    CHECK_EQ_INT(noshi_send_as_parse(answer_value, SELF, rows, premium, 4, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].peer_kind, 1);
    CHECK_EQ_INT(rows[0].saved, 1);
    CHECK(strcmp(rows[0].title, "Me") == 0);
    CHECK_EQ_INT(rows[0].peer_hash, 321);
    CHECK_EQ_INT(rows[1].peer_kind, 3);
    CHECK_EQ_INT(rows[1].peer_id, 77);
    CHECK_EQ_INT(rows[1].peer_hash, 5555);
    CHECK(strcmp(rows[1].title, "News") == 0);
    CHECK_EQ_INT(premium[1], 0);
    /* the cap cuts the list, the wrong answer is malformed, and count is zero for both */
    CHECK_EQ_INT(noshi_send_as_parse(answer_value, SELF, rows, premium, 1, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(noshi_send_as_parse(obj("boolTrue"), SELF, rows, premium, 4, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_send_as_parse(NULL, SELF, rows, premium, 4, &count), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_send_as_parse(answer_value, SELF, rows, premium, 0, &count), NOSHI_E_ARG);
}

static void test_parse_premium(void) {
    noshi_dialog_row rows[2];
    uint8_t premium[2];
    size_t count;
    noshi_tl_value *peers[1], *chats[1], *users[1], *answer_value, *news;
    news = obj("channel");
    set_i64(news, "id", 77);
    set_i64(news, "access_hash", 5555);
    set_str(news, "title", "News");
    chats[0] = news;
    users[0] = obj("userEmpty");
    peers[0] = as_peer("peerChannel", "channel_id", 77, 1);
    answer_value = obj("channels.sendAsPeers");
    set(answer_value, "peers", vec_of(peers, 1));
    set(answer_value, "chats", vec_of(chats, 1));
    set(answer_value, "users", vec_of(users, 0));
    CHECK_EQ_INT(noshi_send_as_parse(answer_value, SELF, rows, premium, 2, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(premium[0], 1);
}

static void test_set(void) {
    noshi_tl_value *request = obj("messages.sendMessage"), *saved = NULL;
    noshi_peer_ref channel = {3, 500, 7, 0, 0}, user = {1, 5, 9, 0, 0}, group = {2, 6, 0, 0, 0}, nohash = {3, 500, 0, 0, 0}, self = {1, 1, 0, 1, 0};
    noshi_peer_ref chat = {3, 800, 1, 0, 0};
    noshi_writer wire;
    CHECK_EQ_INT(noshi_set_send_as(&arena, request, &channel), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "send_as"), NOSHI_TL_ID_inputPeerChannel));
    request = obj("messages.sendMessage");
    CHECK_EQ_INT(noshi_set_send_as(&arena, request, &user), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "send_as"), NOSHI_TL_ID_inputPeerUser));
    /* a basic group, an identity without a hash, the account itself and nothing at all cannot be a sender, and leave the request alone */
    request = obj("messages.sendMessage");
    CHECK_EQ_INT(noshi_set_send_as(&arena, request, &group), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_set_send_as(&arena, request, &nohash), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_set_send_as(&arena, request, &self), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_set_send_as(&arena, request, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_set_send_as(&arena, NULL, &channel), NOSHI_E_ARG);
    CHECK(!noshi_tl_has(request, "send_as"));
    /* the saved choice */
    CHECK_EQ_INT(noshi_save_default_send_as_request(&arena, &chat, &channel, &saved), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(saved), NOSHI_TL_ID_messages_saveDefaultSendAs);
    CHECK(noshi_tl_is(noshi_tl_get(saved, "send_as"), NOSHI_TL_ID_inputPeerChannel));
    noshi_writer_init(&wire, 1024);
    CHECK_EQ_INT(noshi_tl_encode(saved, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_save_default_send_as_request(&arena, &chat, &self, &saved), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(saved, "send_as"), NOSHI_TL_ID_inputPeerSelf));
    CHECK_EQ_INT(noshi_save_default_send_as_request(&arena, &chat, &nohash, &saved), NOSHI_E_ARG);
    CHECK(saved == NULL);
    CHECK_EQ_INT(noshi_save_default_send_as_request(&arena, &user, &channel, &saved), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_save_default_send_as_request(&arena, &chat, NULL, &saved), NOSHI_E_ARG);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_request();
    test_parse();
    test_parse_premium();
    test_set();
    noshi_arena_free(&arena);
    return test_finish("test_send_as");
}
