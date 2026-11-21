#include "test_util.h"
#include "noshi_messages.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static noshi_tl_value *document(int64_t id, int animated, int sticker) {
    noshi_tl_value *doc = obj("document"), *attributes = noshi_tl_new_vec(&arena, 1), *attribute;
    const uint8_t ref[2] = {5, 6};
    CHECK(attributes != NULL);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, doc, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, doc, "access_hash", 99), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, doc, "file_reference", ref, 2), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, doc, "dc_id", 2), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, doc, "mime_type", "video/mp4"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, doc, "size", 1000), NOSHI_OK);
    attribute = obj(sticker ? "documentAttributeSticker" : (animated ? "documentAttributeAnimated" : "documentAttributeFilename"));
    if (sticker) CHECK_EQ_INT(noshi_tl_set_str(&arena, attribute, "alt", "x"), NOSHI_OK);
    if (!animated && !sticker) CHECK_EQ_INT(noshi_tl_set_str(&arena, attribute, "file_name", "a.mp4"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(attributes, 0, attribute), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(doc, "attributes", attributes), NOSHI_OK);
    return doc;
}

static void test_saved_gifs(void) {
    noshi_sticker_row rows[4];
    size_t count;
    noshi_tl_value *answer_value = obj("messages.savedGifs"), *list = noshi_tl_new_vec(&arena, 3), *request = NULL;
    CHECK_EQ_INT(noshi_saved_gifs_request(&arena, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_getSavedGifs);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 0, document(10, 1, 0)), NOSHI_OK);
    /* a video that is no animation and a sticker are not gifs */
    CHECK_EQ_INT(noshi_tl_vec_set(list, 1, document(11, 0, 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 2, document(12, 1, 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer_value, "gifs", list), NOSHI_OK);
    CHECK_EQ_INT(noshi_saved_gifs_parse(answer_value, rows, 4, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].media.kind, NOSHI_PREVIEW_GIF);
    CHECK_EQ_INT(rows[0].media.ref.id, 10);
    CHECK_EQ_INT(rows[1].media.ref.id, 12);
    CHECK_EQ_INT(noshi_saved_gifs_parse(answer_value, rows, 1, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(noshi_saved_gifs_parse(obj("messages.savedGifsNotModified"), rows, 4, &count), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_saved_gifs_parse(NULL, rows, 4, &count), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_saved_gifs_parse(answer_value, rows, 0, &count), NOSHI_E_ARG);
}

static void test_animation_without_thumbnail(void) {
    noshi_media_info media;
    noshi_tl_value *doc = document(50, 1, 0);
    noshi_tl_value *attributes = noshi_tl_new_vec(&arena, 2), *video = obj("documentAttributeVideo");
    CHECK(attributes != NULL);
    CHECK_EQ_INT(noshi_tl_set_f64(&arena, video, "duration", 1.0), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, video, "w", 320), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, video, "h", 240), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(attributes, 0, video), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(attributes, 1, obj("documentAttributeAnimated")), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(doc, "attributes", attributes), NOSHI_OK);
    noshi_document_read(doc, &media);
    CHECK_EQ_INT(media.kind, NOSHI_PREVIEW_GIF);
    CHECK_EQ_INT(media.duration, 1);
    CHECK_EQ_INT(media.width, 320);
    CHECK_EQ_INT(media.height, 240);
    CHECK_EQ_INT(media.ref.source, NOSHI_MEDIA_SOURCE_DOCUMENT);
    CHECK_EQ_INT(media.ref.id, 50);
    CHECK_EQ_INT(media.preview.source, NOSHI_MEDIA_SOURCE_NONE);
    CHECK(noshi_media_uses_picture(media.kind, media.ref.source != NOSHI_MEDIA_SOURCE_NONE,
                                    media.preview.source != NOSHI_MEDIA_SOURCE_NONE, 0));
    /* the same download and playback path also needs room when dimensions are absent */
    doc = document(51, 1, 0);
    noshi_document_read(doc, &media);
    CHECK_EQ_INT(media.width, 0);
    CHECK_EQ_INT(media.height, 0);
    CHECK(noshi_media_uses_picture(media.kind, media.ref.source != NOSHI_MEDIA_SOURCE_NONE, 0, 0));
}

static void test_picture_sources(void) {
    static const struct {
        noshi_preview_kind kind;
        int file;
        int preview;
        int local;
        int picture;
    } cases[] = {
        {NOSHI_PREVIEW_GIF, 1, 0, 0, 1},
        {NOSHI_PREVIEW_GIF, 1, 1, 0, 1},
        {NOSHI_PREVIEW_GIF, 0, 1, 0, 1},
        {NOSHI_PREVIEW_GIF, 0, 0, 1, 1},
        {NOSHI_PREVIEW_GIF, 0, 0, 0, 0},
        {NOSHI_PREVIEW_VIDEO, 1, 0, 0, 1},
        {NOSHI_PREVIEW_VIDEO, 0, 1, 0, 1},
        {NOSHI_PREVIEW_VIDEO, 0, 0, 0, 0},
        {NOSHI_PREVIEW_VIDEO_MESSAGE, 1, 0, 0, 1},
        {NOSHI_PREVIEW_PHOTO, 1, 0, 0, 1},
        {NOSHI_PREVIEW_PHOTO, 0, 0, 1, 1},
        {NOSHI_PREVIEW_PHOTO, 0, 1, 0, 0},
        {NOSHI_PREVIEW_FILE, 1, 1, 0, 0},
        {NOSHI_PREVIEW_AUDIO, 1, 1, 0, 0},
        {NOSHI_PREVIEW_VOICE, 1, 1, 0, 0},
        {NOSHI_PREVIEW_STICKER, 1, 1, 0, 0},
        {NOSHI_PREVIEW_NONE, 0, 0, 0, 0},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        CHECK_EQ_INT(noshi_media_uses_picture(cases[i].kind, cases[i].file, cases[i].preview, cases[i].local), cases[i].picture);
    }
}

static void test_viewer_kinds(void) {
    CHECK(noshi_media_opens_viewer(NOSHI_PREVIEW_PHOTO));
    CHECK(noshi_media_opens_viewer(NOSHI_PREVIEW_VIDEO));
    CHECK(!noshi_media_opens_viewer(NOSHI_PREVIEW_GIF));
    CHECK(!noshi_media_opens_viewer(NOSHI_PREVIEW_VIDEO_MESSAGE));
    CHECK(!noshi_media_opens_viewer(NOSHI_PREVIEW_STICKER));
    CHECK(!noshi_media_opens_viewer(NOSHI_PREVIEW_FILE));
    CHECK(!noshi_media_opens_viewer(NOSHI_PREVIEW_AUDIO));
    CHECK(!noshi_media_opens_viewer(NOSHI_PREVIEW_VOICE));
    CHECK(!noshi_media_opens_viewer(NOSHI_PREVIEW_NONE));
    CHECK(!noshi_media_opens_viewer((noshi_preview_kind)-1));
}

static void test_faved(void) {
    noshi_sticker_row rows[4];
    size_t count;
    noshi_tl_value *answer_value = obj("messages.favedStickers"), *list = noshi_tl_new_vec(&arena, 2), *request = NULL;
    noshi_media_ref ref;
    noshi_writer wire;
    CHECK_EQ_INT(noshi_faved_stickers_request(&arena, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_getFavedStickers);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 0, document(20, 0, 1)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 1, document(21, 1, 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer_value, "stickers", list), NOSHI_OK);
    CHECK_EQ_INT(noshi_faved_stickers_parse(answer_value, rows, 4, &count), NOSHI_OK);
    /* only the sticker is read as one */
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].media.ref.id, 20);
    CHECK_EQ_INT(noshi_faved_stickers_parse(obj("messages.favedStickersNotModified"), rows, 4, &count), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_faved_stickers_parse(obj("boolTrue"), rows, 4, &count), NOSHI_E_MALFORMED);
    ref = rows[0].media.ref;
    CHECK_EQ_INT(noshi_fave_sticker_request(&arena, &ref, 0, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_faveSticker);
    CHECK(noshi_tl_is(noshi_tl_get(request, "unfave"), NOSHI_TL_ID_boolFalse));
    noshi_writer_init(&wire, 1024);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_fave_sticker_request(&arena, &ref, 1, &request), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request, "unfave"), NOSHI_TL_ID_boolTrue));
    /* a thumbnail of a sticker or a file with no source cannot be faved */
    ref.thumb[0] = 'm';
    CHECK_EQ_INT(noshi_fave_sticker_request(&arena, &ref, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    ref.thumb[0] = 0;
    ref.source = 0;
    CHECK_EQ_INT(noshi_fave_sticker_request(&arena, &ref, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_fave_sticker_request(&arena, NULL, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_clear_recent_stickers_request(&arena, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_clearRecentStickers);
    CHECK_EQ_INT(noshi_clear_recent_stickers_request(&arena, NULL), NOSHI_E_ARG);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_saved_gifs();
    test_animation_without_thumbnail();
    test_picture_sources();
    test_viewer_kinds();
    test_faved();
    noshi_arena_free(&arena);
    return test_finish("test_gifs");
}
