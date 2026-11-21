#include "test_util.h"
#include "noshi_updates.h"
#include "noshi_tl_ids.h"
#include "noshi_people.h"

#include <limits.h>
#include <string.h>
#include <unistd.h>

static noshi_tl_value *state(noshi_arena *a, int32_t pts, int32_t qts, int32_t seq) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "updates.state");
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "pts", pts), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "qts", qts), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "seq", seq), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "date", 100), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "unread_count", 0), NOSHI_OK);
    return v;
}

static noshi_tl_value *short_update(noshi_arena *a, int32_t pts, int32_t count, int32_t id) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "updateShortMessage");
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(a, v, "user_id", INT64_C(4294967399)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(a, v, "message", "hello"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "pts", pts), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "pts_count", count), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "date", 101), NOSHI_OK);
    return v;
}

static noshi_status count_visit(void *ctx, int64_t id, const noshi_tl_value *v) {
    int *count = ctx;
    CHECK(id > 0);
    CHECK(v != NULL);
    ++*count;
    return NOSHI_OK;
}

static void test_atomic(void) {
    noshi_store *s = NULL, *other = NULL;
    noshi_arena a, read;
    noshi_updates u;
    noshi_tl_value *v, *got, *request;
    noshi_cursor cursor;
    noshi_peer peer = {1, INT64_C(4294967399)};
    noshi_peer zero = {0, 0};
    noshi_outbox_item item;
    char path[] = "/tmp/noshigram-store-XXXXXX";
    int fd = mkstemp(path), count = 0;
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    noshi_arena_init(&a, 8u * 1024u * 1024u);
    noshi_arena_init(&read, 8u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&s, path, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, s, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_request(&u, 0, NULL, &a, &request), NOSHI_OK);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_updates_getState));
    CHECK_EQ_INT(noshi_updates_state(&u, state(&a, 10, 5, 2)), NOSHI_OK);
    v = short_update(&a, 11, 1, 7);
    CHECK_EQ_INT(noshi_updates_apply(&u, v), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_MESSAGE, peer, 7, &read, &got), NOSHI_OK);
    CHECK(noshi_tl_is(got, NOSHI_TL_ID_message));
    CHECK_EQ_INT(noshi_updates_apply(&u, v), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_journal_page(s, 0, 512, count_visit, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 1);
    {
        noshi_tl_value *wrapper = noshi_tl_new_obj(&a, "updateShort");
        noshi_tl_value *typing = noshi_tl_new_obj(&a, "updateUserTyping");
        CHECK_EQ_INT(noshi_tl_set_i64(&a, typing, "user_id", peer.id), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(typing, "action", noshi_tl_new_obj(&a, "sendMessageTypingAction")), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(wrapper, "update", typing), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&a, wrapper, "date", 102), NOSHI_OK);
        CHECK_EQ_INT(noshi_updates_apply(&u, wrapper), NOSHI_OK);
        count = 0;
        CHECK_EQ_INT(noshi_store_journal_page(s, 0, 512, count_visit, &count), NOSHI_OK);
        CHECK_EQ_INT(count, 1);
    }
    CHECK_EQ_INT(noshi_updates_apply(&u, short_update(&a, 13, 1, 9)), NOSHI_E_RETRY);
    CHECK_EQ_INT(noshi_store_cursor_get(s, 0, &cursor), NOSHI_OK);
    CHECK_EQ_INT(cursor.pts, 11);
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_MESSAGE, peer, 9, &read, &got), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_updates_apply(&u, short_update(&a, 12, 1, 8)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_apply(&u, short_update(&a, 13, 1, 9)), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_begin(s), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_put(s, NOSHI_RECORD_USER, zero, INT64_MAX - 1, noshi_tl_new_obj(&a, "boolTrue")), NOSHI_OK);
    cursor.pts = 999;
    CHECK_EQ_INT(noshi_store_cursor_put(s, 0, &cursor), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_rollback(s), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_cursor_get(s, 0, &cursor), NOSHI_OK);
    CHECK_EQ_INT(cursor.pts, 13);
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_USER, zero, INT64_MAX - 1, &read, &got), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_store_open(&other, path, 124), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_get(other, NOSHI_RECORD_MESSAGE, peer, 7, &read, &got), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_store_begin(s), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_begin(other), NOSHI_E_RETRY);
    CHECK_EQ_INT(noshi_store_rollback(s), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_close(other), NOSHI_OK);
    request = noshi_tl_new_obj(&a, "messages.sendMessage");
    v = noshi_tl_new_obj(&a, "inputPeerUser");
    CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "user_id", peer.id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&a, v, "access_hash", INT64_MIN + 17), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(request, "peer", v), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&a, request, "message", "durable"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&a, request, "random_id", INT64_MIN + 19), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_outbox_add(s, peer, request), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_outbox_add(s, peer, request), NOSHI_E_STORAGE);
    CHECK_EQ_INT(noshi_store_outbox_next(s, &read, &item), NOSHI_OK);
    CHECK_EQ_INT(item.random_id, INT64_MIN + 19);
    CHECK_EQ_INT(noshi_store_outbox_set(s, item.random_id, NOSHI_OUTBOX_SENDING, 0, 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_open(&s, path, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_outbox_recover(s), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_outbox_next(s, &read, &item), NOSHI_OK);
    CHECK_EQ_INT(item.random_id, INT64_MIN + 19);
    CHECK_EQ_INT(noshi_store_outbox_set(s, item.random_id, NOSHI_OUTBOX_SENT, 42, 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_outbox_set(s, item.random_id, NOSHI_OUTBOX_PENDING, 0, 0), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_store_outbox_next(s, &read, &item), NOSHI_E_NOTFOUND);
    count = 0;
    CHECK_EQ_INT(noshi_store_page(s, NOSHI_RECORD_MESSAGE, peer, INT64_MAX, 2, count_visit, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(noshi_store_page(s, NOSHI_RECORD_MESSAGE, peer, INT64_MAX, 513, count_visit, &count), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_store_begin(s), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_journal_ack(s, INT64_MAX), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_commit(s), NOSHI_OK);
    count = 0;
    CHECK_EQ_INT(noshi_store_journal_page(s, 0, 512, count_visit, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    unlink(path);
    noshi_arena_free(&a);
    noshi_arena_free(&read);
}

static void test_difference(void) {
    noshi_store *s = NULL;
    noshi_updates u;
    noshi_cursor c, next;
    noshi_arena a;
    noshi_tl_value *v, *vec, *request;
    noshi_arena_init(&a, 2u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&s, ":memory:", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, s, 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_state(&u, state(&a, 10, 4, 1)), NOSHI_OK);
    v = noshi_tl_new_obj(&a, "updates.differenceSlice");
    vec = noshi_tl_new_vec(&a, 0);
    CHECK_EQ_INT(noshi_tl_set(v, "new_messages", vec), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "new_encrypted_messages", vec), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "other_updates", vec), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "users", vec), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "chats", vec), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(v, "intermediate_state", state(&a, 15, 4, 2)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_difference(&u, 0, v), NOSHI_OK);
    CHECK(u.more_difference);
    CHECK_EQ_INT(noshi_updates_request(&u, 0, NULL, &a, &request), NOSHI_OK);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_updates_getDifference));
    CHECK_EQ_INT(noshi_tl_get_i32(request, "pts", &c.pts), NOSHI_OK);
    CHECK_EQ_INT(c.pts, 15);
    CHECK_EQ_INT(noshi_tl_set(v, "intermediate_state", state(&a, 14, 4, 2)), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_difference(&u, 0, v), NOSHI_E_MALFORMED);
    /* a state that carries an earlier date than the cursor holds is a good answer, and the cursor keeps its date */
    CHECK_EQ_INT(noshi_store_cursor_get(s, 0, &c), NOSHI_OK);
    {
        noshi_tl_value *later = state(&a, 16, 4, 2);
        CHECK_EQ_INT(noshi_tl_set_i32(&a, later, "date", c.date - 1), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(v, "intermediate_state", later), NOSHI_OK);
        CHECK_EQ_INT(noshi_updates_difference(&u, 0, v), NOSHI_OK);
        CHECK_EQ_INT(noshi_store_cursor_get(s, 0, &next), NOSHI_OK);
        CHECK_EQ_INT(next.pts, 16);
        CHECK_EQ_INT(next.date, c.date);
    }
    v = noshi_tl_new_obj(&a, "updates.channelDifferenceEmpty");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "pts", 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_flag(v, "final"), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_difference(&u, INT64_C(4294967299), v), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_cursor_get(s, INT64_C(4294967299), &c), NOSHI_OK);
    CHECK_EQ_INT(c.pts, 123);
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    noshi_arena_free(&a);
}

