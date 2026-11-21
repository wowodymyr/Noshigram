#include "test_util.h"
#include "noshi_profile.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set(noshi_tl_value *v, const char *field, noshi_tl_value *x) {
    CHECK_EQ_INT(noshi_tl_set(v, field, x), NOSHI_OK);
}
static void str(noshi_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, field, x), NOSHI_OK);
}
static void roundtrip(noshi_tl_value *request, uint32_t constructor) {
    noshi_writer writer;
    noshi_tl_value *decoded = NULL;
    noshi_writer_init(&writer, 65536);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, writer.data, writer.len, &decoded), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(decoded), constructor);
    noshi_writer_free(&writer);
}

static void test_full_user(void) {
    noshi_full_user full;
    noshi_tl_value *answer = obj("users.userFull"), *inner = obj("userFull");
    noshi_tl_value *request = NULL;
    CHECK_EQ_INT(noshi_full_user_request(&arena, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_users_getFullUser);
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_E_MALFORMED);
    set(answer, "full_user", inner);
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
    CHECK_EQ_INT(full.about[0], 0);
    CHECK_EQ_INT(full.require_premium, 0);
    CHECK_EQ_INT(full.sharing_restricted, 0);
    CHECK_EQ_INT(full.has_intro, 0);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, inner, "common_chats_count", 4), NOSHI_OK);
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
    CHECK_EQ_INT(full.common_chats, 4);
    {
        noshi_tl_value *other = obj("users.userFull"), *mine = obj("userFull"), *intro = obj("businessIntro");
        set(other, "full_user", mine);
        CHECK_EQ_INT(noshi_tl_set_str(&arena, intro, "title", "hello"), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_str(&arena, intro, "description", "take cocoa"), NOSHI_OK);
        set(mine, "business_intro", intro);
        CHECK_EQ_INT(noshi_full_user_parse(other, &full), NOSHI_OK);
        CHECK_EQ_INT(full.has_intro, 1);
        CHECK(!strcmp(full.intro_title, "hello"));
        CHECK(!strcmp(full.intro_text, "take cocoa"));
        CHECK_EQ_INT(full.has_intro_sticker, 0);
    }
    CHECK_EQ_INT(noshi_tl_set_flag(inner, "noforwards_peer_enabled"), NOSHI_OK);
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
    CHECK_EQ_INT(full.sharing_restricted, 1);
    {
        noshi_tl_value *other = obj("users.userFull"), *mine = obj("userFull");
        set(other, "full_user", mine);
        CHECK_EQ_INT(noshi_tl_set_flag(mine, "noforwards_my_enabled"), NOSHI_OK);
        CHECK_EQ_INT(noshi_full_user_parse(other, &full), NOSHI_OK);
        CHECK_EQ_INT(full.sharing_restricted, 1);
    }
    {
        noshi_tl_value *rating = obj("starsRating");
        set(inner, "stars_rating", rating);
        CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_E_MALFORMED);
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, rating, "level", -1), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, rating, "current_level_stars", -100), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, rating, "stars", -20), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, rating, "next_level_stars", 0), NOSHI_OK);
        CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
        CHECK(full.has_rating && full.rating.has_next);
        CHECK_EQ_INT(full.rating.level, -1);
        CHECK_EQ_INT(full.rating.stars, -20);
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, rating, "next_level_stars", -100), NOSHI_OK);
        CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_E_MALFORMED);
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, rating, "next_level_stars", 0), NOSHI_OK);
        set(inner, "stars_my_pending_rating", rating);
        CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_E_MALFORMED);
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, inner, "stars_my_pending_rating_date", 123), NOSHI_OK);
        CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
        CHECK(full.has_pending_rating);
        CHECK_EQ_INT(full.pending_rating_date, 123);
    }
    CHECK_EQ_INT(noshi_tl_set_flag(inner, "contact_require_premium"), NOSHI_OK);
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
    CHECK_EQ_INT(full.require_premium, 1);
    str(inner, "about", "another developer\nline two");
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
    CHECK(!strcmp(full.about, "another developer\nline two"));
    {
        char big[NOSHI_ABOUT_MAX + 40];
        size_t i;
        for (i = 0; i + 2 < sizeof(big); i += 2) { big[i] = (char)0xd0; big[i + 1] = (char)0xb0; }
        big[sizeof(big) - 2] = 0;
        str(inner, "about", big);
        CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
        CHECK(strlen(full.about) < NOSHI_ABOUT_MAX);
        CHECK_EQ_INT(strlen(full.about) % 2, 0);
    }
    CHECK_EQ_INT(noshi_full_user_parse(obj("boolTrue"), &full), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(full.about[0], 0);
    CHECK_EQ_INT(noshi_full_user_parse(answer, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_full_user_request(&arena, NULL), NOSHI_E_ARG);
}

static void test_update(void) {
    noshi_tl_value *request = NULL;
    char name[NOSHI_NAME_PART_MAX + 2], about[NOSHI_ABOUT_MAX + 1];
    CHECK_EQ_INT(noshi_profile_update_request(&arena, "Ann", "Lee", "hi", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "first_name"), 1);
    CHECK_EQ_INT(noshi_tl_has(request, "last_name"), 1);
    CHECK_EQ_INT(noshi_tl_has(request, "about"), 1);
    roundtrip(request, NOSHI_TL_ID_account_updateProfile);
    /* only the fields that were given go out, and a last name or bio can be cleared with an empty string */
    CHECK_EQ_INT(noshi_profile_update_request(&arena, NULL, "", NULL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "first_name"), 0);
    CHECK_EQ_INT(noshi_tl_has(request, "last_name"), 1);
    CHECK_EQ_INT(noshi_tl_has(request, "about"), 0);
    roundtrip(request, NOSHI_TL_ID_account_updateProfile);
    CHECK_EQ_INT(noshi_profile_update_request(&arena, NULL, NULL, NULL, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_profile_update_request(&arena, "", NULL, NULL, &request), NOSHI_E_ARG);
    memset(name, 'a', sizeof(name));
    name[NOSHI_NAME_PART_MAX + 1] = 0;
    CHECK_EQ_INT(noshi_profile_update_request(&arena, name, NULL, NULL, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_profile_update_request(&arena, NULL, name, NULL, &request), NOSHI_E_ARG);
    name[NOSHI_NAME_PART_MAX] = 0;
    CHECK_EQ_INT(noshi_profile_update_request(&arena, name, NULL, NULL, &request), NOSHI_OK);
    memset(about, 'b', sizeof(about));
    about[NOSHI_ABOUT_MAX] = 0;
    CHECK_EQ_INT(noshi_profile_update_request(&arena, NULL, NULL, about, &request), NOSHI_E_ARG);
    about[NOSHI_ABOUT_MAX - 1] = 0;
    CHECK_EQ_INT(noshi_profile_update_request(&arena, NULL, NULL, about, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_profile_update_request(&arena, "Ann", NULL, NULL, NULL), NOSHI_E_ARG);
}

static void test_username(void) {
    static const char *good[] = {"", "lowspecialist", "abcde", "a_b_c_d1", "A1234", "abcdefghijklmnopqrstuvwxyz012345"};
    static const char *bad[] = {"abcd", "1abcde", "_abcde", "abcde_", "ab-cde", "ab cde", "abcdefghijklmnopqrstuvwxyz0123456", "ab\xc3\xa9" "cde", "@name1"};
    noshi_tl_value *request = NULL;
    size_t i;
    for (i = 0; i < sizeof(good) / sizeof(good[0]); ++i) CHECK_EQ_INT(noshi_username_check(good[i]), NOSHI_OK);
    for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) CHECK_EQ_INT(noshi_username_check(bad[i]), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_username_check(NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_username_request(&arena, "lowspecialist", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_account_updateUsername);
    CHECK_EQ_INT(noshi_username_request(&arena, "", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_username_request(&arena, "ab", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
}

static void test_photo(void) {
    noshi_tl_value *request = NULL, *file = obj("inputFile");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, file, "id", 5), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, file, "parts", 1), NOSHI_OK);
    str(file, "name", "photo.jpg");
    str(file, "md5_checksum", "");
    CHECK_EQ_INT(noshi_profile_photo_request(&arena, file, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_photos_uploadProfilePhoto);
    CHECK_EQ_INT(noshi_profile_photo_request(&arena, NULL, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    /* a clip: the request carries the video and the second that stands for it, and a second outside the clip is refused */
    CHECK_EQ_INT(noshi_profile_video_request(&arena, file, 1.5, &request), NOSHI_OK);
    CHECK(noshi_tl_has(request, "video") && noshi_tl_has(request, "video_start_ts") && !noshi_tl_has(request, "file"));
    roundtrip(request, NOSHI_TL_ID_photos_uploadProfilePhoto);
    CHECK_EQ_INT(noshi_profile_video_request(&arena, file, 11, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_profile_video_request(&arena, NULL, 0, &request), NOSHI_E_ARG);
    /* the public photo is the same upload with the fallback flag, and without a file it is refused */
    CHECK_EQ_INT(noshi_profile_public_photo_request(&arena, file, &request), NOSHI_OK);
    CHECK(noshi_tl_has(request, "fallback") && noshi_tl_has(request, "file"));
    roundtrip(request, NOSHI_TL_ID_photos_uploadProfilePhoto);
    CHECK_EQ_INT(noshi_profile_public_photo_request(&arena, NULL, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
}

static void test_photo_delete(void) {
    noshi_tl_value *request = NULL;
    noshi_media_ref photo;
    memset(&photo, 0, sizeof(photo));
    photo.source = NOSHI_MEDIA_SOURCE_PHOTO;
    photo.id = 77;
    photo.access_hash = 88;
    photo.ref_len = 3;
    memcpy(photo.file_ref, "abc", 3);
    CHECK_EQ_INT(noshi_profile_photo_delete_request(&arena, &photo, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_photos_deletePhotos);
    /* a document or a photo without an id cannot be a profile photo */
    photo.id = 0;
    CHECK_EQ_INT(noshi_profile_photo_delete_request(&arena, &photo, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    photo.id = 77;
    photo.source = NOSHI_MEDIA_SOURCE_DOCUMENT;
    CHECK_EQ_INT(noshi_profile_photo_delete_request(&arena, &photo, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_profile_photo_delete_request(&arena, NULL, &request), NOSHI_E_ARG);
}

/* the note, the photo the account set for a contact and the public photo of the account itself come out of the full user */
static void test_full_user_photos_note(void) {
    noshi_full_user full;
    noshi_tl_value *answer = obj("users.userFull"), *inner = obj("userFull"), *note = obj("textWithEntities"), *photo = obj("photo");
    set(answer, "full_user", inner);
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
    CHECK_EQ_INT(full.note[0], 0);
    CHECK_EQ_INT(full.has_personal_photo, 0);
    CHECK_EQ_INT(full.has_public_photo, 0);
    str(note, "text", "met at the fair");
    CHECK_EQ_INT(noshi_tl_set(note, "entities", noshi_tl_new_vec(&arena, 0)), NOSHI_OK);
    set(inner, "note", note);
    set(inner, "personal_photo", obj("photo"));
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
    CHECK(!strcmp(full.note, "met at the fair"));
    CHECK_EQ_INT(full.has_personal_photo, 1);
    /* a fallback photo that cannot be fetched is not offered */
    set(inner, "fallback_photo", photo);
    CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
    CHECK_EQ_INT(full.has_public_photo, 0);
    /* and one with an id, a reference and a size is */
    {
        noshi_tl_value *fallback = obj("photo"), *size = obj("photoSize"), *sizes;
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, fallback, "id", 4242), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, fallback, "access_hash", 7), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_bytes(&arena, fallback, "file_reference", "ref", 3), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, fallback, "date", 100), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, fallback, "dc_id", 2), NOSHI_OK);
        str(size, "type", "x");
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, size, "w", 800), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, size, "h", 800), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, size, "size", 5000), NOSHI_OK);
        sizes = noshi_tl_new_vec(&arena, 1);
        CHECK(sizes != NULL);
        CHECK_EQ_INT(noshi_tl_vec_set(sizes, 0, size), NOSHI_OK);
        set(fallback, "sizes", sizes);
        set(inner, "fallback_photo", fallback);
        CHECK_EQ_INT(noshi_full_user_parse(answer, &full), NOSHI_OK);
        CHECK_EQ_INT(full.has_public_photo, 1);
        CHECK_EQ_INT(full.public_photo.ref.id, 4242);
    }
}

static void test_contact_note_photo(void) {
    noshi_tl_value *request = NULL, *file = obj("inputFile");
    noshi_peer_ref contact = {1, 77, 99, 0, 0}, no_hash = {1, 77, 0, 0, 0}, group = {2, 77, 99, 0, 0};
    char big[NOSHI_CONTACT_NOTE_MAX + 1];
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, file, "id", 5), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, file, "parts", 1), NOSHI_OK);
    str(file, "name", "photo.jpg");
    str(file, "md5_checksum", "");
    /* a note is plain text; an empty one takes the note off, and a user without a hash or a note that does not fit is refused */
    CHECK_EQ_INT(noshi_contact_note_request(&arena, &contact, "met at the fair", &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_contacts_updateContactNote);
    CHECK_EQ_INT(noshi_contact_note_request(&arena, &contact, "", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_contact_note_request(&arena, &no_hash, "x", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_contact_note_request(&arena, &group, "x", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_note_request(&arena, &contact, NULL, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_contact_note_request(&arena, NULL, "x", &request), NOSHI_E_ARG);
    memset(big, 'a', sizeof(big));
    big[NOSHI_CONTACT_NOTE_MAX - 1] = 0;
    CHECK_EQ_INT(noshi_contact_note_request(&arena, &contact, big, &request), NOSHI_OK);
    big[NOSHI_CONTACT_NOTE_MAX - 1] = 'a';
    big[NOSHI_CONTACT_NOTE_MAX] = 0;
    CHECK_EQ_INT(noshi_contact_note_request(&arena, &contact, big, &request), NOSHI_E_ARG);
    /* a photo for the contact: set on the account's side, or suggested to them with the suggest flag */
    CHECK_EQ_INT(noshi_contact_photo_request(&arena, &contact, file, 0, &request), NOSHI_OK);
    CHECK(noshi_tl_has(request, "file") && !noshi_tl_has(request, "suggest") && !noshi_tl_has(request, "save"));
    roundtrip(request, NOSHI_TL_ID_photos_uploadContactProfilePhoto);
    CHECK_EQ_INT(noshi_contact_photo_request(&arena, &contact, file, 1, &request), NOSHI_OK);
    CHECK(noshi_tl_has(request, "file") && noshi_tl_has(request, "suggest") && !noshi_tl_has(request, "save"));
    roundtrip(request, NOSHI_TL_ID_photos_uploadContactProfilePhoto);
    CHECK_EQ_INT(noshi_contact_photo_request(&arena, &contact, NULL, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_contact_photo_request(&arena, &no_hash, file, 0, &request), NOSHI_E_ARG);
    /* taking the photo away is the save flag without a file */
    CHECK_EQ_INT(noshi_contact_photo_reset_request(&arena, &contact, &request), NOSHI_OK);
    CHECK(noshi_tl_has(request, "save") && !noshi_tl_has(request, "file") && !noshi_tl_has(request, "suggest"));
    roundtrip(request, NOSHI_TL_ID_photos_uploadContactProfilePhoto);
    CHECK_EQ_INT(noshi_contact_photo_reset_request(&arena, &no_hash, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
}

static noshi_tl_value *vec_of(noshi_tl_value **items, uint32_t n) {
    noshi_tl_value *vec = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(vec, i, items[i]), NOSHI_OK);
    return vec;
}

static noshi_tl_value *user(int64_t id, const char *name, const char *phone) {
    noshi_tl_value *v = obj("user");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, "access_hash", 99), NOSHI_OK);
    str(v, "first_name", name);
    if (phone) str(v, "phone", phone);
    return v;
}

static noshi_tl_value *channel(int64_t id, const char *title, int with_hash) {
    noshi_tl_value *v = obj("channel");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, "id", id), NOSHI_OK);
    if (with_hash) CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, "access_hash", 55), NOSHI_OK);
    str(v, "title", title);
    CHECK_EQ_INT(noshi_tl_set_flag(v, "broadcast"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "participants_count", 83), NOSHI_OK);
    return v;
}

static void test_peer_profile(void) {
    noshi_full_user *full = calloc(1, sizeof(*full));
    noshi_tl_value *answer = obj("users.userFull"), *inner = obj("userFull"), *birthday = obj("birthday"), *request = NULL;
    noshi_tl_value *users[1], *chats[2];
    noshi_peer_ref other = {1, 5, 7, 0, 0}, bad = {1, 5, 0, 0, 0}, group = {2, 5, 0, 0, 0};
    CHECK(full != NULL);
    CHECK_EQ_INT(noshi_full_user_peer_request(&arena, &other, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_users_getFullUser);
    CHECK_EQ_INT(noshi_full_user_peer_request(&arena, &bad, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_full_user_peer_request(&arena, &group, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    {
        noshi_peer_ref self = {1, 1, 0, 1, 0};
        CHECK_EQ_INT(noshi_full_user_peer_request(&arena, &self, &request), NOSHI_OK);
    }
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, inner, "id", 5), NOSHI_OK);
    str(inner, "about", "bio");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, birthday, "day", 12), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, birthday, "month", 3), NOSHI_OK);
    set(inner, "birthday", birthday);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, inner, "personal_channel_id", 700), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, inner, "personal_channel_message", 42), NOSHI_OK);
    set(answer, "full_user", inner);
    users[0] = user(5, "Kim", "79991234567");
    chats[0] = channel(700, "Kim news", 1);
    set(answer, "users", vec_of(users, 1));
    set(answer, "chats", vec_of(chats, 1));
    CHECK_EQ_INT(noshi_full_user_parse(answer, full), NOSHI_OK);
    CHECK_EQ_INT(full->has_person, 1);
    CHECK(!strcmp(full->person.name, "Kim"));
    CHECK(!strcmp(full->person.phone, "79991234567"));
    CHECK_EQ_INT(full->has_birthday, 1);
    CHECK_EQ_INT(full->birthday_day, 12);
    CHECK_EQ_INT(full->birthday_month, 3);
    CHECK_EQ_INT(full->birthday_year, 0);
    CHECK_EQ_INT(full->has_channel, 1);
    CHECK_EQ_INT(full->channel.peer_id, 700);
    CHECK_EQ_INT(full->channel.peer_hash, 55);
    CHECK(!strcmp(full->channel.title, "Kim news"));
    CHECK_EQ_INT(full->channel_participants, 83);
    CHECK_EQ_INT(full->channel_message, 42);
    /* a channel the answer does not carry, or a birthday outside the calendar, is left out */
    set(answer, "chats", noshi_tl_new_vec(&arena, 0));
    CHECK_EQ_INT(noshi_full_user_parse(answer, full), NOSHI_OK);
    CHECK_EQ_INT(full->has_channel, 0);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, birthday, "month", 13), NOSHI_OK);
    CHECK_EQ_INT(noshi_full_user_parse(answer, full), NOSHI_OK);
    CHECK_EQ_INT(full->has_birthday, 0);
    free(full);
}

