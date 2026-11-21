/* a public dc cannot be a deterministic dependency of host tests.
   Asks for a login code for a number that cannot exist, so no message is sent: the answer shows whether the
   api id and hash are accepted and whether the client, the transport and the auth state machine work end to end.
   a PHONE_MIGRATE answer counts as success: it comes from the server after the credentials were accepted.
   usage: NOSHI_API_ID=... NOSHI_API_HASH=... probe_login [dc] [number] */
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "noshi_client.h"
#include "noshi_mt_socket.h"
#include "noshi_session_file.h"

typedef struct probe {
    noshi_mt_socket sock;
    noshi_mt_session_state session;
    int have_session;
    int done;
    noshi_auth_state state;
    noshi_status status;
    char error[128];
} probe;

static noshi_status send_bytes(void *ctx, int32_t dc, const uint8_t *data, size_t len) {
    probe *p = ctx;
    (void)dc;
    return noshi_mt_socket_write_all(&p->sock, data, len, 10000);
}

static noshi_status load(void *ctx, int32_t dc, noshi_mt_session_state *out) {
    probe *p = ctx;
    (void)dc;
    if (!p->have_session) return NOSHI_E_NOTFOUND;
    *out = p->session;
    return NOSHI_OK;
}

static noshi_status save(void *ctx, int32_t dc, const noshi_mt_session_state *s) {
    probe *p = ctx;
    (void)dc;
    p->session = *s;
    p->have_session = 1;
    return NOSHI_OK;
}

static void auth(void *ctx, noshi_auth_state state, noshi_status status, const noshi_tl_value *value, const char *error) {
    probe *p = ctx;
    (void)value;
    p->state = state;
    p->status = status;
    snprintf(p->error, sizeof(p->error), "%s", error ? error : "");
    /* starting a login cancels the previous one, which reports a clean idle first; a refused request reports idle with its error */
    if (state != NOSHI_AUTH_WAITING && (state != NOSHI_AUTH_IDLE || status != NOSHI_OK)) p->done = 1;
}

static void report(void *ctx, noshi_status status, const char *boundary) {
    (void)ctx;
    fprintf(stderr, "client error at %s: %s\n", boundary, noshi_status_name(status));
}

int main(int argc, char **argv) {
    const char *hash = getenv("NOSHI_API_HASH");
    const char *id = getenv("NOSHI_API_ID");
    int dc = argc > 1 ? atoi(argv[1]) : 2;
    const char *number = argc > 2 ? argv[2] : "+99966123456";
    probe p;
    noshi_client client;
    noshi_client_events events;
    noshi_mt_client_config config;
    noshi_status status;
    int rounds;
    if (!id || !hash) {
        fprintf(stderr, "set NOSHI_API_ID and NOSHI_API_HASH\n");
        return 1;
    }
    memset(&p, 0, sizeof(p));
    noshi_mt_socket_init(&p.sock);
    memset(&events, 0, sizeof(events));
    events.ctx = &p;
    events.send = send_bytes;
    events.load_session = load;
    events.save_session = save;
    events.auth = auth;
    events.error = report;
    memset(&config, 0, sizeof(config));
    config.dc_id = dc;
    config.transport = NOSHI_MT_INTERMEDIATE;
    config.obfuscation.enabled = 1;
    config.obfuscation.dc_id = (int16_t)dc;
    config.api_id = atoi(id);
    config.device_model = "probe";
    config.system_version = "host";
    config.app_version = "0.1.0";
    config.lang_pack = "ios";
    config.lang_code = "en";
    status = noshi_client_init(&client, &config, hash, &events);
    if (status != NOSHI_OK) { printf("init failed: %s\n", noshi_status_name(status)); return 2; }
    status = noshi_mt_socket_connect(&p.sock, noshi_dc_host(dc), noshi_dc_port(), 10000);
    if (status != NOSHI_OK) { printf("connect failed: %s\n", noshi_status_name(status)); return 3; }
    status = noshi_client_connect(&client);
    if (status != NOSHI_OK) { printf("client connect failed: %s\n", noshi_status_name(status)); return 4; }
    status = noshi_auth_phone(&client.auth, number, NULL);
    if (status != NOSHI_OK) { printf("auth_phone failed: %s\n", noshi_status_name(status)); return 5; }
    for (rounds = 0; rounds < 200 && !p.done; ++rounds) {
        struct pollfd fd;
        uint8_t buf[16384];
        size_t got = 0;
        uint32_t next = 0;
        fd.fd = p.sock.fd;
        fd.events = POLLIN;
        fd.revents = 0;
        if (poll(&fd, 1, 500) > 0) {
            status = noshi_mt_socket_read(&p.sock, buf, sizeof(buf), &got, 0);
            if (status == NOSHI_OK) status = noshi_client_feed(&client, buf, got);
            if (status != NOSHI_OK && status != NOSHI_E_RETRY && status != NOSHI_E_TIMEOUT) {
                printf("link failed: %s\n", noshi_status_name(status));
                return 6;
            }
        }
        (void)noshi_client_tick(&client, &next);

    }
    printf("auth state %d, status %s, error \"%s\"\n", (int)p.state, noshi_status_name(p.status), p.error);
    noshi_client_free(&client);
    noshi_mt_socket_close(&p.sock);
    return p.done ? 0 : 7;
}
