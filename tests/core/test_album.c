#include "test_util.h"
#include "noshi_messages.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static noshi_upload_spec spec(noshi_upload_kind kind) {
    noshi_upload_spec s;
    memset(&s, 0, sizeof(s));
    s.kind = kind;
    s.duration_ms = 4000;
    s.width = 640;
    s.height = 480;
    return s;
}

static void test_shared(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref group = {2, 600, 0, 0, 0}, channel = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    int32_t value = 0;
    CHECK_EQ_INT(noshi_shared_request(&arena, &channel, NOSHI_SHARED_MEDIA, 0, 60, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_search);
    CHECK(noshi_tl_is(noshi_tl_get(request, "filter"), NOSHI_TL_ID_inputMessagesFilterPhotoVideo));
    CHECK_EQ_INT(noshi_tl_get_i32(request, "offset_id", &value), NOSHI_OK);
    CHECK_EQ_INT(value, 0);
    CHECK_EQ_INT(noshi_shared_request(&arena, &group, NOSHI_SHARED_FILES, 40, 60, &request), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "filter"), NOSHI_TL_ID_inputMessagesFilterDocument));
    CHECK_EQ_INT(noshi_tl_get_i32(request, "offset_id", &value), NOSHI_OK);
    CHECK_EQ_INT(value, 40);
    CHECK_EQ_INT(noshi_shared_request(&arena, &group, NOSHI_SHARED_LINKS, 0, 60, &request), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "filter"), NOSHI_TL_ID_inputMessagesFilterUrl));
    CHECK_EQ_INT(noshi_shared_request(&arena, &channel, NOSHI_SHARED_AUDIO, 0, 30, &request), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "filter"), NOSHI_TL_ID_inputMessagesFilterMusic));
    CHECK_EQ_INT(noshi_shared_request(&arena, &channel, (noshi_shared_kind)7, 0, 60, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_shared_request(&arena, &channel, NOSHI_SHARED_MEDIA, -1, 60, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_shared_request(&arena, &channel, NOSHI_SHARED_MEDIA, 0, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_shared_request(&arena, &nohash, NOSHI_SHARED_MEDIA, 0, 60, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_own_messages_request(&arena, &channel, 0, 100, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_search);
    CHECK(noshi_tl_is(noshi_tl_get(request, "filter"), NOSHI_TL_ID_inputMessagesFilterEmpty));
    CHECK(noshi_tl_is(noshi_tl_get(request, "from_id"), NOSHI_TL_ID_inputPeerSelf));
    CHECK(!noshi_tl_has(request, "top_msg_id"));
    {
        noshi_peer_ref topic = {3, 500, 7, 0, 0};
        topic.topic_id = 12;
        CHECK_EQ_INT(noshi_own_messages_request(&arena, &topic, 40, 50, &request), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_get_i32(request, "top_msg_id", &value), NOSHI_OK);
        CHECK_EQ_INT(value, 12);
        CHECK_EQ_INT(noshi_tl_get_i32(request, "offset_id", &value), NOSHI_OK);
        CHECK_EQ_INT(value, 40);
    }
    CHECK_EQ_INT(noshi_own_messages_request(&arena, &channel, -1, 100, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_own_messages_request(&arena, &channel, 0, 101, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_own_messages_request(&arena, &nohash, 0, 100, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_shared_oldest_request(&arena, &channel, NOSHI_SHARED_AUDIO, 1, &request), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "filter"), NOSHI_TL_ID_inputMessagesFilterMusic));
    CHECK_EQ_INT(noshi_tl_get_i32(request, "offset_id", &value), NOSHI_OK);
    CHECK_EQ_INT(value, 1);
    CHECK_EQ_INT(noshi_tl_get_i32(request, "add_offset", &value), NOSHI_OK);
    CHECK_EQ_INT(value, -1);
    CHECK_EQ_INT(noshi_tl_get_i32(request, "limit", &value), NOSHI_OK);
    CHECK_EQ_INT(value, 1);
    CHECK_EQ_INT(noshi_shared_oldest_request(&arena, &channel, NOSHI_SHARED_AUDIO, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_shared_oldest_request(&arena, &nohash, NOSHI_SHARED_AUDIO, 1, &request), NOSHI_E_ARG);
}

static void test_upload(void) {
    noshi_tl_value *request = NULL, *file = obj("inputFile"), *answer_value, *photo;
    noshi_peer_ref channel = {3, 500, 7, 0, 0};
    noshi_upload_spec photo_spec = spec(NOSHI_UPLOAD_PHOTO), video_spec = spec(NOSHI_UPLOAD_VIDEO), voice_spec = spec(NOSHI_UPLOAD_VOICE);
    noshi_album_media media;
    const uint8_t ref[3] = {4, 5, 6};
    CHECK_EQ_INT(noshi_album_upload_request(&arena, &channel, file, &photo_spec, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_uploadMedia);
    CHECK(noshi_tl_is(noshi_tl_get(request, "media"), NOSHI_TL_ID_inputMediaUploadedPhoto));
    CHECK_EQ_INT(noshi_album_upload_request(&arena, &channel, file, &video_spec, &request), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "media"), NOSHI_TL_ID_inputMediaUploadedDocument));
    /* a voice message or a file is not an album item */
    CHECK_EQ_INT(noshi_album_upload_request(&arena, &channel, file, &voice_spec, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_album_upload_request(&arena, &channel, NULL, &photo_spec, &request), NOSHI_E_ARG);
    /* the answer */
    answer_value = obj("messageMediaPhoto");
    photo = obj("photo");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, photo, "id", 31), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, photo, "access_hash", 32), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, photo, "file_reference", ref, 3), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer_value, "photo", photo), NOSHI_OK);
    CHECK_EQ_INT(noshi_album_media_parse(answer_value, &media), NOSHI_OK);
    CHECK_EQ_INT(media.is_photo, 1);
    CHECK_EQ_INT(media.id, 31);
    CHECK_EQ_INT(media.file_reference_len, 3);
    CHECK_EQ_INT(noshi_album_media_parse(obj("messageMediaEmpty"), &media), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(media.id, 0);
    CHECK_EQ_INT(noshi_album_media_parse(NULL, &media), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_album_media_parse(answer_value, NULL), NOSHI_E_ARG);
}

static void test_send(void) {
    noshi_tl_value *request = NULL;
    noshi_peer_ref channel = {3, 500, 7, 0, 0}, topic = {3, 500, 7, 0, 12}, nohash = {3, 500, 0, 0, 0};
    noshi_album_media items[3];
    int64_t ids[3] = {101, 102, 103}, same[3] = {101, 102, 101};
    const char *captions[3] = {"first", NULL, ""};
    const noshi_tl_value *list;
    noshi_writer wire;
    memset(items, 0, sizeof(items));
    items[0].is_photo = 1;
    items[0].id = 1;
    items[1].id = 2;
    items[2].is_photo = 1;
    items[2].id = 3;
    CHECK_EQ_INT(noshi_album_send_request(&arena, &channel, items, ids, captions, 3, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_sendMultiMedia);
    CHECK_EQ_INT(noshi_tl_get_vec(request, "multi_media", &list), NOSHI_OK);
    CHECK_EQ_INT(list->u.vec.count, 3);
    noshi_writer_init(&wire, 4096);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_album_send_request(&arena, &topic, items, ids, NULL, 2, &request), NOSHI_OK);
    CHECK(noshi_tl_has(request, "reply_to"));
    CHECK(!noshi_tl_has(noshi_tl_get(list->u.vec.items[0], "media"), "spoiler"));
    items[1].spoiler = 1;
    CHECK_EQ_INT(noshi_album_send_request(&arena, &channel, items, ids, NULL, 3, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_get_vec(request, "multi_media", &list), NOSHI_OK);
    CHECK(!noshi_tl_has(noshi_tl_get(list->u.vec.items[0], "media"), "spoiler"));
    CHECK(noshi_tl_has(noshi_tl_get(list->u.vec.items[1], "media"), "spoiler"));
    items[1].spoiler = 0;
    CHECK_EQ_INT(noshi_album_send_request(&arena, &topic, items, ids, NULL, 2, &request), NOSHI_OK);
    /* an album is two or more, ten at most, with a random id for each that is not zero and not repeated */
    CHECK_EQ_INT(noshi_album_send_request(&arena, &channel, items, ids, NULL, 1, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_album_send_request(&arena, &channel, items, ids, NULL, NOSHI_ALBUM_ITEMS_MAX + 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_album_send_request(&arena, &channel, items, same, NULL, 3, &request), NOSHI_E_ARG);
    ids[1] = 0;
    CHECK_EQ_INT(noshi_album_send_request(&arena, &channel, items, ids, NULL, 3, &request), NOSHI_E_ARG);
    ids[1] = 102;
    items[2].id = 0;
    CHECK_EQ_INT(noshi_album_send_request(&arena, &channel, items, ids, NULL, 3, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_album_send_request(&arena, &nohash, items, ids, NULL, 2, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_album_send_request(&arena, NULL, items, ids, NULL, 2, &request), NOSHI_E_ARG);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_shared();
    test_upload();
    test_send();
    noshi_arena_free(&arena);
    return test_finish("test_album");
}
