#ifndef NOSHI_TL_SCHEMA_H
#define NOSHI_TL_SCHEMA_H

#include <stdint.h>


typedef enum noshi_tl_kind {
    NOSHI_TL_K_INT,
    NOSHI_TL_K_LONG,
    NOSHI_TL_K_DOUBLE,
    NOSHI_TL_K_INT128,
    NOSHI_TL_K_INT256,
    NOSHI_TL_K_STRING,
    NOSHI_TL_K_BYTES,
    NOSHI_TL_K_TRUE,
    NOSHI_TL_K_FLAGS,
    NOSHI_TL_K_OBJECT,
    NOSHI_TL_K_VECTOR,
    NOSHI_TL_K_GENERIC
} noshi_tl_kind;

typedef struct noshi_tl_type {
    uint8_t kind;
    uint8_t bare;
    uint16_t arg;
} noshi_tl_type;

#define NOSHI_TL_NO_FLAGS 255

typedef struct noshi_tl_field {
    const char *name;
    uint16_t type;
    uint8_t flags_field;
    uint8_t flag_bit;
} noshi_tl_field;

typedef struct noshi_tl_ctor {
    uint32_t id;
    uint16_t result;
    uint16_t type_name;
    uint32_t first_field;
    uint8_t field_count;
    uint8_t is_function;
    const char *name;
} noshi_tl_ctor;

#define NOSHI_TL_REF_ANY 0

extern const uint32_t noshi_tl_layer;
extern const char *const noshi_tl_type_names[];
extern const uint32_t noshi_tl_type_name_count;
extern const noshi_tl_type noshi_tl_types[];
extern const uint32_t noshi_tl_type_count;
extern const int32_t noshi_tl_bare_ctor[];
extern const noshi_tl_field noshi_tl_fields[];
extern const uint32_t noshi_tl_field_count;
extern const noshi_tl_ctor noshi_tl_ctors[];
extern const uint32_t noshi_tl_ctor_count;
extern const uint32_t noshi_tl_ctors_by_name[];

#endif
