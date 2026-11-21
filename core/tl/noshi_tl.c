#include "noshi_tl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <zlib.h>

#define TL_VECTOR_ID 0x1cb5c415u
#define TL_GZIP_ID 0x3072cfa1u

const noshi_tl_limits noshi_tl_default_limits = { 64u, 400000u, 16u * 1024u * 1024u, 0 };

static const noshi_tl_value tl_true_value = { NOSHI_TL_V_TRUE, { 0 } };

static const noshi_tl_type *type_at(uint16_t ref) {
    return ref < noshi_tl_type_count ? &noshi_tl_types[ref] : NULL;
}

static int is_any_type(uint16_t type_name) {
    return type_name == noshi_tl_types[NOSHI_TL_REF_ANY].arg;
}

const noshi_tl_ctor *noshi_tl_find_ctor(uint32_t id) {
    uint32_t lo = 0, hi = noshi_tl_ctor_count;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        uint32_t cur = noshi_tl_ctors[mid].id;
        if (cur == id) return &noshi_tl_ctors[mid];
        if (cur < id) lo = mid + 1;
        else hi = mid;
    }
    return NULL;
}

const noshi_tl_ctor *noshi_tl_find_ctor_by_name(const char *name) {
    uint32_t lo = 0, hi = noshi_tl_ctor_count;
    if (!name) return NULL;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        const noshi_tl_ctor *c = &noshi_tl_ctors[noshi_tl_ctors_by_name[mid]];
        int cmp = strcmp(c->name, name);
        if (cmp == 0) return c;
        if (cmp < 0) lo = mid + 1;
        else hi = mid;
    }
    return NULL;
}

const noshi_tl_field *noshi_tl_ctor_fields(const noshi_tl_ctor *ctor) {
    return &noshi_tl_fields[ctor->first_field];
}

int noshi_tl_field_index(const noshi_tl_ctor *ctor, const char *name) {
    const noshi_tl_field *f = noshi_tl_ctor_fields(ctor);
    unsigned i;
    if (!name) return -1;
    for (i = 0; i < ctor->field_count; ++i) {
        if (strcmp(f[i].name, name) == 0) return (int)i;
    }
    return -1;
}

const char *noshi_tl_result_type_name(const noshi_tl_ctor *ctor) {
    if (type_at(ctor->result)->kind != NOSHI_TL_K_OBJECT) return NULL;
    return noshi_tl_type_names[ctor->type_name];
}

typedef struct dctx {
    noshi_arena *arena;
    noshi_tl_limits limits;
    uint32_t values;
    int in_gzip;
} dctx;

static noshi_tl_value *dnew(dctx *d, uint8_t kind) {
    noshi_tl_value *v;
    if (d->values >= d->limits.max_values) return NULL;
    v = (noshi_tl_value *)noshi_arena_alloc(d->arena, sizeof(*v));
    if (!v) return NULL;
    d->values++;
    v->kind = kind;
    return v;
}

static noshi_status read_string(noshi_reader *r, const uint8_t **data, uint32_t *len) {
    uint32_t n, total;
    uint8_t first = noshi_rd_u8(r);
    const uint8_t *p;
    if (r->status != NOSHI_OK) return r->status;
    if (first < 254) {
        n = first;
        total = 1u + n;
    } else if (first == 254) {
        const uint8_t *b = noshi_rd_bytes(r, 3);
        if (!b) return r->status;
        n = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16);
        total = 4u + n;
    } else {
        return NOSHI_E_MALFORMED;
    }
    p = noshi_rd_bytes(r, n);
    if (!p && n) return r->status;
    *data = p ? p : (const uint8_t *)"";
    *len = n;
    if (total % 4u) {
        if (!noshi_rd_bytes(r, 4u - total % 4u)) return r->status;
    }
    return NOSHI_OK;
}

static noshi_status dec_type(dctx *d, noshi_reader *r, uint16_t ref, uint32_t depth, noshi_tl_value **out);

static noshi_status inflate_string(noshi_reader *r, noshi_writer *out) {
    const uint8_t *packed;
    uint32_t packed_len;
    uint8_t chunk[4096];
    z_stream zs;
    size_t mark = out->len;
    int zr;
    noshi_status s = read_string(r, &packed, &packed_len);
    if (s != NOSHI_OK) return s;
    memset(&zs, 0, sizeof(zs));
    /* auto detection preserves the zlib framing accepted by the existing decoder */
    zr = inflateInit2(&zs, 15 + 32);
    if (zr != Z_OK) return zr == Z_MEM_ERROR ? NOSHI_E_NOMEM : NOSHI_E_MALFORMED;
    zs.next_in = (Bytef *)(uintptr_t)packed;
    zs.avail_in = packed_len;
    do {
        size_t got;
        zs.next_out = chunk;
        zs.avail_out = sizeof(chunk);
        zr = inflate(&zs, Z_NO_FLUSH);
        got = sizeof(chunk) - zs.avail_out;
        if (zr != Z_OK && zr != Z_STREAM_END) {
            s = zr == Z_MEM_ERROR ? NOSHI_E_NOMEM : NOSHI_E_MALFORMED;
            break;
        }
        s = noshi_wr_bytes(out, chunk, got);
        if (s != NOSHI_OK) break;
        if (zr == Z_OK && zs.avail_in == 0 && zs.avail_out != 0) {
            s = NOSHI_E_TRUNCATED;
            break;
        }
    } while (zr != Z_STREAM_END);
    /* a second stream or trailing data makes the packed body ambiguous */
    if (s == NOSHI_OK && zs.avail_in != 0) s = NOSHI_E_MALFORMED;
    inflateEnd(&zs);
    if (s != NOSHI_OK) out->len = mark;
    return s;
}

