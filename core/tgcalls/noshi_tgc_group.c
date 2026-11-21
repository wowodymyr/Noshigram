#include "noshi_tgc_group.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "noshi_random.h"
#include "noshi_rtp.h"

#define CREDENTIAL_ALPHABET "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/"
#define UFRAG_LEN 4
#define PWD_LEN 24
#define RTP_VERSION_EXTENSION 0x90u
#define EXTENSION_PROFILE_ONE_BYTE 0xBEDEu
#define TRANSPORT_SEQUENCE_EXT 3
#define RTCP_TYPE_FIRST 64
#define RTCP_TYPE_LAST 95
#define SEND_HEADER_LEN (NOSHI_RTP_FIXED_LEN + 4 + 8)

struct noshi_tgc_group {
    noshi_tgc_group_events events;
    noshi_tgc_group_state state;
    uint8_t applied;
    uint8_t dtls_server;
    uint8_t dtls_started;
    uint8_t srtp_ready;
    uint8_t failed;
    uint8_t payload_type;
    uint8_t level_ext;
    uint32_t ssrc;
    uint16_t audio_seq;
    uint32_t audio_ts;
    uint16_t transport_seq;
    char local_ufrag[UFRAG_LEN + 1];
    char local_pwd[PWD_LEN + 1];
    uint64_t now_ms;
    uint64_t applied_ms;
    noshi_tgc_ice ice;
    noshi_dtls *dtls;
    noshi_tgc_srtp send_srtp;
    noshi_tgc_srtp recv_srtp;
    unsigned audio_rx;
    unsigned audio_tx;
    unsigned rtcp_rx;
    unsigned rtp_refused;
};

static void gtrace(const noshi_tgc_group *g, const char *format, ...) {
    char line[200];
    va_list args;
    if (!g->events.trace) return;
    va_start(args, format);
    vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    g->events.trace(g->events.context, line);
}

static uint32_t random_u32(void) {
    uint32_t v = 0;
    while (v == 0) {
        if (noshi_random(&v, sizeof(v)) != NOSHI_OK) return 1;
    }
    return v;
}

static void random_text(char *out, size_t n) {
    uint8_t bytes[PWD_LEN];
    size_t i;
    if (noshi_random(bytes, n) != NOSHI_OK) memset(bytes, 0x41, n);
    for (i = 0; i < n; ++i) out[i] = CREDENTIAL_ALPHABET[bytes[i] & 63];
    out[n] = '\0';
}

static void set_state(noshi_tgc_group *g, noshi_tgc_group_state state) {
    if (g->state == state || g->failed) return;
    gtrace(g, "group state %d -> %d", (int)g->state, (int)state);
    g->state = state;
    if (state == NOSHI_TGC_GROUP_FAILED) g->failed = 1;
    if (g->events.state) g->events.state(g->events.context, state);
}

static void fail(noshi_tgc_group *g) {
    set_state(g, NOSHI_TGC_GROUP_FAILED);
}

static void update_state(noshi_tgc_group *g) {
    if (g->failed || !g->applied) return;
    if (g->srtp_ready) set_state(g, g->ice.state == NOSHI_TGC_ICE_DISCONNECTED ? NOSHI_TGC_GROUP_RECONNECTING : NOSHI_TGC_GROUP_CONNECTED);
    else if (g->state == NOSHI_TGC_GROUP_NEW) set_state(g, NOSHI_TGC_GROUP_CONNECTING);
}

static void pump_dtls_out(noshi_tgc_group *g) {
    uint8_t buf[NOSHI_DTLS_MAX_DATAGRAM];
    size_t n = 0;
    while (noshi_dtls_poll(g->dtls, buf, sizeof(buf), &n) == NOSHI_OK) {
        /* before a path is nominated nothing can go, and the handshake sends its flight again */
        noshi_tgc_ice_send(&g->ice, buf, n);
    }
}

