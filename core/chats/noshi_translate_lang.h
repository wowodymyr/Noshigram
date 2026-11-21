#ifndef NOSHI_TRANSLATE_LANG_H
#define NOSHI_TRANSLATE_LANG_H

#include <stddef.h>

#include "noshi_status.h"

/* the language codes of the translators */

#define NOSHI_TR_LANG_MAX 16

typedef enum {
    NOSHI_TR_GOOGLE = 1,
    NOSHI_TR_YANDEX = 3,
    NOSHI_TR_LINGO = 4,
    NOSHI_TR_BING = 5,
    NOSHI_TR_DEEPL = 7,
    NOSHI_TR_TELEGRAM = 8,
    NOSHI_TR_TRANSMART = 9,
    NOSHI_TR_LLM = 10
} noshi_tr_provider;

/* which API of Google answers: the new one of translate-pa, the Cloud API when a key is set, or else the one of the Google app */
typedef enum {
    NOSHI_TR_GOOGLE_NEW,
    NOSHI_TR_GOOGLE_CLOUD,
    NOSHI_TR_GOOGLE_APP
} noshi_tr_google_api;

/* the target language as the service wants it, from a code of the form "ru", "pt-BR", "zh_CN" (either separator,
   any case) */
noshi_status noshi_tr_target_for(int provider, int api, const char *code, char *out, size_t cap);

/* the target as the DeepL API names it: "EN-GB", "PT-BR", "ZH-HANS", "ZH-HANT", or the language in capitals */
noshi_status noshi_tr_deepl_target(const char *code, char *out, size_t cap);

#endif
