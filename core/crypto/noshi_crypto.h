#ifndef NOSHI_CRYPTO_H
#define NOSHI_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_bytes.h"
#include "noshi_status.h"

/* openssl stays behind this boundary so protocol code builds against 1.1.1 and 3.x */

#define NOSHI_SHA1_LEN 20
#define NOSHI_SHA256_LEN 32
#define NOSHI_MD5_LEN 16

noshi_status noshi_sha1(const noshi_slice *parts, size_t count, uint8_t out[NOSHI_SHA1_LEN]);
noshi_status noshi_sha256(const noshi_slice *parts, size_t count, uint8_t out[NOSHI_SHA256_LEN]);
noshi_status noshi_md5(const noshi_slice *parts, size_t count, uint8_t out[NOSHI_MD5_LEN]);

/* the message is the parts joined, at most NOSHI_HMAC_MAX_MESSAGE bytes (NOSHI_E_LIMIT above that) */
#define NOSHI_HMAC_MAX_MESSAGE 4096
noshi_status noshi_hmac_sha1(const uint8_t *key, size_t key_len, const noshi_slice *parts, size_t count,
                                 uint8_t out[NOSHI_SHA1_LEN]);

/* AES-128 in counter mode over len bytes, the whole 16 byte iv being the first counter block. in and out may be the same */
noshi_status noshi_aes128_ctr(const uint8_t key[16], const uint8_t iv[16], const uint8_t *in, uint8_t *out, size_t len);

noshi_status noshi_sha1_one(const void *data, size_t len, uint8_t out[NOSHI_SHA1_LEN]);
noshi_status noshi_sha256_one(const void *data, size_t len, uint8_t out[NOSHI_SHA256_LEN]);

/* the WireGuard primitives: the curve25519 function of RFC 7748 and the AEAD of RFC 8439 with a 12 byte nonce */
#define NOSHI_X25519_LEN 32
#define NOSHI_CHACHA_KEY_LEN 32
#define NOSHI_CHACHA_NONCE_LEN 12
#define NOSHI_POLY1305_TAG_LEN 16

/* the public key of a private key (which need not be clamped) */
noshi_status noshi_x25519_public(const uint8_t priv[NOSHI_X25519_LEN], uint8_t pub[NOSHI_X25519_LEN]);
/* the shared secret; NOSHI_E_SECURITY when the peer key is a point of small order (the secret would be all zeros) */
noshi_status noshi_x25519_shared(const uint8_t priv[NOSHI_X25519_LEN], const uint8_t peer[NOSHI_X25519_LEN], uint8_t out[NOSHI_X25519_LEN]);

/* out holds len bytes and may be the same buffer as in; ad may be empty */
noshi_status noshi_chacha20poly1305_seal(const uint8_t key[NOSHI_CHACHA_KEY_LEN], const uint8_t nonce[NOSHI_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             uint8_t tag[NOSHI_POLY1305_TAG_LEN]);
/* NOSHI_E_SECURITY when the tag does not match; out is wiped then */
noshi_status noshi_chacha20poly1305_open(const uint8_t key[NOSHI_CHACHA_KEY_LEN], const uint8_t nonce[NOSHI_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             const uint8_t tag[NOSHI_POLY1305_TAG_LEN]);

noshi_status noshi_pbkdf2_sha512(const uint8_t *password, size_t password_len,
                                     const uint8_t *salt, size_t salt_len,
                                     uint32_t iterations, uint8_t *out, size_t out_len);

noshi_status noshi_aes_ige(const uint8_t key[32], const uint8_t iv[32], int encrypt,
                               const uint8_t *in, uint8_t *out, size_t len);

typedef struct noshi_digest noshi_digest;
noshi_digest *noshi_digest_new(int sha256);
noshi_status noshi_digest_update(noshi_digest *digest, const void *data, size_t len);
noshi_status noshi_digest_finish(noshi_digest *digest, uint8_t *out, size_t cap);
void noshi_digest_free(noshi_digest *digest);

typedef struct noshi_aes_ctr noshi_aes_ctr;
noshi_aes_ctr *noshi_aes_ctr_new(const uint8_t key[32], const uint8_t iv[16]);
noshi_status noshi_aes_ctr_apply(noshi_aes_ctr *ctr, const uint8_t *in, uint8_t *out, size_t len);
void noshi_aes_ctr_free(noshi_aes_ctr *ctr);

typedef struct noshi_bn noshi_bn;

noshi_bn *noshi_bn_from_bin(const uint8_t *be, size_t len);
noshi_bn *noshi_bn_from_u64(uint64_t value);
void noshi_bn_free(noshi_bn *bn);
size_t noshi_bn_bits(const noshi_bn *bn);
size_t noshi_bn_bytes(const noshi_bn *bn);
int noshi_bn_cmp(const noshi_bn *a, const noshi_bn *b);
int noshi_bn_is_zero(const noshi_bn *bn);
noshi_status noshi_bn_to_bin_padded(const noshi_bn *bn, uint8_t *out, size_t len);
noshi_status noshi_bn_to_bin(const noshi_bn *bn, uint8_t *out, size_t cap, size_t *len);
noshi_bn *noshi_bn_add(const noshi_bn *a, const noshi_bn *b);
noshi_bn *noshi_bn_sub(const noshi_bn *a, const noshi_bn *b);
noshi_bn *noshi_bn_mul(const noshi_bn *a, const noshi_bn *b);
noshi_bn *noshi_bn_mod(const noshi_bn *a, const noshi_bn *m);
noshi_bn *noshi_bn_mod_add(const noshi_bn *a, const noshi_bn *b, const noshi_bn *m);
noshi_bn *noshi_bn_mod_sub(const noshi_bn *a, const noshi_bn *b, const noshi_bn *m);
noshi_bn *noshi_bn_mod_mul(const noshi_bn *a, const noshi_bn *b, const noshi_bn *m);
noshi_bn *noshi_bn_mod_exp(const noshi_bn *base, const noshi_bn *exp, const noshi_bn *m);
noshi_bn *noshi_bn_mod_exp_secret(const noshi_bn *base, const noshi_bn *exp, const noshi_bn *m);
noshi_bn *noshi_bn_rshift1(const noshi_bn *a);
uint32_t noshi_bn_mod_word(const noshi_bn *a, uint32_t word);
int noshi_bn_is_prime(const noshi_bn *a);

noshi_status noshi_rsa_public_raw(const uint8_t *n, size_t n_len, uint32_t e,
                                      const uint8_t *in, size_t in_len, uint8_t *out);

#endif
