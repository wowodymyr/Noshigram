#include "test_util.h"
#include "noshi_langpack.h"
#include "noshi_tl_ids.h"

#include <string.h>

static noshi_arena arena;

static noshi_tl_value *language_of(const char *name, const char *code, int32_t strings, int32_t translated, int official) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, "langPackLanguage");
    CHECK(v != NULL);
    if (official) CHECK_EQ_INT(noshi_tl_set_flag(v, "official"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, "name", name), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, "native_name", "Русский"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, "lang_code", code), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, "plural_code", "ru"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "strings_count", strings), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, "translated_count", translated), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, v, "translations_url", "https://translations.telegram.org/ru/ios"), NOSHI_OK);
    return v;
}

static void test_request(void) {
    noshi_tl_value *request = NULL, *decoded = NULL;
    noshi_writer writer;
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios", "pt-br", &request), NOSHI_OK);
    noshi_writer_init(&writer, 256);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, writer.data, writer.len, &decoded), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(decoded), NOSHI_TL_ID_langpack_getLanguage);
    noshi_writer_free(&writer);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios", "vi_dev_2", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios", "abcdefghijklmnopqrstuvwxyz012345", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios", "abcdefghijklmnopqrstuvwxyz0123456", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios", "ru;drop", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "", "ru", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios2", "ru", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "abcdefghijklmnopq", "ru", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_langpack_request(&arena, NULL, "ru", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios", NULL, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_langpack_request(&arena, "ios", "ru", NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_langpack_request(NULL, "ios", "ru", &request), NOSHI_E_ARG);
}

static void test_parse(void) {
    noshi_langpack_info info;
    CHECK_EQ_INT(noshi_langpack_parse(language_of("Russian", "ru", 3000, 2999, 1), &info), NOSHI_OK);
    CHECK_EQ_INT(info.official, 1);
    CHECK_EQ_INT(info.rtl, 0);
    CHECK(!strcmp(info.name, "Russian"));
    CHECK(!strcmp(info.native_name, "Русский"));
    CHECK(!strcmp(info.lang_code, "ru"));
    CHECK_EQ_INT(info.base_lang_code[0], 0);
    CHECK_EQ_INT(info.strings_count, 3000);
    CHECK_EQ_INT(info.translated_count, 2999);
    CHECK(!strcmp(info.translations_url, "https://translations.telegram.org/ru/ios"));
    CHECK_EQ_INT(noshi_langpack_parse(language_of("Custom", "xyz", 0, 0, 0), &info), NOSHI_OK);
    CHECK_EQ_INT(info.official, 0);
    CHECK_EQ_INT(info.strings_count, 0);
    {
        noshi_tl_value *v = language_of("Custom", "xyz", 10, 5, 0);
        CHECK_EQ_INT(noshi_tl_set_str(&arena, v, "base_lang_code", "en"), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_flag(v, "rtl"), NOSHI_OK);
        CHECK_EQ_INT(noshi_langpack_parse(v, &info), NOSHI_OK);
        CHECK(!strcmp(info.base_lang_code, "en"));
        CHECK_EQ_INT(info.rtl, 1);
    }
    /* a name is cut at a character boundary, a code that does not fit is refused */
    {
        char longname[200];
        noshi_tl_value *v;
        memset(longname, 0, sizeof(longname));
        memset(longname, 'a', 94);
        memcpy(longname + 94, "\xD0\xB1", 2);
        v = language_of(longname, "xyz", 10, 5, 0);
        CHECK_EQ_INT(noshi_langpack_parse(v, &info), NOSHI_OK);
        CHECK_EQ_INT(strlen(info.name), 94);
        v = language_of("N", "abcdefghijklmnopqrstuvwxyz0123456789", 10, 5, 0);
        CHECK_EQ_INT(noshi_langpack_parse(v, &info), NOSHI_E_MALFORMED);
        CHECK_EQ_INT(info.name[0], 0);
    }
    CHECK_EQ_INT(noshi_langpack_parse(language_of("N", "xyz", -1, 0, 0), &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_langpack_parse(language_of("N", "xyz", 5, -3, 0), &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_langpack_parse(language_of("", "xyz", 5, 3, 0), &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_langpack_parse(language_of("N", "", 5, 3, 0), &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_langpack_parse(noshi_tl_new_obj(&arena, "boolTrue"), &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_langpack_parse(NULL, &info), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_langpack_parse(language_of("N", "xyz", 5, 3, 0), NULL), NOSHI_E_ARG);
    {
        noshi_tl_value *v = noshi_tl_new_obj(&arena, "langPackLanguage");
        CHECK_EQ_INT(noshi_tl_set_str(&arena, v, "name", "N"), NOSHI_OK);
        CHECK_EQ_INT(noshi_langpack_parse(v, &info), NOSHI_E_MALFORMED);
    }
}

static void test_percent(void) {
    CHECK_EQ_INT(noshi_langpack_percent(0, 0), 0);
    CHECK_EQ_INT(noshi_langpack_percent(5, 0), 0);
    CHECK_EQ_INT(noshi_langpack_percent(0, 100), 0);
    CHECK_EQ_INT(noshi_langpack_percent(-4, 100), 0);
    CHECK_EQ_INT(noshi_langpack_percent(1, 3000), 1);
    CHECK_EQ_INT(noshi_langpack_percent(2999, 3000), 100);
    CHECK_EQ_INT(noshi_langpack_percent(1500, 3000), 50);
    CHECK_EQ_INT(noshi_langpack_percent(3000, 3000), 100);
    CHECK_EQ_INT(noshi_langpack_percent(4000, 3000), 100);
    CHECK_EQ_INT(noshi_langpack_percent(2147483647, 2147483647), 100);
    CHECK_EQ_INT(noshi_langpack_percent(1073741823, 2147483647), 50);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_request();
    test_parse();
    test_percent();
    noshi_arena_free(&arena);
    return test_finish("test_langpack");
}
