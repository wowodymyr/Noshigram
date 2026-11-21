#ifndef NOSHI_TRANSLATE_HTML_H
#define NOSHI_TRANSLATE_HTML_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the styled runs of a message go to a web translator as light markup and come back from it it */

#define NOSHI_TH_TEXT_MAX 8192u
#define NOSHI_TH_SPAN_MAX 512u

typedef enum {
    NOSHI_TH_BOLD = 1,
    NOSHI_TH_ITALIC,
    NOSHI_TH_UNDERLINE,
    NOSHI_TH_STRIKE,
    NOSHI_TH_CODE,
    NOSHI_TH_LINK
} noshi_th_kind;

typedef struct noshi_th_span {
    int32_t kind;
    uint32_t offset;
    uint32_t length;
} noshi_th_span;

/* the text with its spans as markup; a span with no length, one that leaves the text or one of a kind not listed
   above is left out */
noshi_status noshi_th_encode(const uint16_t *text, size_t len, const noshi_th_span *spans, size_t count, uint16_t *out, size_t cap, size_t *out_len);

/* the markup a translator returned as plain text and spans, ordered by offset and then by length, longest first */
noshi_status noshi_th_decode(const uint16_t *markup, size_t len, uint16_t *out, size_t out_cap, size_t *out_len, noshi_th_span *spans, size_t span_cap,
                                 size_t *span_count);

#endif
