#include "noshi_passcode.h"

#include <string.h>

#include "noshi_bytes.h"
#include "noshi_crypto.h"

#define WAIT_FREE_TRIES 4u
#define WAIT_FIRST_SECONDS 5u
#define WAIT_MAX_SECONDS 300u

int noshi_passcode_valid(noshi_passcode_type type, const char *code, size_t len) {
    size_t i;
    if (!code) return 0;
    if (type == NOSHI_PASSCODE_PIN) {
        if (len != NOSHI_PASSCODE_PIN_LEN) return 0;
        for (i = 0; i < len; ++i) {
            if (code[i] < '0' || code[i] > '9') return 0;
        }
        return 1;
    }
    if (type != NOSHI_PASSCODE_PASSWORD || len == 0 || len > NOSHI_PASSCODE_MAX_LEN) return 0;
    for (i = 0; i < len; ++i) {
        unsigned char c = (unsigned char)code[i];
        if (c < 0x20 || c == 0x7f) return 0;
    }
    return 1;
}

noshi_status noshi_passcode_hash(const uint8_t salt[NOSHI_PASSCODE_SALT_LEN], const char *code, size_t len, char out[NOSHI_PASSCODE_HEX_LEN + 1]) {
    static const char digits[] = "0123456789abcdef";
    noshi_slice parts[3];
    uint8_t digest[NOSHI_SHA256_LEN];
    noshi_status status;
    size_t i;
    out[0] = '\0';
    if (!salt || !code || len == 0 || len > NOSHI_PASSCODE_MAX_LEN) return NOSHI_E_ARG;
    parts[0].data = salt;
    parts[0].len = NOSHI_PASSCODE_SALT_LEN;
    parts[1].data = (const uint8_t *)code;
    parts[1].len = len;
    parts[2] = parts[0];
    status = noshi_sha256(parts, 3, digest);
    if (status != NOSHI_OK) return status;
    for (i = 0; i < NOSHI_SHA256_LEN; ++i) {
        out[i * 2] = digits[digest[i] >> 4];
        out[i * 2 + 1] = digits[digest[i] & 15];
    }
    out[NOSHI_PASSCODE_HEX_LEN] = '\0';
    return NOSHI_OK;
}

int noshi_passcode_matches(const uint8_t salt[NOSHI_PASSCODE_SALT_LEN], const char *code, size_t len, const char *hex) {
    char made[NOSHI_PASSCODE_HEX_LEN + 1];
    if (!hex || strlen(hex) != NOSHI_PASSCODE_HEX_LEN) return 0;
    if (noshi_passcode_hash(salt, code, len, made) != NOSHI_OK) return 0;
    return noshi_ct_equal(made, hex, NOSHI_PASSCODE_HEX_LEN);
}

uint32_t noshi_passcode_wait_seconds(uint32_t failures) {
    uint32_t wait = WAIT_FIRST_SECONDS;
    if (failures <= WAIT_FREE_TRIES) return 0;
    for (failures -= WAIT_FREE_TRIES + 1; failures > 0 && wait < WAIT_MAX_SECONDS; --failures) wait *= 2;
    return wait < WAIT_MAX_SECONDS ? wait : WAIT_MAX_SECONDS;
}

int noshi_passcode_should_lock(uint32_t auto_lock, int64_t left_at, int64_t now) {
    if (auto_lock == 0) return 0;
    if (auto_lock == NOSHI_PASSCODE_AT_ONCE) return 1;
    if (left_at <= 0 || now < left_at) return 1;
    return now - left_at >= (int64_t)auto_lock;
}
