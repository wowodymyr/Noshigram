#include "noshi_mt_socket.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include <stdlib.h>

#include "noshi_clock.h"
#include "noshi_faketls.h"
#include "noshi_random.h"
#include "noshi_mt_traffic.h"
#include "noshi_socks.h"

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

struct noshi_mt_faketls {
    noshi_faketls_reader reader;
};

void noshi_mt_socket_init(noshi_mt_socket *s) {
    s->fd = -1;
    s->tls = NULL;
}

void noshi_mt_socket_close(noshi_mt_socket *s) {
    if (s->fd >= 0) close(s->fd);
    s->fd = -1;
    free(s->tls);
    s->tls = NULL;
}

static noshi_status set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return NOSHI_E_IO;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) return NOSHI_E_IO;
    return NOSHI_OK;
}

static int remaining_ms(uint64_t deadline) {
    uint64_t now = noshi_system_clock.monotonic_ms(NULL);
    if (now >= deadline) return 0;
    return deadline - now > INT_MAX ? INT_MAX : (int)(deadline - now);
}

/* poll restarts after a signal with the time that is left, so a signal storm cannot stretch a timeout */
static noshi_status wait_fd(int fd, short events, uint64_t deadline) {
    for (;;) {
        struct pollfd p;
        int rc;
        p.fd = fd;
        p.events = events;
        p.revents = 0;
        rc = poll(&p, 1, remaining_ms(deadline));
        if (rc < 0) {
            if (errno == EINTR) continue;
            return NOSHI_E_IO;
        }
        if (rc == 0) return NOSHI_E_TIMEOUT;
        if (p.revents & POLLNVAL) return NOSHI_E_IO;
        if (p.revents & (events | POLLERR | POLLHUP)) return NOSHI_OK;
    }
}

static noshi_status connect_one(const struct addrinfo *ai, uint64_t deadline, int *out_fd) {
    int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    noshi_status s;
    int err = 0;
    socklen_t len = sizeof(err);
    if (fd < 0) return NOSHI_E_IO;
#ifdef SO_NOSIGPIPE
    {
        /* ios has no MSG_NOSIGNAL, a write to a closed peer would kill the process */
        int one = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) { close(fd); return NOSHI_E_IO; }
    }
#endif
    s = set_nonblocking(fd);
    if (s != NOSHI_OK) {
        close(fd);
        return s;
    }
    if (connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
        if (errno != EINPROGRESS && errno != EINTR) {
            close(fd);
            return NOSHI_E_IO;
        }
        s = wait_fd(fd, POLLOUT, deadline);
        if (s != NOSHI_OK) {
            close(fd);
            return s;
        }
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0 || err != 0) {
            close(fd);
            errno = err;
            return NOSHI_E_IO;
        }
    }
    {
        int one = 1;
        (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    }
    *out_fd = fd;
    return NOSHI_OK;
}

noshi_status noshi_mt_socket_connect(noshi_mt_socket *s, const char *host, uint16_t port, int timeout_ms) {
    struct addrinfo hints, *list = NULL, *ai;
    char service[8];
    uint64_t deadline;
    noshi_status last = NOSHI_E_IO;
    if (!s || !host || !*host || !port || timeout_ms <= 0) return NOSHI_E_ARG;
    if (s->fd >= 0) return NOSHI_E_STATE;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(service, sizeof(service), "%u", (unsigned)port);
    if (getaddrinfo(host, service, &hints, &list) != 0 || !list) return NOSHI_E_IO;
    deadline = noshi_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    for (ai = list; ai; ai = ai->ai_next) {
        int fd = -1;
        last = connect_one(ai, deadline, &fd);
        if (last == NOSHI_OK) {
            s->fd = fd;
            break;
        }
        if (remaining_ms(deadline) == 0) {
            last = NOSHI_E_TIMEOUT;
            break;
        }
    }
    freeaddrinfo(list);
    return last;
}

noshi_status noshi_mt_socket_adopt(noshi_mt_socket *s, int fd) {
    if (!s || fd < 0) return NOSHI_E_ARG;
    if (s->fd >= 0) return NOSHI_E_STATE;
    s->fd = fd;
    return NOSHI_OK;
}

