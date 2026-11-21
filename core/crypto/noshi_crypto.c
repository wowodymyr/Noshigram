#include "noshi_crypto.h"

#include <stdlib.h>
#include <string.h>

#include <openssl/bn.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/opensslv.h>

static noshi_status digest_parts(const EVP_MD *md, const noshi_slice *parts, size_t count,
                                   uint8_t *out, unsigned expected) {
    EVP_MD_CTX *ctx;
    unsigned got = 0;
    size_t i;
    noshi_status status = NOSHI_E_CRYPTO;
    if (!md || !out || (count && !parts)) return NOSHI_E_ARG;
    ctx = EVP_MD_CTX_new();
    if (!ctx) return NOSHI_E_NOMEM;
    if (EVP_DigestInit_ex(ctx, md, NULL) != 1) goto done;
    for (i = 0; i < count; ++i) {
        if (parts[i].len == 0) continue;
        if (!parts[i].data || EVP_DigestUpdate(ctx, parts[i].data, parts[i].len) != 1) goto done;
    }
    if (EVP_DigestFinal_ex(ctx, out, &got) != 1 || got != expected) goto done;
    status = NOSHI_OK;
done:
    EVP_MD_CTX_free(ctx);
    return status;
}

noshi_status noshi_sha1(const noshi_slice *parts, size_t count, uint8_t out[NOSHI_SHA1_LEN]) {
    return digest_parts(EVP_sha1(), parts, count, out, NOSHI_SHA1_LEN);
}

noshi_status noshi_sha256(const noshi_slice *parts, size_t count, uint8_t out[NOSHI_SHA256_LEN]) {
    return digest_parts(EVP_sha256(), parts, count, out, NOSHI_SHA256_LEN);
}

noshi_status noshi_md5(const noshi_slice *parts, size_t count, uint8_t out[NOSHI_MD5_LEN]) {
    return digest_parts(EVP_md5(), parts, count, out, NOSHI_MD5_LEN);
}

noshi_status noshi_sha1_one(const void *data, size_t len, uint8_t out[NOSHI_SHA1_LEN]) {
    noshi_slice part;
    part.data = (const uint8_t *)data;
    part.len = len;
    return noshi_sha1(&part, 1, out);
}

noshi_status noshi_sha256_one(const void *data, size_t len, uint8_t out[NOSHI_SHA256_LEN]) {
    noshi_slice part;
    part.data = (const uint8_t *)data;
    part.len = len;
    return noshi_sha256(&part, 1, out);
}

noshi_status noshi_hmac_sha1(const uint8_t *key, size_t key_len, const noshi_slice *parts, size_t count,
                                 uint8_t out[NOSHI_SHA1_LEN]) {
    uint8_t joined[NOSHI_HMAC_MAX_MESSAGE];
    size_t used = 0, i;
    unsigned got = 0;
    if (!out || (key_len && !key) || (count && !parts) || key_len > 0x7fffffffu) return NOSHI_E_ARG;
    for (i = 0; i < count; ++i) {
        if (parts[i].len == 0) continue;
        if (!parts[i].data) return NOSHI_E_ARG;
        if (parts[i].len > sizeof(joined) - used) return NOSHI_E_LIMIT;
        memcpy(joined + used, parts[i].data, parts[i].len);
        used += parts[i].len;
    }
    if (!HMAC(EVP_sha1(), key ? key : (const uint8_t *)"", (int)key_len, joined, used, out, &got) || got != NOSHI_SHA1_LEN) return NOSHI_E_CRYPTO;
    return NOSHI_OK;
}

noshi_status noshi_aes128_ctr(const uint8_t key[16], const uint8_t iv[16], const uint8_t *in, uint8_t *out, size_t len) {
    EVP_CIPHER_CTX *ctx;
    size_t done = 0;
    noshi_status status = NOSHI_E_CRYPTO;
    if (!key || !iv || (len && (!in || !out))) return NOSHI_E_ARG;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return NOSHI_E_NOMEM;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_128_ctr(), NULL, key, iv) != 1) goto done;
    while (done < len) {
        size_t step = len - done;
        int outl = 0;
        if (step > 0x40000000u) step = 0x40000000u;
        if (EVP_EncryptUpdate(ctx, out + done, &outl, in + done, (int)step) != 1 || (size_t)outl != step) goto done;
        done += step;
    }
    status = NOSHI_OK;
done:
    EVP_CIPHER_CTX_free(ctx);
    return status;
}

