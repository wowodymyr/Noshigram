#include "test_util.h"
#include "noshi_theme_link.h"
#include "noshi_tl_ids.h"

#include <string.h>

static noshi_arena arena;

static noshi_tl_value *document_of(int64_t id) {
    static const uint8_t reference[] = {9, 8, 7};
    noshi_tl_value *d = noshi_tl_new_obj(&arena, "document");
    CHECK(d != NULL);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, d, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, d, "access_hash", id * 3), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_bytes(&arena, d, "file_reference", reference, sizeof(reference)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, d, "dc_id", 4), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, d, "size", 5120), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, d, "mime_type", "application/x-tgtheme-ios"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(d, "attributes", noshi_tl_new_vec(&arena, 0)), NOSHI_OK);
    return d;
}

static noshi_tl_value *theme_of(const char *title, noshi_tl_value *document) {
    noshi_tl_value *t = noshi_tl_new_obj(&arena, "theme");
    CHECK(t != NULL);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, t, "id", 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, t, "access_hash", 2), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, t, "slug", "EUv1TXVWMHmXclaj"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, t, "title", title), NOSHI_OK);
    if (document) CHECK_EQ_INT(noshi_tl_set(t, "document", document), NOSHI_OK);
    return t;
}

static noshi_tl_value *colors_of(const char *title, const char *base, int32_t accent) {
    noshi_tl_value *t = theme_of(title, NULL), *settings = noshi_tl_new_obj(&arena, "themeSettings"), *list = noshi_tl_new_vec(&arena, 1);
    CHECK(settings != NULL && list != NULL);
    if (base) CHECK_EQ_INT(noshi_tl_set(settings, "base_theme", noshi_tl_new_obj(&arena, base)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, settings, "accent_color", accent), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(list, 0, settings), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(t, "settings", list), NOSHI_OK);
    return t;
}

static void test_request(void) {
    noshi_tl_value *request = NULL, *decoded = NULL;
    noshi_writer writer;
    CHECK_EQ_INT(noshi_theme_link_request(&arena, "EUv1TXVWMHmXclaj", &request), NOSHI_OK);
    noshi_writer_init(&writer, 256);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, writer.data, writer.len, &decoded), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(decoded), NOSHI_TL_ID_account_getTheme);
    noshi_writer_free(&writer);
    CHECK_EQ_INT(noshi_theme_link_request(&arena, "a-b_C9", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_theme_link_request(&arena, "", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_theme_link_request(&arena, "bad slug", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_theme_link_request(&arena, "x;y", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_theme_link_request(NULL, "abc", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_theme_link_request(&arena, NULL, &request), NOSHI_E_ARG);
}

static void test_request_slug_length(void) {
    char slug[NOSHI_THEME_SLUG_MAX + 2];
    noshi_tl_value *request = NULL;
    memset(slug, 'a', sizeof(slug));
    slug[NOSHI_THEME_SLUG_MAX] = 0;
    CHECK_EQ_INT(noshi_theme_link_request(&arena, slug, &request), NOSHI_OK);
    slug[NOSHI_THEME_SLUG_MAX] = 'a';
    slug[NOSHI_THEME_SLUG_MAX + 1] = 0;
    CHECK_EQ_INT(noshi_theme_link_request(&arena, slug, &request), NOSHI_E_ARG);
}

static void test_parse(void) {
    noshi_theme_link_info info;
    char long_title[300];
    CHECK_EQ_INT(noshi_theme_link_parse(theme_of("Night", document_of(77)), &info), NOSHI_OK);
    CHECK(!strcmp(info.title, "Night"));
    CHECK_EQ_INT(info.has_file, 1);
    CHECK_EQ_INT(info.file.ref.source, NOSHI_MEDIA_SOURCE_DOCUMENT);
    CHECK_EQ_INT(info.file.ref.id, 77);
    CHECK_EQ_INT(info.file.ref.dc, 4);
    CHECK_EQ_INT(info.file.size, 5120);
    /* a theme with accent settings only has no file to import */
    CHECK_EQ_INT(noshi_theme_link_parse(theme_of("Accent", NULL), &info), NOSHI_OK);
    CHECK_EQ_INT(info.has_file, 0);
    CHECK(!strcmp(info.title, "Accent"));
    CHECK_EQ_INT(info.has_colors, 0);
    /* a theme of colors: the base look and the accent, with the alpha byte a signed value carries cut off */
    CHECK_EQ_INT(noshi_theme_link_parse(colors_of("Moon", "baseThemeNight", (int32_t)0xFF3A7BD5u), &info), NOSHI_OK);
    CHECK_EQ_INT(info.has_file, 0);
    CHECK_EQ_INT(info.has_colors, 1);
    CHECK_EQ_INT(info.dark, 1);
    CHECK_EQ_INT(info.accent, 0x3A7BD5u);
    CHECK_EQ_INT(noshi_theme_link_parse(colors_of("Sun", "baseThemeDay", 0x112233), &info), NOSHI_OK);
    CHECK_EQ_INT(info.dark, 0);
    CHECK_EQ_INT(info.accent, 0x112233u);
    CHECK_EQ_INT(noshi_theme_link_parse(colors_of("Dusk", "baseThemeTinted", 0x445566), &info), NOSHI_OK);
    CHECK_EQ_INT(info.dark, 1);
    /* settings with no base look are no colors */
    CHECK_EQ_INT(noshi_theme_link_parse(colors_of("Odd", NULL, 0x445566), &info), NOSHI_OK);
    CHECK_EQ_INT(info.has_colors, 0);
    /* a document that is not a fetchable file */
    CHECK_EQ_INT(noshi_theme_link_parse(theme_of("Gone", noshi_tl_new_obj(&arena, "documentEmpty")), &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(info.has_file, 0);
    CHECK_EQ_INT(info.title[0], 0);
    CHECK_EQ_INT(noshi_theme_link_parse(noshi_tl_new_obj(&arena, "themeSettings"), &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_theme_link_parse(NULL, &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_theme_link_parse(theme_of("x", NULL), NULL), NOSHI_E_ARG);
    /* a title that does not fit is cut on a character boundary, never inside a two byte letter */
    memset(long_title, 0, sizeof(long_title));
    for (size_t i = 0; i + 1 < 200; i += 2) memcpy(long_title + i, "\xd0\xaf", 2);
    CHECK_EQ_INT(noshi_theme_link_parse(theme_of(long_title, NULL), &info), NOSHI_OK);
    CHECK(strlen(info.title) < NOSHI_THEME_TITLE_MAX);
    CHECK_EQ_INT(strlen(info.title) % 2, 0);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_request();
    test_request_slug_length();
    test_parse();
    noshi_arena_free(&arena);
    return test_finish("test_theme_link");
}