static void handshake_done(noshi_tgc_group *g) {
    uint8_t send_key[NOSHI_DTLS_SRTP_KEY_LEN], send_salt[NOSHI_DTLS_SRTP_SALT_LEN], recv_key[NOSHI_DTLS_SRTP_KEY_LEN], recv_salt[NOSHI_DTLS_SRTP_SALT_LEN];
    if (g->srtp_ready) return;
    if (noshi_dtls_srtp_keys(g->dtls, send_key, send_salt, recv_key, recv_salt) != NOSHI_OK ||
        noshi_tgc_srtp_init(&g->send_srtp, send_key, send_salt) != NOSHI_OK || noshi_tgc_srtp_init(&g->recv_srtp, recv_key, recv_salt) != NOSHI_OK) {
        memset(send_key, 0, sizeof(send_key));
        memset(recv_key, 0, sizeof(recv_key));
        fail(g);
        return;
    }
    memset(send_key, 0, sizeof(send_key));
    memset(recv_key, 0, sizeof(recv_key));
    g->srtp_ready = 1;
    gtrace(g, "dtls connected, srtp keys derived");
    update_state(g);
}

static void dtls_changed(noshi_tgc_group *g) {
    noshi_dtls_state st;
    pump_dtls_out(g);
    st = noshi_dtls_get_state(g->dtls);
    if (st == NOSHI_DTLS_FAILED) {
        gtrace(g, "dtls failed");
        fail(g);
    } else if (st == NOSHI_DTLS_CONNECTED) {
        handshake_done(g);
    }
}

static void maybe_start_dtls(noshi_tgc_group *g) {
    if (g->dtls_started || !g->applied || g->ice.state != NOSHI_TGC_ICE_CONNECTED) return;
    g->dtls_started = 1;
    gtrace(g, "dtls starts as %s", g->dtls_server ? "server" : "client");
    if (noshi_dtls_start(g->dtls, g->dtls_server ? 0 : 1) != NOSHI_OK) {
        fail(g);
        return;
    }
    dtls_changed(g);
}

/* the audio level element (id level_ext, one byte: a voice bit and 7 bits of -dBov) of a one-byte header extension; -1 when the packet carries none */
static int read_audio_level(const uint8_t *pkt, size_t len, uint8_t level_ext, int *voice) {
    size_t pos = NOSHI_RTP_FIXED_LEN + 4u * (size_t)(pkt[0] & 0x0F), words, end;
    *voice = 0;
    if (!(pkt[0] & 0x10) || pos + 4 > len) return -1;
    if ((((unsigned)pkt[pos] << 8) | pkt[pos + 1]) != EXTENSION_PROFILE_ONE_BYTE) return -1;
    words = ((size_t)pkt[pos + 2] << 8) | pkt[pos + 3];
    pos += 4;
    end = pos + words * 4;
    if (end > len) return -1;
    while (pos < end) {
        uint8_t id, size;
        if (pkt[pos] == 0) {
            ++pos;
            continue;
        }
        id = (uint8_t)(pkt[pos] >> 4);
        size = (uint8_t)((pkt[pos] & 0x0F) + 1);
        if (id == 15 || pos + 1 + size > end) return -1;
        if (id == level_ext && size == 1) {
            *voice = (pkt[pos + 1] & 0x80) ? 1 : 0;
            return pkt[pos + 1] & 0x7F;
        }
        pos += 1u + size;
    }
    return -1;
}

static void handle_rtp(noshi_tgc_group *g, const uint8_t *data, size_t len) {
    uint8_t buf[NOSHI_DTLS_MAX_DATAGRAM];
    size_t n = 0;
    noshi_rtp_header h;
    int level, voice = 0;
    if (len > sizeof(buf)) return;
    memcpy(buf, data, len);
    if (noshi_tgc_srtp_unprotect(&g->recv_srtp, buf, len, &n) != NOSHI_OK) {
        ++g->rtp_refused;
        return;
    }
    if (noshi_rtp_parse(buf, n, &h) != NOSHI_OK || h.payload_len == 0) return;
    /* only Opus is played, and never what this phone sent itself */
    if (h.payload_type != g->payload_type || h.ssrc == g->ssrc) return;
    if (++g->audio_rx == 1) gtrace(g, "first audio packet received (%u bytes)", (unsigned)h.payload_len);
    level = read_audio_level(buf, n, g->level_ext, &voice);
    if (g->events.audio) g->events.audio(g->events.context, h.ssrc, buf + h.payload_offset, h.payload_len, h.sequence, h.timestamp, level, voice);
}

