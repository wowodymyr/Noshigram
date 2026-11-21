#include "noshi_langpack.h"

#include <string.h>

#include "noshi_tl_ids.h"

#define PACK_NAME_MAX 17
#define CODE_INPUT_MAX 32

static int word_ok(const char *s, size_t max, int allow_digits) {
    size_t i;
    if (!s || !s[0]) return 0;
    for (i = 0; s[i]; ++i) {
        char c = s[i];
        int letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        int extra = (c >= '0' && c <= '9') || c == '-' || c == '_';
        if (i >= max || !(letter || (allow_digits && extra))) return 0;
    }
    return 1;
}

noshi_status noshi_langpack_request(noshi_arena *arena, const char *lang_pack, const char *lang_code, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !word_ok(lang_pack, PACK_NAME_MAX - 1, 0) || !word_ok(lang_code, CODE_INPUT_MAX, 1)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "langpack.getLanguage");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "lang_pack", lang_pack);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "lang_code", lang_code);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* a string field into a buffer: whole when it fits, else cut at a character boundary when cut is set, else NOSHI_E_MALFORMED */
static noshi_status take(const noshi_tl_value *obj, const char *field, char *dst, size_t cap, int cut, int required) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (!noshi_tl_has(obj, field)) return required ? NOSHI_E_MALFORMED : NOSHI_OK;
    if (noshi_tl_get_bytes(obj, field, &data, &len) != NOSHI_OK || (!data && len)) return NOSHI_E_MALFORMED;
    if (len >= cap) {
        if (!cut) return NOSHI_E_MALFORMED;
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    if (len) memcpy(dst, data, len);
    dst[len] = 0;
    return NOSHI_OK;
}

noshi_status noshi_langpack_parse(const noshi_tl_value *answer, noshi_langpack_info *out) {
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_langPackLanguage)) return NOSHI_E_MALFORMED;
    out->official = noshi_tl_has(answer, "official");
    out->rtl = noshi_tl_has(answer, "rtl");
    status = take(answer, "name", out->name, sizeof(out->name), 1, 1);
    if (status == NOSHI_OK) status = take(answer, "native_name", out->native_name, sizeof(out->native_name), 1, 1);
    if (status == NOSHI_OK) status = take(answer, "lang_code", out->lang_code, sizeof(out->lang_code), 0, 1);
    if (status == NOSHI_OK) status = take(answer, "base_lang_code", out->base_lang_code, sizeof(out->base_lang_code), 0, 0);
    if (status == NOSHI_OK) status = take(answer, "translations_url", out->translations_url, sizeof(out->translations_url), 1, 0);
    if (status == NOSHI_OK && !out->name[0]) status = NOSHI_E_MALFORMED;
    if (status == NOSHI_OK && !out->lang_code[0]) status = NOSHI_E_MALFORMED;
    if (status == NOSHI_OK) status = noshi_tl_get_i32(answer, "strings_count", &out->strings_count);
    if (status == NOSHI_OK) status = noshi_tl_get_i32(answer, "translated_count", &out->translated_count);
    if (status == NOSHI_OK && (out->strings_count < 0 || out->translated_count < 0)) status = NOSHI_E_MALFORMED;
    if (status != NOSHI_OK) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    return NOSHI_OK;
}

int noshi_langpack_percent(int32_t translated, int32_t strings) {
    int64_t share;
    if (strings <= 0 || translated <= 0) return 0;
    if (translated >= strings) return 100;
    share = ((int64_t)translated * 100 + strings - 1) / strings;
    return (int)share;
}
