#include "noshi_tgc_sctp.h"

#include <string.h>

#include "noshi_bytes.h"

#define COMMON_HEADER_LEN 12
#define CHUNK_HEADER_LEN 4
#define CHUNK_DATA 0
#define CHUNK_INIT 1
#define CHUNK_INIT_ACK 2
#define CHUNK_SACK 3
#define CHUNK_HEARTBEAT 4
#define CHUNK_HEARTBEAT_ACK 5
#define CHUNK_ABORT 6
#define CHUNK_SHUTDOWN 7
#define CHUNK_SHUTDOWN_ACK 8
#define CHUNK_ERROR 9
#define CHUNK_COOKIE_ECHO 10
#define CHUNK_COOKIE_ACK 11
#define CHUNK_SHUTDOWN_COMPLETE 14
#define PARAM_STATE_COOKIE 7
#define FLAG_END 0x01
#define FLAG_BEGIN 0x02
#define FLAG_UNORDERED 0x04
#define PPID_DCEP 50
#define PPID_STRING 51
#define PPID_BINARY 53
#define PPID_STRING_EMPTY 56
#define PPID_BINARY_EMPTY 57
#define DCEP_OPEN 0x03
#define DCEP_ACK 0x02
#define DCEP_OPEN_FIXED_LEN 12
#define MY_RWND 131072u
#define MY_STREAMS 16
#define MIN_PEER_RWND 1500u
#define RTO_INITIAL_MS 500
#define RTO_MAX_MS 8000
#define T1_INITIAL_MS 1000
#define T1_MAX_MS 8000
#define MAX_RETRIES 12
#define DATA_CHUNK_OVERHEAD 16
#define SACK_MAX_GAPS 8

/* the CRC of RFC 3309 / 4960 appendix B: CRC-32C, reflected, with the check value of "123456789" being 0xE3069283 */
uint32_t noshi_tgc_crc32c(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    size_t i;
    int bit;
    for (i = 0; i < len; ++i) {
        crc ^= data[i];
        for (bit = 0; bit < 8; ++bit) crc = (crc >> 1) ^ (0x82F63B78u & (0u - (crc & 1u)));
    }
    return ~crc;
}

static uint16_t get16(const uint8_t *p) {
    return (uint16_t)((unsigned)p[0] << 8 | p[1]);
}

static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

static void put16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)v;
}

/* serial number arithmetic over 32 bits: a is before b */
static int tsn_before(uint32_t a, uint32_t b) {
    return (int32_t)(a - b) < 0;
}

typedef struct packet_builder {
    uint8_t buf[NOSHI_TGC_SCTP_MAX_PACKET];
    size_t len;
    int overflow;
} packet_builder;

static void pb_begin(packet_builder *pb, uint32_t tag) {
    memset(pb, 0, sizeof(*pb));
    put16(pb->buf, NOSHI_TGC_SCTP_PORT);
    put16(pb->buf + 2, NOSHI_TGC_SCTP_PORT);
    noshi_put_u32be(pb->buf + 4, tag);
    pb->len = COMMON_HEADER_LEN;
}

static uint8_t *pb_chunk(packet_builder *pb, uint8_t type, uint8_t flags, size_t value_len) {
    size_t total = CHUNK_HEADER_LEN + value_len, padded = (total + 3) & ~(size_t)3;
    uint8_t *p;
    if (pb->overflow || pb->len + padded > sizeof(pb->buf)) {
        pb->overflow = 1;
        return NULL;
    }
    p = pb->buf + pb->len;
    p[0] = type;
    p[1] = flags;
    put16(p + 2, (uint16_t)total);
    memset(p + total, 0, padded - total);
    pb->len += padded;
    return p + CHUNK_HEADER_LEN;
}

static void pb_send(noshi_tgc_sctp *s, packet_builder *pb) {
    uint32_t crc;
    if (pb->overflow || pb->len <= COMMON_HEADER_LEN || !s->events.send) return;
    memset(pb->buf + 8, 0, 4);
    crc = noshi_tgc_crc32c(pb->buf, pb->len);
    /* the checksum goes out in little endian order, as every sctp stack writes it */
    pb->buf[8] = (uint8_t)crc;
    pb->buf[9] = (uint8_t)(crc >> 8);
    pb->buf[10] = (uint8_t)(crc >> 16);
    pb->buf[11] = (uint8_t)(crc >> 24);
    s->events.send(s->events.context, pb->buf, pb->len);
}