static void ice_payload(void *context, const uint8_t *data, size_t len) {
    noshi_tgc_group *g = (noshi_tgc_group *)context;
    uint8_t first;
    if (len == 0) return;
    first = data[0];
    if (first >= 20 && first <= 63) {
        noshi_dtls_input(g->dtls, data, len);
        dtls_changed(g);
    } else if (first >= 128 && first <= 191 && g->srtp_ready && len >= 8) {
        uint8_t kind = data[1] & 0x7F;
        /* the receiver and sender reports of the server are not needed to play audio, so they are only counted */
        if (kind >= RTCP_TYPE_FIRST && kind <= RTCP_TYPE_LAST) ++g->rtcp_rx;
        else handle_rtp(g, data, len);
    }
}

static void ice_send(void *context, unsigned index, const uint8_t *data, size_t len) {
    noshi_tgc_group *g = (noshi_tgc_group *)context;
    if (g->events.send_datagram) g->events.send_datagram(g->events.context, index, data, len);
}

static void ice_trace(void *context, const char *line) {
    noshi_tgc_group *g = (noshi_tgc_group *)context;
    if (g->events.trace) g->events.trace(g->events.context, line);
}

static void ice_state(void *context, noshi_tgc_ice_state state) {
    noshi_tgc_group *g = (noshi_tgc_group *)context;
    if (state == NOSHI_TGC_ICE_CONNECTED) maybe_start_dtls(g);
    update_state(g);
}

static void ice_candidate(void *context, const char *sdp) {
    /* the server is ICE lite and takes no candidates of this side: it answers the checks from wherever they come */
    (void)context;
    (void)sdp;
}

noshi_status noshi_tgc_group_new(noshi_tgc_group **out, const noshi_tgc_group_events *events) {
    noshi_tgc_group *g;
    noshi_tgc_ice_events ice_events;
    uint64_t tie = 0;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || !events) return NOSHI_E_ARG;
    g = (noshi_tgc_group *)calloc(1, sizeof(*g));
    if (!g) return NOSHI_E_NOMEM;
    g->events = *events;
    g->state = NOSHI_TGC_GROUP_NEW;
    g->ssrc = random_u32();
    g->payload_type = 111;
    g->level_ext = 1;
    g->audio_seq = (uint16_t)random_u32();
    g->audio_ts = random_u32();
    g->transport_seq = 1;
    random_text(g->local_ufrag, UFRAG_LEN);
    random_text(g->local_pwd, PWD_LEN);
    if (noshi_random(&tie, sizeof(tie)) != NOSHI_OK) {
        free(g);
        return NOSHI_E_CRYPTO;
    }
    memset(&ice_events, 0, sizeof(ice_events));
    ice_events.context = g;
    ice_events.send = ice_send;
    ice_events.local_candidate = ice_candidate;
    ice_events.state = ice_state;
    ice_events.payload = ice_payload;
    ice_events.trace = ice_trace;
    status = noshi_tgc_ice_init_direct(&g->ice, 1, tie, g->local_ufrag, g->local_pwd, &ice_events);
    if (status == NOSHI_OK) status = noshi_dtls_new(&g->dtls);
    if (status != NOSHI_OK) {
        noshi_tgc_group_free(g);
        return status;
    }
    *out = g;
    return NOSHI_OK;
}

void noshi_tgc_group_free(noshi_tgc_group *g) {
    if (!g) return;
    noshi_dtls_free(g->dtls);
    noshi_tgc_srtp_wipe(&g->send_srtp);
    noshi_tgc_srtp_wipe(&g->recv_srtp);
    memset(g->local_pwd, 0, sizeof(g->local_pwd));
    free(g);
}

