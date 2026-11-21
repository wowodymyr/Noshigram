#ifndef NOSHI_MT_SOCKET_H
#define NOSHI_MT_SOCKET_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

typedef struct noshi_mt_socket {
    int fd;
    /* set by noshi_mt_socket_start_faketls: what the records of the fake TLS layer keep between reads; owned by the socket */
    struct noshi_mt_faketls *tls;
} noshi_mt_socket;

void noshi_mt_socket_init(noshi_mt_socket *s);
noshi_status noshi_mt_socket_connect(noshi_mt_socket *s, const char *host, uint16_t port, int timeout_ms);
/* takes over a connected non blocking stream socket that another part of the program opened, such as a stream of
   the tunnel */
noshi_status noshi_mt_socket_adopt(noshi_mt_socket *s, int fd);
noshi_status noshi_mt_socket_connect_socks5(noshi_mt_socket *s, const char *proxy_host, uint16_t proxy_port,
                                                const char *user, const char *pass,
                                                const char *dest_host, uint16_t dest_port, int timeout_ms);
/* negotiates on an already connected stream, including one opened through shiro; closes it on failure */
noshi_status noshi_mt_socket_negotiate_socks5(noshi_mt_socket *s, const char *user, const char *pass,
                                                  const char *dest_host, uint16_t dest_port, int timeout_ms);
/* the fake TLS handshake of an "ee" proxy, on a socket that is connected to it (directly, through the tunnel or through a SOCKS5 proxy): the hello that proves
   the secret, and the proxy's reply that proves it back (NOSHI_E_SECURITY when it does not, NOSHI_E_MALFORMED for a reply that is not TLS, NOSHI_E_EOF
   when the proxy closes, which is how it refuses a hello). From then on writes and reads carry the records, so what the caller sends and receives is the
   payload alone. The socket is closed on a failure */
noshi_status noshi_mt_socket_start_faketls(noshi_mt_socket *s, const uint8_t secret[16], const char *domain, int timeout_ms);
noshi_status noshi_mt_socket_write_all(noshi_mt_socket *s, const uint8_t *data, size_t len, int timeout_ms);
noshi_status noshi_mt_socket_read(noshi_mt_socket *s, uint8_t *buf, size_t cap, size_t *got, int timeout_ms);
void noshi_mt_socket_close(noshi_mt_socket *s);

#endif