static void test_cached_senders(void) {
    static const char *const kinds[] = {"channel", "channelForbidden", "community", "communityForbidden", "chat"};
    noshi_store *s = NULL;
    noshi_updates u;
    noshi_arena a, read;
    noshi_tl_value *answer, *chats, *empty, *got;
    size_t i;
    noshi_arena_init(&a, 2u * 1024u * 1024u);
    noshi_arena_init(&read, 2u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&s, ":memory:", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, s, 1), NOSHI_OK);
    answer = noshi_tl_new_obj(&a, "messages.messages");
    chats = noshi_tl_new_vec(&a, 5);
    empty = noshi_tl_new_vec(&a, 0);
    for (i = 0; i < 5; ++i) {
        noshi_tl_value *sender = noshi_tl_new_obj(&a, kinds[i]);
        int64_t id = INT64_C(4294967399) + (int64_t)(i % 4);
        CHECK_EQ_INT(noshi_tl_set_i64(&a, sender, "id", id), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_str(&a, sender, "title", kinds[i]), NOSHI_OK);
        if (i != 4) CHECK_EQ_INT(noshi_tl_set_i64(&a, sender, "access_hash", 77), NOSHI_OK);
        if (i == 0 || i == 2 || i == 4) {
            noshi_tl_value *photo = noshi_tl_new_obj(&a, "chatPhoto");
            CHECK_EQ_INT(noshi_tl_set_i64(&a, photo, "photo_id", 900), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set_i32(&a, photo, "dc_id", 4), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set(sender, "photo", photo), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set_i32(&a, sender, "date", 100), NOSHI_OK);
        }
        if (i == 4) {
            CHECK_EQ_INT(noshi_tl_set_i32(&a, sender, "participants_count", 2), NOSHI_OK);
            CHECK_EQ_INT(noshi_tl_set_i32(&a, sender, "version", 1), NOSHI_OK);
        }
        CHECK_EQ_INT(noshi_tl_vec_set(chats, (uint32_t)i, sender), NOSHI_OK);
    }
    CHECK_EQ_INT(noshi_tl_set(answer, "chats", chats), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "users", empty), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "messages", empty), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache(&u, answer), NOSHI_OK);
    for (i = 0; i < 5; ++i) {
        noshi_peer peer = {i == 4 ? 2 : 3, INT64_C(4294967399) + (int64_t)(i % 4)};
        CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_CHAT, peer, peer.id, &read, &got), NOSHI_OK);
        CHECK(noshi_tl_is(got, chats->u.vec.items[i]->u.obj.ctor->id));
        if (i != 4) {
            noshi_person_row row;
            CHECK_EQ_INT(noshi_channel_person_parse(got, &row), NOSHI_OK);
            CHECK_EQ_INT(row.id, peer.id);
            CHECK(!strcmp(row.name, kinds[i]));
            CHECK_EQ_INT(row.photo.photo_id, i == 0 || i == 2 ? 900 : 0);
        }
        if (i > 0 && i < 4) {
            peer.kind = 2;
            CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_CHAT, peer, peer.id, &read, &got), NOSHI_E_NOTFOUND);
        }
    }
    {
        noshi_peer peer = {3, INT64_C(4294967401)};
        noshi_person_row row;
        noshi_tl_value *update = noshi_tl_new_obj(&a, "updates");
        CHECK_EQ_INT(noshi_updates_state(&u, state(&a, 10, 0, 1)), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_str(&a, chats->u.vec.items[2], "title", "Renamed community"), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(update, "chats", chats), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(update, "users", empty), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(update, "updates", empty), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&a, update, "date", 101), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&a, update, "seq", 2), NOSHI_OK);
        CHECK_EQ_INT(noshi_updates_apply(&u, update), NOSHI_OK);
        CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_CHAT, peer, peer.id, &read, &got), NOSHI_OK);
        CHECK_EQ_INT(noshi_channel_person_parse(got, &row), NOSHI_OK);
        CHECK(!strcmp(row.name, "Renamed community"));
    }
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    noshi_arena_free(&a);
    noshi_arena_free(&read);
}

