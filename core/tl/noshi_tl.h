#ifndef NOSHI_TL_H
#define NOSHI_TL_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_arena.h"
#include "noshi_bytes.h"
#include "noshi_status.h"
#include "noshi_tl_schema.h"

typedef enum noshi_tl_vkind {
    NOSHI_TL_V_I32 = 1,
    NOSHI_TL_V_I64,
    NOSHI_TL_V_F64,
    NOSHI_TL_V_BYTES,
    NOSHI_TL_V_TRUE,
    NOSHI_TL_V_OBJ,
    NOSHI_TL_V_VEC
} noshi_tl_vkind;

typedef struct noshi_tl_value noshi_tl_value;

struct noshi_tl_value {
    uint8_t kind;
    union {
        int32_t i32;
        int64_t i64;
        double f64;
        struct {
            const uint8_t *data;
            uint32_t len;
        } bytes;
        struct {
            const noshi_tl_ctor *ctor;
            noshi_tl_value **fields;
        } obj;
        struct {
            uint32_t count;
            noshi_tl_value **items;
        } vec;
    } u;
};

typedef struct noshi_tl_limits {
    uint32_t max_depth;
    uint32_t max_values;
    uint32_t max_inflate;
    int borrow_bytes;      /* borrowed values alias the packet, so its storage must outlive the arena */
} noshi_tl_limits;

extern const noshi_tl_limits noshi_tl_default_limits;

typedef struct noshi_tl_error {
    const char *ctor;
    const char *field;
} noshi_tl_error;

const noshi_tl_ctor *noshi_tl_find_ctor(uint32_t id);
const noshi_tl_ctor *noshi_tl_find_ctor_by_name(const char *name);
const noshi_tl_field *noshi_tl_ctor_fields(const noshi_tl_ctor *ctor);
int noshi_tl_field_index(const noshi_tl_ctor *ctor, const char *name);
const char *noshi_tl_result_type_name(const noshi_tl_ctor *ctor);

noshi_status noshi_tl_decode(noshi_arena *arena, const noshi_tl_limits *limits, uint16_t type_ref,
                                 const uint8_t *data, size_t len, size_t *consumed, noshi_tl_value **out);
noshi_status noshi_tl_decode_all(noshi_arena *arena, const noshi_tl_limits *limits, uint16_t type_ref,
                                     const uint8_t *data, size_t len, noshi_tl_value **out);

/* mtproto must dispatch the unpacked rpc envelope before decoding its request-specific result */
noshi_status noshi_tl_unpack_gzip(const uint8_t *data, size_t len, noshi_writer *out);

noshi_status noshi_tl_encode(const noshi_tl_value *value, noshi_writer *w, noshi_tl_error *error);
noshi_status noshi_tl_result_ref(const noshi_tl_value *request, uint16_t *ref);

noshi_tl_value *noshi_tl_new_i32(noshi_arena *a, int32_t v);
noshi_tl_value *noshi_tl_new_i64(noshi_arena *a, int64_t v);
noshi_tl_value *noshi_tl_new_f64(noshi_arena *a, double v);
noshi_tl_value *noshi_tl_new_bytes(noshi_arena *a, const void *data, size_t len);
noshi_tl_value *noshi_tl_new_str(noshi_arena *a, const char *s);
noshi_tl_value *noshi_tl_new_vec(noshi_arena *a, uint32_t count);
noshi_tl_value *noshi_tl_new_obj(noshi_arena *a, const char *ctor_name);
noshi_tl_value *noshi_tl_new_obj_ctor(noshi_arena *a, const noshi_tl_ctor *ctor);
noshi_status noshi_tl_vec_set(noshi_tl_value *vec, uint32_t index, noshi_tl_value *item);

noshi_status noshi_tl_set(noshi_tl_value *obj, const char *field, noshi_tl_value *value);
noshi_status noshi_tl_set_i32(noshi_arena *a, noshi_tl_value *obj, const char *field, int32_t v);
noshi_status noshi_tl_set_i64(noshi_arena *a, noshi_tl_value *obj, const char *field, int64_t v);
noshi_status noshi_tl_set_f64(noshi_arena *a, noshi_tl_value *obj, const char *field, double v);
noshi_status noshi_tl_set_bytes(noshi_arena *a, noshi_tl_value *obj, const char *field, const void *data, size_t len);
noshi_status noshi_tl_set_str(noshi_arena *a, noshi_tl_value *obj, const char *field, const char *s);
noshi_status noshi_tl_set_flag(noshi_tl_value *obj, const char *field);
/* takes an optional field or a flag off the object, as if the sender had not set it; NOSHI_E_NOTFOUND for a field the constructor does not have */
noshi_status noshi_tl_clear(noshi_tl_value *obj, const char *field);
noshi_status noshi_tl_set_i64_vec(noshi_arena *a, noshi_tl_value *obj, const char *field, const int64_t *v, uint32_t count);
noshi_status noshi_tl_set_i32_vec(noshi_arena *a, noshi_tl_value *obj, const char *field, const int32_t *v, uint32_t count);

const noshi_tl_value *noshi_tl_get(const noshi_tl_value *obj, const char *field);
uint32_t noshi_tl_id(const noshi_tl_value *obj);
int noshi_tl_is(const noshi_tl_value *obj, uint32_t id);
int noshi_tl_has(const noshi_tl_value *obj, const char *field);
noshi_status noshi_tl_get_i32(const noshi_tl_value *obj, const char *field, int32_t *out);
noshi_status noshi_tl_get_i64(const noshi_tl_value *obj, const char *field, int64_t *out);
noshi_status noshi_tl_get_f64(const noshi_tl_value *obj, const char *field, double *out);
noshi_status noshi_tl_get_bytes(const noshi_tl_value *obj, const char *field, const uint8_t **data, size_t *len);
noshi_status noshi_tl_get_obj(const noshi_tl_value *obj, const char *field, const noshi_tl_value **out);
noshi_status noshi_tl_get_vec(const noshi_tl_value *obj, const char *field, const noshi_tl_value **out);

/* bounded byte output keeps file parts from filling diagnostic logs */
noshi_status noshi_tl_dump(const noshi_tl_value *value, noshi_writer *w);

#endif
