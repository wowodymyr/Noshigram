#include "test_util.h"
#include "noshi_dialogs.h"
#include "noshi_people.h"
#include "noshi_photos.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set_i32(noshi_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, f, x), NOSHI_OK); }
static void set_i64(noshi_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, f, x), NOSHI_OK); }
static void set_flag(noshi_tl_value *v, const char *f) { CHECK_EQ_INT(noshi_tl_set_flag(v, f), NOSHI_OK); }
static void set(noshi_tl_value *v, const char *f, noshi_tl_value *x) { CHECK_EQ_INT(noshi_tl_set(v, f, x), NOSHI_OK); }

static noshi_tl_value *photo(const char *ctor, int64_t id, int32_t dc) {
    noshi_tl_value *p = obj(ctor);
    set_i64(p, "photo_id", id);
    set_i32(p, "dc_id", dc);
    return p;
}

static void test_read(void) {
    noshi_photo_ref ref;
    noshi_tl_value *user = obj("user"), *chat = obj("chat"), *channel = obj("channel");
    set_i64(user, "id", 5);
    set_i64(user, "access_hash", -77);
    set(user, "photo", photo("userProfilePhoto", 900, 4));
    CHECK_EQ_INT(noshi_photo_ref_read(user, 1, 5, &ref), 1);
    CHECK_EQ_INT(ref.photo_id, 900);
    CHECK_EQ_INT(ref.dc, 4);
    CHECK_EQ_INT(ref.access_hash, -77);
    CHECK_EQ_INT(ref.peer_kind, 1);

    /* a basic group needs no hash */
    set(chat, "photo", photo("chatPhoto", 11, 2));
    CHECK_EQ_INT(noshi_photo_ref_read(chat, 2, 8, &ref), 1);
    CHECK_EQ_INT(ref.access_hash, 0);

    /* a channel without a hash, or seen in part, cannot be fetched */
    set(channel, "photo", photo("chatPhoto", 12, 2));
    CHECK_EQ_INT(noshi_photo_ref_read(channel, 3, 9, &ref), 0);
    CHECK_EQ_INT(ref.photo_id, 0);
    set_i64(channel, "access_hash", 3);
    CHECK_EQ_INT(noshi_photo_ref_read(channel, 3, 9, &ref), 1);
    set_flag(channel, "min");
    CHECK_EQ_INT(noshi_photo_ref_read(channel, 3, 9, &ref), 0);

    set(user, "photo", obj("userProfilePhotoEmpty"));
    CHECK_EQ_INT(noshi_photo_ref_read(user, 1, 5, &ref), 0);
    set(user, "photo", photo("userProfilePhoto", 0, 4));
    CHECK_EQ_INT(noshi_photo_ref_read(user, 1, 5, &ref), 0);
    set(user, "photo", photo("userProfilePhoto", 5, 0));
    CHECK_EQ_INT(noshi_photo_ref_read(user, 1, 5, &ref), 0);
    CHECK_EQ_INT(noshi_photo_ref_read(NULL, 1, 5, &ref), 0);
    CHECK_EQ_INT(noshi_photo_ref_read(user, 4, 5, &ref), 0);
    CHECK_EQ_INT(noshi_photo_ref_read(user, 1, 0, &ref), 0);
    CHECK_EQ_INT(noshi_photo_ref_read(user, 1, 5, NULL), 0);
}

static void test_location(void) {
    noshi_photo_ref ref;
    noshi_tl_value *location;
    int64_t value;
    memset(&ref, 0, sizeof(ref));
    ref.photo_id = 900;
    ref.dc = 4;
    ref.peer_kind = 1;
    ref.peer_id = 5;
    ref.access_hash = -77;
    CHECK_EQ_INT(noshi_photo_location(&arena, &ref, &location), NOSHI_OK);
    CHECK(noshi_tl_is(location, NOSHI_TL_ID_inputPeerPhotoFileLocation));
    CHECK_EQ_INT(noshi_tl_get_i64(location, "photo_id", &value), NOSHI_OK);
    CHECK_EQ_INT(value, 900);
    CHECK(noshi_tl_is(noshi_tl_get(location, "peer"), NOSHI_TL_ID_inputPeerUser));
    CHECK_EQ_INT(noshi_tl_get_i64(noshi_tl_get(location, "peer"), "access_hash", &value), NOSHI_OK);
    CHECK_EQ_INT(value, -77);
    CHECK(!noshi_tl_has(location, "big"));

    ref.peer_kind = 2;
    CHECK_EQ_INT(noshi_photo_location(&arena, &ref, &location), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(location, "peer"), NOSHI_TL_ID_inputPeerChat));
    CHECK(!noshi_tl_has(noshi_tl_get(location, "peer"), "access_hash"));
    ref.peer_kind = 3;
    CHECK_EQ_INT(noshi_photo_location(&arena, &ref, &location), NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(location, "peer"), NOSHI_TL_ID_inputPeerChannel));

    ref.peer_kind = 9;
    CHECK_EQ_INT(noshi_photo_location(&arena, &ref, &location), NOSHI_E_ARG);
    CHECK(location == NULL);
    ref.peer_kind = 1;
    ref.photo_id = 0;
    CHECK_EQ_INT(noshi_photo_location(&arena, &ref, &location), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_photo_location(NULL, &ref, &location), NOSHI_E_ARG);
}

static void test_rows_carry_photos(void) {
    noshi_person_row person;
    noshi_dialog_row rows[2];
    size_t count;
    noshi_tl_value *u = obj("user"), *d = obj("dialog"), *dp = obj("peerUser"), *answer = obj("messages.dialogs");
    noshi_tl_value *items[1];
    noshi_tl_value *dv = noshi_tl_new_vec(&arena, 1), *mv = noshi_tl_new_vec(&arena, 0), *cv = noshi_tl_new_vec(&arena, 0), *uv = noshi_tl_new_vec(&arena, 1);
    set_i64(u, "id", 5);
    set_i64(u, "access_hash", 1);
    set(u, "photo", photo("userProfilePhoto", 900, 4));
    CHECK_EQ_INT(noshi_person_parse(u, &person), NOSHI_OK);
    CHECK_EQ_INT(person.photo.photo_id, 900);
    CHECK_EQ_INT(person.photo.peer_id, 5);

    set_i64(dp, "user_id", 5);
    set(d, "peer", dp);
    items[0] = d;
    CHECK_EQ_INT(noshi_tl_vec_set(dv, 0, items[0]), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(uv, 0, u), NOSHI_OK);
    set(answer, "dialogs", dv);
    set(answer, "messages", mv);
    set(answer, "chats", cv);
    set(answer, "users", uv);
    CHECK_EQ_INT(noshi_dialogs_parse(answer, 1, 0, rows, 2, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].photo.photo_id, 900);
    CHECK_EQ_INT(rows[0].photo.dc, 4);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_read();
    test_location();
    test_rows_carry_photos();
    noshi_arena_free(&arena);
    return test_finish("test_photos");
}