/* a channel seen in part (min) must not replace the whole one the store holds: its photo and its hash are what the avatar is fetched with */
static noshi_tl_value *channel_object(noshi_arena *a, int64_t id, const char *title, int with_hash, int min) {
    noshi_tl_value *channel = noshi_tl_new_obj(a, "channel"), *photo = noshi_tl_new_obj(a, "chatPhoto");
    CHECK_EQ_INT(noshi_tl_set_i64(a, channel, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(a, channel, "title", title), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, channel, "date", 100), NOSHI_OK);
    if (with_hash) CHECK_EQ_INT(noshi_tl_set_i64(a, channel, "access_hash", 77), NOSHI_OK);
    if (min) CHECK_EQ_INT(noshi_tl_set_flag(channel, "min"), NOSHI_OK);
    if (with_hash) {
        CHECK_EQ_INT(noshi_tl_set_i64(a, photo, "photo_id", 900), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(a, photo, "dc_id", 4), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(channel, "photo", photo), NOSHI_OK);
    } else {
        /* the photo field of a channel is not optional, and an empty one is what a stub without a photo carries */
        CHECK_EQ_INT(noshi_tl_set(channel, "photo", noshi_tl_new_obj(a, "chatPhotoEmpty")), NOSHI_OK);
    }
    return channel;
}