noshi_status noshi_tgc_sctp_init(noshi_tgc_sctp *s, int is_opener, uint32_t tag, uint32_t initial_tsn, const uint8_t cookie[32],
                                     const noshi_tgc_sctp_events *events) {
    if (!s) return NOSHI_E_ARG;
    memset(s, 0, sizeof(*s));
    if (tag == 0 || !cookie || !events || !events->send) return NOSHI_E_ARG;
    s->events = *events;
    s->opener = is_opener ? 1 : 0;
    s->my_tag = tag;
    s->my_initial_tsn = initial_tsn;
    s->next_tsn = initial_tsn;
    memcpy(s->cookie, cookie, sizeof(s->cookie));
    s->has_cookie = 1;
    s->rto_ms = RTO_INITIAL_MS;
    s->peer_rwnd = MY_RWND;
    return NOSHI_OK;
}

static void send_init(noshi_tgc_sctp *s) {
    packet_builder pb;
    uint8_t *v;
    pb_begin(&pb, 0);
    v = pb_chunk(&pb, CHUNK_INIT, 0, 16);
    if (!v) return;
    noshi_put_u32be(v, s->my_tag);
    noshi_put_u32be(v + 4, MY_RWND);
    put16(v + 8, MY_STREAMS);
    put16(v + 10, MY_STREAMS);
    noshi_put_u32be(v + 12, s->my_initial_tsn);
    pb_send(s, &pb);
}

static void send_init_ack(noshi_tgc_sctp *s) {
    packet_builder pb;
    uint8_t *v;
    pb_begin(&pb, s->peer_tag);
    v = pb_chunk(&pb, CHUNK_INIT_ACK, 0, 16 + 4 + sizeof(s->cookie));
    if (!v) return;
    noshi_put_u32be(v, s->my_tag);
    noshi_put_u32be(v + 4, MY_RWND);
    put16(v + 8, MY_STREAMS);
    put16(v + 10, MY_STREAMS);
    noshi_put_u32be(v + 12, s->my_initial_tsn);
    put16(v + 16, PARAM_STATE_COOKIE);
    put16(v + 18, (uint16_t)(4 + sizeof(s->cookie)));
    memcpy(v + 20, s->cookie, sizeof(s->cookie));
    pb_send(s, &pb);
}

static void send_cookie_echo(noshi_tgc_sctp *s, const uint8_t *cookie, size_t len) {
    packet_builder pb;
    uint8_t *v;
    pb_begin(&pb, s->peer_tag);
    v = pb_chunk(&pb, CHUNK_COOKIE_ECHO, 0, len);
    if (!v) return;
    memcpy(v, cookie, len);
    pb_send(s, &pb);
}

static void send_simple(noshi_tgc_sctp *s, uint8_t type, uint8_t flags) {
    packet_builder pb;
    pb_begin(&pb, s->peer_tag);
    pb_chunk(&pb, type, flags, 0);
    pb_send(s, &pb);
}

noshi_status noshi_tgc_sctp_start(noshi_tgc_sctp *s, uint64_t now_ms) {
    if (!s) return NOSHI_E_ARG;
    if (s->state != NOSHI_TGC_SCTP_CLOSED) return NOSHI_E_STATE;
    s->state = NOSHI_TGC_SCTP_COOKIE_WAIT;
    s->t1_tries = 0;
    s->t1_due = now_ms + T1_INITIAL_MS;
    send_init(s);
    return NOSHI_OK;
}

