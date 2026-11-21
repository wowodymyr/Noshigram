#ifndef NOSHI_PROXY_H
#define NOSHI_PROXY_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_links.h"
#include "noshi_status.h"

#define NOSHI_PROXY_SECRET_LEN 16
#define NOSHI_PROXY_DOMAIN_MAX 120

typedef enum noshi_proxy_kind {
    NOSHI_PROXY_MTPROTO = 1,  /* an MTProto proxy: the obfuscated stream of the transport, keyed by a secret */
    NOSHI_PROXY_SOCKS5        /* a SOCKS5 proxy, with a user and a password or without */
} noshi_proxy_kind;

typedef struct noshi_proxy {
    noshi_proxy_kind kind;
    char server[NOSHI_LINK_SERVER_MAX];
    uint16_t port;
    uint8_t secret[NOSHI_PROXY_SECRET_LEN];
    uint8_t padded;             /* the secret began with dd: the padded intermediate transport, which proxies of the current kind ask for */
    char tls_domain[NOSHI_PROXY_DOMAIN_MAX + 1];
    char user[NOSHI_LINK_CREDENTIAL_MAX];
    char password[NOSHI_LINK_CREDENTIAL_MAX];
} noshi_proxy;

/* the secret of an MTProto proxy as a link or a person types it, hex or base64url: 16 bytes, or dd and 16 bytes for the padded transport. NOSHI_E_UNSUPPORTED
   for ee and a domain, the fake TLS secrets this client does not speak, NOSHI_E_MALFORMED for anything else */
noshi_status noshi_proxy_secret_decode(const char *text, uint8_t secret[NOSHI_PROXY_SECRET_LEN], uint8_t *padded);

/* a name or an IPv4 address in the form a server field takes: letters, digits, dots and hyphens, 1 to 253 characters, no empty label */
int noshi_proxy_server_valid(const char *server);

/* the proxy a tg://proxy, tg://socks, t.me/proxy or t.me/socks link names. NOSHI_E_ARG for a link of another kind, NOSHI_E_UNSUPPORTED or
   NOSHI_E_MALFORMED as the secret decode says */
noshi_status noshi_proxy_from_link(const noshi_tg_link *link, noshi_proxy *out);

/* the link that adds this proxy in another client: tg://proxy?server=&port=&secret= (secret in hex, with dd when padded) or tg://socks?..., into out;
   NOSHI_E_LIMIT when it does not fit */
noshi_status noshi_proxy_link(const noshi_proxy *proxy, char *out, size_t cap);

#endif
