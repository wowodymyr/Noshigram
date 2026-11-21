/* a public dc cannot be a deterministic dependency of host tests */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "noshi_mt_handshake.h"
#include "noshi_mt_socket.h"
#include "noshi_mt_transport.h"

static int send_frame(noshi_mt_socket *sock, noshi_mt_transport *t, const uint8_t *packet, size_t len) {
    noshi_writer w;
    noshi_status s;
    noshi_writer_init(&w, 1 << 16);
    s = noshi_mt_transport_wrap(t, packet, len, 0, &w);
    if (s == NOSHI_OK) s = noshi_mt_socket_write_all(sock, w.data, w.len, 10000);
    noshi_writer_free(&w);
    return (int)s;
}

static int recv_frame(noshi_mt_socket *sock, noshi_mt_transport *t, noshi_mt_frame *f) {
    uint8_t buf[4096];
    for (;;) {
        noshi_status s = noshi_mt_transport_next(t, f);
        size_t got = 0;
        if (s == NOSHI_OK) return 0;
        if (s != NOSHI_E_TRUNCATED) return (int)s;
        s = noshi_mt_socket_read(sock, buf, sizeof(buf), &got, 10000);
        if (s != NOSHI_OK) return (int)s;
        s = noshi_mt_transport_feed(t, buf, got);
        if (s != NOSHI_OK) return (int)s;
    }
}

int main(int argc, char **argv) {
    const char *host = argc > 1 ? argv[1] : "149.154.167.40";
    int is_test = argc > 2 ? atoi(argv[2]) : 1;
    int obfuscated = argc > 3 ? atoi(argv[3]) : 1;
    noshi_mt_socket sock;
    noshi_mt_transport t;
    noshi_mt_obfuscation obf;
    noshi_mt_handshake hs;
    noshi_mt_hs_config cfg;
    noshi_writer out, first;
    noshi_mt_frame f;
    noshi_status s;
    int rc;
    memset(&obf, 0, sizeof(obf));
    obf.enabled = obfuscated;
    obf.dc_id = (int16_t)(is_test ? 10002 : 2);
    memset(&cfg, 0, sizeof(cfg));
    cfg.dc_id = 2;
    cfg.is_test = is_test;
    noshi_mt_socket_init(&sock);
    noshi_mt_transport_init(&t);
    noshi_writer_init(&out, 1 << 16);
    noshi_writer_init(&first, 1 << 16);
    s = noshi_mt_socket_connect(&sock, host, 443, 10000);
    if (s != NOSHI_OK) {
        printf("connect failed: %s\n", noshi_status_name(s));
        return 2;
    }
    s = noshi_mt_transport_start(&t, NOSHI_MT_INTERMEDIATE, &obf, &first);
    if (s != NOSHI_OK) return 3;
    noshi_mt_hs_init(&hs, &cfg);
    s = noshi_mt_hs_start(&hs, &out);
    if (s != NOSHI_OK) return 4;
    if (noshi_mt_transport_wrap(&t, out.data, out.len, 0, &first) != NOSHI_OK) return 5;
    if (noshi_mt_socket_write_all(&sock, first.data, first.len, 10000) != NOSHI_OK) return 6;
    while (hs.state != NOSHI_MT_HS_DONE && hs.state != NOSHI_MT_HS_FAILED) {
        rc = recv_frame(&sock, &t, &f);
        if (rc != 0) {
            printf("receive failed in state %d: %s\n", (int)hs.state, noshi_status_name((noshi_status)rc));
            return 7;
        }
        if (f.kind == NOSHI_MT_FRAME_ERROR) {
            printf("transport error %d\n", (int)f.error_code);
            return 8;
        }
        out.len = 0;
        s = noshi_mt_hs_receive(&hs, f.data, f.len, noshi_mt_transport_padded(&t), &out);
        if (s != NOSHI_OK) {
            printf("handshake failed: %s\n", noshi_status_name(s));
            return 9;
        }
        if (out.len && send_frame(&sock, &t, out.data, out.len) != 0) return 10;
    }
    {
        const noshi_mt_hs_result *r = noshi_mt_hs_result_get(&hs);
        if (!r) return 11;
        printf("handshake ok, key id %016llx salt %016llx time offset %lld ms\n",
               (unsigned long long)r->key.id, (unsigned long long)r->server_salt, (long long)r->time_offset_ms);
    }
    noshi_mt_socket_close(&sock);
    noshi_mt_transport_free(&t);
    noshi_writer_free(&out);
    noshi_writer_free(&first);
    return 0;
}
