#include "test_util.h"
#include "noshi_messages.h"
#include "noshi_tl_ids.h"

static void check_caption(noshi_arena *arena, const noshi_peer_ref *peer, noshi_upload_spec *spec, const char *text) {
    noshi_tl_value *file = noshi_tl_new_obj(arena, "inputFile"), *request = NULL;
    const uint8_t *bytes = NULL;
    size_t length = 0;
    CHECK(file != NULL);
    CHECK_EQ_INT(noshi_tl_set_i64(arena, file, "id", 44), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(arena, file, "parts", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(arena, file, "name", "photo.jpg"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(arena, file, "md5_checksum", ""), NOSHI_OK);
    snprintf(spec->caption, sizeof(spec->caption), "%s", text);
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, spec, 52, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_get_bytes(request, "message", &bytes, &length), NOSHI_OK);
    CHECK_EQ_INT(length, strlen(text));
    CHECK_MEM(bytes, text, length);
    noshi_writer writer;
    noshi_writer_init(&writer, 8192);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    CHECK(writer.len > length);
    noshi_writer_free(&writer);
    const noshi_tl_value *reply = noshi_tl_get(request, "reply_to");
    int32_t id = 0;
    CHECK_EQ_INT(noshi_tl_get_i32(reply, "reply_to_msg_id", &id), NOSHI_OK);
    CHECK_EQ_INT(id, peer->topic_id);
    memset(spec->caption, 'a', sizeof(spec->caption));
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, spec, 52, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
}

/* the spoiler flag reaches the media of a photo and of a video, and of nothing else */
static void check_spoiler(noshi_arena *arena, const noshi_peer_ref *peer, noshi_upload_spec *spec, int expected) {
    noshi_tl_value *file = noshi_tl_new_obj(arena, "inputFile"), *request = NULL;
    CHECK_EQ_INT(noshi_tl_set_i64(arena, file, "id", 44), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(arena, file, "parts", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(arena, file, "name", "photo.jpg"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(arena, file, "md5_checksum", ""), NOSHI_OK);
    spec->caption[0] = 0;
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, spec, 52, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(noshi_tl_get(request, "media"), "spoiler"), expected);
}

/* a song sent as a file carries an audio attribute that is not a voice note, its text and its seconds, and is not forced to be a file */
static void check_music(noshi_arena *arena, const noshi_peer_ref *peer) {
    noshi_tl_value *file = noshi_tl_new_obj(arena, "inputFile"), *request = NULL;
    CHECK_EQ_INT(noshi_tl_set_i64(arena, file, "id", 45), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(arena, file, "parts", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(arena, file, "name", "song.mp3"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(arena, file, "md5_checksum", ""), NOSHI_OK);
    noshi_upload_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.kind = NOSHI_UPLOAD_FILE;
    spec.music = 1;
    spec.duration_ms = 215400;
    snprintf(spec.name, sizeof(spec.name), "song.mp3");
    snprintf(spec.mime, sizeof(spec.mime), "audio/mpeg");
    snprintf(spec.title, sizeof(spec.title), "Название");
    snprintf(spec.performer, sizeof(spec.performer), "Artist");
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, &spec, 53, &request), NOSHI_OK);
    const noshi_tl_value *media = noshi_tl_get(request, "media"), *attributes = noshi_tl_get(media, "attributes");
    CHECK(attributes && attributes->u.vec.count == 2);
    CHECK(noshi_tl_is(attributes->u.vec.items[0], NOSHI_TL_ID_documentAttributeFilename));
    const noshi_tl_value *song = attributes->u.vec.items[1];
    CHECK(noshi_tl_is(song, NOSHI_TL_ID_documentAttributeAudio));
    CHECK(!noshi_tl_has(song, "voice"));
    int32_t seconds = 0;
    const uint8_t *text = NULL;
    size_t length = 0;
    CHECK_EQ_INT(noshi_tl_get_i32(song, "duration", &seconds), NOSHI_OK);
    CHECK_EQ_INT(seconds, 215);
    CHECK_EQ_INT(noshi_tl_get_bytes(song, "title", &text, &length), NOSHI_OK);
    CHECK(length == strlen("Название") && memcmp(text, "Название", length) == 0);
    CHECK_EQ_INT(noshi_tl_get_bytes(song, "performer", &text, &length), NOSHI_OK);
    CHECK(length == 6 && memcmp(text, "Artist", 6) == 0);
    CHECK(!noshi_tl_has(media, "force_file"));
    noshi_writer writer;
    noshi_writer_init(&writer, 8192);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    noshi_writer_free(&writer);
    /* a song without a performer leaves the field out */
    spec.performer[0] = 0;
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, &spec, 53, &request), NOSHI_OK);
    song = noshi_tl_get(noshi_tl_get(request, "media"), "attributes")->u.vec.items[1];
    CHECK(!noshi_tl_has(song, "performer") && noshi_tl_has(song, "title"));
    /* only an audio file can be a song, and not a gif, a photo or a voice note */
    snprintf(spec.mime, sizeof(spec.mime), "image/jpeg");
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, &spec, 53, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    snprintf(spec.mime, sizeof(spec.mime), "audio/mpeg");
    spec.kind = NOSHI_UPLOAD_PHOTO;
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, &spec, 53, &request), NOSHI_E_ARG);
    spec.kind = NOSHI_UPLOAD_FILE;
    spec.duration_ms = -1;
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, &spec, 53, &request), NOSHI_E_ARG);
    /* a file that is not a song keeps the forced file mode */
    memset(&spec, 0, sizeof(spec));
    spec.kind = NOSHI_UPLOAD_FILE;
    snprintf(spec.name, sizeof(spec.name), "a.zip"); snprintf(spec.mime, sizeof(spec.mime), "application/zip");
    CHECK_EQ_INT(noshi_send_upload_request(arena, peer, file, &spec, 53, &request), NOSHI_OK);
    CHECK(noshi_tl_has(noshi_tl_get(request, "media"), "force_file"));
}