noshi_status noshi_tl_unpack_gzip(const uint8_t *data, size_t len, noshi_writer *out) {
    noshi_reader r;
    size_t mark;
    noshi_status s;
    if (!data || !out) return NOSHI_E_ARG;
    if (len < 4) return NOSHI_E_TRUNCATED;
    noshi_reader_init(&r, data, len);
    if (noshi_rd_u32le(&r) != TL_GZIP_ID) return NOSHI_E_MALFORMED;
    mark = out->len;
    s = inflate_string(&r, out);
    if (s == NOSHI_OK && noshi_reader_left(&r) != 0) s = NOSHI_E_MALFORMED;
    if (s != NOSHI_OK) out->len = mark;
    return s;
}

static noshi_status dec_gzip(dctx *d, noshi_reader *r, uint16_t ref, uint32_t depth, noshi_tl_value **out) {
    noshi_writer plain;
    noshi_reader inner;
    dctx sub;
    uint8_t *kept;
    size_t len;
    noshi_status s;
    if (d->in_gzip) return NOSHI_E_MALFORMED;
    noshi_writer_init(&plain, d->limits.max_inflate);
    s = inflate_string(r, &plain);
    if (s != NOSHI_OK) {
        noshi_writer_free(&plain);
        return s;
    }
    len = plain.len;
    kept = (uint8_t *)noshi_arena_copy(d->arena, plain.data, len);
    noshi_writer_free(&plain);
    if (!kept) return NOSHI_E_LIMIT;
    noshi_reader_init(&inner, kept, len);
    sub = *d;
    sub.in_gzip = 1;
    s = dec_type(&sub, &inner, ref, depth, out);
    d->values = sub.values;
    if (s != NOSHI_OK) return s == NOSHI_E_TRUNCATED ? NOSHI_E_MALFORMED : s;
    if (noshi_reader_left(&inner) != 0) return NOSHI_E_MALFORMED;
    return NOSHI_OK;
}

static noshi_status dec_fields(dctx *d, noshi_reader *r, const noshi_tl_ctor *ctor, uint32_t depth,
                                 noshi_tl_value **out) {
    noshi_tl_value *v = dnew(d, NOSHI_TL_V_OBJ);
    const noshi_tl_field *f = noshi_tl_ctor_fields(ctor);
    unsigned i;
    if (!v) return NOSHI_E_LIMIT;
    v->u.obj.ctor = ctor;
    v->u.obj.fields = NULL;
    if (ctor->field_count) {
        v->u.obj.fields = (noshi_tl_value **)noshi_arena_alloc(d->arena, sizeof(noshi_tl_value *) * ctor->field_count);
        if (!v->u.obj.fields) return NOSHI_E_LIMIT;
    }
    for (i = 0; i < ctor->field_count; ++i) {
        const noshi_tl_type *t = type_at(f[i].type);
        noshi_status s;
        if (f[i].flags_field != NOSHI_TL_NO_FLAGS) {
            const noshi_tl_value *fv = v->u.obj.fields[f[i].flags_field];
            if (!fv || !((uint32_t)fv->u.i32 & (1u << f[i].flag_bit))) continue;
            if (t->kind == NOSHI_TL_K_TRUE) {
                v->u.obj.fields[i] = (noshi_tl_value *)(uintptr_t)&tl_true_value;
                continue;
            }
        }
        s = dec_type(d, r, f[i].type, depth + 1, &v->u.obj.fields[i]);
        if (s != NOSHI_OK) return s;
    }
    *out = v;
    return NOSHI_OK;
}