static void cache_chat(noshi_updates *u, noshi_arena *a, noshi_tl_value *channel) {
    noshi_tl_value *answer = noshi_tl_new_obj(a, "messages.messages"), *chats = noshi_tl_new_vec(a, 1), *empty = noshi_tl_new_vec(a, 0);
    CHECK_EQ_INT(noshi_tl_vec_set(chats, 0, channel), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "chats", chats), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "users", empty), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "messages", empty), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache(u, answer), NOSHI_OK);
}

static void test_min_keeps_whole(void) {
    noshi_store *s = NULL;
    noshi_updates u;
    noshi_arena a, read;
    noshi_tl_value *got;
    noshi_person_row row;
    noshi_peer whole = {3, INT64_C(4294967500)}, stub = {3, INT64_C(4294967501)};
    noshi_arena_init(&a, 2u * 1024u * 1024u);
    noshi_arena_init(&read, 2u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&s, ":memory:", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, s, 1), NOSHI_OK);
    cache_chat(&u, &a, channel_object(&a, whole.id, "Whole", 1, 0));
    /* the stub of the same channel comes later in a group's messages: the whole one stays, photo and hash with it */
    cache_chat(&u, &a, channel_object(&a, whole.id, "Stub", 0, 1));
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_CHAT, whole, whole.id, &read, &got), NOSHI_OK);
    CHECK_EQ_INT(noshi_channel_person_parse(got, &row), NOSHI_OK);
    CHECK(!strcmp(row.name, "Whole"));
    CHECK_EQ_INT(row.access_hash, 77);
    CHECK_EQ_INT(row.photo.photo_id, 900);
    /* a stub of a channel the store has never held is kept, since it is all there is */
    cache_chat(&u, &a, channel_object(&a, stub.id, "Only a stub", 0, 1));
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_CHAT, stub, stub.id, &read, &got), NOSHI_OK);
    CHECK_EQ_INT(noshi_channel_person_parse(got, &row), NOSHI_OK);
    CHECK(!strcmp(row.name, "Only a stub"));
    CHECK_EQ_INT(row.photo.photo_id, 0);
    /* and a whole object does replace a stub, and another whole one */
    cache_chat(&u, &a, channel_object(&a, stub.id, "Now whole", 1, 0));
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_CHAT, stub, stub.id, &read, &got), NOSHI_OK);
    CHECK_EQ_INT(noshi_channel_person_parse(got, &row), NOSHI_OK);
    CHECK(!strcmp(row.name, "Now whole"));
    CHECK_EQ_INT(row.photo.photo_id, 900);
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    noshi_arena_free(&a);
    noshi_arena_free(&read);
}

/* a voice note that was played elsewhere loses its unplayed mark in the store, and an id the store does not hold is no error */
static void test_contents_read(void) {
    noshi_store *s = NULL;
    noshi_arena a, read;
    noshi_updates u;
    noshi_tl_value *m, *from, *update, *wrapper, *got;
    noshi_peer peer = {1, INT64_C(4294967399)};
    int32_t ids[2] = {7, 99};
    char path[] = "/tmp/noshigram-contents-XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    noshi_arena_init(&a, 8u * 1024u * 1024u);
    noshi_arena_init(&read, 8u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&s, path, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, s, 123), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_state(&u, state(&a, 10, 5, 2)), NOSHI_OK);
    m = noshi_tl_new_obj(&a, "message");
    from = noshi_tl_new_obj(&a, "peerUser");
    CHECK(m && from);
    CHECK_EQ_INT(noshi_tl_set_i64(&a, from, "user_id", peer.id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(m, "peer_id", from), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, m, "id", 7), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, m, "date", 100), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&a, m, "message", ""), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_flag(m, "media_unread"), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_cache_message(&u, m), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_MESSAGE, peer, 7, &read, &got), NOSHI_OK);
    CHECK(noshi_tl_has(got, "media_unread"));
    update = noshi_tl_new_obj(&a, "updateReadMessagesContents");
    CHECK(update != NULL);
    CHECK_EQ_INT(noshi_tl_set_i32_vec(&a, update, "messages", ids, 2), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, update, "pts", 11), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, update, "pts_count", 1), NOSHI_OK);
    wrapper = noshi_tl_new_obj(&a, "updateShort");
    CHECK(wrapper != NULL);
    CHECK_EQ_INT(noshi_tl_set(wrapper, "update", update), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&a, wrapper, "date", 101), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_apply(&u, wrapper), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_MESSAGE, peer, 7, &read, &got), NOSHI_OK);
    CHECK(!noshi_tl_has(got, "media_unread"));
    CHECK_EQ_INT(noshi_tl_get_i32(got, "id", &ids[1]), NOSHI_OK);
    CHECK_EQ_INT(ids[1], 7);
    CHECK_EQ_INT(noshi_tl_clear(got, "no_such_field"), NOSHI_E_NOTFOUND);
    noshi_store_close(s);
    unlink(path);
    noshi_arena_free(&a);
    noshi_arena_free(&read);
}

