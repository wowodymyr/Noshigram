#ifndef NOSHI_TGC_ICE_H
#define NOSHI_TGC_ICE_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_tgc_reflector.h"
#include "noshi_tgc_stun.h"
#include "noshi_tgc_turn.h"

/* the connection a call makes through the Telegram reflectors and TURN servers, as an ICE agent (RFC 8445) that
   knows two kinds of path */

#define NOSHI_TGC_ICE_MAX_REFLECTORS 8
#define NOSHI_TGC_ICE_MAX_TURNS 3
#define NOSHI_TGC_ICE_MAX_PAIRS 96
#define NOSHI_TGC_ICE_UFRAG_MAX 64
#define NOSHI_TGC_ICE_PWD_MAX 128
#define NOSHI_TGC_ICE_LOCAL_PRIORITY 41885439u
#define NOSHI_TGC_ICE_HELLO_FAST_MS 500
#define NOSHI_TGC_ICE_HELLO_SLOW_MS 10000
#define NOSHI_TGC_ICE_KEEPALIVE_MS 2000
#define NOSHI_TGC_ICE_SILENCE_MS 10000

typedef enum noshi_tgc_ice_state {
    NOSHI_TGC_ICE_NEW,
    NOSHI_TGC_ICE_CHECKING,
    NOSHI_TGC_ICE_CONNECTED,
    NOSHI_TGC_ICE_DISCONNECTED    /* was connected; nothing has come on the nominated pair for a while */
} noshi_tgc_ice_state;

typedef struct noshi_tgc_ice_reflector_config {
    uint8_t server_id;
    uint8_t peer_tag[NOSHI_TGC_PEER_TAG_LEN];
    uint32_t local_tag;
    uint8_t tcp;
    uint16_t port;
    /* the address of the server, which is what the other phone sees as the source of every packet that comes through it and what the answers to its
       checks name as the mapped address */
    uint8_t ipv6;
    uint8_t address[16];
} noshi_tgc_ice_reflector_config;

typedef struct noshi_tgc_ice_events {
    void *context;
    /* a datagram for the socket of reflector number index */
    void (*send)(void *context, unsigned index, const uint8_t *data, size_t len);
    /* the candidate line to hand to the other phone in a Candidates message, once its server has answered */
    void (*local_candidate)(void *context, const char *sdp);
    void (*state)(void *context, noshi_tgc_ice_state state);
    /* a datagram that is not STUN, from a pair that has proved itself */
    void (*payload)(void *context, const uint8_t *data, size_t len);
    /* optional: one line of what the agent does, for the log of a call; never holds a key or a password */
    void (*trace)(void *context, const char *line);
} noshi_tgc_ice_events;

typedef struct noshi_tgc_ice_pair {
    uint8_t used;
    /* a pair through one of our TURN allocations; otherwise reflector is the number of our reflector and
       remote_tag the tag of the other phone */
    uint8_t turn;
    uint8_t server;
    uint32_t remote_ip;
    uint16_t remote_port;
    uint8_t reflector;
    uint32_t remote_tag;
    uint32_t remote_priority;
    uint8_t state;              /* 0 waiting, 1 checking, 2 succeeded */
    uint8_t valid;              /* a check of ours was answered, or a check of theirs was authenticated and answered */
    uint8_t nominated;
    uint8_t nominate_wanted;    /* controlling: the next check carries USE-CANDIDATE. controlled: USE-CANDIDATE came, waiting for the pair to be valid */
    uint8_t triggered;
    uint8_t tries;
    uint8_t outstanding;
    uint8_t outstanding_nominating;
    uint8_t txid[NOSHI_STUN_TXID_LEN];
    uint64_t last_tx_ms;
    uint64_t last_rx_ms;
    uint64_t gave_up_ms;
} noshi_tgc_ice_pair;

typedef struct noshi_tgc_ice_reflector {
    noshi_tgc_reflector wire;
    noshi_tgc_ice_reflector_config config;
    uint8_t announced;
    uint64_t last_hello_ms;
    uint8_t hello_sent;
} noshi_tgc_ice_reflector;

