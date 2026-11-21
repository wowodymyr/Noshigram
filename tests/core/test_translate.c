#include "test_util.h"
#include "noshi_translate.h"
#include "noshi_tl_ids.h"

#include <string.h>

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static noshi_tl_value *answer_of(const char *text) {
    noshi_tl_value *result = obj("messages.translateResult"), *item = obj("textWithEntities"), *vec = noshi_tl_new_vec(&arena, 1);
    CHECK(vec != NULL);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, item, "text", text), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(item, "entities", noshi_tl_new_vec(&arena, 0)), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(vec, 0, item), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(result, "result", vec), NOSHI_OK);
    return result;
}

static void test_request(void) {
    noshi_tl_value *request = NULL, *decoded = NULL;
    noshi_writer writer;
    char big[NOSHI_TRANSLATE_TEXT_MAX + 2];
    CHECK_EQ_INT(noshi_translate_request(&arena, "hello", "ru", &request), NOSHI_OK);
    noshi_writer_init(&writer, 4096);
    CHECK_EQ_INT(noshi_tl_encode(request, &writer, NULL), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, writer.data, writer.len, &decoded), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(decoded), NOSHI_TL_ID_messages_translateText);
    noshi_writer_free(&writer);
    CHECK_EQ_INT(noshi_translate_request(&arena, "x", "zh-CN", &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_translate_request(&arena, "", "ru", &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_translate_request(&arena, "x", "", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_translate_request(&arena, "x", "ru;drop", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_translate_request(&arena, "x", "abcdefghijklmnop", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_translate_request(&arena, NULL, "ru", &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_translate_request(&arena, "x", "ru", NULL), NOSHI_E_ARG);
    memset(big, 'a', sizeof(big));
    big[NOSHI_TRANSLATE_TEXT_MAX] = 0;
    CHECK_EQ_INT(noshi_translate_request(&arena, big, "ru", &request), NOSHI_OK);
    big[NOSHI_TRANSLATE_TEXT_MAX] = 'a';
    big[NOSHI_TRANSLATE_TEXT_MAX + 1] = 0;
    CHECK_EQ_INT(noshi_translate_request(&arena, big, "ru", &request), NOSHI_E_ARG);
}

static void test_parse(void) {
    char out[16];
    CHECK_EQ_INT(noshi_translate_parse(answer_of("Привет"), out, sizeof(out)), NOSHI_OK);
    CHECK(!strcmp(out, "Привет"));
    /* cut at a character boundary, never inside one */
    CHECK_EQ_INT(noshi_translate_parse(answer_of("Привет"), out, 6), NOSHI_OK);
    CHECK(!strcmp(out, "Пр"));
    CHECK_EQ_INT(noshi_translate_parse(obj("boolTrue"), out, sizeof(out)), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(out[0], 0);
    {
        noshi_tl_value *empty = obj("messages.translateResult");
        CHECK_EQ_INT(noshi_tl_set(empty, "result", noshi_tl_new_vec(&arena, 0)), NOSHI_OK);
        CHECK_EQ_INT(noshi_translate_parse(empty, out, sizeof(out)), NOSHI_E_MALFORMED);
    }
    CHECK_EQ_INT(noshi_translate_parse(answer_of("x"), NULL, 4), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_translate_parse(answer_of("x"), out, 0), NOSHI_E_ARG);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_request();
    test_parse();
    noshi_arena_free(&arena);
    return test_finish("test_translate");
}
