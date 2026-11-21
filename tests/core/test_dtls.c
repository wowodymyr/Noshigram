#include "noshi_dtls.h"
#include "noshi_rtp.h"
#include "noshi_tgc_srtp.h"
#include "test_util.h"

#include <time.h>
#include <unistd.h>

/* moves datagrams between two sessions until both are quiet. drop(n) says whether the nth datagram sent (counted over both directions) is lost */
typedef int (*drop_fn)(int n);

static int sent;

static int pump(noshi_dtls *a, noshi_dtls *b, drop_fn drop) {
    uint8_t buf[NOSHI_DTLS_MAX_DATAGRAM];
    size_t len = 0;
    int moved = 0, progress;
    do {
        noshi_dtls *ends[2];
        int i;
        progress = 0;
        ends[0] = a;
        ends[1] = b;
        for (i = 0; i < 2; ++i) {
            while (noshi_dtls_poll(ends[i], buf, sizeof(buf), &len) == NOSHI_OK) {
                int lost = drop && drop(sent);
                ++sent;
                progress = 1;
                if (lost) continue;
                ++moved;
                noshi_dtls_input(ends[1 - i], buf, len);
            }
        }
    } while (progress);
    return moved;
}

static void make_pair(noshi_dtls **client, noshi_dtls **server) {
    CHECK_EQ_INT(noshi_dtls_new(client), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_new(server), NOSHI_OK);
    CHECK(*client && *server);
    CHECK_EQ_INT(strlen(noshi_dtls_local_fingerprint(*client)), NOSHI_DTLS_FINGERPRINT_LEN);
    CHECK(strcmp(noshi_dtls_local_fingerprint(*client), noshi_dtls_local_fingerprint(*server)) != 0);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(*client, "sha-256", noshi_dtls_local_fingerprint(*server)), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(*server, "SHA-256", noshi_dtls_local_fingerprint(*client)), NOSHI_OK);
}

