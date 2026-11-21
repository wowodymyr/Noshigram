#include "noshi_base64.h"

static const char b64_alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

noshi_status noshi_base64_encode(const uint8_t *data, size_t len, char *out, size_t cap, size_t *out_len) {
    size_t need = (len + 2) / 3 * 4, i, o = 0;
    if (out_len) *out_len = 0;
    if (!out || !out_len || (len && !data)) return NOSHI_E_ARG;
    if (cap < need + 1) return NOSHI_E_LIMIT;
    for (i = 0; i + 3 <= len; i += 3) {
        uint32_t v = (uint32_t)data[i] << 16 | (uint32_t)data[i + 1] << 8 | data[i + 2];
        out[o++] = b64_alphabet[v >> 18 & 63];
        out[o++] = b64_alphabet[v >> 12 & 63];
        out[o++] = b64_alphabet[v >> 6 & 63];
        out[o++] = b64_alphabet[v & 63];
    }
    if (len - i == 1) {
        uint32_t v = (uint32_t)data[i] << 16;
        out[o++] = b64_alphabet[v >> 18 & 63];
        out[o++] = b64_alphabet[v >> 12 & 63];
        out[o++] = '=';
        out[o++] = '=';
    } else if (len - i == 2) {
        uint32_t v = (uint32_t)data[i] << 16 | (uint32_t)data[i + 1] << 8;
        out[o++] = b64_alphabet[v >> 18 & 63];
        out[o++] = b64_alphabet[v >> 12 & 63];
        out[o++] = b64_alphabet[v >> 6 & 63];
        out[o++] = '=';
    }
    out[o] = 0;
    *out_len = o;
    return NOSHI_OK;
}