noshi_status noshi_x25519_public(const uint8_t priv[NOSHI_X25519_LEN], uint8_t pub[NOSHI_X25519_LEN]) {
    EVP_PKEY *key;
    size_t len = NOSHI_X25519_LEN;
    noshi_status status = NOSHI_E_CRYPTO;
    if (!priv || !pub) return NOSHI_E_ARG;
    key = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, priv, NOSHI_X25519_LEN);
    if (!key) return NOSHI_E_CRYPTO;
    if (EVP_PKEY_get_raw_public_key(key, pub, &len) == 1 && len == NOSHI_X25519_LEN) status = NOSHI_OK;
    EVP_PKEY_free(key);
    return status;
}

noshi_status noshi_x25519_shared(const uint8_t priv[NOSHI_X25519_LEN], const uint8_t peer[NOSHI_X25519_LEN], uint8_t out[NOSHI_X25519_LEN]) {
    EVP_PKEY *own, *other;
    EVP_PKEY_CTX *ctx = NULL;
    size_t len = NOSHI_X25519_LEN;
    uint8_t zero = 0;
    size_t i;
    noshi_status status = NOSHI_E_CRYPTO;
    if (!priv || !peer || !out) return NOSHI_E_ARG;
    own = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, priv, NOSHI_X25519_LEN);
    other = EVP_PKEY_new_raw_public_key(EVP_PKEY_X25519, NULL, peer, NOSHI_X25519_LEN);
    if (!own || !other) goto done;
    ctx = EVP_PKEY_CTX_new(own, NULL);
    if (!ctx || EVP_PKEY_derive_init(ctx) != 1 || EVP_PKEY_derive_set_peer(ctx, other) != 1) goto done;
    /* with two well formed keys the only way derive fails is a peer point of small order, which openssl refuses */
    if (EVP_PKEY_derive(ctx, out, &len) != 1) {
        status = NOSHI_E_SECURITY;
        goto done;
    }
    if (len != NOSHI_X25519_LEN) goto done;
    for (i = 0; i < NOSHI_X25519_LEN; ++i) zero |= out[i];
    if (zero == 0) {
        status = NOSHI_E_SECURITY;
        goto done;
    }
    status = NOSHI_OK;
done:
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(own);
    EVP_PKEY_free(other);
    if (status != NOSHI_OK) noshi_wipe(out, NOSHI_X25519_LEN);
    return status;
}

static noshi_status chacha_run(int encrypt, const uint8_t key[NOSHI_CHACHA_KEY_LEN], const uint8_t nonce[NOSHI_CHACHA_NONCE_LEN],
                                 const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out, uint8_t *tag) {
    EVP_CIPHER_CTX *ctx;
    uint8_t final_block[NOSHI_POLY1305_TAG_LEN];
    int outl = 0;
    noshi_status status = NOSHI_E_CRYPTO;
    if (!key || !nonce || (ad_len && !ad) || (len && (!in || !out)) || !tag || ad_len > 0x40000000u || len > 0x40000000u) return NOSHI_E_ARG;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return NOSHI_E_NOMEM;
    if (EVP_CipherInit_ex(ctx, EVP_chacha20_poly1305(), NULL, key, nonce, encrypt) != 1) goto done;
    if (!encrypt && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, NOSHI_POLY1305_TAG_LEN, tag) != 1) goto done;
    if (ad_len && EVP_CipherUpdate(ctx, NULL, &outl, ad, (int)ad_len) != 1) goto done;
    if (len) {
        if (EVP_CipherUpdate(ctx, out, &outl, in, (int)len) != 1 || (size_t)outl != len) goto done;
    }
    if (EVP_CipherFinal_ex(ctx, final_block, &outl) != 1) {
        /* a decryption whose tag fails ends here, and nothing it produced may be used */
        status = encrypt ? NOSHI_E_CRYPTO : NOSHI_E_SECURITY;
        if (!encrypt && len) noshi_wipe(out, len);
        goto done;
    }
    if (encrypt && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, NOSHI_POLY1305_TAG_LEN, tag) != 1) goto done;
    status = NOSHI_OK;
done:
    EVP_CIPHER_CTX_free(ctx);
    return status;
}

