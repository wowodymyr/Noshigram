#include "noshi_proxy.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#define SECRET_BYTES_MAX (1 + NOSHI_PROXY_SECRET_LEN + NOSHI_PROXY_DOMAIN_MAX)

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int base64_value(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '-' || c == '+') return 62;
    if (c == '_' || c == '/') return 63;
    return -1;
}

/* base64url, or the standard alphabet, with the padding left off or on; false for a character outside both or a length no byte count gives */
static int base64_decode(const char *text, size_t len, uint8_t *out, size_t cap, size_t *count) {
    uint32_t bits = 0;
    int have = 0;
    size_t n = 0, i;
    while (len && text[len - 1] == '=') --len;
    if (len % 4 == 1) return 0;
    for (i = 0; i < len; ++i) {
        int v = base64_value(text[i]);
        if (v < 0) return 0;
        bits = (bits << 6) | (uint32_t)v;
        have += 6;
        if (have >= 8) {
            have -= 8;
            if (n >= cap) return 0;
            out[n++] = (uint8_t)(bits >> have);
            bits &= (1u << have) - 1u;
        }
    }
    *count = n;
    return 1;
}

static int is_hex_text(const char *text, size_t len) {
    size_t i;
    if (len == 0 || len % 2) return 0;
    for (i = 0; i < len; ++i) if (hex_digit(text[i]) < 0) return 0;
    return 1;
}