static void transmit_chunk(noshi_tgc_sctp *s, noshi_tgc_sctp_chunk *c, uint64_t now_ms) {
    packet_builder pb;
    uint8_t *v;
    pb_begin(&pb, s->peer_tag);
    v = pb_chunk(&pb, CHUNK_DATA, FLAG_BEGIN | FLAG_END, DATA_CHUNK_OVERHEAD - CHUNK_HEADER_LEN + c->len);
    if (!v) return;
    noshi_put_u32be(v, c->tsn);
    put16(v + 4, 0);
    put16(v + 6, c->ssn);
    noshi_put_u32be(v + 8, c->ppid);
    memcpy(v + 12, c->data, c->len);
    c->sent_ms = now_ms;
    ++c->tries;
    pb_send(s, &pb);
}

static noshi_status queue_data(noshi_tgc_sctp *s, uint32_t ppid, const uint8_t *data, size_t len, uint64_t now_ms) {
    int i;
    noshi_tgc_sctp_chunk *c = NULL;
    if (len > NOSHI_TGC_SCTP_MAX_MESSAGE) return NOSHI_E_LIMIT;
    for (i = 0; i < NOSHI_TGC_SCTP_WINDOW; ++i) {
        if (!s->window[i].used) {
            c = &s->window[i];
            break;
        }
    }
    if (!c) return NOSHI_E_LIMIT;
    memset(c, 0, sizeof(*c));
    c->used = 1;
    c->tsn = s->next_tsn++;
    c->ssn = s->next_ssn++;
    c->ppid = ppid;
    c->len = (uint16_t)len;
    if (len) memcpy(c->data, data, len);
    transmit_chunk(s, c, now_ms);
    if (s->t3_due == 0) {
        s->t3_tries = 0;
        s->t3_due = now_ms + s->rto_ms;
    }
    return NOSHI_OK;
}

noshi_status noshi_tgc_sctp_send_text(noshi_tgc_sctp *s, const char *text, size_t len, uint64_t now_ms) {
    if (!s || (!text && len)) return NOSHI_E_ARG;
    if (s->state != NOSHI_TGC_SCTP_ESTABLISHED || !s->channel_open) return NOSHI_E_STATE;
    if (len == 0) {
        /* an empty string has a PPID of its own and carries one zero byte, as the data channel protocol says */
        uint8_t zero = 0;
        return queue_data(s, PPID_STRING_EMPTY, &zero, 1, now_ms);
    }
    return queue_data(s, PPID_STRING, (const uint8_t *)text, len, now_ms);
}

static void close_association(noshi_tgc_sctp *s, noshi_tgc_sctp_state to) {
    int was_open = s->channel_open;
    s->state = to;
    s->channel_open = 0;
    s->t1_due = 0;
    s->t3_due = 0;
    if (was_open && s->events.channel) s->events.channel(s->events.context, 0);
}

void noshi_tgc_sctp_abort(noshi_tgc_sctp *s) {
    if (!s) return;
    if (s->state == NOSHI_TGC_SCTP_ESTABLISHED || s->state == NOSHI_TGC_SCTP_COOKIE_ECHOED) send_simple(s, CHUNK_ABORT, 0);
    close_association(s, NOSHI_TGC_SCTP_CLOSED);
}

static void open_channel(noshi_tgc_sctp *s) {
    if (s->channel_open) return;
    s->channel_open = 1;
    if (s->events.channel) s->events.channel(s->events.context, 1);
}

static void send_dcep_open(noshi_tgc_sctp *s, uint64_t now_ms) {
    uint8_t msg[DCEP_OPEN_FIXED_LEN + sizeof(NOSHI_TGC_SCTP_CHANNEL_LABEL) - 1];
    size_t label_len = sizeof(NOSHI_TGC_SCTP_CHANNEL_LABEL) - 1;
    memset(msg, 0, sizeof(msg));
    msg[0] = DCEP_OPEN;
    msg[1] = 0x00;                  /* reliable, ordered */
    put16(msg + 8, (uint16_t)label_len);
    memcpy(msg + DCEP_OPEN_FIXED_LEN, NOSHI_TGC_SCTP_CHANNEL_LABEL, label_len);
    if (queue_data(s, PPID_DCEP, msg, sizeof(msg), now_ms) == NOSHI_OK) s->open_sent = 1;
}