static noshi_status dec_bytes_value(dctx *d, noshi_reader *r, size_t fixed, noshi_tl_value **out) {
    const uint8_t *p;
    uint32_t n;
    noshi_tl_value *v;
    noshi_status s;
    if (fixed) {
        p = noshi_rd_bytes(r, fixed);
        if (!p) return r->status;
        n = (uint32_t)fixed;
    } else {
        s = read_string(r, &p, &n);
        if (s != NOSHI_OK) return s;
    }
    v = dnew(d, NOSHI_TL_V_BYTES);
    if (!v) return NOSHI_E_LIMIT;
    if (d->limits.borrow_bytes && !d->in_gzip) {
        v->u.bytes.data = p;
    } else {
        uint8_t *copy = (uint8_t *)noshi_arena_alloc(d->arena, (size_t)n + 1);
        if (!copy) return NOSHI_E_LIMIT;
        if (n) memcpy(copy, p, n);
        v->u.bytes.data = copy;
    }
    v->u.bytes.len = n;
    *out = v;
    return NOSHI_OK;
}

static noshi_status dec_object(dctx *d, noshi_reader *r, const noshi_tl_type *t, uint32_t depth,
                                 noshi_tl_value **out) {
    const noshi_tl_ctor *ctor;
    int any = is_any_type(t->arg);
    if (t->bare) {
        int32_t ci = noshi_tl_bare_ctor[t->arg];
        if (ci < 0) return NOSHI_E_UNSUPPORTED;
        ctor = &noshi_tl_ctors[ci];
    } else {
        uint32_t id = noshi_rd_u32le(r);
        if (r->status != NOSHI_OK) return r->status;
        if (id == TL_GZIP_ID) return dec_gzip(d, r, (uint16_t)(t - noshi_tl_types), depth, out);
        ctor = noshi_tl_find_ctor(id);
        if (!ctor) return NOSHI_E_UNSUPPORTED;
        if (!any && (ctor->is_function || ctor->type_name != t->arg)) return NOSHI_E_MALFORMED;
    }
    return dec_fields(d, r, ctor, depth, out);
}

static noshi_status dec_type(dctx *d, noshi_reader *r, uint16_t ref, uint32_t depth, noshi_tl_value **out) {
    const noshi_tl_type *t = type_at(ref);
    noshi_tl_value *v;
    if (!t) return NOSHI_E_ARG;
    if (depth > d->limits.max_depth) return NOSHI_E_LIMIT;
    switch (t->kind) {
    case NOSHI_TL_K_INT:
    case NOSHI_TL_K_FLAGS: {
        uint32_t x = noshi_rd_u32le(r);
        if (r->status != NOSHI_OK) return r->status;
        v = dnew(d, NOSHI_TL_V_I32);
        if (!v) return NOSHI_E_LIMIT;
        v->u.i32 = (int32_t)x;
        *out = v;
        return NOSHI_OK;
    }
    case NOSHI_TL_K_LONG: {
        uint64_t x = noshi_rd_u64le(r);
        if (r->status != NOSHI_OK) return r->status;
        v = dnew(d, NOSHI_TL_V_I64);
        if (!v) return NOSHI_E_LIMIT;
        v->u.i64 = (int64_t)x;
        *out = v;
        return NOSHI_OK;
    }
    case NOSHI_TL_K_DOUBLE: {
        uint64_t x = noshi_rd_u64le(r);
        double f;
        if (r->status != NOSHI_OK) return r->status;
        v = dnew(d, NOSHI_TL_V_F64);
        if (!v) return NOSHI_E_LIMIT;
        memcpy(&f, &x, sizeof(f));
        v->u.f64 = f;
        *out = v;
        return NOSHI_OK;
    }
    case NOSHI_TL_K_INT128:
        return dec_bytes_value(d, r, 16, out);
    case NOSHI_TL_K_INT256:
        return dec_bytes_value(d, r, 32, out);
    case NOSHI_TL_K_STRING:
    case NOSHI_TL_K_BYTES:
        return dec_bytes_value(d, r, 0, out);
    case NOSHI_TL_K_TRUE:
        *out = (noshi_tl_value *)(uintptr_t)&tl_true_value;
        return NOSHI_OK;
    case NOSHI_TL_K_OBJECT:
        return dec_object(d, r, t, depth, out);
    case NOSHI_TL_K_GENERIC:
        return dec_object(d, r, &noshi_tl_types[NOSHI_TL_REF_ANY], depth, out);
    case NOSHI_TL_K_VECTOR: {
        uint32_t count, i;
        if (!t->bare) {
            uint32_t id = noshi_rd_u32le(r);
            if (r->status != NOSHI_OK) return r->status;
            if (id == TL_GZIP_ID) return dec_gzip(d, r, ref, depth, out);
            if (id != TL_VECTOR_ID) return NOSHI_E_MALFORMED;
        }
        count = noshi_rd_u32le(r);
        if (r->status != NOSHI_OK) return r->status;
        /* every element takes at least four bytes, this bounds the allocation by the input */
        if (count > noshi_reader_left(r) / 4u) return NOSHI_E_MALFORMED;
        v = dnew(d, NOSHI_TL_V_VEC);
        if (!v) return NOSHI_E_LIMIT;
        v->u.vec.count = count;
        v->u.vec.items = NULL;
        if (count) {
            v->u.vec.items = (noshi_tl_value **)noshi_arena_alloc(d->arena, sizeof(noshi_tl_value *) * count);
            if (!v->u.vec.items) return NOSHI_E_LIMIT;
        }
        for (i = 0; i < count; ++i) {
            noshi_status s = dec_type(d, r, t->arg, depth + 1, &v->u.vec.items[i]);
            if (s != NOSHI_OK) return s;
        }
        *out = v;
        return NOSHI_OK;
    }
    }
    return NOSHI_E_UNSUPPORTED;
}

