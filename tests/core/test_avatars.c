#include "noshi_avatars.h"
#include "noshi_tl_ids.h"
#include "test_util.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void set(noshi_tl_value *v, const char *f, noshi_tl_value *x) { CHECK_EQ_INT(noshi_tl_set(v, f, x), NOSHI_OK); }
static void set_i32(noshi_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, f, x), NOSHI_OK); }
static void set_i64(noshi_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, f, x), NOSHI_OK); }

static noshi_tl_value *vec_of(noshi_tl_value **items, uint32_t n) {
    noshi_tl_value *v = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(v != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(v, i, items[i]), NOSHI_OK);
    return v;
}

static noshi_tl_value *size(const char *type, int32_t w, int32_t h) {
    noshi_tl_value *s = obj("photoSize");
    CHECK_EQ_INT(noshi_tl_set_str(&arena, s, "type", type), NOSHI_OK);
    set_i32(s, "w", w);
    set_i32(s, "h", h);
    set_i32(s, "size", w * h / 10);
    return s;
}

static noshi_tl_value *photo(int64_t id) {
    noshi_tl_value *p = obj("photo"), *sizes[3];
    set_i64(p, "id", id);
    set_i64(p, "access_hash", id * 3);
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, p, "file_reference", "ref", 3), NOSHI_OK);
    set_i32(p, "date", 10);
    sizes[0] = size("m", 320, 320);
    sizes[1] = size("x", 800, 800);
    sizes[2] = size("y", 1280, 1280);
    set(p, "sizes", vec_of(sizes, 3));
    set_i32(p, "dc_id", 2);
    return p;
}

static noshi_peer_ref peer(int32_t kind, int64_t id, int64_t hash, int self) {
    noshi_peer_ref r;
    memset(&r, 0, sizeof(r));
    r.kind = kind;
    r.id = id;
    r.access_hash = hash;
    r.self = (uint8_t)self;
    return r;
}

static void roundtrip(noshi_tl_value *request, uint32_t id) {
    noshi_writer writer;
    noshi_tl_value *decoded = NULL;
    CHECK(request != NULL);
    noshi_writer_init(&writer, 65536);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, writer.data, writer.len, &decoded), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(decoded), id);
    noshi_writer_free(&writer);
}

static void requests(void) {
    noshi_peer_ref other = peer(1, 77, 5, 0), self = peer(1, 0, 0, 1), group = peer(2, 9, 0, 0), nohash = peer(1, 77, 0, 0);
    noshi_tl_value *request = NULL;
    CHECK_EQ_INT(noshi_user_photos_request(&arena, &other, NOSHI_AVATARS_MAX, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_photos_getUserPhotos);
    CHECK_EQ_INT(noshi_user_photos_request(&arena, &self, 1, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_photos_getUserPhotos);
    CHECK_EQ_INT(noshi_user_photos_request(&arena, &group, 10, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_user_photos_request(&arena, &nohash, 10, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_user_photos_request(&arena, &other, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_user_photos_request(&arena, &other, NOSHI_AVATARS_MAX + 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_user_photos_request(&arena, NULL, 10, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_user_photos_request(&arena, &other, 10, NULL), NOSHI_E_ARG);

    group = peer(2, 9, 0, 0);
    CHECK_EQ_INT(noshi_chat_photos_request(&arena, &group, 20, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_messages_search);
    CHECK_EQ_INT(noshi_chat_photos_request(&arena, &group, 0, &request), NOSHI_E_ARG);
}

static void user_answers(void) {
    noshi_media_info photos[4];
    noshi_tl_value *items[3], *answer = obj("photos.photosSlice");
    size_t count = 99;
    int32_t total = 99;

    items[0] = photo(11);
    items[1] = obj("photoEmpty");
    set_i64(items[1], "id", 12);
    items[2] = photo(13);
    set_i32(answer, "count", 8);
    set(answer, "photos", vec_of(items, 3));
    CHECK_EQ_INT(noshi_user_avatars_parse(answer, photos, 4, &count, &total), NOSHI_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(total, 8);
    CHECK_EQ_INT(photos[0].ref.id, 11);
    CHECK_EQ_INT(photos[0].ref.source, NOSHI_MEDIA_SOURCE_PHOTO);
    CHECK(!strcmp(photos[0].ref.thumb, "y"));
    CHECK_EQ_INT(photos[1].ref.id, 13);

    /* the whole list fits in a plain answer, whose total is its length; room for one cuts it */
    answer = obj("photos.photos");
    set(answer, "photos", vec_of(items, 3));
    CHECK_EQ_INT(noshi_user_avatars_parse(answer, photos, 1, &count, &total), NOSHI_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(total, 3);
    CHECK_EQ_INT(noshi_user_avatars_parse(answer, photos, 0, &count, &total), NOSHI_OK);
    CHECK_EQ_INT(count, 0);

    CHECK_EQ_INT(noshi_user_avatars_parse(obj("photos.photosSlice"), photos, 4, &count, &total), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(total, 0);
    answer = obj("photos.photosSlice");
    set(answer, "photos", vec_of(items, 1));
    CHECK_EQ_INT(noshi_user_avatars_parse(answer, photos, 4, &count, &total), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_user_avatars_parse(obj("boolTrue"), photos, 4, &count, &total), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_user_avatars_parse(NULL, photos, 4, &count, &total), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_user_avatars_parse(answer, photos, 4, NULL, &total), NOSHI_E_ARG);
}

static noshi_tl_value *service(const char *action_name, noshi_tl_value *p) {
    noshi_tl_value *m = obj("messageService"), *action = obj(action_name);
    if (p) set(action, "photo", p);
    set(m, "action", action);
    return m;
}

static void chat_answers(void) {
    noshi_media_info photos[4];
    noshi_tl_value *items[4], *answer;
    size_t count = 99;

    items[0] = service("messageActionChatEditPhoto", photo(21));
    items[1] = service("messageActionChatEditTitle", NULL);
    items[2] = obj("message");
    items[3] = service("messageActionChatEditPhoto", photo(22));
    answer = obj("messages.channelMessages");
    set(answer, "messages", vec_of(items, 4));
    CHECK_EQ_INT(noshi_chat_avatars_parse(answer, photos, 4, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(photos[0].ref.id, 21);
    CHECK_EQ_INT(photos[1].ref.id, 22);
    CHECK_EQ_INT(noshi_chat_avatars_parse(answer, photos, 1, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 1);

    /* a photo that was deleted is an empty one and leaves no page */
    items[0] = service("messageActionChatEditPhoto", obj("photoEmpty"));
    answer = obj("messages.messages");
    set(answer, "messages", vec_of(items, 1));
    CHECK_EQ_INT(noshi_chat_avatars_parse(answer, photos, 4, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 0);

    CHECK_EQ_INT(noshi_chat_avatars_parse(obj("messages.messagesNotModified"), photos, 4, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_chat_avatars_parse(obj("messages.messages"), photos, 4, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_chat_avatars_parse(answer, photos, 4, NULL), NOSHI_E_ARG);
}

int main(void) {
    noshi_arena_init(&arena, 1u << 20);
    requests();
    user_answers();
    chat_answers();
    noshi_arena_free(&arena);
    return test_finish("test_avatars");
}