static void established(noshi_tgc_sctp *s, uint64_t now_ms) {
    if (s->state == NOSHI_TGC_SCTP_ESTABLISHED) return;
    s->state = NOSHI_TGC_SCTP_ESTABLISHED;
    s->t1_due = 0;
    s->cumulative = s->peer_initial_tsn - 1;
    s->cumulative_valid = 1;
    if (s->opener) send_dcep_open(s, now_ms);
}

static void deliver_message(noshi_tgc_sctp *s, uint16_t stream, uint32_t ppid, const uint8_t *data, size_t len, uint64_t now_ms) {
    if (stream != 0) return;
    if (ppid == PPID_DCEP) {
        if (len >= 1 && data[0] == DCEP_OPEN && len >= DCEP_OPEN_FIXED_LEN && !s->opener) {
            uint8_t ack = DCEP_ACK;
            queue_data(s, PPID_DCEP, &ack, 1, now_ms);
            open_channel(s);
        } else if (len == 1 && data[0] == DCEP_ACK && s->opener && s->open_sent) {
            open_channel(s);
        }
        return;
    }
    /* a message from the other end means it has seen the OPEN: that opens the channel for the opener too (RFC 8832 section 6) */
    if (s->opener && s->open_sent) open_channel(s);
    if (!s->channel_open) return;
    if (ppid == PPID_STRING_EMPTY) {
        if (s->events.message) s->events.message(s->events.context, "", 0);
    } else if (ppid == PPID_STRING) {
        /* the assembly buffer holds the message with a NUL after it */
        if (s->events.message) s->events.message(s->events.context, (const char *)data, len);
    } else if (ppid == PPID_BINARY || ppid == PPID_BINARY_EMPTY) {
        /* the tgcalls channel carries text only */
    }
}

static void consume_in_order(noshi_tgc_sctp *s, noshi_tgc_sctp_rx *r, uint64_t now_ms) {
    if (r->flags & FLAG_BEGIN) {
        s->assembling = 1;
        s->assembly_len = 0;
        s->assembly_stream = r->stream;
        s->assembly_ppid = r->ppid;
    }
    if (!s->assembling || r->stream != s->assembly_stream) return;
    if (r->len > NOSHI_TGC_SCTP_RX_MESSAGE_MAX - s->assembly_len) {
        s->assembling = 0;
        s->assembly_len = 0;
        return;
    }
    memcpy(s->assembly + s->assembly_len, r->data, r->len);
    s->assembly_len += r->len;
    if (r->flags & FLAG_END) {
        s->assembly[s->assembly_len] = '\0';
        s->assembling = 0;
        deliver_message(s, s->assembly_stream, s->assembly_ppid, s->assembly, s->assembly_len, now_ms);
        s->assembly_len = 0;
    }
}

static void handle_data(noshi_tgc_sctp *s, const uint8_t *v, size_t vlen, uint8_t flags, uint64_t now_ms) {
    uint32_t tsn;
    int i;
    noshi_tgc_sctp_rx *slot = NULL;
    if (vlen < DATA_CHUNK_OVERHEAD - CHUNK_HEADER_LEN + 1 || s->state != NOSHI_TGC_SCTP_ESTABLISHED || !s->cumulative_valid) return;
    tsn = get32(v);
    s->need_sack = 1;
    if (!tsn_before(s->cumulative, tsn)) {
        if (s->dup_count < 4) s->dup_tsn[s->dup_count++] = tsn;
        return;
    }
    if ((uint32_t)(tsn - s->cumulative) > NOSHI_TGC_SCTP_RX_SLOTS) return;
    for (i = 0; i < NOSHI_TGC_SCTP_RX_SLOTS; ++i) {
        if (s->rx[i].used && s->rx[i].tsn == tsn) {
            if (s->dup_count < 4) s->dup_tsn[s->dup_count++] = tsn;
            return;
        }
        if (!s->rx[i].used && !slot) slot = &s->rx[i];
    }
    if (!slot) return;
    slot->used = 1;
    slot->flags = flags;
    slot->tsn = tsn;
    slot->stream = get16(v + 4);
    slot->ssn = get16(v + 6);
    slot->ppid = get32(v + 8);
    slot->len = (uint16_t)(vlen - 12);
    memcpy(slot->data, v + 12, slot->len);
    /* what is now in sequence goes up, in the order of the TSNs */
    for (;;) {
        noshi_tgc_sctp_rx *next = NULL;
        for (i = 0; i < NOSHI_TGC_SCTP_RX_SLOTS; ++i) {
            if (s->rx[i].used && s->rx[i].tsn == s->cumulative + 1) next = &s->rx[i];
        }
        if (!next) break;
        s->cumulative = next->tsn;
        consume_in_order(s, next, now_ms);
        next->used = 0;
    }
}

