#include "noshi_drafts.h"
#include "noshi_tl_ids.h"
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

static noshi_tl_value *peer_of(const char *ctor, const char *field, int64_t id) {
    noshi_tl_value *p = obj(ctor);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, p, field, id), NOSHI_OK);
    return p;
}

static noshi_tl_value *entity(const char *ctor, int32_t offset, int32_t length) {
    noshi_tl_value *e = obj(ctor);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, e, "offset", offset), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, e, "length", length), NOSHI_OK);
    return e;
}

static noshi_tl_value *reply_to(int32_t id, int32_t top) {
    noshi_tl_value *r = obj("inputReplyToMessage");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, r, "reply_to_msg_id", id), NOSHI_OK);
    if (top) CHECK_EQ_INT(noshi_tl_set_i32(&arena, r, "top_msg_id", top), NOSHI_OK);
    return r;
}

static noshi_tl_value *draft_of(const char *text, int32_t date, noshi_tl_value *reply, noshi_tl_value *entities) {
    noshi_tl_value *d = obj("draftMessage");
    CHECK_EQ_INT(noshi_tl_set_str(&arena, d, "message", text), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, d, "date", date), NOSHI_OK);
    if (reply) set(d, "reply_to", reply);
    if (entities) set(d, "entities", entities);
    return d;
}

static noshi_draft *fresh(void) {
    noshi_draft *d = malloc(sizeof(*d));
    CHECK(d != NULL);
    return d;
}

static void reads_text_reply_and_entities(void) {
    noshi_draft *out = fresh();
    noshi_tl_value *list = noshi_tl_new_vec(&arena, 2), *d;
    CHECK_EQ_INT(noshi_tl_vec_set(list, 0, entity("messageEntityBold", 0, 5)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 1, entity("messageEntityItalic", 6, 3)), NOSHI_OK);
    d = draft_of("hello you", 1700000000, reply_to(42, 0), list);
    CHECK_EQ_INT(noshi_tl_set_flag(d, "no_webpage"), NOSHI_OK);
    CHECK_EQ_INT(noshi_draft_read(d, 0, out), NOSHI_OK);
    CHECK_EQ_INT(out->present, 1);
    CHECK_EQ_INT(out->no_webpage, 1);
    CHECK_EQ_INT(out->date, 1700000000);
    CHECK_EQ_INT(out->reply_to, 42);
    CHECK(strcmp(out->text, "hello you") == 0);
    CHECK_EQ_INT(out->entity_count, 2);
    CHECK_EQ_INT(out->entities[0].kind, NOSHI_ENTITY_BOLD);
    CHECK_EQ_INT(out->entities[1].offset, 6);
    free(out);
}

static void empty_draft_is_not_present(void) {
    noshi_draft *out = fresh();
    noshi_tl_value *e = obj("draftMessageEmpty");
    CHECK_EQ_INT(noshi_draft_read(e, 0, out), NOSHI_OK);
    CHECK_EQ_INT(out->present, 0);
    CHECK_EQ_INT(out->date, 0);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, e, "date", 77), NOSHI_OK);
    CHECK_EQ_INT(noshi_draft_read(e, 0, out), NOSHI_OK);
    CHECK_EQ_INT(out->date, 77);
    /* no text and no answer keeps nothing, even as a draftMessage */
    CHECK_EQ_INT(noshi_draft_read(draft_of("", 5, NULL, NULL), 0, out), NOSHI_OK);
    CHECK_EQ_INT(out->present, 0);
    /* a bare reply is kept: the person pressed reply and has not typed yet */
    CHECK_EQ_INT(noshi_draft_read(draft_of("", 5, reply_to(9, 0), NULL), 0, out), NOSHI_OK);
    CHECK_EQ_INT(out->present, 1);
    CHECK_EQ_INT(out->reply_to, 9);
    free(out);
}

static void topic_root_is_not_an_answer(void) {
    noshi_draft *out = fresh();
    noshi_tl_value *d = draft_of("in a topic", 5, reply_to(300, 300), NULL);
    CHECK_EQ_INT(noshi_draft_read(d, 300, out), NOSHI_OK);
    CHECK_EQ_INT(out->reply_to, 0);
    CHECK_EQ_INT(out->present, 1);
    d = draft_of("in a topic", 5, reply_to(310, 300), NULL);
    CHECK_EQ_INT(noshi_draft_read(d, 300, out), NOSHI_OK);
    CHECK_EQ_INT(out->reply_to, 310);
    free(out);
}