noshi_status noshi_tl_decode(noshi_arena *arena, const noshi_tl_limits *limits, uint16_t type_ref,
                                 const uint8_t *data, size_t len, size_t *consumed, noshi_tl_value **out) {
    dctx d;
    noshi_reader r;
    noshi_status s;
    if (out) *out = NULL;
    if (consumed) *consumed = 0;
    if (!arena || !out || (len && !data)) return NOSHI_E_ARG;
    d.arena = arena;
    d.limits = limits ? *limits : noshi_tl_default_limits;
    d.values = 0;
    d.in_gzip = 0;
    noshi_reader_init(&r, data, len);
    s = dec_type(&d, &r, type_ref, 0, out);
    if (s != NOSHI_OK) {
        *out = NULL;
        return s;
    }
    if (consumed) *consumed = r.pos;
    return NOSHI_OK;
}

noshi_status noshi_tl_decode_all(noshi_arena *arena, const noshi_tl_limits *limits, uint16_t type_ref,
                                     const uint8_t *data, size_t len, noshi_tl_value **out) {
    size_t used = 0;
    noshi_status s = noshi_tl_decode(arena, limits, type_ref, data, len, &used, out);
    if (s != NOSHI_OK) return s;
    if (used != len) {
        *out = NULL;
        return NOSHI_E_MALFORMED;
    }
    return NOSHI_OK;
}

#define ENC_MAX_DEPTH 96u

static noshi_status write_string(noshi_writer *w, const uint8_t *data, size_t len) {
    static const uint8_t zeros[4] = { 0, 0, 0, 0 };
    size_t total;
    noshi_status s;
    if (len >= 0x1000000u) return NOSHI_E_LIMIT;
    if (len < 254) {
        s = noshi_wr_u8(w, (uint8_t)len);
        total = 1 + len;
    } else {
        uint8_t h[4];
        h[0] = 254;
        h[1] = (uint8_t)len;
        h[2] = (uint8_t)(len >> 8);
        h[3] = (uint8_t)(len >> 16);
        s = noshi_wr_bytes(w, h, 4);
        total = 4 + len;
    }
    if (s != NOSHI_OK) return s;
    s = noshi_wr_bytes(w, data, len);
    if (s != NOSHI_OK) return s;
    if (total % 4) return noshi_wr_bytes(w, zeros, 4 - total % 4);
    return NOSHI_OK;
}

static noshi_status fail_at(noshi_tl_error *err, const noshi_tl_ctor *ctor, const char *field,
                              noshi_status s) {
    if (err) {
        err->ctor = ctor ? ctor->name : NULL;
        err->field = field;
    }
    return s;
}

static noshi_status enc_type(noshi_writer *w, const noshi_tl_value *v, uint16_t ref, uint32_t depth,
                               const noshi_tl_ctor *owner, const char *field, noshi_tl_error *err);

static noshi_status enc_object(noshi_writer *w, const noshi_tl_value *v, int boxed, uint32_t depth,
                                 noshi_tl_error *err) {
    const noshi_tl_ctor *ctor = v->u.obj.ctor;
    const noshi_tl_field *f = noshi_tl_ctor_fields(ctor);
    unsigned i, j;
    noshi_status s;
    if (depth > ENC_MAX_DEPTH) return fail_at(err, ctor, NULL, NOSHI_E_LIMIT);
    if (boxed) {
        s = noshi_wr_u32le(w, ctor->id);
        if (s != NOSHI_OK) return s;
    }
    for (i = 0; i < ctor->field_count; ++i) {
        const noshi_tl_type *t = type_at(f[i].type);
        const noshi_tl_value *fv = v->u.obj.fields[i];
        if (t->kind == NOSHI_TL_K_FLAGS) {
            uint32_t word = 0;
            for (j = 0; j < ctor->field_count; ++j) {
                if (f[j].flags_field == i && v->u.obj.fields[j]) word |= 1u << f[j].flag_bit;
            }
            s = noshi_wr_u32le(w, word);
            if (s != NOSHI_OK) return s;
            continue;
        }
        if (!fv) {
            if (f[i].flags_field != NOSHI_TL_NO_FLAGS || t->kind == NOSHI_TL_K_TRUE) continue;
            return fail_at(err, ctor, f[i].name, NOSHI_E_ARG);
        }
        if (t->kind == NOSHI_TL_K_TRUE) continue;
        s = enc_type(w, fv, f[i].type, depth + 1, ctor, f[i].name, err);
        if (s != NOSHI_OK) return s;
    }
    return NOSHI_OK;
}