static noshi_tl_value *song(int64_t id, const char *title, const char *performer, int32_t seconds, int with_reference) {
    static const uint8_t reference[] = {9, 8, 7};
    noshi_tl_value *d = obj("document"), *audio = obj("documentAttributeAudio"), *attributes[1];
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, d, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, d, "access_hash", id * 3), NOSHI_OK);
    if (with_reference) CHECK_EQ_INT(noshi_tl_set_bytes(&arena, d, "file_reference", reference, sizeof(reference)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, d, "dc_id", 2), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, d, "size", 5000000), NOSHI_OK);
    str(d, "mime_type", "audio/mpeg");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, audio, "duration", seconds), NOSHI_OK);
    if (title) str(audio, "title", title);
    if (performer) str(audio, "performer", performer);
    attributes[0] = audio;
    set(d, "attributes", vec_of(attributes, 1));
    return d;
}

static void test_music(void) {
    noshi_tl_value *request = NULL, *answer = obj("users.savedMusic"), *docs[4];
    noshi_peer_ref other = {1, 5, 7, 0, 0}, self = {1, 1, 0, 1, 0}, bad = {1, 5, 0, 0, 0}, group = {2, 5, 0, 0, 0};
    noshi_media_info tracks[3];
    size_t count = 99;
    int32_t total = 99;
    noshi_full_user *full = calloc(1, sizeof(*full));
    noshi_tl_value *inner = obj("userFull"), *user_full = obj("users.userFull");
    CHECK(full != NULL);

    CHECK_EQ_INT(noshi_saved_music_request(&arena, &other, 0, NOSHI_MUSIC_PAGE, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "hash"), 1);
    roundtrip(request, NOSHI_TL_ID_users_getSavedMusic);
    CHECK_EQ_INT(noshi_saved_music_request(&arena, &self, 30, 1, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_users_getSavedMusic);
    CHECK_EQ_INT(noshi_saved_music_request(&arena, &bad, 0, 10, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_saved_music_request(&arena, &group, 0, 10, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_saved_music_request(&arena, &other, -1, 10, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_saved_music_request(&arena, &other, 0, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_saved_music_request(&arena, &other, 0, NOSHI_MUSIC_PAGE + 1, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_saved_music_request(&arena, &other, 0, 10, NULL), NOSHI_E_ARG);

    /* a song without a file reference cannot be fetched and is left out, and the page is cut at the room the caller has */
    docs[0] = song(11, "The Science of Lies", "Demon Hunter", 215, 1);
    docs[1] = song(12, "Lost", "Nobody", 100, 0);
    docs[2] = song(13, NULL, NULL, 61, 1);
    docs[3] = song(14, "Fourth", "Band", 70, 1);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, answer, "count", 57), NOSHI_OK);
    set(answer, "documents", vec_of(docs, 4));
    CHECK_EQ_INT(noshi_saved_music_parse(answer, tracks, 3, &count, &total), NOSHI_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(total, 57);
    CHECK(!strcmp(tracks[0].title, "The Science of Lies"));
    CHECK(!strcmp(tracks[0].performer, "Demon Hunter"));
    CHECK_EQ_INT(tracks[0].duration, 215);
    CHECK_EQ_INT(tracks[0].kind, NOSHI_PREVIEW_AUDIO);
    CHECK_EQ_INT(tracks[0].ref.id, 11);
    CHECK_EQ_INT(tracks[0].size, 5000000);
    CHECK_EQ_INT(tracks[1].ref.id, 13);
    CHECK_EQ_INT(tracks[1].title[0], 0);
    CHECK_EQ_INT(tracks[1].performer[0], 0);
    CHECK_EQ_INT(tracks[2].ref.id, 14);

    CHECK_EQ_INT(noshi_saved_music_parse(obj("users.savedMusicNotModified"), tracks, 3, &count, &total), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_saved_music_parse(obj("boolTrue"), tracks, 3, &count, &total), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_saved_music_parse(answer, tracks, 3, NULL, &total), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_saved_music_parse(answer, tracks, 0, &count, &total), NOSHI_OK);
    CHECK_EQ_INT(count, 0);

    /* the profile's first song comes with the full user, and one without a usable file is left out */
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, inner, "id", 5), NOSHI_OK);
    set(user_full, "full_user", inner);
    CHECK_EQ_INT(noshi_full_user_parse(user_full, full), NOSHI_OK);
    CHECK_EQ_INT(full->has_music, 0);
    set(inner, "saved_music", song(21, "Intro", "Band", 33, 1));
    CHECK_EQ_INT(noshi_full_user_parse(user_full, full), NOSHI_OK);
    CHECK_EQ_INT(full->has_music, 1);
    CHECK(!strcmp(full->music.title, "Intro"));
    CHECK_EQ_INT(full->music.ref.id, 21);
    set(inner, "saved_music", song(22, "Gone", "Band", 33, 0));
    CHECK_EQ_INT(noshi_full_user_parse(user_full, full), NOSHI_OK);
    CHECK_EQ_INT(full->has_music, 0);
    CHECK_EQ_INT(full->music.title[0], 0);
    free(full);
}

static void test_save_music(void) {
    noshi_tl_value *request = NULL;
    noshi_media_ref song;
    memset(&song, 0, sizeof(song));
    song.source = NOSHI_MEDIA_SOURCE_DOCUMENT;
    song.id = 77;
    song.access_hash = 5;
    song.ref_len = 3;
    song.file_ref[0] = 9;
    song.file_ref[1] = 8;
    song.file_ref[2] = 7;
    CHECK_EQ_INT(noshi_save_music_request(&arena, &song, 0, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "unsave"), 0);
    roundtrip(request, NOSHI_TL_ID_account_saveMusic);
    CHECK_EQ_INT(noshi_save_music_request(&arena, &song, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "unsave"), 1);
    roundtrip(request, NOSHI_TL_ID_account_saveMusic);
    /* a cover of the song, a photo, a song without a reference or without an id cannot be saved */
    song.thumb[0] = 'm';
    CHECK_EQ_INT(noshi_save_music_request(&arena, &song, 0, &request), NOSHI_E_ARG);
    song.thumb[0] = 0;
    song.source = NOSHI_MEDIA_SOURCE_PHOTO;
    CHECK_EQ_INT(noshi_save_music_request(&arena, &song, 0, &request), NOSHI_E_ARG);
    song.source = NOSHI_MEDIA_SOURCE_DOCUMENT;
    song.ref_len = 0;
    CHECK_EQ_INT(noshi_save_music_request(&arena, &song, 0, &request), NOSHI_E_ARG);
    song.ref_len = 3;
    song.id = 0;
    CHECK_EQ_INT(noshi_save_music_request(&arena, &song, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_save_music_request(&arena, NULL, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_save_music_request(&arena, &song, 0, NULL), NOSHI_E_ARG);
}

static void test_birthday_channels(void) {
    noshi_tl_value *request = NULL, *answer = obj("messages.chats"), *chats[3];
    noshi_dialog_row rows[4];
    size_t count = 9;
    noshi_peer_ref chan = {3, 700, 55, 0, 0}, nohash = {3, 700, 0, 0, 0}, user_peer = {1, 5, 7, 0, 0};
    CHECK_EQ_INT(noshi_birthday_request(&arena, 29, 2, 2000, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_account_updateBirthday);
    CHECK_EQ_INT(noshi_tl_has(request, "birthday"), 1);
    CHECK_EQ_INT(noshi_birthday_request(&arena, 29, 2, 0, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_birthday_request(&arena, 29, 2, 2001, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_birthday_request(&arena, 31, 4, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_birthday_request(&arena, 0, 4, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_birthday_request(&arena, 5, 0, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_birthday_request(&arena, 5, 13, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_birthday_request(&arena, 5, 6, 1899, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_birthday_request(&arena, 5, 6, 2101, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_birthday_clear_request(&arena, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "birthday"), 0);
    roundtrip(request, NOSHI_TL_ID_account_updateBirthday);

    CHECK_EQ_INT(noshi_personal_channel_request(&arena, &chan, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_account_updatePersonalChannel);
    CHECK_EQ_INT(noshi_personal_channel_request(&arena, NULL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(noshi_tl_get(request, "channel")), NOSHI_TL_ID_inputChannelEmpty);
    CHECK_EQ_INT(noshi_personal_channel_request(&arena, &nohash, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_personal_channel_request(&arena, &user_peer, &request), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_admined_channels_request(&arena, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_has(request, "for_personal"), 1);
    roundtrip(request, NOSHI_TL_ID_channels_getAdminedPublicChannels);
    chats[0] = channel(1, "One", 1);
    chats[1] = channel(2, "Min", 0);
    chats[2] = obj("chatEmpty");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, chats[2], "id", 3), NOSHI_OK);
    set(answer, "chats", vec_of(chats, 3));
    CHECK_EQ_INT(noshi_admined_channels_parse(answer, rows, 4, &count), NOSHI_OK);
    /* the channel without a hash and the one that is no channel are left out */
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].peer_id, 1);
    CHECK_EQ_INT(rows[0].peer_hash, 55);
    CHECK_EQ_INT(noshi_admined_channels_parse(obj("boolTrue"), rows, 4, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_admined_channels_parse(answer, NULL, 4, &count), NOSHI_E_ARG);

    /* the groups in common with a user: a page after the last chat id, basic groups and supergroups, the left-out ones still count for paging */
    {
        noshi_tl_value *group = obj("chat"), *super = channel(8, "Super", 1), *nohash_super = channel(9, "Hidden", 0);
        noshi_dialog_row common[4];
        noshi_peer_ref person = {1, 5, 7, 0, 0}, person_nohash = {1, 5, 0, 0, 0};
        int64_t last = -1;
        size_t raw = 99;
        CHECK_EQ_INT(noshi_common_chats_request(&arena, &person, 0, 100, &request), NOSHI_OK);
        roundtrip(request, NOSHI_TL_ID_messages_getCommonChats);
        CHECK_EQ_INT(noshi_common_chats_request(&arena, &person, 41, 1, &request), NOSHI_OK);
        CHECK_EQ_INT(noshi_common_chats_request(&arena, &person, 0, 101, &request), NOSHI_E_ARG);
        CHECK_EQ_INT(noshi_common_chats_request(&arena, &person, 0, 0, &request), NOSHI_E_ARG);
        CHECK_EQ_INT(noshi_common_chats_request(&arena, &person, -1, 10, &request), NOSHI_E_ARG);
        CHECK_EQ_INT(noshi_common_chats_request(&arena, &person_nohash, 0, 10, &request), NOSHI_E_ARG);
        CHECK_EQ_INT(noshi_common_chats_request(&arena, &chan, 0, 10, &request), NOSHI_E_ARG);
        CHECK_EQ_INT(noshi_tl_set_i64(&arena, group, "id", 7), NOSHI_OK);
        str(group, "title", "Basic");
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, group, "participants_count", 12), NOSHI_OK);
        chats[0] = group;
        chats[1] = super;
        chats[2] = nohash_super;
        answer = obj("messages.chatsSlice");
        CHECK_EQ_INT(noshi_tl_set_i32(&arena, answer, "count", 3), NOSHI_OK);
        set(answer, "chats", vec_of(chats, 3));
        CHECK_EQ_INT(noshi_common_chats_parse(answer, common, 4, &count, &last, &raw), NOSHI_OK);
        CHECK_EQ_INT(count, 2);
        CHECK_EQ_INT(raw, 3);
        CHECK_EQ_INT(last, 9);
        CHECK_EQ_INT(common[0].peer_kind, 2);
        CHECK_EQ_INT(common[0].peer_id, 7);
        CHECK_EQ_INT(common[0].participants_count, 12);
        CHECK_EQ_INT(common[1].peer_kind, 3);
        CHECK_EQ_INT(common[1].peer_hash, 55);
        /* a full page of the row buffer keeps counting what the answer held */
        CHECK_EQ_INT(noshi_common_chats_parse(answer, common, 1, &count, &last, &raw), NOSHI_OK);
        CHECK_EQ_INT(count, 1);
        CHECK_EQ_INT(raw, 3);
        CHECK_EQ_INT(last, 9);
        answer = obj("messages.chats");
        set(answer, "chats", vec_of(chats, 0));
        CHECK_EQ_INT(noshi_common_chats_parse(answer, common, 4, &count, &last, &raw), NOSHI_OK);
        CHECK_EQ_INT(count, 0);
        CHECK_EQ_INT(raw, 0);
        CHECK_EQ_INT(last, 0);
        CHECK_EQ_INT(noshi_common_chats_parse(obj("boolTrue"), common, 4, &count, &last, &raw), NOSHI_E_MALFORMED);
        CHECK_EQ_INT(noshi_common_chats_parse(answer, NULL, 4, &count, &last, &raw), NOSHI_E_ARG);
    }

    CHECK_EQ_INT(noshi_channel_message_request(&arena, &chan, 42, &request), NOSHI_OK);
    roundtrip(request, NOSHI_TL_ID_channels_getMessages);
    CHECK_EQ_INT(noshi_channel_message_request(&arena, &chan, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_channel_message_request(&arena, &nohash, 42, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
}

int main(void) {
    noshi_arena_init(&arena, 16u * 1024u * 1024u);
    test_full_user();
    test_update();
    test_username();
    test_photo();
    test_photo_delete();
    test_contact_note_photo();
    test_full_user_photos_note();
    test_peer_profile();
    test_birthday_channels();
    test_music();
    test_save_music();
    noshi_arena_free(&arena);
    return test_finish("test_profile");
}
