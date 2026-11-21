#include "test_util.h"
#include "noshi_content.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void test_requests(void) {
    noshi_tl_value *request = NULL;
    noshi_writer wire;
    CHECK_EQ_INT(noshi_content_settings_request(&arena, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_account_getContentSettings);
    noshi_writer_init(&wire, 64);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_content_set_request(&arena, 1, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_account_setContentSettings);
    CHECK(noshi_tl_has(request, "sensitive_enabled"));
    noshi_writer_init(&wire, 64);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_content_set_request(&arena, 0, &request), NOSHI_OK);
    CHECK(!noshi_tl_has(request, "sensitive_enabled"));
    CHECK_EQ_INT(noshi_content_settings_request(NULL, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_content_settings_request(&arena, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_content_set_request(&arena, 1, NULL), NOSHI_E_ARG);
}

static void test_parse(void) {
    noshi_content_settings out;
    noshi_tl_value *answer = obj("account.contentSettings");
    CHECK_EQ_INT(noshi_content_settings_parse(answer, &out), NOSHI_OK);
    CHECK_EQ_INT(out.sensitive_enabled, 0);
    CHECK_EQ_INT(out.sensitive_can_change, 0);
    CHECK_EQ_INT(noshi_tl_set_flag(answer, "sensitive_enabled"), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_flag(answer, "sensitive_can_change"), NOSHI_OK);
    CHECK_EQ_INT(noshi_content_settings_parse(answer, &out), NOSHI_OK);
    CHECK_EQ_INT(out.sensitive_enabled, 1);
    CHECK_EQ_INT(out.sensitive_can_change, 1);
    /* a wrong answer leaves nothing behind, and a missing output is refused */
    CHECK_EQ_INT(noshi_content_settings_parse(obj("boolTrue"), &out), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(out.sensitive_enabled, 0);
    CHECK_EQ_INT(noshi_content_settings_parse(NULL, &out), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_content_settings_parse(answer, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_content_set_parse(obj("boolTrue")), NOSHI_OK);
    CHECK_EQ_INT(noshi_content_set_parse(obj("boolFalse")), NOSHI_E_STATE);
    CHECK_EQ_INT(noshi_content_set_parse(obj("updates")), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_content_set_parse(NULL), NOSHI_E_MALFORMED);
}

int main(void) {
    noshi_arena_init(&arena, 1024u * 1024u);
    test_requests();
    test_parse();
    noshi_arena_free(&arena);
    return test_finish("test_content");
}