static int value_fits(const noshi_tl_type *t, const noshi_tl_value *v) {
    switch (t->kind) {
    case NOSHI_TL_K_INT:
    case NOSHI_TL_K_FLAGS: return v->kind == NOSHI_TL_V_I32;
    case NOSHI_TL_K_LONG: return v->kind == NOSHI_TL_V_I64;
    case NOSHI_TL_K_DOUBLE: return v->kind == NOSHI_TL_V_F64;
    case NOSHI_TL_K_INT128: return v->kind == NOSHI_TL_V_BYTES && v->u.bytes.len == 16;
    case NOSHI_TL_K_INT256: return v->kind == NOSHI_TL_V_BYTES && v->u.bytes.len == 32;
    case NOSHI_TL_K_STRING:
    case NOSHI_TL_K_BYTES: return v->kind == NOSHI_TL_V_BYTES;
    case NOSHI_TL_K_TRUE: return v->kind == NOSHI_TL_V_TRUE;
    case NOSHI_TL_K_OBJECT:
        if (v->kind != NOSHI_TL_V_OBJ) return 0;
        if (is_any_type(t->arg)) return 1;
        return !v->u.obj.ctor->is_function && v->u.obj.ctor->type_name == t->arg;
    case NOSHI_TL_K_VECTOR: return v->kind == NOSHI_TL_V_VEC;
    case NOSHI_TL_K_GENERIC: return v->kind == NOSHI_TL_V_OBJ;
    }
    return 0;
}

static noshi_status enc_type(noshi_writer *w, const noshi_tl_value *v, uint16_t ref, uint32_t depth,
                               const noshi_tl_ctor *owner, const char *field, noshi_tl_error *err) {
    const noshi_tl_type *t = type_at(ref);
    noshi_status s;
    if (!t) return fail_at(err, owner, field, NOSHI_E_ARG);
    if (depth > ENC_MAX_DEPTH) return fail_at(err, owner, field, NOSHI_E_LIMIT);
    if (!value_fits(t, v)) return fail_at(err, owner, field, NOSHI_E_ARG);
    switch (t->kind) {
    case NOSHI_TL_K_INT:
    case NOSHI_TL_K_FLAGS:
        return noshi_wr_u32le(w, (uint32_t)v->u.i32);
    case NOSHI_TL_K_LONG:
        return noshi_wr_u64le(w, (uint64_t)v->u.i64);
    case NOSHI_TL_K_DOUBLE: {
        uint64_t x;
        memcpy(&x, &v->u.f64, sizeof(x));
        return noshi_wr_u64le(w, x);
    }
    case NOSHI_TL_K_INT128:
    case NOSHI_TL_K_INT256:
        return noshi_wr_bytes(w, v->u.bytes.data, v->u.bytes.len);
    case NOSHI_TL_K_STRING:
    case NOSHI_TL_K_BYTES:
        return write_string(w, v->u.bytes.data, v->u.bytes.len);
    case NOSHI_TL_K_TRUE:
        return NOSHI_OK;
    case NOSHI_TL_K_OBJECT:
        return enc_object(w, v, !t->bare, depth, err);
    case NOSHI_TL_K_GENERIC:
        return enc_object(w, v, 1, depth, err);
    case NOSHI_TL_K_VECTOR: {
        uint32_t i;
        if (!t->bare) {
            s = noshi_wr_u32le(w, TL_VECTOR_ID);
            if (s != NOSHI_OK) return s;
        }
        s = noshi_wr_u32le(w, v->u.vec.count);
        if (s != NOSHI_OK) return s;
        for (i = 0; i < v->u.vec.count; ++i) {
            if (!v->u.vec.items[i]) return fail_at(err, owner, field, NOSHI_E_ARG);
            s = enc_type(w, v->u.vec.items[i], t->arg, depth + 1, owner, field, err);
            if (s != NOSHI_OK) return s;
        }
        return NOSHI_OK;
    }
    }
    return NOSHI_E_UNSUPPORTED;
}

noshi_status noshi_tl_encode(const noshi_tl_value *value, noshi_writer *w, noshi_tl_error *error) {
    size_t mark;
    noshi_status s;
    if (error) {
        error->ctor = NULL;
        error->field = NULL;
    }
    if (!value || !w || value->kind != NOSHI_TL_V_OBJ) return NOSHI_E_ARG;
    mark = w->len;
    s = enc_object(w, value, 1, 0, error);
    /* a failed encode must not corrupt earlier requests in the writer */
    if (s != NOSHI_OK && w->len > mark) w->len = mark;
    return s;
}