noshi_status noshi_chacha20poly1305_seal(const uint8_t key[NOSHI_CHACHA_KEY_LEN], const uint8_t nonce[NOSHI_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             uint8_t tag[NOSHI_POLY1305_TAG_LEN]) {
    return chacha_run(1, key, nonce, ad, ad_len, in, len, out, tag);
}

noshi_status noshi_chacha20poly1305_open(const uint8_t key[NOSHI_CHACHA_KEY_LEN], const uint8_t nonce[NOSHI_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             const uint8_t tag[NOSHI_POLY1305_TAG_LEN]) {
    uint8_t copy[NOSHI_POLY1305_TAG_LEN];
    noshi_status status;
    if (!tag) return NOSHI_E_ARG;
    memcpy(copy, tag, sizeof(copy));
    status = chacha_run(0, key, nonce, ad, ad_len, in, len, out, copy);
    return status;
}

noshi_status noshi_pbkdf2_sha512(const uint8_t *password, size_t password_len,
                                     const uint8_t *salt, size_t salt_len,
                                     uint32_t iterations, uint8_t *out, size_t out_len) {
    if (!password || !salt || !out || iterations == 0 || out_len == 0) return NOSHI_E_ARG;
    if (password_len > 0x7fffffffu || salt_len > 0x7fffffffu || out_len > 0x7fffffffu) return NOSHI_E_LIMIT;
    if (PKCS5_PBKDF2_HMAC((const char *)password, (int)password_len, salt, (int)salt_len,
                          (int)iterations, EVP_sha512(), (int)out_len, out) != 1) return NOSHI_E_CRYPTO;
    return NOSHI_OK;
}

/* evp has no ige mode, so chaining must use its ecb block primitive */
noshi_status noshi_aes_ige(const uint8_t key[32], const uint8_t iv[32], int encrypt,
                               const uint8_t *in, uint8_t *out, size_t len) {
    EVP_CIPHER_CTX *ctx;
    uint8_t prev_c[16], prev_p[16], block[16], res[16];
    size_t off;
    int outl;
    unsigned i;
    noshi_status status = NOSHI_E_CRYPTO;
    if (!key || !iv || (len && (!in || !out)) || (len % 16) != 0) return NOSHI_E_ARG;
    if (len == 0) return NOSHI_OK;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return NOSHI_E_NOMEM;
    if (EVP_CipherInit_ex(ctx, EVP_aes_256_ecb(), NULL, key, NULL, encrypt ? 1 : 0) != 1) goto done;
    EVP_CIPHER_CTX_set_padding(ctx, 0);
    memcpy(prev_c, iv, 16);
    memcpy(prev_p, iv + 16, 16);
    for (off = 0; off < len; off += 16) {
        memcpy(block, in + off, 16);
        if (encrypt) {
            uint8_t x[16];
            for (i = 0; i < 16; ++i) x[i] = (uint8_t)(block[i] ^ prev_c[i]);
            if (EVP_CipherUpdate(ctx, res, &outl, x, 16) != 1 || outl != 16) goto done;
            for (i = 0; i < 16; ++i) res[i] ^= prev_p[i];
            memcpy(prev_c, res, 16);
            memcpy(prev_p, block, 16);
        } else {
            uint8_t x[16];
            for (i = 0; i < 16; ++i) x[i] = (uint8_t)(block[i] ^ prev_p[i]);
            if (EVP_CipherUpdate(ctx, res, &outl, x, 16) != 1 || outl != 16) goto done;
            for (i = 0; i < 16; ++i) res[i] ^= prev_c[i];
            memcpy(prev_p, res, 16);
            memcpy(prev_c, block, 16);
        }
        memcpy(out + off, res, 16);
    }
    status = NOSHI_OK;
done:
    noshi_wipe(prev_c, sizeof(prev_c));
    noshi_wipe(prev_p, sizeof(prev_p));
    noshi_wipe(block, sizeof(block));
    noshi_wipe(res, sizeof(res));
    EVP_CIPHER_CTX_free(ctx);
    return status;
}

struct noshi_aes_ctr {
    EVP_CIPHER_CTX *ctx;
};

noshi_aes_ctr *noshi_aes_ctr_new(const uint8_t key[32], const uint8_t iv[16]) {
    noshi_aes_ctr *c;
    if (!key || !iv) return NULL;
    c = (noshi_aes_ctr *)calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->ctx = EVP_CIPHER_CTX_new();
    if (!c->ctx || EVP_EncryptInit_ex(c->ctx, EVP_aes_256_ctr(), NULL, key, iv) != 1) {
        noshi_aes_ctr_free(c);
        return NULL;
    }
    return c;
}

noshi_status noshi_aes_ctr_apply(noshi_aes_ctr *ctr, const uint8_t *in, uint8_t *out, size_t len) {
    size_t done = 0;
    if (!ctr || (len && (!in || !out))) return NOSHI_E_ARG;
    while (done < len) {
        size_t step = len - done;
        int outl = 0;
        if (step > 0x40000000u) step = 0x40000000u;
        if (EVP_EncryptUpdate(ctr->ctx, out + done, &outl, in + done, (int)step) != 1 || (size_t)outl != step)
            return NOSHI_E_CRYPTO;
        done += step;
    }
    return NOSHI_OK;
}

void noshi_aes_ctr_free(noshi_aes_ctr *ctr) {
    if (!ctr) return;
    EVP_CIPHER_CTX_free(ctr->ctx);
    free(ctr);
}

#define BNP(x) ((BIGNUM *)(x))
#define BNC(x) ((const BIGNUM *)(x))

noshi_bn *noshi_bn_from_bin(const uint8_t *be, size_t len) {
    if (len && !be) return NULL;
    if (len > 0x7fffffffu) return NULL;
    return (noshi_bn *)BN_bin2bn(be, (int)len, NULL);
}

noshi_bn *noshi_bn_from_u64(uint64_t value) {
    uint8_t b[8];
    noshi_put_u64be(b, value);
    return noshi_bn_from_bin(b, sizeof(b));
}

void noshi_bn_free(noshi_bn *bn) {
    BN_clear_free(BNP(bn));
}

size_t noshi_bn_bits(const noshi_bn *bn) {
    return (size_t)BN_num_bits(BNC(bn));
}

size_t noshi_bn_bytes(const noshi_bn *bn) {
    return (size_t)BN_num_bytes(BNC(bn));
}

int noshi_bn_cmp(const noshi_bn *a, const noshi_bn *b) {
    return BN_cmp(BNC(a), BNC(b));
}

int noshi_bn_is_zero(const noshi_bn *bn) {
    return BN_is_zero(BNC(bn)) ? 1 : 0;
}

noshi_status noshi_bn_to_bin_padded(const noshi_bn *bn, uint8_t *out, size_t len) {
    if (!bn || !out || len > 0x7fffffffu) return NOSHI_E_ARG;
    if (noshi_bn_bytes(bn) > len) return NOSHI_E_LIMIT;
    if (BN_bn2binpad(BNC(bn), out, (int)len) != (int)len) return NOSHI_E_CRYPTO;
    return NOSHI_OK;
}

noshi_status noshi_bn_to_bin(const noshi_bn *bn, uint8_t *out, size_t cap, size_t *len) {
    size_t n;
    if (!bn || !len) return NOSHI_E_ARG;
    n = noshi_bn_bytes(bn);
    *len = n;
    if (n > cap) return NOSHI_E_LIMIT;
    if (n && (!out || BN_bn2bin(BNC(bn), out) != (int)n)) return NOSHI_E_CRYPTO;
    return NOSHI_OK;
}

static noshi_bn *bn_result(BIGNUM *r, int ok) {
    if (!ok) {
        BN_clear_free(r);
        return NULL;
    }
    return (noshi_bn *)r;
}

noshi_bn *noshi_bn_add(const noshi_bn *a, const noshi_bn *b) {
    BIGNUM *r = BN_new();
    if (!r) return NULL;
    return bn_result(r, BN_add(r, BNC(a), BNC(b)));
}

noshi_bn *noshi_bn_sub(const noshi_bn *a, const noshi_bn *b) {
    BIGNUM *r;
    if (BN_cmp(BNC(a), BNC(b)) < 0) return NULL;
    r = BN_new();
    if (!r) return NULL;
    return bn_result(r, BN_sub(r, BNC(a), BNC(b)));
}

noshi_bn *noshi_bn_mul(const noshi_bn *a, const noshi_bn *b) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && BN_mul(r, BNC(a), BNC(b), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

noshi_bn *noshi_bn_mod(const noshi_bn *a, const noshi_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_nnmod(r, BNC(a), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

noshi_bn *noshi_bn_mod_add(const noshi_bn *a, const noshi_bn *b, const noshi_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_mod_add(r, BNC(a), BNC(b), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

noshi_bn *noshi_bn_mod_sub(const noshi_bn *a, const noshi_bn *b, const noshi_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_mod_sub(r, BNC(a), BNC(b), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

noshi_bn *noshi_bn_mod_mul(const noshi_bn *a, const noshi_bn *b, const noshi_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_mod_mul(r, BNC(a), BNC(b), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

noshi_bn *noshi_bn_mod_exp(const noshi_bn *base, const noshi_bn *exp, const noshi_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_mod_exp(r, BNC(base), BNC(exp), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

noshi_bn *noshi_bn_mod_exp_secret(const noshi_bn *base, const noshi_bn *exp, const noshi_bn *m) {
    BIGNUM *r;
    BN_CTX *ctx;
    int ok;
    if (!base || !exp || !m || !BN_is_odd(BNC(m))) return NULL;
    r = BN_new();
    ctx = BN_CTX_new();
    /* dh and srp exponents must not choose a password-dependent multiplication schedule */
    ok = r && ctx && BN_mod_exp_mont_consttime(r, BNC(base), BNC(exp), BNC(m), ctx, NULL);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

noshi_bn *noshi_bn_rshift1(const noshi_bn *a) {
    BIGNUM *r = BN_new();
    if (!r) return NULL;
    return bn_result(r, BN_rshift1(r, BNC(a)));
}

uint32_t noshi_bn_mod_word(const noshi_bn *a, uint32_t word) {
    BN_ULONG r;
    if (word == 0) return UINT32_MAX;
    r = BN_mod_word(BNC(a), word);
    if (r == (BN_ULONG)-1) return UINT32_MAX;
    return (uint32_t)r;
}

/* dh validation needs the same minimum 64 rounds with both supported openssl versions */
int noshi_bn_is_prime(const noshi_bn *a) {
    BN_CTX *ctx;
    int prime;
    if (!a) return 0;
    ctx = BN_CTX_new();
    if (!ctx) return 0;
#if OPENSSL_VERSION_NUMBER >= 0x30000000L
    prime = BN_check_prime(BNC(a), ctx, NULL) == 1;
#else
    prime = BN_is_prime_ex(BNC(a), 64, ctx, NULL) == 1;
#endif
    BN_CTX_free(ctx);
    return prime;
}

noshi_status noshi_rsa_public_raw(const uint8_t *n, size_t n_len, uint32_t e,
                                      const uint8_t *in, size_t in_len, uint8_t *out) {
    noshi_bn *bn_n = noshi_bn_from_bin(n, n_len);
    noshi_bn *bn_e = noshi_bn_from_u64(e);
    noshi_bn *bn_in = noshi_bn_from_bin(in, in_len);
    noshi_bn *r = NULL;
    noshi_status status = NOSHI_E_CRYPTO;
    if (!bn_n || !bn_e || !bn_in) goto done;
    if (noshi_bn_cmp(bn_in, bn_n) >= 0) {
        status = NOSHI_E_ARG;
        goto done;
    }
    r = noshi_bn_mod_exp(bn_in, bn_e, bn_n);
    if (!r) goto done;
    status = noshi_bn_to_bin_padded(r, out, n_len);
done:
    noshi_bn_free(bn_n);
    noshi_bn_free(bn_e);
    noshi_bn_free(bn_in);
    noshi_bn_free(r);
    return status;
}

struct noshi_digest {
    EVP_MD_CTX *ctx;
    size_t length;
    int done;
};

noshi_digest *noshi_digest_new(int sha256) {
    noshi_digest *digest = calloc(1, sizeof(*digest));
    if (!digest) return NULL;
    digest->ctx = EVP_MD_CTX_new();
    digest->length = sha256 ? 32u : 16u;
    if (!digest->ctx || EVP_DigestInit_ex(digest->ctx, sha256 ? EVP_sha256() : EVP_md5(), NULL) != 1) {
        noshi_digest_free(digest);
        return NULL;
    }
    return digest;
}

noshi_status noshi_digest_update(noshi_digest *digest, const void *data, size_t len) {
    if (!digest || (!data && len)) return NOSHI_E_ARG;
    if (digest->done) return NOSHI_E_STATE;
    return EVP_DigestUpdate(digest->ctx, data, len) == 1 ? NOSHI_OK : NOSHI_E_CRYPTO;
}

noshi_status noshi_digest_finish(noshi_digest *digest, uint8_t *out, size_t cap) {
    unsigned len = 0;
    if (!digest || !out) return NOSHI_E_ARG;
    if (digest->done) return NOSHI_E_STATE;
    if (cap < digest->length) return NOSHI_E_LIMIT;
    digest->done = 1;
    if (EVP_DigestFinal_ex(digest->ctx, out, &len) != 1 || len != digest->length) return NOSHI_E_CRYPTO;
    return NOSHI_OK;
}

void noshi_digest_free(noshi_digest *digest) {
    if (!digest) return;
    EVP_MD_CTX_free(digest->ctx);
    free(digest);
}
