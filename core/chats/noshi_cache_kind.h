#ifndef NOSHI_CACHE_KIND_H
#define NOSHI_CACHE_KIND_H

#include <stddef.h>
#include <stdint.h>

/* what a file of the media cache is, for the storage screen; the cache keeps files by key with no extension, so the
   kind comes from the first bytes */
typedef enum noshi_cache_kind {
    NOSHI_CACHE_VIDEO = 0,
    NOSHI_CACHE_PHOTO,
    NOSHI_CACHE_MUSIC,
    NOSHI_CACHE_STICKER,
    NOSHI_CACHE_OTHER,
    NOSHI_CACHE_KIND_COUNT
} noshi_cache_kind;

/* name is the file's name in the cache directory, head the first bytes and len how many of them there are (16 are
   enough); an unknown or empty file is NOSHI_CACHE_OTHER */
noshi_cache_kind noshi_cache_classify(const char *name, const uint8_t *head, size_t len);

#endif
