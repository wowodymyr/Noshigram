#include "test_util.h"
#include "noshi_name_color.h"
#include "noshi_people.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static noshi_tl_value *vec_of(noshi_tl_value **items, uint32_t n) {
    noshi_tl_value *v = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(v, i, items[i]), NOSHI_OK);
    return v;
}

static noshi_tl_value *color_set(int32_t first) {
    noshi_tl_value *set = obj("help.peerColorSet");
    CHECK_EQ_INT(noshi_tl_set_i32_vec(&arena, set, "colors", &first, 1), NOSHI_OK);
    return set;
}

static noshi_tl_value *option(int32_t id, int32_t light, int has_dark, int32_t dark, int hidden) {
    noshi_tl_value *o = obj("help.peerColorOption");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, o, "color_id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(o, "colors", color_set(light)), NOSHI_OK);
    if (has_dark) CHECK_EQ_INT(noshi_tl_set(o, "dark_colors", color_set(dark)), NOSHI_OK);
    if (hidden) CHECK_EQ_INT(noshi_tl_set_flag(o, "hidden"), NOSHI_OK);
    return o;
}

static void test_user_color(void) {
    noshi_person_row row;
    noshi_tl_value *user = obj("user"), *color = obj("peerColor");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, user, "id", 77), NOSHI_OK);
    CHECK_EQ_INT(noshi_person_parse(user, &row), NOSHI_OK);
    CHECK_EQ_INT(row.has_name_color, 0);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, color, "color", 12), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(user, "color", color), NOSHI_OK);
    CHECK_EQ_INT(noshi_person_parse(user, &row), NOSHI_OK);
    CHECK_EQ_INT(row.has_name_color, 1);
    CHECK_EQ_INT(row.name_color, 12);
    /* a color that carries only an emoji background chooses no id, and a collectible leaves the name to the default */
    noshi_tl_value *emoji_only = obj("peerColor");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, emoji_only, "background_emoji_id", 5), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(user, "color", emoji_only), NOSHI_OK);
    CHECK_EQ_INT(noshi_person_parse(user, &row), NOSHI_OK);
    CHECK_EQ_INT(row.has_name_color, 0);
}

static void test_colors_parse(void) {
    noshi_name_color_option rows[8];
    size_t count = 9;
    noshi_tl_value *answer = obj("help.peerColors"), *items[5];
    items[0] = option(7, 0xFF112233, 1, 0xFF445566, 0);
    items[1] = option(8, 0x00AABBCC, 0, 0, 1);
    items[2] = option(21, 0x010203, 0, 0, 0);          /* an id the app has no place for is left out */
    items[3] = obj("help.peerColorOption");            /* one with no colors is left out */
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, items[3], "color_id", 9), NOSHI_OK);
    items[4] = option(20, 0x0A0B0C, 1, 0x0D0E0F, 0);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, answer, "hash", 5), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "colors", vec_of(items, 5)), NOSHI_OK);
    CHECK_EQ_INT(noshi_name_colors_parse(answer, rows, 8, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(rows[0].id, 7);
    CHECK_EQ_INT(rows[0].light, 0x112233);
    CHECK_EQ_INT(rows[0].dark, 0x445566);
    CHECK_EQ_INT(rows[0].hidden, 0);
    CHECK_EQ_INT(rows[1].id, 8);
    CHECK_EQ_INT(rows[1].light, 0xAABBCC);
    CHECK_EQ_INT(rows[1].dark, 0xAABBCC);
    CHECK_EQ_INT(rows[1].hidden, 1);
    CHECK_EQ_INT(rows[2].id, 20);
    /* too many for the caller, another answer, and the list that has not changed */
    CHECK_EQ_INT(noshi_name_colors_parse(answer, rows, 2, &count), NOSHI_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_name_colors_parse(obj("boolTrue"), rows, 8, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_name_colors_parse(obj("help.peerColorsNotModified"), rows, 8, &count), NOSHI_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(noshi_name_colors_parse(NULL, rows, 8, &count), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_name_colors_parse(answer, rows, 0, &count), NOSHI_E_ARG);
}

static void test_requests(void) {
    noshi_tl_value *request = NULL;
    noshi_writer wire;
    int32_t id = 0;
    CHECK_EQ_INT(noshi_name_colors_request(&arena, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_help_getPeerColors);
    noshi_writer_init(&wire, 64);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_name_color_set_request(&arena, 5, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_account_updateColor);
    CHECK(!noshi_tl_has(request, "for_profile"));
    CHECK_EQ_INT(noshi_tl_get_i32(noshi_tl_get(request, "color"), "color", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 5);
    noshi_writer_init(&wire, 64);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_name_color_set_request(&arena, 0, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_name_color_set_request(&arena, NOSHI_NAME_COLOR_MAX, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_name_color_set_request(&arena, -1, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_name_color_set_request(&arena, NOSHI_NAME_COLOR_MAX + 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_name_color_set_request(&arena, 1, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_name_color_set_parse(obj("boolTrue")), NOSHI_OK);
    CHECK_EQ_INT(noshi_name_color_set_parse(obj("boolFalse")), NOSHI_E_STATE);
    CHECK_EQ_INT(noshi_name_color_set_parse(NULL), NOSHI_E_MALFORMED);
}

int main(void) {
    noshi_arena_init(&arena, 1024u * 1024u);
    test_user_color();
    test_colors_parse();
    test_requests();
    noshi_arena_free(&arena);
    return test_finish("test_name_color");
}