static void rejects_what_is_not_a_draft(void) {
    noshi_draft *out = fresh();
    CHECK_EQ_INT(noshi_draft_read(NULL, 0, out), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_draft_read(obj("boolTrue"), 0, out), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_draft_read(obj("draftMessage"), 0, out), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(out->present, 0);
    CHECK_EQ_INT(noshi_draft_read(obj("draftMessageEmpty"), 0, NULL), NOSHI_E_ARG);
    free(out);
}

static void save_request_carries_everything(void) {
    noshi_peer_ref chat = {3, 500, 7, 0, 0}, topic = {3, 500, 7, 0, 300};
    noshi_send_entity bold = {NOSHI_ENTITY_BOLD, 0, 0, 5, 0, 0, 0, NULL};
    noshi_tl_value *request = NULL;
    const noshi_tl_value *list, *reply;
    int32_t id = 0;
    CHECK_EQ_INT(noshi_draft_save_request(&arena, &chat, "hello you", &bold, 1, 42, 1, &request), NOSHI_OK);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_messages_saveDraft));
    CHECK(noshi_tl_has(request, "no_webpage"));
    CHECK(noshi_tl_has(request, "peer"));
    list = noshi_tl_get(request, "entities");
    CHECK(list && list->kind == NOSHI_TL_V_VEC && list->u.vec.count == 1);
    reply = noshi_tl_get(request, "reply_to");
    CHECK(reply != NULL);
    CHECK_EQ_INT(noshi_tl_get_i32(reply, "reply_to_msg_id", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 42);
    CHECK(!noshi_tl_has(reply, "top_msg_id"));

    /* a draft in a topic names the root when it answers nothing, and the root as the thread when it answers a message */
    CHECK_EQ_INT(noshi_draft_save_request(&arena, &topic, "t", NULL, 0, 0, 0, &request), NOSHI_OK);
    reply = noshi_tl_get(request, "reply_to");
    CHECK(reply != NULL);
    CHECK_EQ_INT(noshi_tl_get_i32(reply, "reply_to_msg_id", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 300);
    CHECK(!noshi_tl_has(request, "no_webpage"));
    CHECK(!noshi_tl_has(request, "entities"));
    CHECK_EQ_INT(noshi_draft_save_request(&arena, &topic, "t", NULL, 0, 310, 0, &request), NOSHI_OK);
    reply = noshi_tl_get(request, "reply_to");
    CHECK_EQ_INT(noshi_tl_get_i32(reply, "reply_to_msg_id", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 310);
    CHECK_EQ_INT(noshi_tl_get_i32(reply, "top_msg_id", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 300);

    /* the way a draft is cleared: no text, no answer */
    CHECK_EQ_INT(noshi_draft_save_request(&arena, &chat, "", NULL, 0, 0, 0, &request), NOSHI_OK);
    CHECK(!noshi_tl_has(request, "reply_to"));
    CHECK(!noshi_tl_has(request, "entities"));
}

static void save_request_refuses_bad_input(void) {
    noshi_peer_ref chat = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    noshi_send_entity past = {NOSHI_ENTITY_BOLD, 0, 0, 50, 0, 0, 0, NULL};
    noshi_tl_value *request = (noshi_tl_value *)1;
    CHECK_EQ_INT(noshi_draft_save_request(&arena, &chat, "short", &past, 1, 0, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_draft_save_request(&arena, &chat, "x", NULL, 0, -1, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_draft_save_request(&arena, &nohash, "x", NULL, 0, 0, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_draft_save_request(&arena, &chat, NULL, NULL, 0, 0, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_draft_save_request(&arena, NULL, "x", NULL, 0, 0, 0, &request), NOSHI_E_ARG);
}

static void update_names_chat_and_topic(void) {
    int32_t kind = -1, topic = -1;
    int64_t id = -1;
    const noshi_tl_value *draft = NULL;
    noshi_tl_value *update = obj("updateDraftMessage"), *body = draft_of("x", 9, NULL, NULL);
    set(update, "peer", peer_of("peerUser", "user_id", 77));
    set(update, "draft", body);
    CHECK_EQ_INT(noshi_draft_update_read(update, &kind, &id, &topic, &draft), NOSHI_OK);
    CHECK_EQ_INT(kind, 1);
    CHECK_EQ_INT(id, 77);
    CHECK_EQ_INT(topic, 0);
    CHECK(draft == body);

    update = obj("updateDraftMessage");
    set(update, "peer", peer_of("peerChannel", "channel_id", 500));
    set(update, "draft", body);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, update, "top_msg_id", 300), NOSHI_OK);
    CHECK_EQ_INT(noshi_draft_update_read(update, &kind, &id, &topic, &draft), NOSHI_OK);
    CHECK_EQ_INT(kind, 3);
    CHECK_EQ_INT(topic, 300);

    /* the draft of a saved chat of a monoforum is not a draft of this chat */
    CHECK_EQ_INT(noshi_tl_set(update, "saved_peer_id", peer_of("peerUser", "user_id", 5)), NOSHI_OK);
    CHECK_EQ_INT(noshi_draft_update_read(update, &kind, &id, &topic, &draft), NOSHI_E_UNSUPPORTED);
    CHECK_EQ_INT(kind, 0);
    CHECK(draft == NULL);

    CHECK_EQ_INT(noshi_draft_update_read(obj("updateUserStatus"), &kind, &id, &topic, &draft), NOSHI_E_UNSUPPORTED);
    update = obj("updateDraftMessage");
    set(update, "draft", body);
    CHECK_EQ_INT(noshi_draft_update_read(update, &kind, &id, &topic, &draft), NOSHI_E_MALFORMED);
}

typedef struct seen {
    int count;
    int32_t kind[8];
    int64_t id[8];
    int32_t topic[8];
    const noshi_tl_value *draft[8];
} seen;

static noshi_status collect(void *ctx, int32_t kind, int64_t id, int32_t topic, const noshi_tl_value *draft) {
    seen *s = ctx;
    if (s->count >= 8) return NOSHI_E_LIMIT;
    s->kind[s->count] = kind;
    s->id[s->count] = id;
    s->topic[s->count] = topic;
    s->draft[s->count] = draft;
    ++s->count;
    return NOSHI_OK;
}

static noshi_status stop(void *ctx, int32_t kind, int64_t id, int32_t topic, const noshi_tl_value *draft) {
    (void)kind; (void)id; (void)topic; (void)draft;
    ++*(int *)ctx;
    return NOSHI_E_STATE;
}

static void walks_dialogs(void) {
    noshi_tl_value *answer = obj("messages.dialogs"), *list = noshi_tl_new_vec(&arena, 3), *a = obj("dialog"), *b = obj("dialog"), *folder = obj("dialogFolder");
    noshi_tl_value *body = draft_of("kept", 5, NULL, NULL);
    seen s;
    int calls = 0;
    memset(&s, 0, sizeof(s));
    set(a, "peer", peer_of("peerUser", "user_id", 1));
    set(a, "draft", body);
    set(b, "peer", peer_of("peerChat", "chat_id", 2));
    CHECK_EQ_INT(noshi_tl_vec_set(list, 0, a), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 1, folder), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 2, b), NOSHI_OK);
    set(answer, "dialogs", list);
    CHECK_EQ_INT(noshi_draft_dialogs_visit(answer, collect, &s), NOSHI_OK);
    CHECK_EQ_INT(s.count, 2);
    CHECK_EQ_INT(s.kind[0], 1);
    CHECK(s.draft[0] == body);
    CHECK_EQ_INT(s.kind[1], 2);
    CHECK_EQ_INT(s.id[1], 2);
    CHECK(s.draft[1] == NULL);
    CHECK_EQ_INT(noshi_draft_dialogs_visit(answer, stop, &calls), NOSHI_E_STATE);
    CHECK_EQ_INT(calls, 1);
    CHECK_EQ_INT(noshi_draft_dialogs_visit(obj("messages.dialogsNotModified"), collect, &s), NOSHI_OK);
    CHECK_EQ_INT(noshi_draft_dialogs_visit(obj("boolTrue"), collect, &s), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_draft_dialogs_visit(NULL, collect, &s), NOSHI_E_ARG);
}

static void walks_topics(void) {
    noshi_tl_value *answer = obj("messages.forumTopics"), *list = noshi_tl_new_vec(&arena, 3), *general = obj("forumTopic"), *topic = obj("forumTopic"), *gone = obj("forumTopicDeleted");
    noshi_tl_value *body = draft_of("kept", 5, NULL, NULL);
    seen s;
    memset(&s, 0, sizeof(s));
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, general, "id", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, topic, "id", 300), NOSHI_OK);
    set(topic, "draft", body);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 0, general), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 1, topic), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 2, gone), NOSHI_OK);
    set(answer, "topics", list);
    CHECK_EQ_INT(noshi_draft_topics_visit(answer, 3, 500, collect, &s), NOSHI_OK);
    CHECK_EQ_INT(s.count, 2);
    CHECK_EQ_INT(s.topic[0], 0);
    CHECK(s.draft[0] == NULL);
    CHECK_EQ_INT(s.topic[1], 300);
    CHECK_EQ_INT(s.id[1], 500);
    CHECK(s.draft[1] == body);
    CHECK_EQ_INT(noshi_draft_topics_visit(answer, 1, 500, collect, &s), NOSHI_E_ARG);
}

int main(void) {
    noshi_arena_init(&arena, 1u << 22);
    reads_text_reply_and_entities();
    empty_draft_is_not_present();
    topic_root_is_not_an_answer();
    rejects_what_is_not_a_draft();
    save_request_carries_everything();
    save_request_refuses_bad_input();
    update_names_chat_and_topic();
    walks_dialogs();
    walks_topics();
    noshi_arena_free(&arena);
    return test_finish("test_drafts");
}