static void send_sack(noshi_tgc_sctp *s) {
    packet_builder pb;
    uint8_t *v;
    uint16_t starts[SACK_MAX_GAPS], ends[SACK_MAX_GAPS];
    unsigned gaps = 0, dups = s->dup_count, i;
    int open = 0;
    uint32_t offset;
    if (!s->cumulative_valid) return;
    /* gap blocks: runs of received TSNs above the cumulative one, as offsets from it */
    for (offset = 2; offset <= NOSHI_TGC_SCTP_RX_SLOTS + 1 && gaps < SACK_MAX_GAPS; ++offset) {
        int have = 0;
        for (i = 0; i < NOSHI_TGC_SCTP_RX_SLOTS; ++i) {
            if (s->rx[i].used && s->rx[i].tsn == s->cumulative + offset) have = 1;
        }
        if (have && !open) {
            starts[gaps] = (uint16_t)offset;
            open = 1;
        }
        if (!have && open) {
            ends[gaps++] = (uint16_t)(offset - 1);
            open = 0;
        }
    }
    if (open && gaps < SACK_MAX_GAPS) ends[gaps++] = (uint16_t)(NOSHI_TGC_SCTP_RX_SLOTS + 1);
    pb_begin(&pb, s->peer_tag);
    v = pb_chunk(&pb, CHUNK_SACK, 0, 12 + 4 * gaps + 4 * dups);
    if (!v) return;
    noshi_put_u32be(v, s->cumulative);
    noshi_put_u32be(v + 4, MY_RWND);
    put16(v + 8, (uint16_t)gaps);
    put16(v + 10, (uint16_t)dups);
    for (i = 0; i < gaps; ++i) {
        put16(v + 12 + 4 * i, starts[i]);
        put16(v + 14 + 4 * i, ends[i]);
    }
    for (i = 0; i < dups; ++i) noshi_put_u32be(v + 12 + 4 * gaps + 4 * i, s->dup_tsn[i]);
    s->dup_count = 0;
    s->need_sack = 0;
    pb_send(s, &pb);
}

static void handle_sack(noshi_tgc_sctp *s, const uint8_t *v, size_t vlen, uint64_t now_ms) {
    uint32_t cum;
    int i, left = 0;
    if (vlen < 12 || s->state != NOSHI_TGC_SCTP_ESTABLISHED) return;
    cum = get32(v);
    s->peer_rwnd = get32(v + 4);
    for (i = 0; i < NOSHI_TGC_SCTP_WINDOW; ++i) {
        if (s->window[i].used && !tsn_before(cum, s->window[i].tsn)) s->window[i].used = 0;
        if (s->window[i].used) ++left;
    }
    s->t3_tries = 0;
    s->rto_ms = RTO_INITIAL_MS;
    s->t3_due = left ? now_ms + s->rto_ms : 0;
}

static void handle_init(noshi_tgc_sctp *s, const uint8_t *v, size_t vlen, uint32_t header_tag) {
    uint32_t tag, rwnd;
    uint16_t streams_out, streams_in;
    if (vlen < 16 || header_tag != 0) return;
    tag = get32(v);
    rwnd = get32(v + 4);
    streams_out = get16(v + 8);
    streams_in = get16(v + 10);
    if (tag == 0 || rwnd < MIN_PEER_RWND || streams_out == 0 || streams_in == 0) return;
    /* a repeated INIT of the peer we already know is answered again; one with a new tag after the association stands would be a restart, which is not
       something this agent takes part in */
    if (s->state == NOSHI_TGC_SCTP_ESTABLISHED && s->has_peer_init && tag != s->peer_tag) return;
    s->peer_tag = tag;
    s->peer_rwnd = rwnd;
    s->peer_initial_tsn = get32(v + 12);
    s->has_peer_init = 1;
    s->answered_init = 1;
    send_init_ack(s);
}

