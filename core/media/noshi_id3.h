#ifndef NOSHI_ID3_H
#define NOSHI_ID3_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the cover picture of a music file from its ID3v2 tag (versions 2.2, 2.3 and 2.4), which sits at the start of the file; the player reads it from the head
   of the download so a track that Telegram stored without a thumbnail still has its cover */

#define NOSHI_ID3_HEADER 10u
/* a tag larger than this is not read: the head of the file is fetched in one ranged request, whose size is at most the 1 MiB the server allows */
#define NOSHI_ID3_TAG_MAX (1024u * 1024u)

/* the size of the whole tag (header, frames and padding) from the first NOSHI_ID3_HEADER bytes of a file.
   NOSHI_E_NOTFOUND when the file does not start with a tag, NOSHI_E_MALFORMED for a bad size or version,
   NOSHI_E_LIMIT above NOSHI_ID3_TAG_MAX, NOSHI_E_UNSUPPORTED for a tag the reader cannot walk (unsynchronised or compressed as a whole) */
noshi_status noshi_id3_tag_size(const uint8_t *head, size_t len, size_t *tag_size);

/* where the picture bytes lie inside data, the first len bytes of the file: the front cover when the tag has one, else the first picture.
   NOSHI_E_NOTFOUND when the tag has no usable picture, NOSHI_E_TRUNCATED when len ends before the tag does and the picture may follow (read
   noshi_id3_tag_size bytes and ask again), NOSHI_E_MALFORMED for frames that overrun the tag */
noshi_status noshi_id3_cover(const uint8_t *data, size_t len, size_t *offset, size_t *size);

#endif
