#ifndef NOSHI_ARENA_H
#define NOSHI_ARENA_H

#include <stddef.h>

typedef struct noshi_arena_chunk noshi_arena_chunk;

typedef struct noshi_arena {
    noshi_arena_chunk *head;
    size_t used;
    size_t limit;
} noshi_arena;

void noshi_arena_init(noshi_arena *a, size_t limit);
void *noshi_arena_alloc(noshi_arena *a, size_t n);
void *noshi_arena_copy(noshi_arena *a, const void *data, size_t n);
char *noshi_arena_strdup(noshi_arena *a, const char *s);
void noshi_arena_free(noshi_arena *a);

#endif