noshi_status noshi_tl_result_ref(const noshi_tl_value *request, uint16_t *ref) {
    unsigned guard;
    if (!request || !ref || request->kind != NOSHI_TL_V_OBJ) return NOSHI_E_ARG;
    for (guard = 0; guard < 16; ++guard) {
        const noshi_tl_ctor *ctor = request->u.obj.ctor;
        const noshi_tl_field *f = noshi_tl_ctor_fields(ctor);
        unsigned i;
        const noshi_tl_value *inner = NULL;
        if (!ctor->is_function) return NOSHI_E_ARG;
        if (type_at(ctor->result)->kind != NOSHI_TL_K_GENERIC) {
            *ref = ctor->result;
            return NOSHI_OK;
        }
        for (i = 0; i < ctor->field_count; ++i) {
            if (type_at(f[i].type)->kind == NOSHI_TL_K_GENERIC) inner = request->u.obj.fields[i];
        }
        if (!inner || inner->kind != NOSHI_TL_V_OBJ) return NOSHI_E_ARG;
        request = inner;
    }
    return NOSHI_E_LIMIT;
}

static noshi_tl_value *new_value(noshi_arena *a, uint8_t kind) {
    noshi_tl_value *v = (noshi_tl_value *)noshi_arena_alloc(a, sizeof(*v));
    if (v) v->kind = kind;
    return v;
}

noshi_tl_value *noshi_tl_new_i32(noshi_arena *a, int32_t x) {
    noshi_tl_value *v = new_value(a, NOSHI_TL_V_I32);
    if (v) v->u.i32 = x;
    return v;
}

noshi_tl_value *noshi_tl_new_i64(noshi_arena *a, int64_t x) {
    noshi_tl_value *v = new_value(a, NOSHI_TL_V_I64);
    if (v) v->u.i64 = x;
    return v;
}

noshi_tl_value *noshi_tl_new_f64(noshi_arena *a, double x) {
    noshi_tl_value *v = new_value(a, NOSHI_TL_V_F64);
    if (v) v->u.f64 = x;
    return v;
}

noshi_tl_value *noshi_tl_new_bytes(noshi_arena *a, const void *data, size_t len) {
    noshi_tl_value *v;
    uint8_t *copy;
    if (len > 0x7fffffffu || (len && !data)) return NULL;
    v = new_value(a, NOSHI_TL_V_BYTES);
    copy = (uint8_t *)noshi_arena_alloc(a, len + 1);
    if (!v || !copy) return NULL;
    if (len) memcpy(copy, data, len);
    v->u.bytes.data = copy;
    v->u.bytes.len = (uint32_t)len;
    return v;
}

noshi_tl_value *noshi_tl_new_str(noshi_arena *a, const char *s) {
    if (!s) return NULL;
    return noshi_tl_new_bytes(a, s, strlen(s));
}

noshi_tl_value *noshi_tl_new_vec(noshi_arena *a, uint32_t count) {
    noshi_tl_value *v = new_value(a, NOSHI_TL_V_VEC);
    if (!v) return NULL;
    v->u.vec.count = count;
    v->u.vec.items = NULL;
    if (count) {
        if (count > 0x10000000u) return NULL;
        v->u.vec.items = (noshi_tl_value **)noshi_arena_alloc(a, sizeof(noshi_tl_value *) * count);
        if (!v->u.vec.items) return NULL;
    }
    return v;
}

noshi_tl_value *noshi_tl_new_obj_ctor(noshi_arena *a, const noshi_tl_ctor *ctor) {
    noshi_tl_value *v;
    if (!ctor) return NULL;
    v = new_value(a, NOSHI_TL_V_OBJ);
    if (!v) return NULL;
    v->u.obj.ctor = ctor;
    v->u.obj.fields = NULL;
    if (ctor->field_count) {
        v->u.obj.fields = (noshi_tl_value **)noshi_arena_alloc(a, sizeof(noshi_tl_value *) * ctor->field_count);
        if (!v->u.obj.fields) return NULL;
    }
    return v;
}

noshi_tl_value *noshi_tl_new_obj(noshi_arena *a, const char *ctor_name) {
    return noshi_tl_new_obj_ctor(a, noshi_tl_find_ctor_by_name(ctor_name));
}

noshi_status noshi_tl_vec_set(noshi_tl_value *vec, uint32_t index, noshi_tl_value *item) {
    if (!vec || vec->kind != NOSHI_TL_V_VEC || !item || index >= vec->u.vec.count) return NOSHI_E_ARG;
    vec->u.vec.items[index] = item;
    return NOSHI_OK;
}

noshi_status noshi_tl_set(noshi_tl_value *obj, const char *field, noshi_tl_value *value) {
    const noshi_tl_field *f;
    int idx;
    if (!obj || obj->kind != NOSHI_TL_V_OBJ || !value) return NOSHI_E_ARG;
    idx = noshi_tl_field_index(obj->u.obj.ctor, field);
    if (idx < 0) return NOSHI_E_NOTFOUND;
    f = &noshi_tl_ctor_fields(obj->u.obj.ctor)[idx];
    if (type_at(f->type)->kind == NOSHI_TL_K_FLAGS) return NOSHI_E_ARG;
    if (!value_fits(type_at(f->type), value)) return NOSHI_E_ARG;
    obj->u.obj.fields[idx] = value;
    return NOSHI_OK;
}

