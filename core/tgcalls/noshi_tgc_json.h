#ifndef NOSHI_TGC_JSON_H
#define NOSHI_TGC_JSON_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the JSON the tgcalls signaling speaks, read and written with hard bounds; the text comes from the other phone,
   so the depth, the number of values and the size of the text are all capped, and every string is checked to be
   UTF-8 */

#define NOSHI_JSON_MAX_DEPTH 12
#define NOSHI_JSON_MAX_TEXT (64u * 1024u)
#define NOSHI_JSON_MAX_NODES 4096u

typedef enum noshi_json_type {
    NOSHI_JSON_NULL,
    NOSHI_JSON_BOOL,
    NOSHI_JSON_NUMBER,
    NOSHI_JSON_STRING,
    NOSHI_JSON_ARRAY,
    NOSHI_JSON_OBJECT
} noshi_json_type;

typedef struct noshi_json noshi_json;
typedef struct noshi_json_doc noshi_json_doc;

/* parses a whole document, which must be one value and nothing after it but white space */
noshi_status noshi_json_parse(const char *text, size_t len, noshi_json_doc **out);
void noshi_json_free(noshi_json_doc *doc);
const noshi_json *noshi_json_root(const noshi_json_doc *doc);

noshi_json_type noshi_json_kind(const noshi_json *node);

/* the last member of an object with that key, or NULL; also NULL when node is not an object */
const noshi_json *noshi_json_get(const noshi_json *object, const char *key);

/* array elements and object members in document order: first and next are NULL at the end, and for a node that holds none */
const noshi_json *noshi_json_first(const noshi_json *node);
const noshi_json *noshi_json_next(const noshi_json *node);
size_t noshi_json_count(const noshi_json *node);
/* the key of an object member, NULL for anything else */
const char *noshi_json_key(const noshi_json *node);

/* the string value, NUL terminated, with its length in bytes; NULL when node is not a string */
const char *noshi_json_string(const noshi_json *node, size_t *len);
/* an integral number that fits int64; NOSHI_E_MALFORMED for a fraction, an exponent form or a value out of range, and for a
   node that is no number */
noshi_status noshi_json_int(const noshi_json *node, int64_t *out);
noshi_status noshi_json_bool(const noshi_json *node, int *out);

/* writing: values go to a buffer the caller owns, commas and the colons come by themselves; a failed step (a
   buffer too small, a misplaced call, a nesting too deep) sticks, and finish reports it */
typedef struct noshi_json_out {
    char *buf;
    size_t cap;
    size_t len;
    noshi_status status;
    int depth;
    uint8_t member_count[NOSHI_JSON_MAX_DEPTH];
    uint8_t is_object[NOSHI_JSON_MAX_DEPTH];
    uint8_t key_pending;
} noshi_json_out;

void noshi_json_out_init(noshi_json_out *out, char *buf, size_t cap);
void noshi_json_out_object(noshi_json_out *out);
void noshi_json_out_array(noshi_json_out *out);
void noshi_json_out_end(noshi_json_out *out);
/* the key of the next object member; the value follows in the next call */
void noshi_json_out_key(noshi_json_out *out, const char *key);
void noshi_json_out_string(noshi_json_out *out, const char *value);
void noshi_json_out_int(noshi_json_out *out, int64_t value);
void noshi_json_out_bool(noshi_json_out *out, int value);
/* NOSHI_OK with the length (the text is NUL terminated) once exactly one value is complete */
noshi_status noshi_json_out_finish(noshi_json_out *out, size_t *len);

#endif