static noshi_status raw_write_all(noshi_mt_socket *s, const uint8_t *data, size_t len, int timeout_ms) {
    uint64_t deadline;
    if (!s || s->fd < 0 || (len && !data) || timeout_ms <= 0) return NOSHI_E_ARG;
    deadline = noshi_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    while (len) {
        ssize_t n = send(s->fd, data, len, MSG_NOSIGNAL);
        if (n < 0) {
            noshi_status w;
            if (errno == EINTR) continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK) return NOSHI_E_IO;
            w = wait_fd(s->fd, POLLOUT, deadline);
            if (w != NOSHI_OK) return w;
            continue;
        }
        if (n == 0) return NOSHI_E_EOF;
        noshi_traffic_add((uint64_t)n, 0);
        data += n;
        len -= (size_t)n;
    }
    return NOSHI_OK;
}

static noshi_status raw_read(noshi_mt_socket *s, uint8_t *buf, size_t cap, size_t *got, int timeout_ms) {
    uint64_t deadline;
    if (got) *got = 0;
    if (!s || s->fd < 0 || !buf || cap == 0 || !got || timeout_ms < 0) return NOSHI_E_ARG;
    deadline = noshi_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    for (;;) {
        ssize_t n = recv(s->fd, buf, cap, 0);
        if (n > 0) {
            *got = (size_t)n;
            noshi_traffic_add(0, (uint64_t)n);
            return NOSHI_OK;
        }
        if (n == 0) return NOSHI_E_EOF;
        if (errno == EINTR) continue;
        if (errno != EAGAIN && errno != EWOULDBLOCK) return NOSHI_E_IO;
        {
            noshi_status w = wait_fd(s->fd, POLLIN, deadline);
            if (w != NOSHI_OK) return w;
        }
    }
}

noshi_status noshi_mt_socket_write_all(noshi_mt_socket *s, const uint8_t *data, size_t len, int timeout_ms) {
    noshi_writer records;
    noshi_status status;
    if (!s || s->fd < 0 || (len && !data) || timeout_ms <= 0) return NOSHI_E_ARG;
    if (!s->tls) return raw_write_all(s, data, len, timeout_ms);
    noshi_writer_init(&records, len + (len / NOSHI_FAKETLS_RECORD_MAX + 1) * 5);
    status = noshi_faketls_wrap(data, len, &records);
    if (status == NOSHI_OK) status = raw_write_all(s, records.data, records.len, timeout_ms);
    noshi_wipe(records.data, records.cap);
    noshi_writer_free(&records);
    return status;
}

/* the records come out as payload that is never longer than what was read, so a buffer of the caller's size always holds it; a read that only brought a
   header or a change cipher spec goes on waiting for payload within the time that is left */
noshi_status noshi_mt_socket_read(noshi_mt_socket *s, uint8_t *buf, size_t cap, size_t *got, int timeout_ms) {
    uint8_t chunk[4096];
    uint64_t deadline;
    if (got) *got = 0;
    if (!s || s->fd < 0 || !buf || cap == 0 || !got || timeout_ms < 0) return NOSHI_E_ARG;
    if (!s->tls) return raw_read(s, buf, cap, got, timeout_ms);
    deadline = noshi_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    for (;;) {
        size_t raw = 0, payload = 0;
        noshi_status status = raw_read(s, chunk, cap < sizeof(chunk) ? cap : sizeof(chunk), &raw, remaining_ms(deadline));
        if (status != NOSHI_OK) return status;
        status = noshi_faketls_unwrap(&s->tls->reader, chunk, raw, buf, cap, &payload);
        if (status != NOSHI_OK) return status;
        if (payload) {
            *got = payload;
            return NOSHI_OK;
        }
    }
}