uint32_t noshi_tgc_group_ssrc(const noshi_tgc_group *g) {
    return g ? g->ssrc : 0;
}

noshi_status noshi_tgc_group_join_payload(const noshi_tgc_group *g, char *out, size_t capacity, size_t *len) {
    if (len) *len = 0;
    if (!g) return NOSHI_E_ARG;
    return noshi_tgc_group_join_json(g->ssrc, g->local_ufrag, g->local_pwd, noshi_dtls_local_fingerprint(g->dtls), out, capacity, len);
}

noshi_status noshi_tgc_group_apply(noshi_tgc_group *g, const noshi_tgc_group_transport *t, uint64_t now_ms) {
    size_t i, usable = 0;
    noshi_status status;
    if (!g || !t) return NOSHI_E_ARG;
    if (g->applied) return NOSHI_E_STATE;
    status = noshi_dtls_set_peer_fingerprint(g->dtls, "sha-256", t->fingerprint);
    if (status != NOSHI_OK) return NOSHI_E_SECURITY;
    status = noshi_tgc_ice_set_remote(&g->ice, t->ufrag, t->pwd);
    if (status != NOSHI_OK) return status;
    for (i = 0; i < t->candidate_count; ++i) {
        const noshi_tgc_group_candidate *c = &t->candidates[i];
        uint8_t address[4];
        unsigned index = 0;
        uint32_t ip;
        if (strcmp(c->protocol, "udp") != 0 || sscanf(c->ip, "%hhu.%hhu.%hhu.%hhu", &address[0], &address[1], &address[2], &address[3]) != 4) continue;
        ip = ((uint32_t)address[0] << 24) | ((uint32_t)address[1] << 16) | ((uint32_t)address[2] << 8) | address[3];
        if (noshi_tgc_ice_add_direct(&g->ice, ip, c->port, c->priority, &index) == NOSHI_OK) ++usable;
    }
    if (!usable) return NOSHI_E_UNSUPPORTED;
    /* the server names its own role: "active" means it starts the handshake and this side answers as the server */
    g->dtls_server = strcmp(t->setup, "active") == 0 ? 1 : 0;
    if (t->audio_payload_type) g->payload_type = t->audio_payload_type;
    if (t->audio_level_ext) g->level_ext = t->audio_level_ext;
    g->applied = 1;
    g->applied_ms = now_ms;
    g->now_ms = now_ms;
    gtrace(g, "transport applied: %u endpoints, dtls %s, opus %u, level ext %u", (unsigned)usable, g->dtls_server ? "server" : "client", (unsigned)g->payload_type,
           (unsigned)g->level_ext);
    update_state(g);
    return NOSHI_OK;
}

noshi_status noshi_tgc_group_endpoint(const noshi_tgc_group *g, unsigned index, uint32_t *ip, uint16_t *port) {
    if (ip) *ip = 0;
    if (port) *port = 0;
    if (!g || !ip || !port) return NOSHI_E_ARG;
    if (index >= NOSHI_TGC_ICE_MAX_PAIRS || !g->ice.pairs[index].used) return NOSHI_E_NOTFOUND;
    *ip = g->ice.pairs[index].remote_ip;
    *port = g->ice.pairs[index].remote_port;
    return NOSHI_OK;
}

noshi_status noshi_tgc_group_datagram(noshi_tgc_group *g, unsigned index, const uint8_t *data, size_t len, uint64_t now_ms) {
    if (!g || !data) return NOSHI_E_ARG;
    if (!g->applied) return NOSHI_E_STATE;
    g->now_ms = now_ms;
    return noshi_tgc_ice_input(&g->ice, index, data, len, now_ms);
}

void noshi_tgc_group_tick(noshi_tgc_group *g, uint64_t now_ms) {
    if (!g || !g->applied || g->failed) return;
    g->now_ms = now_ms;
    noshi_tgc_ice_tick(&g->ice, now_ms);
    if (g->dtls_started && noshi_dtls_get_state(g->dtls) == NOSHI_DTLS_HANDSHAKING) {
        noshi_dtls_on_timeout(g->dtls);
        dtls_changed(g);
    }
    if (!g->srtp_ready && now_ms - g->applied_ms > NOSHI_TGC_GROUP_CONNECT_TIMEOUT_MS) {
        gtrace(g, "no media path after %u ms: ice state %d, dtls started %d", (unsigned)(now_ms - g->applied_ms), (int)g->ice.state, (int)g->dtls_started);
        fail(g);
    }
}