typedef struct noshi_tgc_ice_turn_link {
    struct noshi_tgc_ice *ice;
    unsigned index;
} noshi_tgc_ice_turn_link;

typedef struct noshi_tgc_ice {
    noshi_tgc_ice_events events;
    uint8_t controlling;
    uint64_t tie_breaker;
    char local_ufrag[NOSHI_TGC_ICE_UFRAG_MAX];
    char local_pwd[NOSHI_TGC_ICE_PWD_MAX];
    char remote_ufrag[NOSHI_TGC_ICE_UFRAG_MAX];
    char remote_pwd[NOSHI_TGC_ICE_PWD_MAX];
    uint8_t has_remote;
    uint8_t reflector_count;
    noshi_tgc_ice_reflector reflectors[NOSHI_TGC_ICE_MAX_REFLECTORS];
    uint8_t turn_count;
    noshi_tgc_turn turns[NOSHI_TGC_ICE_MAX_TURNS];
    noshi_tgc_ice_turn_link turn_links[NOSHI_TGC_ICE_MAX_TURNS];
    uint8_t turn_announced[NOSHI_TGC_ICE_MAX_TURNS];
    noshi_tgc_ice_pair pairs[NOSHI_TGC_ICE_MAX_PAIRS];
    int selected;               /* index into pairs, -1 when none */
    noshi_tgc_ice_state state;
    uint64_t last_check_ms;
    uint8_t started;
    uint8_t direct_mode;
    unsigned rejected_stun;
    unsigned stun_in;
} noshi_tgc_ice;

/* ufrag of 4 to 63 characters and password of 22 to 127, as ICE requires; controlling for the side that placed the
   call; tie_breaker random */
noshi_status noshi_tgc_ice_init(noshi_tgc_ice *ice, int controlling, uint64_t tie_breaker, const char *local_ufrag, const char *local_pwd,
                                    const noshi_tgc_ice_reflector_config *reflectors, size_t reflector_count, const noshi_tgc_ice_events *events);

/* direct mode uses one connected UDP socket per candidate, indexed by the returned path */
noshi_status noshi_tgc_ice_init_direct(noshi_tgc_ice *ice, int controlling, uint64_t tie_breaker, const char *local_ufrag, const char *local_pwd,
                                           const noshi_tgc_ice_events *events);
noshi_status noshi_tgc_ice_add_direct(noshi_tgc_ice *ice, uint32_t ip, uint16_t port, uint32_t priority, unsigned *index);

/* a TURN server of the call (IPv4, host order); call it after init and before the first tick */
noshi_status noshi_tgc_ice_add_turn(noshi_tgc_ice *ice, uint32_t ip, uint16_t port, const char *username, const char *password);

/* the credentials of the other phone, from its InitialSetup */
noshi_status noshi_tgc_ice_set_remote(noshi_tgc_ice *ice, const char *ufrag, const char *pwd);

/* a candidate line of the other phone: a reflector candidate pairs with the reflector that serves it; an IPv4 UDP
   candidate of type host, srflx */
noshi_status noshi_tgc_ice_add_remote_candidate(noshi_tgc_ice *ice, const char *sdp, uint64_t now_ms);

/* a datagram from the socket of reflector number index, or of TURN server index - reflector_count */
noshi_status noshi_tgc_ice_input(noshi_tgc_ice *ice, unsigned index, const uint8_t *data, size_t len, uint64_t now_ms);

/* run the timers: hellos, checks, retransmissions, keepalives, silence; call it every 50 ms or so */
void noshi_tgc_ice_tick(noshi_tgc_ice *ice, uint64_t now_ms);

/* send a datagram (DTLS, SRTP or SCTP bytes) over the nominated pair; NOSHI_E_STATE when there is none */
noshi_status noshi_tgc_ice_send(noshi_tgc_ice *ice, const uint8_t *data, size_t len);

/* the reflector and remote tag of the nominated pair, for the statistics; false when none */
int noshi_tgc_ice_selected(const noshi_tgc_ice *ice, unsigned *reflector, uint32_t *remote_tag);

#endif
