#include "noshi_srp.h"

#include <string.h>

#include "noshi_crypto.h"
#include "noshi_mt_handshake.h"
#include "noshi_random.h"
#include "noshi_tl_ids.h"

static noshi_status parameters(const noshi_tl_value *algo, noshi_slice *s1, noshi_slice *s2,
                                 const uint8_t **prime, int32_t *g) {
    size_t len;
    if (!noshi_tl_is(algo, NOSHI_TL_ID_passwordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow))
        return NOSHI_E_UNSUPPORTED;
    if (noshi_tl_get_bytes(algo, "salt1", &s1->data, &s1->len) != NOSHI_OK ||
        noshi_tl_get_bytes(algo, "salt2", &s2->data, &s2->len) != NOSHI_OK ||
        noshi_tl_get_bytes(algo, "p", prime, &len) != NOSHI_OK ||
        noshi_tl_get_i32(algo, "g", g) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (!s1->len || !s2->len || s1->len > 1024 || s2->len > 1024 || len != 256) return NOSHI_E_SECURITY;
    return noshi_mt_check_dh_prime(*prime, len, *g);
}

static noshi_status password_x(noshi_slice s1, noshi_slice s2, const uint8_t *password,
                                 size_t len, uint8_t out[32]) {
    uint8_t h[32], stretched[64];
    noshi_slice parts[3];
    noshi_status status;
    if ((!password && len) || len > 1024) return NOSHI_E_ARG;
    parts[0] = s1;
    parts[1].data = password; parts[1].len = len;
    parts[2] = s1;
    status = noshi_sha256(parts, 3, h);
    parts[0] = s2;
    parts[1].data = h; parts[1].len = sizeof(h);
    parts[2] = s2;
    if (status == NOSHI_OK) status = noshi_sha256(parts, 3, h);
    if (status == NOSHI_OK) status = noshi_pbkdf2_sha512(h, sizeof(h), s1.data, s1.len, 100000, stretched, sizeof(stretched));
    parts[1].data = stretched; parts[1].len = sizeof(stretched);
    if (status == NOSHI_OK) status = noshi_sha256(parts, 3, out);
    noshi_wipe(h, sizeof(h));
    noshi_wipe(stretched, sizeof(stretched));
    return status;
}

noshi_status noshi_srp_check(const noshi_tl_value *account_password,
                                const uint8_t *password, size_t len, noshi_srp_proof *out) {
    const noshi_tl_value *algo;
    const uint8_t *prime, *server_B;
    size_t B_len;
    int32_t generator;
    noshi_slice s1, s2, parts[6];
    noshi_bn *p = NULL, *g = NULL, *B = NULL, *a = NULL, *A = NULL, *x = NULL;
    noshi_bn *k = NULL, *u = NULL, *v = NULL, *kv = NULL, *t = NULL, *ux = NULL, *exp = NULL, *S = NULL;
    uint8_t gp[256] = {0}, bp[256], entropy[256], xh[32], kh[32], uh[32], sp[256], K[32], h1[32], h2[32];
    noshi_status status;
    size_t i;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!account_password || (!password && len) || len > 1024) return NOSHI_E_ARG;
    algo = noshi_tl_get(account_password, "current_algo");
    status = parameters(algo, &s1, &s2, &prime, &generator);
    if (status != NOSHI_OK) return status;
    if (noshi_tl_get_bytes(account_password, "srp_B", &server_B, &B_len) != NOSHI_OK ||
        !B_len || B_len > 256 || noshi_tl_get_i64(account_password, "srp_id", &out->id) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    gp[255] = (uint8_t)generator;
    status = password_x(s1, s2, password, len, xh);
    if (status != NOSHI_OK) goto done;
    status = noshi_random(entropy, sizeof(entropy));
    if (status != NOSHI_OK) goto done;
    p = noshi_bn_from_bin(prime, 256); g = noshi_bn_from_u64((uint64_t)generator);
    B = noshi_bn_from_bin(server_B, B_len); a = noshi_bn_from_bin(entropy, 256); x = noshi_bn_from_bin(xh, 32);
    if (!p || !g || !B || !a || !x) { status = NOSHI_E_NOMEM; goto done; }
    if (noshi_bn_is_zero(B) || noshi_bn_cmp(B, p) >= 0 || noshi_bn_is_zero(a)) { status = NOSHI_E_SECURITY; goto done; }
    A = noshi_bn_mod_exp_secret(g, a, p);
    if (!A) { status = NOSHI_E_CRYPTO; goto done; }
    status = noshi_bn_to_bin_padded(A, out->A, 256);
    if (status == NOSHI_OK) status = noshi_mt_check_dh_value(prime, 256, out->A, 256);
    if (status != NOSHI_OK) goto done;
    status = noshi_bn_to_bin_padded(B, bp, 256);
    parts[0].data = prime; parts[0].len = 256; parts[1].data = gp; parts[1].len = 256;
    if (status == NOSHI_OK) status = noshi_sha256(parts, 2, kh);
    parts[0].data = out->A; parts[1].data = bp;
    if (status == NOSHI_OK) status = noshi_sha256(parts, 2, uh);
    if (status != NOSHI_OK) goto done;
    k = noshi_bn_from_bin(kh, 32); u = noshi_bn_from_bin(uh, 32);
    if (!k || !u) { status = NOSHI_E_NOMEM; goto done; }
    if (noshi_bn_is_zero(u)) { status = NOSHI_E_SECURITY; goto done; }
    v = noshi_bn_mod_exp_secret(g, x, p);
    if (v) kv = noshi_bn_mod_mul(k, v, p);
    if (kv) t = noshi_bn_mod_sub(B, kv, p);
    if (t) ux = noshi_bn_mul(u, x);
    if (ux) exp = noshi_bn_add(a, ux);
    if (!exp) { status = NOSHI_E_CRYPTO; goto done; }
    status = noshi_bn_to_bin_padded(t, sp, 256);
    if (status == NOSHI_OK) status = noshi_mt_check_dh_value(prime, 256, sp, 256);
    if (status != NOSHI_OK) goto done;
    S = noshi_bn_mod_exp_secret(t, exp, p);
    if (!S) { status = NOSHI_E_CRYPTO; goto done; }
    status = noshi_bn_to_bin_padded(S, sp, 256);
    if (status == NOSHI_OK) status = noshi_sha256_one(sp, 256, K);
    if (status == NOSHI_OK) status = noshi_sha256_one(prime, 256, h1);
    if (status == NOSHI_OK) status = noshi_sha256_one(gp, 256, h2);
    for (i = 0; i < 32; ++i) kh[i] = h1[i] ^ h2[i];
    if (status == NOSHI_OK) status = noshi_sha256_one(s1.data, s1.len, h1);
    if (status == NOSHI_OK) status = noshi_sha256_one(s2.data, s2.len, h2);
    parts[0].data = kh; parts[0].len = 32; parts[1].data = h1; parts[1].len = 32;
    parts[2].data = h2; parts[2].len = 32; parts[3].data = out->A; parts[3].len = 256;
    parts[4].data = bp; parts[4].len = 256; parts[5].data = K; parts[5].len = 32;
    if (status == NOSHI_OK) status = noshi_sha256(parts, 6, out->M1);
done:
    noshi_bn_free(p); noshi_bn_free(g); noshi_bn_free(B); noshi_bn_free(a); noshi_bn_free(A); noshi_bn_free(x);
    noshi_bn_free(k); noshi_bn_free(u); noshi_bn_free(v); noshi_bn_free(kv); noshi_bn_free(t);
    noshi_bn_free(ux); noshi_bn_free(exp); noshi_bn_free(S);
    noshi_wipe(entropy, sizeof(entropy)); noshi_wipe(xh, sizeof(xh)); noshi_wipe(sp, sizeof(sp));
    noshi_wipe(K, sizeof(K)); noshi_wipe(h1, sizeof(h1)); noshi_wipe(h2, sizeof(h2));
    if (status != NOSHI_OK) noshi_wipe(out, sizeof(*out));
    return status;
}

noshi_status noshi_srp_verifier(const noshi_tl_value *algo, const uint8_t *password, size_t len,
                                   noshi_arena *arena, noshi_tl_value **new_algo, uint8_t verifier[256]) {
    noshi_slice s1, s2;
    const uint8_t *prime;
    int32_t generator;
    uint8_t salt[1056], xh[32];
    noshi_bn *p = NULL, *g = NULL, *x = NULL, *v = NULL;
    noshi_tl_value *result;
    noshi_status status;
    if (!new_algo || !verifier) return NOSHI_E_ARG;
    *new_algo = NULL;
    memset(verifier, 0, 256);
    if (!arena || (!password && len) || len > 1024) return NOSHI_E_ARG;
    status = parameters(algo, &s1, &s2, &prime, &generator);
    if (status != NOSHI_OK) return status;
    memcpy(salt, s1.data, s1.len);
    status = noshi_random(salt + s1.len, 32);
    s1.data = salt; s1.len += 32;
    if (status == NOSHI_OK) status = password_x(s1, s2, password, len, xh);
    if (status != NOSHI_OK) goto done;
    p = noshi_bn_from_bin(prime, 256); g = noshi_bn_from_u64((uint64_t)generator); x = noshi_bn_from_bin(xh, 32);
    if (!p || !g || !x) { status = NOSHI_E_NOMEM; goto done; }
    v = noshi_bn_mod_exp_secret(g, x, p);
    if (!v) { status = NOSHI_E_CRYPTO; goto done; }
    status = noshi_bn_to_bin_padded(v, verifier, 256);
    if (status != NOSHI_OK) goto done;
    result = noshi_tl_new_obj(arena, algo->u.obj.ctor->name);
    if (!result) { status = NOSHI_E_NOMEM; goto done; }
    status = noshi_tl_set_bytes(arena, result, "salt1", salt, s1.len);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, result, "salt2", s2.data, s2.len);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, result, "g", generator);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, result, "p", prime, 256);
    if (status == NOSHI_OK) *new_algo = result;
done:
    noshi_bn_free(p); noshi_bn_free(g); noshi_bn_free(x); noshi_bn_free(v);
    noshi_wipe(salt, sizeof(salt)); noshi_wipe(xh, sizeof(xh));
    if (status != NOSHI_OK) noshi_wipe(verifier, 256);
    return status;
}