noshi_status noshi_tgc_group_send_audio(noshi_tgc_group *g, const uint8_t *opus, size_t len, uint32_t samples, int level, int voice) {
    uint8_t buf[SEND_HEADER_LEN + NOSHI_TGC_GROUP_PAYLOAD_MAX + NOSHI_TGC_SRTP_TAG_LEN];
    size_t n = 0;
    if (!g || !opus) return NOSHI_E_ARG;
    if (!g->srtp_ready || g->ice.selected < 0) return NOSHI_E_STATE;
    if (len == 0 || len > NOSHI_TGC_GROUP_PAYLOAD_MAX || level < 0 || level > 127) return NOSHI_E_LIMIT;
    /* the header carries a one-byte extension block: the audio level, the sequence number of the transport, and padding to a whole word */
    buf[0] = RTP_VERSION_EXTENSION;
    buf[1] = g->payload_type;
    buf[2] = (uint8_t)(g->audio_seq >> 8);
    buf[3] = (uint8_t)g->audio_seq;
    buf[4] = (uint8_t)(g->audio_ts >> 24);
    buf[5] = (uint8_t)(g->audio_ts >> 16);
    buf[6] = (uint8_t)(g->audio_ts >> 8);
    buf[7] = (uint8_t)g->audio_ts;
    buf[8] = (uint8_t)(g->ssrc >> 24);
    buf[9] = (uint8_t)(g->ssrc >> 16);
    buf[10] = (uint8_t)(g->ssrc >> 8);
    buf[11] = (uint8_t)g->ssrc;
    buf[12] = (uint8_t)(EXTENSION_PROFILE_ONE_BYTE >> 8);
    buf[13] = (uint8_t)(EXTENSION_PROFILE_ONE_BYTE & 0xFF);
    buf[14] = 0;
    buf[15] = 2;
    buf[16] = (uint8_t)((g->level_ext << 4) | 0);
    buf[17] = (uint8_t)((voice ? 0x80 : 0) | level);
    buf[18] = (uint8_t)((TRANSPORT_SEQUENCE_EXT << 4) | 1);
    buf[19] = (uint8_t)(g->transport_seq >> 8);
    buf[20] = (uint8_t)g->transport_seq;
    buf[21] = buf[22] = buf[23] = 0;
    memcpy(buf + SEND_HEADER_LEN, opus, len);
    if (noshi_tgc_srtp_protect(&g->send_srtp, buf, SEND_HEADER_LEN + len, sizeof(buf), &n) != NOSHI_OK) return NOSHI_E_CRYPTO;
    if (++g->audio_tx == 1) gtrace(g, "first audio packet sent (%u bytes)", (unsigned)len);
    ++g->audio_seq;
    ++g->transport_seq;
    g->audio_ts += samples;
    return noshi_tgc_ice_send(&g->ice, buf, n);
}

void noshi_tgc_group_forget(noshi_tgc_group *g, uint32_t ssrc) {
    if (g) noshi_tgc_srtp_forget(&g->recv_srtp, ssrc);
}

noshi_tgc_group_state noshi_tgc_group_get_state(const noshi_tgc_group *g) {
    return g ? g->state : NOSHI_TGC_GROUP_FAILED;
}

void noshi_tgc_group_diagnostics(const noshi_tgc_group *g, int *ice, int *dtls, unsigned *audio_in, unsigned *audio_out) {
    if (ice) *ice = g ? (int)g->ice.state : 0;
    if (dtls) *dtls = g ? (int)noshi_dtls_get_state(g->dtls) : 0;
    if (audio_in) *audio_in = g ? g->audio_rx : 0;
    if (audio_out) *audio_out = g ? g->audio_tx : 0;
}
