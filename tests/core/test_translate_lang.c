#include "test_util.h"
#include "noshi_translate_lang.h"

#include <string.h>

static void target(int provider, int api, const char *code, noshi_status expected, const char *expected_code) {
    char out[NOSHI_TR_LANG_MAX];
    noshi_status status = noshi_tr_target_for(provider, api, code, out, sizeof(out));
    CHECK_EQ_INT(status, expected);
    if (expected == NOSHI_OK) CHECK(!strcmp(out, expected_code));
    else CHECK_EQ_INT(out[0], 0);
}

static void test_google(void) {
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_NEW, "ru", NOSHI_OK, "ru");
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_NEW, "RU", NOSHI_OK, "ru");
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_NEW, "zh_CN", NOSHI_OK, "zh-CN");
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_NEW, "zh-hk", NOSHI_OK, "zh-TW");
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_NEW, "zh", NOSHI_OK, "zh");
    /* the country is dropped from every other language, so "pt-BR" asks for "pt" */
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_NEW, "pt-BR", NOSHI_OK, "pt");
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_APP, "in", NOSHI_OK, "id");
    /* the languages of the new API that the old ones lack */
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_NEW, "yue", NOSHI_OK, "yue");
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_APP, "yue", NOSHI_E_UNSUPPORTED, NULL);
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_CLOUD, "yue", NOSHI_E_UNSUPPORTED, NULL);
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_CLOUD, "ceb", NOSHI_OK, "ceb");
    target(NOSHI_TR_GOOGLE, NOSHI_TR_GOOGLE_NEW, "xx", NOSHI_E_UNSUPPORTED, NULL);
}

static void test_other_services(void) {
    target(NOSHI_TR_DEEPL, 0, "en-GB", NOSHI_OK, "en-GB");
    target(NOSHI_TR_DEEPL, 0, "en_us", NOSHI_OK, "en-US");
    target(NOSHI_TR_DEEPL, 0, "en-AU", NOSHI_OK, "en");
    target(NOSHI_TR_DEEPL, 0, "pt-br", NOSHI_OK, "pt-BR");
    target(NOSHI_TR_DEEPL, 0, "pt", NOSHI_OK, "pt");
    target(NOSHI_TR_DEEPL, 0, "zh", NOSHI_OK, "zh");
    target(NOSHI_TR_DEEPL, 0, "zh-CN", NOSHI_OK, "zh-CN");
    target(NOSHI_TR_DEEPL, 0, "zh-HK", NOSHI_OK, "zh-TW");
    target(NOSHI_TR_YANDEX, 0, "pt-BR", NOSHI_OK, "pt-BR");
    target(NOSHI_TR_YANDEX, 0, "pt-PT", NOSHI_OK, "pt");
    target(NOSHI_TR_YANDEX, 0, "de-AT", NOSHI_OK, "de");
    target(NOSHI_TR_TELEGRAM, 0, "zh-TW", NOSHI_OK, "zh-TW");
    target(NOSHI_TR_TELEGRAM, 0, "zh_CN", NOSHI_OK, "zh-CN");
    target(NOSHI_TR_TELEGRAM, 0, "zh-HK", NOSHI_OK, "zh");
    target(NOSHI_TR_TELEGRAM, 0, "pt-BR", NOSHI_OK, "pt");
    target(NOSHI_TR_TELEGRAM, 0, "ru", NOSHI_OK, "ru");
    target(NOSHI_TR_LINGO, 0, "ru", NOSHI_OK, "ru");
    target(NOSHI_TR_LINGO, 0, "de", NOSHI_E_UNSUPPORTED, NULL);
    target(NOSHI_TR_BING, 0, "ru", NOSHI_OK, "ru");
    target(NOSHI_TR_BING, 0, "zh", NOSHI_OK, "zh-Hans");
    target(NOSHI_TR_BING, 0, "zh-CN", NOSHI_OK, "zh-Hans");
    target(NOSHI_TR_BING, 0, "zh_TW", NOSHI_OK, "zh-Hant");
    target(NOSHI_TR_BING, 0, "zh-HK", NOSHI_OK, "zh-Hant");
    target(NOSHI_TR_BING, 0, "pt-PT", NOSHI_OK, "pt-PT");
    target(NOSHI_TR_BING, 0, "pt-BR", NOSHI_OK, "pt");
    target(NOSHI_TR_BING, 0, "no", NOSHI_E_UNSUPPORTED, NULL);
    target(NOSHI_TR_BING, 0, "sr", NOSHI_E_UNSUPPORTED, NULL);
    target(NOSHI_TR_TRANSMART, 0, "fil", NOSHI_OK, "fil");
    target(NOSHI_TR_TRANSMART, 0, "uk", NOSHI_E_UNSUPPORTED, NULL);
    target(NOSHI_TR_LLM, 0, "pt-BR", NOSHI_OK, "pt");
    target(NOSHI_TR_LLM, 0, "xx", NOSHI_OK, "xx");
}