static noshi_status decode_secret(const char *text, uint8_t secret[NOSHI_PROXY_SECRET_LEN], uint8_t *padded, char *domain, size_t domain_cap) {
    uint8_t bytes[SECRET_BYTES_MAX];
    size_t len, count = 0, i;
    if (secret) memset(secret, 0, NOSHI_PROXY_SECRET_LEN);
    if (padded) *padded = 0;
    if (domain && domain_cap) domain[0] = 0;
    if (!text || !secret || !padded) return NOSHI_E_ARG;
    len = strlen(text);
    if (len == 0 || len > 4 * SECRET_BYTES_MAX) return NOSHI_E_MALFORMED;
    if (is_hex_text(text, len)) {
        if (len / 2 > SECRET_BYTES_MAX) return NOSHI_E_MALFORMED;
        for (i = 0; i < len / 2; ++i) bytes[i] = (uint8_t)((hex_digit(text[2 * i]) << 4) | hex_digit(text[2 * i + 1]));
        count = len / 2;
    } else if (!base64_decode(text, len, bytes, sizeof(bytes), &count)) {
        return NOSHI_E_MALFORMED;
    }
    if (count == NOSHI_PROXY_SECRET_LEN) {
        memcpy(secret, bytes, NOSHI_PROXY_SECRET_LEN);
        return NOSHI_OK;
    }
    if (count > NOSHI_PROXY_SECRET_LEN + 1 && bytes[0] == 0xee) {
        size_t domain_len = count - 1 - NOSHI_PROXY_SECRET_LEN;
        if (!domain || domain_cap <= domain_len) return NOSHI_E_UNSUPPORTED;
        if (memchr(bytes + 1 + NOSHI_PROXY_SECRET_LEN, 0, domain_len)) return NOSHI_E_MALFORMED;
        memcpy(domain, bytes + 1 + NOSHI_PROXY_SECRET_LEN, domain_len);
        domain[domain_len] = 0;
        if (!noshi_proxy_server_valid(domain)) { domain[0] = 0; return NOSHI_E_MALFORMED; }
        memcpy(secret, bytes + 1, NOSHI_PROXY_SECRET_LEN);
        *padded = 1;
        return NOSHI_OK;
    }
    if (count == NOSHI_PROXY_SECRET_LEN + 1 && bytes[0] == 0xdd) {
        memcpy(secret, bytes + 1, NOSHI_PROXY_SECRET_LEN);
        *padded = 1;
        return NOSHI_OK;
    }
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_proxy_secret_decode(const char *text, uint8_t secret[NOSHI_PROXY_SECRET_LEN], uint8_t *padded) {
    return decode_secret(text, secret, padded, NULL, 0);
}

int noshi_proxy_server_valid(const char *server) {
    size_t len, i, label = 0;
    if (!server) return 0;
    len = strlen(server);
    if (len == 0 || len > 253) return 0;
    for (i = 0; i < len; ++i) {
        char c = server[i];
        if (c == '.') {
            if (label == 0) return 0;
            label = 0;
            continue;
        }
        if (!(isalnum((unsigned char)c) || c == '-')) return 0;
        if (++label > 63) return 0;
    }
    return label > 0 && server[0] != '-';
}

noshi_status noshi_proxy_from_link(const noshi_tg_link *link, noshi_proxy *out) {
    if (out) memset(out, 0, sizeof(*out));
    if (!link || !out) return NOSHI_E_ARG;
    if (link->kind != NOSHI_LINK_PROXY && link->kind != NOSHI_LINK_SOCKS) return NOSHI_E_ARG;
    if (!noshi_proxy_server_valid(link->proxy_server) || link->proxy_port == 0) return NOSHI_E_MALFORMED;
    strcpy(out->server, link->proxy_server);
    out->port = link->proxy_port;
    if (link->kind == NOSHI_LINK_PROXY) {
        noshi_status status = decode_secret(link->proxy_secret, out->secret, &out->padded, out->tls_domain, sizeof(out->tls_domain));
        if (status != NOSHI_OK) {
            memset(out, 0, sizeof(*out));
            return status;
        }
        out->kind = NOSHI_PROXY_MTPROTO;
        return NOSHI_OK;
    }
    if ((link->proxy_user[0] != 0) != (link->proxy_password[0] != 0)) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    out->kind = NOSHI_PROXY_SOCKS5;
    strcpy(out->user, link->proxy_user);
    strcpy(out->password, link->proxy_password);
    return NOSHI_OK;
}

/* a value of a link with everything but letters, digits and the unreserved marks escaped */
static int append_escaped(char *out, size_t cap, size_t *at, const char *value) {
    static const char digits[] = "0123456789ABCDEF";
    for (; *value; ++value) {
        unsigned char c = (unsigned char)*value;
        if (isalnum(c) || c == '-' || c == '.' || c == '_' || c == '~') {
            if (*at + 1 >= cap) return 0;
            out[(*at)++] = (char)c;
        } else {
            if (*at + 3 >= cap) return 0;
            out[(*at)++] = '%';
            out[(*at)++] = digits[c >> 4];
            out[(*at)++] = digits[c & 15];
        }
    }
    return 1;
}

noshi_status noshi_proxy_link(const noshi_proxy *proxy, char *out, size_t cap) {
    char head[64];
    size_t at = 0, i;
    int written;
    if (out && cap) out[0] = 0;
    if (!proxy || !out || cap == 0) return NOSHI_E_ARG;
    if (proxy->kind != NOSHI_PROXY_MTPROTO && proxy->kind != NOSHI_PROXY_SOCKS5) return NOSHI_E_ARG;
    written = snprintf(head, sizeof(head), "tg://%s?server=", proxy->kind == NOSHI_PROXY_MTPROTO ? "proxy" : "socks");
    if (written < 0 || (size_t)written >= sizeof(head) || (size_t)written + 1 > cap) return NOSHI_E_LIMIT;
    memcpy(out, head, (size_t)written);
    at = (size_t)written;
    if (!append_escaped(out, cap, &at, proxy->server)) return NOSHI_E_LIMIT;
    written = snprintf(head, sizeof(head), "&port=%u", (unsigned)proxy->port);
    if (written < 0 || at + (size_t)written + 1 > cap) return NOSHI_E_LIMIT;
    memcpy(out + at, head, (size_t)written);
    at += (size_t)written;
    if (proxy->kind == NOSHI_PROXY_MTPROTO) {
        const char *domain_end = memchr(proxy->tls_domain, 0, sizeof(proxy->tls_domain));
        size_t domain_len;
        if (!domain_end) return NOSHI_E_ARG;
        domain_len = (size_t)(domain_end - proxy->tls_domain);
        if (domain_len && (!proxy->padded || domain_len > NOSHI_PROXY_DOMAIN_MAX || !noshi_proxy_server_valid(proxy->tls_domain))) return NOSHI_E_ARG;
        if (at + 8 + 2 + 2 * NOSHI_PROXY_SECRET_LEN + 2 * domain_len + 1 > cap) return NOSHI_E_LIMIT;
        memcpy(out + at, "&secret=", 8);
        at += 8;
        if (proxy->padded) {
            out[at++] = domain_len ? 'e' : 'd';
            out[at++] = domain_len ? 'e' : 'd';
        }
        for (i = 0; i < NOSHI_PROXY_SECRET_LEN; ++i) {
            static const char hex[] = "0123456789abcdef";
            out[at++] = hex[proxy->secret[i] >> 4];
            out[at++] = hex[proxy->secret[i] & 15];
        }
        for (i = 0; i < domain_len; ++i) {
            static const char hex[] = "0123456789abcdef";
            unsigned char c = (unsigned char)proxy->tls_domain[i];
            out[at++] = hex[c >> 4];
            out[at++] = hex[c & 15];
        }
    } else if (proxy->user[0]) {
        if (at + 6 >= cap) return NOSHI_E_LIMIT;
        memcpy(out + at, "&user=", 6);
        at += 6;
        if (!append_escaped(out, cap, &at, proxy->user)) return NOSHI_E_LIMIT;
        if (proxy->password[0]) {
            if (at + 6 >= cap) return NOSHI_E_LIMIT;
            memcpy(out + at, "&pass=", 6);
            at += 6;
            if (!append_escaped(out, cap, &at, proxy->password)) return NOSHI_E_LIMIT;
        }
    }
    out[at] = 0;
    return NOSHI_OK;
}