static void handshake_and_keys(void) {
    noshi_dtls *c, *s;
    uint8_t ck[16], cs[14], crk[16], crs[14], sk[16], ss[14], srk[16], srs[14];
    make_pair(&c, &s);
    CHECK_EQ_INT(noshi_dtls_get_state(c), NOSHI_DTLS_IDLE);
    CHECK_EQ_INT(noshi_dtls_srtp_keys(c, ck, cs, crk, crs), NOSHI_E_STATE);
    /* the server is started first and waits; the client's first flight starts the exchange */
    CHECK_EQ_INT(noshi_dtls_start(s, 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_start(c, 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_start(c, 1), NOSHI_E_STATE);
    CHECK(pump(c, s, NULL) > 0);
    CHECK_EQ_INT(noshi_dtls_get_state(c), NOSHI_DTLS_CONNECTED);
    CHECK_EQ_INT(noshi_dtls_get_state(s), NOSHI_DTLS_CONNECTED);
    CHECK_EQ_INT(noshi_dtls_srtp_keys(c, ck, cs, crk, crs), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_srtp_keys(s, sk, ss, srk, srs), NOSHI_OK);
    /* what the client sends is what the server receives, and the two directions use different keys */
    CHECK_MEM(ck, srk, 16);
    CHECK_MEM(cs, srs, 14);
    CHECK_MEM(crk, sk, 16);
    CHECK_MEM(crs, ss, 14);
    CHECK(memcmp(ck, crk, 16) != 0);
    CHECK(memcmp(cs, crs, 14) != 0);

    /* and they work as SRTP keys: a packet protected by one end opens at the other, both ways */
    {
        noshi_tgc_srtp tx, rx;
        uint8_t pkt[64];
        size_t n = 0, m = 0;
        CHECK_EQ_INT(noshi_tgc_srtp_init(&tx, ck, cs), NOSHI_OK);
        CHECK_EQ_INT(noshi_tgc_srtp_init(&rx, srk, srs), NOSHI_OK);
        noshi_rtp_write_header(pkt, sizeof(pkt), 111, 0, 1, 1, 0x1234u);
        memcpy(pkt + 12, "voice", 5);
        CHECK_EQ_INT(noshi_tgc_srtp_protect(&tx, pkt, 17, sizeof(pkt), &n), NOSHI_OK);
        CHECK_EQ_INT(noshi_tgc_srtp_unprotect(&rx, pkt, n, &m), NOSHI_OK);
        CHECK(memcmp(pkt + 12, "voice", 5) == 0);
        CHECK_EQ_INT(noshi_tgc_srtp_init(&tx, sk, ss), NOSHI_OK);
        CHECK_EQ_INT(noshi_tgc_srtp_init(&rx, crk, crs), NOSHI_OK);
        noshi_rtp_write_header(pkt, sizeof(pkt), 111, 0, 1, 1, 0x4321u);
        memcpy(pkt + 12, "reply", 5);
        CHECK_EQ_INT(noshi_tgc_srtp_protect(&tx, pkt, 17, sizeof(pkt), &n), NOSHI_OK);
        CHECK_EQ_INT(noshi_tgc_srtp_unprotect(&rx, pkt, n, &m), NOSHI_OK);
        CHECK(memcmp(pkt + 12, "reply", 5) == 0);
    }
    noshi_dtls_free(c);
    noshi_dtls_free(s);
}

static void application_data(void) {
    noshi_dtls *c, *s;
    uint8_t msg[NOSHI_DTLS_MAX_APP_DATA], out[NOSHI_DTLS_MAX_DATAGRAM];
    size_t n = 0, i;
    make_pair(&c, &s);
    CHECK_EQ_INT(noshi_dtls_write(c, msg, 10), NOSHI_E_STATE);
    noshi_dtls_start(s, 0);
    noshi_dtls_start(c, 1);
    pump(c, s, NULL);
    for (i = 0; i < sizeof(msg); ++i) msg[i] = (uint8_t)(i * 5u + 3u);
    /* one byte, a typical packet, and the largest; each arrives as one message, in order */
    CHECK_EQ_INT(noshi_dtls_write(c, msg, 1), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_write(c, msg, 300), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_write(s, msg, NOSHI_DTLS_MAX_APP_DATA), NOSHI_OK);
    pump(c, s, NULL);
    CHECK_EQ_INT(noshi_dtls_read(s, out, sizeof(out), &n), NOSHI_OK);
    CHECK_EQ_INT(n, 1);
    CHECK_EQ_INT(noshi_dtls_read(s, out, sizeof(out), &n), NOSHI_OK);
    CHECK_EQ_INT(n, 300);
    CHECK_MEM(out, msg, 300);
    CHECK_EQ_INT(noshi_dtls_read(s, out, sizeof(out), &n), NOSHI_E_RETRY);
    CHECK_EQ_INT(n, 0);
    CHECK_EQ_INT(noshi_dtls_read(c, out, sizeof(out), &n), NOSHI_OK);
    CHECK_EQ_INT(n, NOSHI_DTLS_MAX_APP_DATA);
    CHECK_MEM(out, msg, NOSHI_DTLS_MAX_APP_DATA);
    /* limits */
    CHECK_EQ_INT(noshi_dtls_write(c, msg, 0), NOSHI_E_LIMIT);
    CHECK_EQ_INT(noshi_dtls_write(c, msg, NOSHI_DTLS_MAX_APP_DATA + 1), NOSHI_E_LIMIT);
    CHECK_EQ_INT(noshi_dtls_write(NULL, msg, 4), NOSHI_E_ARG);
    /* a message the reader's buffer cannot take is dropped, and the next one is still there */
    CHECK_EQ_INT(noshi_dtls_write(c, msg, 500), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_write(c, msg, 20), NOSHI_OK);
    pump(c, s, NULL);
    CHECK_EQ_INT(noshi_dtls_read(s, out, 100, &n), NOSHI_E_LIMIT);
    CHECK_EQ_INT(noshi_dtls_read(s, out, 100, &n), NOSHI_OK);
    CHECK_EQ_INT(n, 20);
    noshi_dtls_free(c);
    noshi_dtls_free(s);
}

static void wrong_or_missing_fingerprint(void) {
    noshi_dtls *c, *s, *other;
    int i;
    /* the client expects another certificate than the server has */
    CHECK_EQ_INT(noshi_dtls_new(&c), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_new(&s), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_new(&other), NOSHI_OK);
    noshi_dtls_set_peer_fingerprint(c, "sha-256", noshi_dtls_local_fingerprint(other));
    noshi_dtls_set_peer_fingerprint(s, "sha-256", noshi_dtls_local_fingerprint(c));
    noshi_dtls_start(s, 0);
    noshi_dtls_start(c, 1);
    pump(c, s, NULL);
    CHECK_EQ_INT(noshi_dtls_get_state(c), NOSHI_DTLS_FAILED);
    CHECK(noshi_dtls_get_state(s) != NOSHI_DTLS_CONNECTED);
    {
        uint8_t k[16], t[14], k2[16], t2[14];
        CHECK_EQ_INT(noshi_dtls_srtp_keys(c, k, t, k2, t2), NOSHI_E_STATE);
    }
    noshi_dtls_free(c);
    noshi_dtls_free(s);

    /* the server expects another certificate than the client has: the server refuses it */
    CHECK_EQ_INT(noshi_dtls_new(&c), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_new(&s), NOSHI_OK);
    noshi_dtls_set_peer_fingerprint(c, "sha-256", noshi_dtls_local_fingerprint(s));
    noshi_dtls_set_peer_fingerprint(s, "sha-256", noshi_dtls_local_fingerprint(other));
    noshi_dtls_start(s, 0);
    noshi_dtls_start(c, 1);
    pump(c, s, NULL);
    CHECK_EQ_INT(noshi_dtls_get_state(s), NOSHI_DTLS_FAILED);
    CHECK(noshi_dtls_get_state(c) != NOSHI_DTLS_CONNECTED);
    noshi_dtls_free(c);
    noshi_dtls_free(s);

    /* none given at all */
    CHECK_EQ_INT(noshi_dtls_new(&c), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_new(&s), NOSHI_OK);
    noshi_dtls_set_peer_fingerprint(s, "sha-256", noshi_dtls_local_fingerprint(c));
    noshi_dtls_start(s, 0);
    noshi_dtls_start(c, 1);
    pump(c, s, NULL);
    CHECK_EQ_INT(noshi_dtls_get_state(c), NOSHI_DTLS_FAILED);
    for (i = 0; i < 3; ++i) {
        uint8_t junk[40] = {0};
        CHECK(noshi_dtls_input(c, junk, sizeof(junk)) != NOSHI_OK);
    }
    noshi_dtls_free(c);
    noshi_dtls_free(s);
    noshi_dtls_free(other);
}

static void fingerprint_parsing(void) {
    noshi_dtls *d;
    char good[NOSHI_DTLS_FINGERPRINT_LEN + 1], lower[NOSHI_DTLS_FINGERPRINT_LEN + 1], bad[NOSHI_DTLS_FINGERPRINT_LEN + 1];
    size_t i;
    CHECK_EQ_INT(noshi_dtls_new(&d), NOSHI_OK);
    snprintf(good, sizeof(good), "%s", noshi_dtls_local_fingerprint(d));
    for (i = 0; i <= NOSHI_DTLS_FINGERPRINT_LEN; ++i) lower[i] = (char)((good[i] >= 'A' && good[i] <= 'F') ? good[i] + 32 : good[i]);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", good), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "Sha-256", lower), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-1", good), NOSHI_E_UNSUPPORTED);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-2560", good), NOSHI_E_UNSUPPORTED);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "", good), NOSHI_E_UNSUPPORTED);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", ""), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", "AA:BB"), NOSHI_E_MALFORMED);
    snprintf(bad, sizeof(bad), "%s", good);
    bad[2] = '-';
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", bad), NOSHI_E_MALFORMED);
    snprintf(bad, sizeof(bad), "%s", good);
    bad[10] = 'G';
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", bad), NOSHI_E_MALFORMED);
    snprintf(bad, sizeof(bad), "%s", good);
    bad[NOSHI_DTLS_FINGERPRINT_LEN - 1] = '\0';
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", bad), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(NULL, "sha-256", good), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, NULL, good), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", NULL), NOSHI_E_ARG);
    /* the fingerprint may not change once the handshake began */
    {
        noshi_dtls *other;
        CHECK_EQ_INT(noshi_dtls_new(&other), NOSHI_OK);
        noshi_dtls_start(d, 1);
        CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", good), NOSHI_OK);
        CHECK_EQ_INT(noshi_dtls_set_peer_fingerprint(d, "sha-256", noshi_dtls_local_fingerprint(other)), NOSHI_E_STATE);
        noshi_dtls_free(other);
    }
    noshi_dtls_free(d);
    CHECK_EQ_INT(noshi_dtls_new(NULL), NOSHI_E_ARG);
    CHECK(noshi_dtls_local_fingerprint(NULL) == NULL);
    CHECK_EQ_INT(noshi_dtls_get_state(NULL), NOSHI_DTLS_FAILED);
    noshi_dtls_free(NULL);
}

