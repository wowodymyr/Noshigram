#include "noshi_logins.h"

#include <string.h>

#include "noshi_tl_ids.h"

noshi_status noshi_logins_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.getAuthorizations");
    if (!request) return NOSHI_E_NOMEM;
    *out = request;
    return NOSHI_OK;
}

/* copies a text field into dst whole characters at a time; empty when the field is missing */
static void copy_field(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

/* "region, country", leaving out what is empty and the region when it only repeats the country */
static void make_place(char *dst, size_t cap, const char *region, const char *country) {
    size_t at = 0, i;
    const char *parts[2] = {region, country};
    dst[0] = 0;
    for (i = 0; i < 2; ++i) {
        size_t len = strlen(parts[i]);
        if (!len || (i == 0 && !strcmp(region, country))) continue;
        if (at) {
            if (at + 2 >= cap) break;
            dst[at++] = ',';
            dst[at++] = ' ';
        }
        if (at + len >= cap) len = cap - 1 - at;
        while (len > 0 && (((unsigned char)parts[i][len]) & 0xC0u) == 0x80u) --len;
        memcpy(dst + at, parts[i], len);
        at += len;
        dst[at] = 0;
    }
}

noshi_status noshi_logins_parse(const noshi_tl_value *answer, noshi_unconfirmed_login *out, size_t cap, size_t *count) {
    const noshi_tl_value *list;
    uint32_t i;
    size_t found = 0, j;
    if (!count) return NOSHI_E_ARG;
    *count = 0;
    if (!out && cap) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_account_authorizations)) return NOSHI_E_MALFORMED;
    list = noshi_tl_get(answer, "authorizations");
    if (!list || list->kind != NOSHI_TL_V_VEC) return NOSHI_E_MALFORMED;
    for (i = 0; i < list->u.vec.count; ++i) {
        const noshi_tl_value *item = list->u.vec.items[i];
        noshi_unconfirmed_login login;
        char region[NOSHI_LOGIN_PLACE_MAX], country[NOSHI_LOGIN_PLACE_MAX];
        size_t at;
        if (!noshi_tl_is(item, NOSHI_TL_ID_authorization) || !noshi_tl_has(item, "unconfirmed") || noshi_tl_has(item, "current")) continue;
        memset(&login, 0, sizeof(login));
        if (noshi_tl_get_i64(item, "hash", &login.hash) != NOSHI_OK || login.hash == 0) continue;
        noshi_tl_get_i32(item, "date_created", &login.date);
        copy_field(login.device, sizeof(login.device), item, "device_model");
        if (!login.device[0]) copy_field(login.device, sizeof(login.device), item, "app_name");
        copy_field(region, sizeof(region), item, "region");
        copy_field(country, sizeof(country), item, "country");
        make_place(login.place, sizeof(login.place), region, country);
        /* newest first: the place in the list where this one belongs */
        at = found;
        while (at > 0 && out[at - 1].date < login.date) --at;
        if (found == cap && at == cap) continue;
        if (found < cap) ++found;
        for (j = found - 1; j > at; --j) out[j] = out[j - 1];
        out[at] = login;
    }
    *count = found;
    return NOSHI_OK;
}

static noshi_status hash_request(noshi_arena *arena, int64_t hash, const char *method, int confirm, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || hash == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, method);
    if (!request) return NOSHI_E_NOMEM;
    status = confirm ? noshi_tl_set_flag(request, "confirmed") : NOSHI_OK;
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", hash);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_login_confirm_request(noshi_arena *arena, int64_t hash, noshi_tl_value **out) {
    return hash_request(arena, hash, "account.changeAuthorizationSettings", 1, out);
}

noshi_status noshi_login_reset_request(noshi_arena *arena, int64_t hash, noshi_tl_value **out) {
    return hash_request(arena, hash, "account.resetAuthorization", 0, out);
}
