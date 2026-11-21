#include "noshi_app_config.h"

#include <math.h>
#include <string.h>

#include "noshi_tl_ids.h"

noshi_status noshi_app_config_i32(const noshi_tl_value *answer, const char *key, int32_t *out) {
    const noshi_tl_value *config, *entries;
    size_t key_len;
    if (out) *out = 0;
    if (!out || !key || !key[0] || !noshi_tl_is(answer, NOSHI_TL_ID_help_appConfig)) return NOSHI_E_MALFORMED;
    key_len = strlen(key);
    config = noshi_tl_get(answer, "config");
    if (!noshi_tl_is(config, NOSHI_TL_ID_jsonObject) || noshi_tl_get_vec(config, "value", &entries) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (uint32_t i = 0; i < entries->u.vec.count; ++i) {
        const noshi_tl_value *entry = entries->u.vec.items[i], *value;
        const uint8_t *name;
        size_t len;
        double number;
        if (!noshi_tl_is(entry, NOSHI_TL_ID_jsonObjectValue) || noshi_tl_get_bytes(entry, "key", &name, &len) != NOSHI_OK ||
            !name || len != key_len || memcmp(name, key, len)) continue;
        value = noshi_tl_get(entry, "value");
        if (!noshi_tl_is(value, NOSHI_TL_ID_jsonNumber) || noshi_tl_get_f64(value, "value", &number) != NOSHI_OK ||
            !isfinite(number) || number < 0 || number > INT32_MAX || floor(number) != number) return NOSHI_E_MALFORMED;
        *out = (int32_t)number;
        return NOSHI_OK;
    }
    return NOSHI_E_NOTFOUND;
}