/* the flights are lost once each: the handshake must finish by resending on the timer */
static int drop_first_of_each_early_datagram(int n) {
    return n == 0 || n == 2;
}

static void loss_and_retransmission(void) {
    noshi_dtls *c, *s;
    int rounds;
    sent = 0;
    make_pair(&c, &s);
    noshi_dtls_start(s, 0);
    noshi_dtls_start(c, 1);
    pump(c, s, drop_first_of_each_early_datagram);
    for (rounds = 0; rounds < 12 && !(noshi_dtls_get_state(c) == NOSHI_DTLS_CONNECTED && noshi_dtls_get_state(s) == NOSHI_DTLS_CONNECTED); ++rounds) {
        uint32_t wait_c = 0, wait_s = 0, wait;
        noshi_status sc = noshi_dtls_timeout(c, &wait_c), ss = noshi_dtls_timeout(s, &wait_s);
        if (sc != NOSHI_OK && ss != NOSHI_OK) break;
        wait = sc == NOSHI_OK ? wait_c : wait_s;
        if (ss == NOSHI_OK && wait_s < wait) wait = wait_s;
        usleep((useconds_t)(wait + 20) * 1000);
        noshi_dtls_on_timeout(c);
        noshi_dtls_on_timeout(s);
        pump(c, s, NULL);
    }
    CHECK_EQ_INT(noshi_dtls_get_state(c), NOSHI_DTLS_CONNECTED);
    CHECK_EQ_INT(noshi_dtls_get_state(s), NOSHI_DTLS_CONNECTED);
    {
        uint32_t ms;
        CHECK_EQ_INT(noshi_dtls_timeout(c, &ms), NOSHI_E_STATE);
        CHECK_EQ_INT(noshi_dtls_on_timeout(c), NOSHI_OK);
    }
    noshi_dtls_free(c);
    noshi_dtls_free(s);
}