int main(void) {
    noshi_arena arena;
    noshi_arena_init(&arena, 1024 * 1024);
    noshi_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = 3; peer.id = 12; peer.access_hash = 34; peer.topic_id = 56;
    noshi_upload_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.kind = NOSHI_UPLOAD_PHOTO;
    check_caption(&arena, &peer, &spec, "");
    check_caption(&arena, &peer, &spec, "Фото 🌅\nвторая строка");
    char maximum[NOSHI_UPLOAD_CAPTION_MAX + 1];
    memset(maximum, 'x', sizeof(maximum) - 1); maximum[sizeof(maximum) - 1] = 0;
    check_caption(&arena, &peer, &spec, maximum);
    spec.kind = NOSHI_UPLOAD_VIDEO; spec.duration_ms = 1000; spec.width = 640; spec.height = 480;
    check_caption(&arena, &peer, &spec, "Видео 🎥");
    spec.spoiler = 1;
    check_spoiler(&arena, &peer, &spec, 1);
    spec.kind = NOSHI_UPLOAD_PHOTO; spec.duration_ms = 0; spec.width = 0; spec.height = 0;
    check_spoiler(&arena, &peer, &spec, 1);
    spec.spoiler = 0;
    check_spoiler(&arena, &peer, &spec, 0);
    /* a file has no blurred mode, so the flag is left off even when asked for */
    spec.kind = NOSHI_UPLOAD_FILE; spec.spoiler = 1;
    snprintf(spec.name, sizeof(spec.name), "a.jpg"); snprintf(spec.mime, sizeof(spec.mime), "image/jpeg");
    check_spoiler(&arena, &peer, &spec, 0);
    check_music(&arena, &peer);
    noshi_arena_free(&arena);
    return test_finish("test_media_caption");
}