static void test_bad_codes(void) {
    char out[NOSHI_TR_LANG_MAX];
    target(NOSHI_TR_GOOGLE, 0, "", NOSHI_E_ARG, NULL);
    target(NOSHI_TR_GOOGLE, 0, "r", NOSHI_E_ARG, NULL);
    target(NOSHI_TR_GOOGLE, 0, "russian", NOSHI_E_ARG, NULL);
    target(NOSHI_TR_GOOGLE, 0, "ru;drop", NOSHI_E_ARG, NULL);
    target(NOSHI_TR_GOOGLE, 0, "ru-", NOSHI_E_ARG, NULL);
    target(NOSHI_TR_GOOGLE, 0, "ru-R", NOSHI_E_ARG, NULL);
    target(NOSHI_TR_GOOGLE, 0, "ru-RU-x", NOSHI_E_ARG, NULL);
    target(NOSHI_TR_GOOGLE, 0, "r1", NOSHI_E_ARG, NULL);
    target(77, 0, "ru", NOSHI_E_ARG, NULL);
    CHECK_EQ_INT(noshi_tr_target_for(NOSHI_TR_GOOGLE, 0, NULL, out, sizeof(out)), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_tr_target_for(NOSHI_TR_GOOGLE, 0, "ru", NULL, 8), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_tr_target_for(NOSHI_TR_GOOGLE, 0, "ru", out, 0), NOSHI_E_ARG);
    /* a buffer that cannot hold the answer is refused, never cut */
    CHECK_EQ_INT(noshi_tr_target_for(NOSHI_TR_DEEPL, 0, "pt-BR", out, 4), NOSHI_E_ARG);
}

static void deepl(const char *code, noshi_status expected, const char *expected_code) {
    char out[NOSHI_TR_LANG_MAX];
    CHECK_EQ_INT(noshi_tr_deepl_target(code, out, sizeof(out)), expected);
    if (expected == NOSHI_OK) CHECK(!strcmp(out, expected_code));
}

static void test_deepl_target(void) {
    deepl("ru", NOSHI_OK, "RU");
    deepl("en-GB", NOSHI_OK, "EN-GB");
    deepl("pt_br", NOSHI_OK, "PT-BR");
    deepl("zh-CN", NOSHI_OK, "ZH-HANS");
    deepl("zh-hans", NOSHI_OK, "ZH-HANS");
    deepl("zh-TW", NOSHI_OK, "ZH-HANT");
    deepl("zh-HK", NOSHI_OK, "ZH-HANT");
    deepl("zh", NOSHI_OK, "ZH");
    deepl("", NOSHI_E_ARG, NULL);
    deepl(NULL, NOSHI_E_ARG, NULL);
    deepl("averyveryverylongcodethatdoesnotfit", NOSHI_E_ARG, NULL);
}

int main(void) {
    test_google();
    test_other_services();
    test_bad_codes();
    test_deepl_target();
    return test_finish("test_translate_lang");
}
