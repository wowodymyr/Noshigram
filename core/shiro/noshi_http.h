#ifndef NOSHI_HTTP_H
#define NOSHI_HTTP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the one HTTP/1.x response a registration call gets back, read strictly */

#define NOSHI_HTTP_MAX_HEADERS 16384u
#define NOSHI_HTTP_LOCATION_MAX 2048u

/* the status line and the headers a caller acts on, before any body byte is read */
typedef struct noshi_http_head {
    int status;                             /* 200 to 599 */
    int chunked;
    int has_length;
    size_t content_length;
    size_t body_start;                      /* offset of the first body byte in the data */
    char location[NOSHI_HTTP_LOCATION_MAX];   /* the Location value, or empty */
} noshi_http_head;

typedef struct noshi_http_response {
    int status;             /* 100 to 599 */
    size_t body_len;
} noshi_http_response;

/* NOSHI_E_TRUNCATED until the blank line that ends the headers has arrived */
noshi_status noshi_http_parse_head(const uint8_t *data, size_t len, int eof, noshi_http_head *out);

/* data is everything received so far; eof says the connection is closed */
noshi_status noshi_http_parse_response(const uint8_t *data, size_t len, int eof, noshi_http_response *out, uint8_t *body, size_t cap);

#endif