noshi_status noshi_mt_socket_start_faketls(noshi_mt_socket *s, const uint8_t secret[16], const char *domain, int timeout_ms) {
    uint8_t entropy[NOSHI_FAKETLS_ENTROPY_LEN], hello[NOSHI_FAKETLS_HELLO_LEN], random[32];
    uint8_t *reply = NULL;
    size_t have = 0, total = 0;
    uint64_t deadline, now_ms;
    noshi_status status;
    if (!s || s->fd < 0 || !secret || !domain || timeout_ms <= 0) return NOSHI_E_ARG;
    if (s->tls) return NOSHI_E_STATE;
    deadline = noshi_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    now_ms = noshi_system_clock.realtime_ms(NULL);
    status = noshi_random(entropy, sizeof(entropy));
    if (status == NOSHI_OK) status = noshi_faketls_hello(secret, domain, (uint32_t)(now_ms / 1000u), entropy, hello, random);
    noshi_wipe(entropy, sizeof(entropy));
    if (status == NOSHI_OK) status = raw_write_all(s, hello, sizeof(hello), timeout_ms);
    if (status == NOSHI_OK) {
        reply = malloc(NOSHI_FAKETLS_REPLY_MAX);
        if (!reply) status = NOSHI_E_NOMEM;
    }
    /* the reply is read to the exact end of its three records, so none of the stream behind it is taken */
    while (status == NOSHI_OK) {
        size_t want, got = 0;
        status = noshi_faketls_reply_progress(reply, have, &total);
        if (status == NOSHI_OK) break;
        if (status != NOSHI_E_RETRY) break;
        want = total > have ? total - have : (have < 5 ? 5 - have : 1);
        if (have + want > NOSHI_FAKETLS_REPLY_MAX) {
            status = NOSHI_E_MALFORMED;
            break;
        }
        {
            int left = remaining_ms(deadline);
            if (!left) {
                status = NOSHI_E_TIMEOUT;
                break;
            }
            status = raw_read(s, reply + have, want, &got, left);
        }
        if (status == NOSHI_OK) have += got;
    }
    if (status == NOSHI_OK) status = noshi_faketls_check_reply(secret, random, reply, have);
    if (status == NOSHI_OK) {
        s->tls = calloc(1, sizeof(*s->tls));
        if (!s->tls) status = NOSHI_E_NOMEM;
    }
    free(reply);
    if (status != NOSHI_OK) noshi_mt_socket_close(s);
    return status;
}

noshi_status noshi_mt_socket_negotiate_socks5(noshi_mt_socket *s, const char *user, const char *pass,
                                                  const char *dest_host, uint16_t dest_port, int timeout_ms) {
    noshi_socks proxy;
    noshi_writer out;
    uint64_t deadline;
    noshi_status status;
    if (!s || s->fd < 0 || timeout_ms <= 0) return NOSHI_E_ARG;
    deadline = noshi_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    noshi_writer_init(&out, 1024);
    status = noshi_socks_start(&proxy, dest_host, dest_port, user, pass, &out);
    if (status != NOSHI_OK) { noshi_mt_socket_close(s); goto done; }
    while (status == NOSHI_OK && proxy.state != NOSHI_SOCKS_READY) {
        uint8_t bytes[262];
        size_t got = 0, used = 0;
        int left = remaining_ms(deadline);
        if (!left) { status = NOSHI_E_TIMEOUT; break; }
        if (out.len) status = noshi_mt_socket_write_all(s, out.data, out.len, left);
        noshi_wipe(out.data, out.len);
        out.len = 0;
        left = remaining_ms(deadline);
        if (status == NOSHI_OK && !left) status = NOSHI_E_TIMEOUT;
        if (status == NOSHI_OK) status = noshi_mt_socket_read(s, bytes, proxy.need - proxy.response_len, &got, left);
        if (status == NOSHI_OK) status = noshi_socks_feed(&proxy, bytes, got, &used, &out);
        if (status == NOSHI_OK && used != got) status = NOSHI_E_MALFORMED;
    }
    if (status != NOSHI_OK) noshi_mt_socket_close(s);
done:
    if (out.data) noshi_wipe(out.data, out.cap);
    noshi_writer_free(&out);
    noshi_socks_free(&proxy);
    return status;
}

noshi_status noshi_mt_socket_connect_socks5(noshi_mt_socket *s, const char *proxy_host, uint16_t proxy_port,
                                                const char *user, const char *pass,
                                                const char *dest_host, uint16_t dest_port, int timeout_ms) {
    uint64_t deadline;
    noshi_status status;
    int left;
    if (!s || timeout_ms <= 0) return NOSHI_E_ARG;
    deadline = noshi_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    status = noshi_mt_socket_connect(s, proxy_host, proxy_port, timeout_ms);
    if (status != NOSHI_OK) return status;
    left = remaining_ms(deadline);
    if (!left) { noshi_mt_socket_close(s); return NOSHI_E_TIMEOUT; }
    status = noshi_mt_socket_negotiate_socks5(s, user, pass, dest_host, dest_port, left);
    if (status != NOSHI_OK) noshi_mt_socket_close(s);
    return status;
}