noshi_status noshi_tl_clear(noshi_tl_value *obj, const char *field) {
    const noshi_tl_field *f;
    int idx;
    if (!obj || obj->kind != NOSHI_TL_V_OBJ) return NOSHI_E_ARG;
    idx = noshi_tl_field_index(obj->u.obj.ctor, field);
    if (idx < 0) return NOSHI_E_NOTFOUND;
    f = &noshi_tl_ctor_fields(obj->u.obj.ctor)[idx];
    if (type_at(f->type)->kind == NOSHI_TL_K_FLAGS) return NOSHI_E_ARG;
    obj->u.obj.fields[idx] = NULL;
    return NOSHI_OK;
}

noshi_status noshi_tl_set_i32(noshi_arena *a, noshi_tl_value *obj, const char *field, int32_t x) {
    noshi_tl_value *v = noshi_tl_new_i32(a, x);
    return v ? noshi_tl_set(obj, field, v) : NOSHI_E_NOMEM;
}

noshi_status noshi_tl_set_i64(noshi_arena *a, noshi_tl_value *obj, const char *field, int64_t x) {
    noshi_tl_value *v = noshi_tl_new_i64(a, x);
    return v ? noshi_tl_set(obj, field, v) : NOSHI_E_NOMEM;
}

noshi_status noshi_tl_set_f64(noshi_arena *a, noshi_tl_value *obj, const char *field, double x) {
    noshi_tl_value *v = noshi_tl_new_f64(a, x);
    return v ? noshi_tl_set(obj, field, v) : NOSHI_E_NOMEM;
}

noshi_status noshi_tl_set_bytes(noshi_arena *a, noshi_tl_value *obj, const char *field, const void *data, size_t len) {
    noshi_tl_value *v = noshi_tl_new_bytes(a, data, len);
    return v ? noshi_tl_set(obj, field, v) : NOSHI_E_NOMEM;
}

noshi_status noshi_tl_set_str(noshi_arena *a, noshi_tl_value *obj, const char *field, const char *s) {
    noshi_tl_value *v = noshi_tl_new_str(a, s);
    return v ? noshi_tl_set(obj, field, v) : NOSHI_E_NOMEM;
}

noshi_status noshi_tl_set_flag(noshi_tl_value *obj, const char *field) {
    return noshi_tl_set(obj, field, (noshi_tl_value *)(uintptr_t)&tl_true_value);
}

noshi_status noshi_tl_set_i64_vec(noshi_arena *a, noshi_tl_value *obj, const char *field, const int64_t *x, uint32_t count) {
    noshi_tl_value *vec = noshi_tl_new_vec(a, count);
    uint32_t i;
    if (!vec) return NOSHI_E_NOMEM;
    for (i = 0; i < count; ++i) {
        noshi_tl_value *item = noshi_tl_new_i64(a, x[i]);
        if (!item) return NOSHI_E_NOMEM;
        vec->u.vec.items[i] = item;
    }
    return noshi_tl_set(obj, field, vec);
}

noshi_status noshi_tl_set_i32_vec(noshi_arena *a, noshi_tl_value *obj, const char *field, const int32_t *x, uint32_t count) {
    noshi_tl_value *vec = noshi_tl_new_vec(a, count);
    uint32_t i;
    if (!vec) return NOSHI_E_NOMEM;
    for (i = 0; i < count; ++i) {
        noshi_tl_value *item = noshi_tl_new_i32(a, x[i]);
        if (!item) return NOSHI_E_NOMEM;
        vec->u.vec.items[i] = item;
    }
    return noshi_tl_set(obj, field, vec);
}

const noshi_tl_value *noshi_tl_get(const noshi_tl_value *obj, const char *field) {
    int idx;
    if (!obj || obj->kind != NOSHI_TL_V_OBJ) return NULL;
    idx = noshi_tl_field_index(obj->u.obj.ctor, field);
    if (idx < 0) return NULL;
    return obj->u.obj.fields[idx];
}

uint32_t noshi_tl_id(const noshi_tl_value *obj) {
    return obj && obj->kind == NOSHI_TL_V_OBJ ? obj->u.obj.ctor->id : 0;
}

int noshi_tl_is(const noshi_tl_value *obj, uint32_t id) {
    return noshi_tl_id(obj) == id;
}

int noshi_tl_has(const noshi_tl_value *obj, const char *field) {
    return noshi_tl_get(obj, field) != NULL;
}