static void handle_init_ack(noshi_tgc_sctp *s, const uint8_t *v, size_t vlen, uint64_t now_ms) {
    uint32_t tag, rwnd;
    size_t pos = 16;
    const uint8_t *cookie = NULL;
    size_t cookie_len = 0;
    if (s->state != NOSHI_TGC_SCTP_COOKIE_WAIT || vlen < 16) return;
    tag = get32(v);
    rwnd = get32(v + 4);
    if (tag == 0 || rwnd < MIN_PEER_RWND || get16(v + 8) == 0 || get16(v + 10) == 0) return;
    while (pos + 4 <= vlen) {
        uint16_t type = get16(v + pos), plen = get16(v + pos + 2);
        if (plen < 4 || pos + plen > vlen) return;
        if (type == PARAM_STATE_COOKIE) {
            cookie = v + pos + 4;
            cookie_len = (size_t)plen - 4;
        }
        pos += ((size_t)plen + 3) & ~(size_t)3;
    }
    /* a cookie must come, and must fit the one chunk of the echo */
    if (!cookie || cookie_len == 0 || cookie_len > NOSHI_TGC_SCTP_MAX_COOKIE) return;
    s->peer_tag = tag;
    s->peer_rwnd = rwnd;
    s->peer_initial_tsn = get32(v + 12);
    s->has_peer_init = 1;
    s->state = NOSHI_TGC_SCTP_COOKIE_ECHOED;
    s->t1_tries = 0;
    s->t1_due = now_ms + T1_INITIAL_MS;
    memcpy(s->echo, cookie, cookie_len);
    s->echo_len = cookie_len;
    send_cookie_echo(s, cookie, cookie_len);
}

noshi_status noshi_tgc_sctp_input(noshi_tgc_sctp *s, const uint8_t *packet, size_t len, uint64_t now_ms) {
    uint8_t copy[NOSHI_TGC_SCTP_MAX_INPUT];
    uint32_t tag, checksum, crc;
    size_t pos = COMMON_HEADER_LEN;
    int saw_init = 0;
    if (!s || !packet) return NOSHI_E_ARG;
    if (len < COMMON_HEADER_LEN + CHUNK_HEADER_LEN || len > sizeof(copy)) return NOSHI_E_MALFORMED;
    if (get16(packet) != NOSHI_TGC_SCTP_PORT || get16(packet + 2) != NOSHI_TGC_SCTP_PORT) return NOSHI_E_MALFORMED;
    memcpy(copy, packet, len);
    checksum = (uint32_t)copy[8] | (uint32_t)copy[9] << 8 | (uint32_t)copy[10] << 16 | (uint32_t)copy[11] << 24;
    memset(copy + 8, 0, 4);
    crc = noshi_tgc_crc32c(copy, len);
    if (crc != checksum) return NOSHI_E_MALFORMED;
    tag = get32(packet + 4);
    if (s->state == NOSHI_TGC_SCTP_FAILED) return NOSHI_E_STATE;
    while (pos + CHUNK_HEADER_LEN <= len) {
        uint8_t type = packet[pos], flags = packet[pos + 1];
        size_t clen = get16(packet + pos + 2), padded;
        const uint8_t *v = packet + pos + CHUNK_HEADER_LEN;
        size_t vlen;
        if (clen < CHUNK_HEADER_LEN || pos + clen > len) return NOSHI_E_MALFORMED;
        vlen = clen - CHUNK_HEADER_LEN;
        padded = (clen + 3) & ~(size_t)3;
        /* every packet but an INIT carries the tag this side chose */
        if (type == CHUNK_INIT) {
            saw_init = 1;
        } else if (tag != s->my_tag) {
            return NOSHI_E_MALFORMED;
        }
        switch (type) {
        case CHUNK_DATA: handle_data(s, v, vlen, flags, now_ms); break;
        case CHUNK_INIT: handle_init(s, v, vlen, tag); break;
        case CHUNK_INIT_ACK: handle_init_ack(s, v, vlen, now_ms); break;
        case CHUNK_SACK: handle_sack(s, v, vlen, now_ms); break;
        case CHUNK_HEARTBEAT:
            if (s->state == NOSHI_TGC_SCTP_ESTABLISHED && vlen <= 256) {
                packet_builder pb;
                uint8_t *out;
                pb_begin(&pb, s->peer_tag);
                out = pb_chunk(&pb, CHUNK_HEARTBEAT_ACK, 0, vlen);
                if (out) {
                    memcpy(out, v, vlen);
                    pb_send(s, &pb);
                }
            }
            break;
        case CHUNK_COOKIE_ECHO:
            /* the cookie this side issued, in the INIT ACK it sent: nothing else opens the association */
            if (s->answered_init && vlen == sizeof(s->cookie) && memcmp(v, s->cookie, sizeof(s->cookie)) == 0) {
                established(s, now_ms);
                send_simple(s, CHUNK_COOKIE_ACK, 0);
            }
            break;
        case CHUNK_COOKIE_ACK:
            if (s->state == NOSHI_TGC_SCTP_COOKIE_ECHOED) established(s, now_ms);
            break;
        case CHUNK_ABORT:
            close_association(s, NOSHI_TGC_SCTP_FAILED);
            return NOSHI_OK;
        case CHUNK_SHUTDOWN:
            send_simple(s, CHUNK_SHUTDOWN_ACK, 0);
            close_association(s, NOSHI_TGC_SCTP_CLOSED);
            return NOSHI_OK;
        case CHUNK_SHUTDOWN_ACK:
            send_simple(s, CHUNK_SHUTDOWN_COMPLETE, 0);
            close_association(s, NOSHI_TGC_SCTP_CLOSED);
            return NOSHI_OK;
        case CHUNK_SHUTDOWN_COMPLETE:
            close_association(s, NOSHI_TGC_SCTP_CLOSED);
            return NOSHI_OK;
        case CHUNK_ERROR:
            break;
        default:
            /* a chunk type from an extension: skipped when its top bits say to, else the rest of the packet is dropped */
            if (!(type & 0x40)) return NOSHI_OK;
            break;
        }
        pos += padded;
        if (saw_init) break;
    }
    if (s->need_sack) send_sack(s);
    return NOSHI_OK;
}

