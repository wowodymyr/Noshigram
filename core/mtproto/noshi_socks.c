#include "noshi_socks.h"

#include <arpa/inet.h>
#include <string.h>

static noshi_status connect_request(noshi_socks *s, noshi_writer *out) {
    const uint8_t prefix[] = {5, 1, 0};
    size_t mark = out->len;
    noshi_status status = noshi_wr_bytes(out, prefix, sizeof(prefix));
    if (status == NOSHI_OK) status = noshi_wr_bytes(out, s->target, s->target_len);
    if (status == NOSHI_OK) { s->state = NOSHI_SOCKS_CONNECT; s->need = 4; }
    else out->len = mark;
    return status;
}

noshi_status noshi_socks_start(noshi_socks *s, const char *host, uint16_t port,
                                  const char *username, const char *password, noshi_writer *out) {
    uint8_t address[16], greeting[] = {5, 1, 0};
    size_t len, user_len, pass_len, pos = 0;
    noshi_status status;
    if (!s) return NOSHI_E_ARG;
    memset(s, 0, sizeof(*s));
    s->state = NOSHI_SOCKS_FAILED;
    if (!host || !*host || !port || !out) return NOSHI_E_ARG;
    len = strlen(host);
    if (inet_pton(AF_INET, host, address) == 1) {
        s->target[pos++] = 1;
        memcpy(s->target + pos, address, 4); pos += 4;
    } else if (inet_pton(AF_INET6, host, address) == 1) {
        s->target[pos++] = 4;
        memcpy(s->target + pos, address, 16); pos += 16;
    } else {
        size_t i;
        if (len > 255) return NOSHI_E_LIMIT;
        for (i = 0; i < len; ++i) if ((unsigned char)host[i] <= 32 || (unsigned char)host[i] >= 127) return NOSHI_E_ARG;
        s->target[pos++] = 3; s->target[pos++] = (uint8_t)len;
        memcpy(s->target + pos, host, len); pos += len;
    }
    s->target[pos++] = (uint8_t)(port >> 8);
    s->target[pos++] = (uint8_t)port;
    s->target_len = pos;
    if (username || password) {
        if (!username || !password) return NOSHI_E_ARG;
        user_len = strlen(username); pass_len = strlen(password);
        if (!user_len || !pass_len || user_len > 255 || pass_len > 255) return NOSHI_E_LIMIT;
        greeting[2] = 2;
        s->credentials[0] = 1;
        s->credentials[1] = (uint8_t)user_len;
        memcpy(s->credentials + 2, username, user_len);
        s->credentials[2 + user_len] = (uint8_t)pass_len;
        memcpy(s->credentials + 3 + user_len, password, pass_len);
        s->credentials_len = 3 + user_len + pass_len;
    }
    status = noshi_wr_bytes(out, greeting, sizeof(greeting));
    if (status == NOSHI_OK) { s->state = NOSHI_SOCKS_METHOD; s->need = 2; }
    return status;
}

noshi_status noshi_socks_feed(noshi_socks *s, const uint8_t *data, size_t len,
                                 size_t *consumed, noshi_writer *out) {
    noshi_status status = NOSHI_OK;
    if (!consumed) return NOSHI_E_ARG;
    *consumed = 0;
    if (!s || !out || (!data && len)) return NOSHI_E_ARG;
    if (s->state == NOSHI_SOCKS_FAILED) return NOSHI_E_STATE;
    while (*consumed < len && s->state != NOSHI_SOCKS_READY) {
        size_t take = s->need - s->response_len;
        if (take > len - *consumed) take = len - *consumed;
        if (s->need > sizeof(s->response)) { status = NOSHI_E_LIMIT; break; }
        memcpy(s->response + s->response_len, data + *consumed, take);
        s->response_len += take;
        *consumed += take;
        if (s->response_len < s->need) break;
        if (s->state == NOSHI_SOCKS_METHOD) {
            if (s->response[0] != 5 || s->response[1] != (s->credentials_len ? 2 : 0)) { status = NOSHI_E_SECURITY; break; }
            if (s->credentials_len) {
                status = noshi_wr_bytes(out, s->credentials, s->credentials_len);
                noshi_wipe(s->credentials, sizeof(s->credentials));
                s->credentials_len = 0;
                s->state = NOSHI_SOCKS_AUTH;
                s->need = 2;
            } else status = connect_request(s, out);
            s->response_len = 0;
        } else if (s->state == NOSHI_SOCKS_AUTH) {
            if (s->response[0] != 1 || s->response[1] != 0) { status = NOSHI_E_SECURITY; break; }
            status = connect_request(s, out);
            s->response_len = 0;
        } else if (s->state == NOSHI_SOCKS_CONNECT) {
            if (s->response_len == 4) {
                s->reply = s->response[1];
                if (s->response[0] != 5 || s->response[2] || s->reply) { status = NOSHI_E_IO; break; }
                if (s->response[3] == 1) s->need = 10;
                else if (s->response[3] == 4) s->need = 22;
                else if (s->response[3] == 3) s->need = 5;
                else { status = NOSHI_E_MALFORMED; break; }
            } else if (s->response_len == 5 && s->response[3] == 3) {
                if (!s->response[4]) { status = NOSHI_E_MALFORMED; break; }
                s->need = (size_t)s->response[4] + 7;
            } else s->state = NOSHI_SOCKS_READY;
        }
        if (status != NOSHI_OK) break;
    }
    if (status != NOSHI_OK) { s->state = NOSHI_SOCKS_FAILED; noshi_wipe(s->credentials, sizeof(s->credentials)); }
    return status;
}

void noshi_socks_free(noshi_socks *s) {
    if (s) noshi_wipe(s, sizeof(*s));
}
