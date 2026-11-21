#ifndef NOSHI_SOCKS_H
#define NOSHI_SOCKS_H

#include "noshi_bytes.h"

typedef enum noshi_socks_state {
    NOSHI_SOCKS_METHOD = 0,
    NOSHI_SOCKS_AUTH,
    NOSHI_SOCKS_CONNECT,
    NOSHI_SOCKS_READY,
    NOSHI_SOCKS_FAILED
} noshi_socks_state;

typedef struct noshi_socks {
    noshi_socks_state state;
    uint8_t target[260];
    size_t target_len;
    uint8_t credentials[513];
    size_t credentials_len;
    uint8_t response[262];
    size_t response_len;
    size_t need;
    uint8_t reply;
} noshi_socks;

noshi_status noshi_socks_start(noshi_socks *s, const char *host, uint16_t port,
                                  const char *username, const char *password, noshi_writer *out);
noshi_status noshi_socks_feed(noshi_socks *s, const uint8_t *data, size_t len,
                                 size_t *consumed, noshi_writer *out);
void noshi_socks_free(noshi_socks *s);

#endif
