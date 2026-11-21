#ifndef NOSHI_HTTPS_H
#define NOSHI_HTTPS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_mt_socket.h"

/* one HTTPS POST for the account call of WARP, over TLS 1.2 or newer with the chain and the host name checked */

#define NOSHI_HTTPS_MAX_RESPONSE (256u * 1024u)
/* the most a caller may ask for with max_response: a page of an article with its pictures, and no more */
#define NOSHI_HTTPS_MAX_RESPONSE_LIMIT (6u * 1024u * 1024u)

/* the ways the first flight of the handshake can leave, for a network that reads the name of the server from the hello. the first is the plain one */
#define NOSHI_HELLO_WHOLE 0
/* the first bytes in small pieces with a short pause between them */
#define NOSHI_HELLO_PIECES 1
/* the byebyedpi tlsrec strategy: the hello record is cut in two records inside the SNI, one byte into the name, and the stream is cut there too (three segments) */
#define NOSHI_HELLO_RECORD 2
/* the same cut at the middle of the name */
#define NOSHI_HELLO_RECORD_MIDDLE 3

typedef struct noshi_https_request {
    const char *host;                   /* the name asked for in the SNI and required in the certificate */
    const char *connect_ip;             /* a dotted IPv4 address to dial instead of resolving host, or NULL */
    uint16_t port;
    const char *path;                   /* starts with / */
    const char *const *headers;         /* "name: value" lines ending with NULL, or NULL */
    const uint8_t *body;
    size_t body_len;
    const char *roots_pem;              /* the trusted roots, PEM, at least one */
    size_t roots_len;
    int split_hello;                    /* how the TLS hello goes out, one of NOSHI_HELLO_*: whole, in small pieces, or cut inside the SNI */
    int timeout_ms;                     /* the whole call */
    size_t max_response;                /* the most the reply (head and body) may take: zero for NOSHI_HTTPS_MAX_RESPONSE, else up to NOSHI_HTTPS_MAX_RESPONSE_LIMIT */
    int (*is_cancelled)(void *ctx);
    void *cancel_ctx;
    noshi_status (*connect_socket)(noshi_mt_socket *socket, const char *host, uint16_t port, int timeout_ms);
} noshi_https_request;

typedef struct noshi_https_response {
    int status;
    uint8_t *body;                      /* owned, free with noshi_https_response_free */
    size_t body_len;
    char headers[16385];
} noshi_https_response;

/* the answer of a streamed GET, read before any body byte is passed on */
#define NOSHI_HTTPS_LOCATION_MAX 2048u
typedef struct noshi_https_head {
    int status;
    uint64_t content_length;                    /* of a 200, else zero */
    char location[NOSHI_HTTPS_LOCATION_MAX];  /* of a redirect, else empty */
} noshi_https_head;

/* receives the body in pieces in order; any status but NOSHI_OK stops the transfer and is returned as it is */
typedef noshi_status (*noshi_https_sink)(void *ctx, const uint8_t *data, size_t len);

/* a GET for a file too large to hold: a 200 with a Content-Length goes to the sink, and max_response (required, here a cap on the body alone
   and not limited to NOSHI_HTTPS_MAX_RESPONSE_LIMIT) refuses a longer one before a byte is read. Every other status returns with the head
   filled and no body read, so the caller can follow a redirect. A chunked or unframed 200 is NOSHI_E_UNSUPPORTED. timeout_ms covers the
   whole transfer */
noshi_status noshi_https_get_stream(const noshi_https_request *request, noshi_https_head *head, noshi_https_sink sink, void *sink_ctx);

/* NOSHI_E_ARG for a request that is not well formed (a header with a line break, no roots, no host),
   NOSHI_E_SECURITY when the certificate chain */
noshi_status noshi_https_post(const noshi_https_request *request, noshi_https_response *response);
/* the same verified transport for bounded raster tiles; no redirects are followed */
noshi_status noshi_https_get(const noshi_https_request *request, noshi_https_response *response);
void noshi_https_response_free(noshi_https_response *response);

#endif
