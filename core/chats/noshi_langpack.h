#ifndef NOSHI_LANGPACK_H
#define NOSHI_LANGPACK_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_tl.h"

/* what a t.me/setlanguage link names: langpack.getLanguage on a pack code, and the langPackLanguage that comes back */

#define NOSHI_LANGPACK_NAME_MAX 96
#define NOSHI_LANGPACK_CODE_MAX 33
#define NOSHI_LANGPACK_URL_MAX 256

typedef struct noshi_langpack_info {
    int official;
    int rtl;
    char name[NOSHI_LANGPACK_NAME_MAX];           /* in English */
    char native_name[NOSHI_LANGPACK_NAME_MAX];
    char lang_code[NOSHI_LANGPACK_CODE_MAX];
    char base_lang_code[NOSHI_LANGPACK_CODE_MAX]; /* the language the pack builds on, empty without one */
    int32_t strings_count;
    int32_t translated_count;
    char translations_url[NOSHI_LANGPACK_URL_MAX];
} noshi_langpack_info;

/* langpack.getLanguage for a pack of a platform ("ios": letters, 1 to 16) and a language code (letters, digits, dash and underscore,
   1 to 32); anything else is NOSHI_E_ARG */
noshi_status noshi_langpack_request(noshi_arena *arena, const char *lang_pack, const char *lang_code, noshi_tl_value **out);

/* a langPackLanguage. a name or a code that does not fit, a missing field and negative counts are NOSHI_E_MALFORMED, with out zeroed; a
   long url is cut at a character boundary */
noshi_status noshi_langpack_parse(const noshi_tl_value *answer, noshi_langpack_info *out);

/* how much of the pack is translated, as the official clients say it: the share rounded up, 0 when the pack has no strings and 100 at most */
int noshi_langpack_percent(int32_t translated, int32_t strings);

#endif
