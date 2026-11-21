#include "noshi_tl_ids.h"
#include "noshi_typing.h"
#include "test_util.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void set(noshi_tl_value *v, const char *field, noshi_tl_value *x) {
    CHECK_EQ_INT(noshi_tl_set(v, field, x), NOSHI_OK);
}

static noshi_tl_value *peer_user(int64_t id) {
    noshi_tl_value *p = obj("peerUser");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, p, "user_id", id), NOSHI_OK);
    return p;
}

static void person_in_a_chat(void) {
    static const struct {
        const char *action;
        noshi_typing_action expected;
    } actions[] = {
        {"sendMessageTypingAction", NOSHI_TYPING_TEXT},
        {"sendMessageRecordAudioAction", NOSHI_TYPING_VOICE},
        {"sendMessageRecordRoundAction", NOSHI_TYPING_VOICE},
        {"sendMessageUploadPhotoAction", NOSHI_TYPING_PHOTO},
        {"sendMessageRecordVideoAction", NOSHI_TYPING_VIDEO},
        {"sendMessageUploadDocumentAction", NOSHI_TYPING_FILE},
        {"sendMessageChooseStickerAction", NOSHI_TYPING_STICKER},
        {"sendMessageGamePlayAction", NOSHI_TYPING_OTHER},
        {"sendMessageCancelAction", NOSHI_TYPING_CANCEL},
    };
    size_t i;
    for (i = 0; i < sizeof(actions) / sizeof(actions[0]); ++i) {
        noshi_tl_value *update = obj("updateUserTyping");
        noshi_typing t;
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, update, "user_id", 777), NOSHI_OK);
        set(update, "action", obj(actions[i].action));
        CHECK_EQ_INT(noshi_typing_read(update, &t), 1);
        CHECK_EQ_INT(t.peer_kind, 1);
        CHECK_EQ_INT(t.peer_id, 777);
        CHECK_EQ_INT(t.user_id, 777);
        CHECK_EQ_INT(t.top_message, 0);
        CHECK_EQ_INT(t.action, actions[i].expected);
    }
}

static void member_of_a_group(void) {
    noshi_tl_value *update = obj("updateChatUserTyping");
    noshi_typing t;
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, update, "chat_id", 4242), NOSHI_OK);
    set(update, "from_id", peer_user(555));
    set(update, "action", obj("sendMessageTypingAction"));
    CHECK_EQ_INT(noshi_typing_read(update, &t), 1);
    CHECK_EQ_INT(t.peer_kind, 2);
    CHECK_EQ_INT(t.peer_id, 4242);
    CHECK_EQ_INT(t.user_id, 555);
    CHECK_EQ_INT(t.action, NOSHI_TYPING_TEXT);

    /* a sender that is not a user (a channel posting as itself) leaves the person unknown, and the action still counts */
    update = obj("updateChatUserTyping");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, update, "chat_id", 4242), NOSHI_OK);
    {
        noshi_tl_value *channel = obj("peerChannel");
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, channel, "channel_id", 9), NOSHI_OK);
        set(update, "from_id", channel);
    }
    set(update, "action", obj("sendMessageTypingAction"));
    CHECK_EQ_INT(noshi_typing_read(update, &t), 1);
    CHECK_EQ_INT(t.user_id, 0);
}

static void member_of_a_supergroup_topic(void) {
    noshi_tl_value *update = obj("updateChannelUserTyping");
    noshi_typing t;
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, update, "channel_id", 1234567), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, update, "top_msg_id", 88), NOSHI_OK);
    set(update, "from_id", peer_user(31));
    set(update, "action", obj("sendMessageRecordAudioAction"));
    CHECK_EQ_INT(noshi_typing_read(update, &t), 1);
    CHECK_EQ_INT(t.peer_kind, 3);
    CHECK_EQ_INT(t.peer_id, 1234567);
    CHECK_EQ_INT(t.user_id, 31);
    CHECK_EQ_INT(t.top_message, 88);
    CHECK_EQ_INT(t.action, NOSHI_TYPING_VOICE);
}

static void anything_else_is_ignored(void) {
    noshi_typing t;
    noshi_tl_value *update = obj("updateUserTyping");
    memset(&t, 0xaa, sizeof(t));
    CHECK_EQ_INT(noshi_typing_read(NULL, &t), 0);
    CHECK_EQ_INT(t.peer_kind, 0);
    CHECK_EQ_INT(noshi_typing_read(update, NULL), 0);
    /* no action, no user */
    CHECK_EQ_INT(noshi_typing_read(update, &t), 0);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, update, "user_id", 0), NOSHI_OK);
    set(update, "action", obj("sendMessageTypingAction"));
    CHECK_EQ_INT(noshi_typing_read(update, &t), 0);
    CHECK_EQ_INT(noshi_typing_read(obj("updateUserStatus"), &t), 0);
    CHECK_EQ_INT(noshi_typing_read(obj("boolTrue"), &t), 0);
    /* an action of a layer this app does not know shows nothing, but the update is still a typing one */
    update = obj("updateUserTyping");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, update, "user_id", 5), NOSHI_OK);
    set(update, "action", obj("sendMessageStopDraftAction"));
    CHECK_EQ_INT(noshi_typing_read(update, &t), 1);
    CHECK_EQ_INT(t.action, NOSHI_TYPING_CANCEL);
}

static void sends_typing(void) {
    noshi_peer_ref peer = {3, 500, 7, 0, 300};
    noshi_tl_value *request = NULL;
    int32_t top = 0;
    CHECK_EQ_INT(noshi_typing_request(&arena, &peer, 0, &request), NOSHI_OK);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_messages_setTyping));
    CHECK(noshi_tl_is(noshi_tl_get(request, "action"), NOSHI_TL_ID_sendMessageTypingAction));
    CHECK_EQ_INT(noshi_tl_get_i32(request, "top_msg_id", &top), NOSHI_OK);
    CHECK_EQ_INT(top, 300);
    peer.topic_id = 1;
    CHECK_EQ_INT(noshi_typing_request(&arena, &peer, 1, &request), NOSHI_OK);
    CHECK(!noshi_tl_has(request, "top_msg_id"));
    CHECK(noshi_tl_is(noshi_tl_get(request, "action"), NOSHI_TL_ID_sendMessageCancelAction));
    peer.topic_id = -1;
    CHECK_EQ_INT(noshi_typing_request(&arena, &peer, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
}

int main(void) {
    noshi_arena_init(&arena, 1u << 20);
    person_in_a_chat();
    member_of_a_group();
    member_of_a_supergroup_topic();
    anything_else_is_ignored();
    sends_typing();
    noshi_arena_free(&arena);
    return test_finish("test_typing");
}