void noshi_tgc_sctp_tick(noshi_tgc_sctp *s, uint64_t now_ms) {
    int i;
    if (!s) return;
    if (s->t1_due && now_ms >= s->t1_due) {
        if (++s->t1_tries > MAX_RETRIES) {
            close_association(s, NOSHI_TGC_SCTP_FAILED);
            return;
        }
        {
            uint64_t backoff = (uint64_t)T1_INITIAL_MS << (s->t1_tries < 4 ? s->t1_tries : 4);
            if (backoff > T1_MAX_MS) backoff = T1_MAX_MS;
            s->t1_due = now_ms + backoff;
        }
        if (s->state == NOSHI_TGC_SCTP_COOKIE_WAIT) send_init(s);
        else if (s->state == NOSHI_TGC_SCTP_COOKIE_ECHOED) send_cookie_echo(s, s->echo, s->echo_len);
    }
    if (s->t3_due && now_ms >= s->t3_due && s->state == NOSHI_TGC_SCTP_ESTABLISHED) {
        noshi_tgc_sctp_chunk *oldest = NULL;
        for (i = 0; i < NOSHI_TGC_SCTP_WINDOW; ++i) {
            if (s->window[i].used && (!oldest || tsn_before(s->window[i].tsn, oldest->tsn))) oldest = &s->window[i];
        }
        if (!oldest) {
            s->t3_due = 0;
        } else if (++s->t3_tries > MAX_RETRIES) {
            send_simple(s, CHUNK_ABORT, 0);
            close_association(s, NOSHI_TGC_SCTP_FAILED);
        } else {
            transmit_chunk(s, oldest, now_ms);
            s->rto_ms = s->rto_ms * 2 > RTO_MAX_MS ? RTO_MAX_MS : s->rto_ms * 2;
            s->t3_due = now_ms + s->rto_ms;
        }
    }
}
