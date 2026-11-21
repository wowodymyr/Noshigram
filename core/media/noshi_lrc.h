#ifndef NOSHI_LRC_H
#define NOSHI_LRC_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* synchronized lyrics in the LRC form that LRCLIB serves: lines that start with one or more [mm:ss.xx] stamps and then the text. tags that name the song ([ar:], [ti:])
   and the word stamps of the enhanced form (<mm:ss.xx>) are dropped, a line with no text is dropped, and the lines come out in the order of their stamps */

#define NOSHI_LRC_INPUT_MAX (256u * 1024u)
#define NOSHI_LRC_LINES_MAX 2000u
#define NOSHI_LRC_TEXT_MAX 512u

typedef struct noshi_lrc_line {
    uint32_t start_ms;
    char *text;     /* UTF-8, owned by the noshi_lrc */
} noshi_lrc_line;

typedef struct noshi_lrc {
    noshi_lrc_line *lines;
    size_t count;
} noshi_lrc;

/* NOSHI_E_MALFORMED when no line carries a stamp (the text is then plain, not synchronized), NOSHI_E_LIMIT for input over NOSHI_LRC_INPUT_MAX; more than
   NOSHI_LRC_LINES_MAX lines keep the first ones. out is empty after a failure */
noshi_status noshi_lrc_parse(const char *text, size_t len, noshi_lrc *out);
void noshi_lrc_free(noshi_lrc *lrc);

/* the line that is being sung at ms: the last one that has started, -1 before the first */
long noshi_lrc_active(const noshi_lrc *lrc, uint32_t ms);

/* a title or an artist as a lyrics search wants it: the parts in [] and () and a trailing "feat." / "ft." / "featuring" credit are cut off; when nothing is left
   the trimmed original stays. NOSHI_E_LIMIT when out is too small */
noshi_status noshi_lrc_search_text(const char *in, char *out, size_t cap);

#endif
