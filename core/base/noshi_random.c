#include "noshi_random.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

noshi_status noshi_random(void *buf, size_t n) {
    uint8_t *p = (uint8_t *)buf;
    int fd;
    if (n && !buf) return NOSHI_E_ARG;
    if (!n) return NOSHI_OK;
    fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return NOSHI_E_IO;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) { close(fd); return NOSHI_E_IO; }
    while (n) {
        ssize_t got = read(fd, p, n);
        if (got < 0) {
            if (errno == EINTR) continue;
            close(fd);
            return NOSHI_E_IO;
        }
        if (got == 0) {
            close(fd);
            return NOSHI_E_EOF;
        }
        p += got;
        n -= (size_t)got;
    }
    close(fd);
    return NOSHI_OK;
}

noshi_status noshi_random_u64(uint64_t *out) {
    uint8_t b[8];
    noshi_status s;
    uint64_t v = 0;
    int i;
    if (!out) return NOSHI_E_ARG;
    *out = 0;
    s = noshi_random(b, sizeof(b));
    if (s != NOSHI_OK) {
        return s;
    }
    for (i = 0; i < 8; ++i) v = (v << 8) | b[i];
    *out = v;
    return NOSHI_OK;
}