/* a person who comes online has the stored user updated, so a chat reopened or a list rebuilt does not show the time of the last talk */
static void status_update(noshi_updates *u, noshi_arena *a, int64_t user, noshi_tl_value *status, noshi_status want) {
    noshi_tl_value *wrapper = noshi_tl_new_obj(a, "updateShort"), *update = noshi_tl_new_obj(a, "updateUserStatus");
    CHECK_EQ_INT(noshi_tl_set_i64(a, update, "user_id", user), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(update, "status", status), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(wrapper, "update", update), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, wrapper, "date", 102), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_apply(u, wrapper), want);
}

static void stored_presence(noshi_store *s, noshi_arena *read, int64_t user, noshi_presence want, int32_t want_seen) {
    noshi_peer zero = {0, 0};
    noshi_tl_value *got;
    noshi_presence presence;
    int32_t seen;
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_USER, zero, user, read, &got), NOSHI_OK);
    noshi_presence_read(noshi_tl_get(got, "status"), &presence, &seen);
    CHECK_EQ_INT(presence, want);
    CHECK_EQ_INT(seen, want_seen);
}

static void test_user_status(void) {
    noshi_store *s = NULL;
    noshi_updates u;
    noshi_arena a, read;
    noshi_peer zero = {0, 0};
    noshi_tl_value *user, *offline, *online, *left;
    noshi_arena_init(&a, 2u * 1024u * 1024u);
    noshi_arena_init(&read, 2u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_store_open(&s, ":memory:", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_init(&u, s, 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_updates_state(&u, state(&a, 10, 5, 2)), NOSHI_OK);
    user = noshi_tl_new_obj(&a, "user");
    CHECK_EQ_INT(noshi_tl_set_i64(&a, user, "id", 7), NOSHI_OK);
    offline = noshi_tl_new_obj(&a, "userStatusOffline");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, offline, "was_online", 100), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(user, "status", offline), NOSHI_OK);
    CHECK_EQ_INT(noshi_store_put(s, NOSHI_RECORD_USER, zero, 7, user), NOSHI_OK);
    stored_presence(s, &read, 7, NOSHI_PRESENCE_OFFLINE, 100);
    online = noshi_tl_new_obj(&a, "userStatusOnline");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, online, "expires", 400), NOSHI_OK);
    status_update(&u, &a, 7, online, NOSHI_OK);
    stored_presence(s, &read, 7, NOSHI_PRESENCE_ONLINE, 0);
    left = noshi_tl_new_obj(&a, "userStatusOffline");
    CHECK_EQ_INT(noshi_tl_set_i32(&a, left, "was_online", 500), NOSHI_OK);
    status_update(&u, &a, 7, left, NOSHI_OK);
    stored_presence(s, &read, 7, NOSHI_PRESENCE_OFFLINE, 500);
    /* a user the store does not hold needs nothing: it arrives whole with its status when it is wanted */
    status_update(&u, &a, 99, online, NOSHI_OK);
    CHECK_EQ_INT(noshi_store_get(s, NOSHI_RECORD_USER, zero, 99, &read, &user), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_store_close(s), NOSHI_OK);
    noshi_arena_free(&a);
    noshi_arena_free(&read);
}

int main(void) {
    test_user_status();
    test_contents_read();
    test_min_keeps_whole();
    test_atomic();
    test_difference();
    test_cached_senders();
    return test_finish("test_store_updates");
}