static noshi_status get_kind(const noshi_tl_value *obj, const char *field, uint8_t kind, const noshi_tl_value **out) {
    const noshi_tl_value *v = noshi_tl_get(obj, field);
    if (!v) return NOSHI_E_NOTFOUND;
    if (v->kind != kind) return NOSHI_E_MALFORMED;
    *out = v;
    return NOSHI_OK;
}

noshi_status noshi_tl_get_i32(const noshi_tl_value *obj, const char *field, int32_t *out) {
    const noshi_tl_value *v;
    noshi_status s = get_kind(obj, field, NOSHI_TL_V_I32, &v);
    if (s == NOSHI_OK) *out = v->u.i32;
    return s;
}

noshi_status noshi_tl_get_i64(const noshi_tl_value *obj, const char *field, int64_t *out) {
    const noshi_tl_value *v;
    noshi_status s = get_kind(obj, field, NOSHI_TL_V_I64, &v);
    if (s == NOSHI_OK) *out = v->u.i64;
    return s;
}

noshi_status noshi_tl_get_f64(const noshi_tl_value *obj, const char *field, double *out) {
    const noshi_tl_value *v;
    noshi_status s = get_kind(obj, field, NOSHI_TL_V_F64, &v);
    if (s == NOSHI_OK) *out = v->u.f64;
    return s;
}

noshi_status noshi_tl_get_bytes(const noshi_tl_value *obj, const char *field, const uint8_t **data, size_t *len) {
    const noshi_tl_value *v;
    noshi_status s = get_kind(obj, field, NOSHI_TL_V_BYTES, &v);
    if (s == NOSHI_OK) {
        *data = v->u.bytes.data;
        *len = v->u.bytes.len;
    }
    return s;
}

noshi_status noshi_tl_get_obj(const noshi_tl_value *obj, const char *field, const noshi_tl_value **out) {
    return get_kind(obj, field, NOSHI_TL_V_OBJ, out);
}

noshi_status noshi_tl_get_vec(const noshi_tl_value *obj, const char *field, const noshi_tl_value **out) {
    return get_kind(obj, field, NOSHI_TL_V_VEC, out);
}

static noshi_status put(noshi_writer *w, const char *s) {
    return noshi_wr_bytes(w, s, strlen(s));
}

static noshi_status dump_value(const noshi_tl_value *v, noshi_writer *w, uint32_t depth) {
    char tmp[48];
    noshi_status s;
    uint32_t i;
    if (depth > ENC_MAX_DEPTH) return put(w, "...");
    if (!v) return put(w, "null");
    switch (v->kind) {
    case NOSHI_TL_V_I32:
        snprintf(tmp, sizeof(tmp), "%d", (int)v->u.i32);
        return put(w, tmp);
    case NOSHI_TL_V_I64:
        snprintf(tmp, sizeof(tmp), "%lld", (long long)v->u.i64);
        return put(w, tmp);
    case NOSHI_TL_V_F64:
        snprintf(tmp, sizeof(tmp), "%g", v->u.f64);
        return put(w, tmp);
    case NOSHI_TL_V_TRUE:
        return put(w, "true");
    case NOSHI_TL_V_BYTES: {
        uint32_t n = v->u.bytes.len < 32 ? v->u.bytes.len : 32;
        s = put(w, "x'");
        for (i = 0; i < n && s == NOSHI_OK; ++i) {
            snprintf(tmp, sizeof(tmp), "%02x", v->u.bytes.data[i]);
            s = put(w, tmp);
        }
        if (s == NOSHI_OK && n < v->u.bytes.len) s = put(w, "...");
        if (s == NOSHI_OK) s = put(w, "'");
        return s;
    }
    case NOSHI_TL_V_VEC:
        s = put(w, "[");
        for (i = 0; i < v->u.vec.count && s == NOSHI_OK; ++i) {
            if (i) s = put(w, ", ");
            if (s == NOSHI_OK) s = dump_value(v->u.vec.items[i], w, depth + 1);
        }
        if (s == NOSHI_OK) s = put(w, "]");
        return s;
    case NOSHI_TL_V_OBJ: {
        const noshi_tl_ctor *c = v->u.obj.ctor;
        const noshi_tl_field *f = noshi_tl_ctor_fields(c);
        unsigned first = 1;
        s = put(w, c->name);
        if (s == NOSHI_OK) s = put(w, "(");
        for (i = 0; i < c->field_count && s == NOSHI_OK; ++i) {
            if (!v->u.obj.fields[i]) continue;
            if (!first) s = put(w, ", ");
            first = 0;
            if (s == NOSHI_OK) s = put(w, f[i].name);
            if (s == NOSHI_OK) s = put(w, "=");
            if (s == NOSHI_OK) s = dump_value(v->u.obj.fields[i], w, depth + 1);
        }
        if (s == NOSHI_OK) s = put(w, ")");
        return s;
    }
    }
    return NOSHI_E_ARG;
}

noshi_status noshi_tl_dump(const noshi_tl_value *value, noshi_writer *w) {
    return dump_value(value, w, 0);
}