static void early_and_damaged_input(void) {
    noshi_dtls *c, *s;
    uint8_t buf[NOSHI_DTLS_MAX_DATAGRAM], big[NOSHI_DTLS_MAX_DATAGRAM + 1];
    size_t n = 0;
    make_pair(&c, &s);
    /* the client's first flight arrives at the server before the server was started: it is kept and used */
    noshi_dtls_start(c, 1);
    while (noshi_dtls_poll(c, buf, sizeof(buf), &n) == NOSHI_OK) CHECK_EQ_INT(noshi_dtls_input(s, buf, n), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_get_state(s), NOSHI_DTLS_IDLE);
    CHECK_EQ_INT(noshi_dtls_start(s, 0), NOSHI_OK);
    pump(c, s, NULL);
    CHECK_EQ_INT(noshi_dtls_get_state(c), NOSHI_DTLS_CONNECTED);
    CHECK_EQ_INT(noshi_dtls_get_state(s), NOSHI_DTLS_CONNECTED);
    /* garbage after the handshake, an empty datagram, one that is too large: dropped, the session lives on */
    memset(buf, 0x5A, 60);
    CHECK_EQ_INT(noshi_dtls_input(c, buf, 60), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_input(c, buf, 0), NOSHI_OK);
    memset(big, 0, sizeof(big));
    CHECK_EQ_INT(noshi_dtls_input(c, big, sizeof(big)), NOSHI_E_LIMIT);
    CHECK_EQ_INT(noshi_dtls_input(c, NULL, 5), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_dtls_get_state(c), NOSHI_DTLS_CONNECTED);
    CHECK_EQ_INT(noshi_dtls_write(c, (const uint8_t *)"still here", 10), NOSHI_OK);
    pump(c, s, NULL);
    CHECK_EQ_INT(noshi_dtls_read(s, buf, sizeof(buf), &n), NOSHI_OK);
    CHECK_EQ_INT(n, 10);
    /* poll with no datagram, with a small buffer */
    CHECK_EQ_INT(noshi_dtls_poll(c, buf, sizeof(buf), &n), NOSHI_E_RETRY);
    CHECK_EQ_INT(n, 0);
    CHECK_EQ_INT(noshi_dtls_write(c, (const uint8_t *)"abc", 3), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_poll(c, buf, 10, &n), NOSHI_E_LIMIT);
    CHECK_EQ_INT(noshi_dtls_poll(c, buf, sizeof(buf), &n), NOSHI_OK);
    CHECK_EQ_INT(noshi_dtls_poll(NULL, buf, sizeof(buf), &n), NOSHI_E_ARG);
    noshi_dtls_free(c);
    noshi_dtls_free(s);

    /* more datagrams than the queue holds before the start: the extra ones are refused, not lost silently */
    {
        noshi_dtls *d;
        int i, refused = 0;
        CHECK_EQ_INT(noshi_dtls_new(&d), NOSHI_OK);
        for (i = 0; i < 40; ++i) if (noshi_dtls_input(d, buf, 50) == NOSHI_E_LIMIT) ++refused;
        CHECK_EQ_INT(refused, 8);
        noshi_dtls_free(d);
    }
}

int main(void) {
    handshake_and_keys();
    application_data();
    wrong_or_missing_fingerprint();
    fingerprint_parsing();
    early_and_damaged_input();
    loss_and_retransmission();
    return test_finish("test_dtls");
}
