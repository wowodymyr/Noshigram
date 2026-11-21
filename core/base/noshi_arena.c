#include "noshi_arena.h"
#include "noshi_bytes.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define ARENA_MIN_CHUNK 4096u

struct noshi_arena_chunk {
    noshi_arena_chunk *next;
    size_t cap;
    size_t used;
    uint64_t data[1];
};

void noshi_arena_init(noshi_arena *a, size_t limit) {
    a->head = NULL;
    a->used = 0;
    a->limit = limit;
}

void *noshi_arena_alloc(noshi_arena *a, size_t n) {
    noshi_arena_chunk *c;
    size_t want, cap;
    void *p;
    if (n > a->limit || n > SIZE_MAX - 7u) return NULL;
    n = (n + 7u) & ~(size_t)7u;
    if (n == 0) n = 8;
    if (n > a->limit - a->used) return NULL;
    c = a->head;
    if (!c || n > c->cap - c->used) {
        want = n > ARENA_MIN_CHUNK ? n : ARENA_MIN_CHUNK;
        cap = want;
        if (cap > SIZE_MAX - offsetof(noshi_arena_chunk, data)) return NULL;
        c = (noshi_arena_chunk *)malloc(offsetof(noshi_arena_chunk, data) + cap);
        if (!c) return NULL;
        c->next = a->head;
        c->cap = cap;
        c->used = 0;
        a->head = c;
    }
    p = (uint8_t *)c->data + c->used;
    c->used += n;
    a->used += n;
    memset(p, 0, n);
    return p;
}

void *noshi_arena_copy(noshi_arena *a, const void *data, size_t n) {
    void *p;
    if (n && !data) return NULL;
    p = noshi_arena_alloc(a, n ? n : 1);
    if (p && n) memcpy(p, data, n);
    return p;
}

char *noshi_arena_strdup(noshi_arena *a, const char *s) {
    size_t n;
    char *p;
    if (!s) return NULL;
    n = strlen(s);
    p = (char *)noshi_arena_alloc(a, n + 1);
    if (p) memcpy(p, s, n + 1);
    return p;
}

void noshi_arena_free(noshi_arena *a) {
    noshi_arena_chunk *c = a->head;
    while (c) {
        noshi_arena_chunk *next = c->next;
        /* freeing the arena must erase auth codes and password proofs */
        noshi_wipe(c->data, c->used);
        free(c);
        c = next;
    }
    a->head = NULL;
    a->used = 0;
}
