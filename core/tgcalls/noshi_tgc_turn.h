#ifndef NOSHI_TGC_TURN_H
#define NOSHI_TGC_TURN_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the part of a TURN client (RFC 5766, over UDP, with the long term credentials of RFC 5389) that a call needs */

#define NOSHI_TGC_TURN_USERNAME_MAX 128
#define NOSHI_TGC_TURN_PASSWORD_MAX 128
#define NOSHI_TGC_TURN_REALM_MAX 128
#define NOSHI_TGC_TURN_NONCE_MAX 128
#define NOSHI_TGC_TURN_MAX_PERMISSIONS 24
#define NOSHI_TGC_TURN_MAX_REQUESTS 8
#define NOSHI_TGC_TURN_MAX_MESSAGE 600
/* the largest datagram wrapped in a Send indication: a Send indication adds a 20 byte header and two attributes (12 and 4 bytes of their own) to it */
#define NOSHI_TGC_TURN_MAX_PAYLOAD 1200
#define NOSHI_TGC_TURN_WRAP_OVERHEAD 36

typedef enum noshi_tgc_turn_state {
    NOSHI_TGC_TURN_IDLE = 0,
    NOSHI_TGC_TURN_ALLOCATING,
    NOSHI_TGC_TURN_READY,
    NOSHI_TGC_TURN_FAILED
} noshi_tgc_turn_state;

typedef struct noshi_tgc_turn_events {
    void *context;
    /* a datagram for the TURN server */
    void (*send)(void *context, const uint8_t *data, size_t len);
    /* optional: one line of what the client does, for the log of a call; never holds the password or the key */
    void (*trace)(void *context, const char *line);
} noshi_tgc_turn_events;

typedef struct noshi_tgc_turn_request {
    uint8_t used;
    uint8_t kind;               /* 1 allocate, 2 refresh, 3 permission */
    uint8_t authenticated;
    uint8_t tries;
    uint8_t permission;         /* the slot a permission request is for */
    uint8_t txid[12];
    uint16_t len;
    uint8_t message[NOSHI_TGC_TURN_MAX_MESSAGE];
    uint64_t last_tx_ms;
} noshi_tgc_turn_request;

typedef struct noshi_tgc_turn_permission {
    uint8_t state;              /* 0 wanted, 1 asked, 2 granted, 3 refused */
    uint8_t renewing;
    uint32_t ip;
    uint64_t granted_ms;
} noshi_tgc_turn_permission;

typedef struct noshi_tgc_turn {
    noshi_tgc_turn_events events;
    uint32_t server_ip;
    uint16_t server_port;
    char username[NOSHI_TGC_TURN_USERNAME_MAX];
    char password[NOSHI_TGC_TURN_PASSWORD_MAX];
    noshi_tgc_turn_state state;
    char realm[NOSHI_TGC_TURN_REALM_MAX];
    uint8_t nonce[NOSHI_TGC_TURN_NONCE_MAX];
    size_t nonce_len;
    uint8_t key[16];
    uint8_t has_key;
    uint32_t relay_ip;
    uint16_t relay_port;
    uint32_t mapped_ip;
    uint16_t mapped_port;
    uint32_t lifetime_s;
    uint64_t refresh_due_ms;
    uint8_t started;
    unsigned data_in, data_out;
    noshi_tgc_turn_request requests[NOSHI_TGC_TURN_MAX_REQUESTS];
    noshi_tgc_turn_permission permissions[NOSHI_TGC_TURN_MAX_PERMISSIONS];
} noshi_tgc_turn;

typedef enum noshi_tgc_turn_kind {
    NOSHI_TGC_TURN_INPUT_NONE = 0,    /* the packet was for the client itself, or was dropped */
    NOSHI_TGC_TURN_INPUT_READY,       /* the allocation just succeeded: the relay address is known */
    NOSHI_TGC_TURN_INPUT_DATA         /* a datagram of the other phone: peer_ip, peer_port and data */
} noshi_tgc_turn_kind;

typedef struct noshi_tgc_turn_output {
    noshi_tgc_turn_kind kind;
    uint32_t peer_ip;
    uint16_t peer_port;
    const uint8_t *data;
    size_t len;
} noshi_tgc_turn_output;

/* NOSHI_E_ARG for a missing address, port or name, or names too long for the fields */
noshi_status noshi_tgc_turn_init(noshi_tgc_turn *t, uint32_t server_ip, uint16_t server_port, const char *username, const char *password,
                                     const noshi_tgc_turn_events *events);

/* the allocation, its refresh, the permissions and the retransmissions of all of those; call it every 50 ms or so */
void noshi_tgc_turn_tick(noshi_tgc_turn *t, uint64_t now_ms);

/* a datagram from the server. out is always initialised */
noshi_status noshi_tgc_turn_input(noshi_tgc_turn *t, const uint8_t *packet, size_t len, uint64_t now_ms, noshi_tgc_turn_output *out);

int noshi_tgc_turn_ready(const noshi_tgc_turn *t);
/* the relayed address and the address the server saw this client at; false before the allocation succeeded */
int noshi_tgc_turn_relayed(const noshi_tgc_turn *t, uint32_t *relay_ip, uint16_t *relay_port, uint32_t *mapped_ip, uint16_t *mapped_port);

/* wants a permission for ip */
int noshi_tgc_turn_permit(noshi_tgc_turn *t, uint32_t ip);

/* a Send indication for payload to ip:port; NOSHI_E_STATE when the allocation is not ready, NOSHI_E_LIMIT for
   a payload over NOSHI_TGC_TURN_MAX_PAYLOAD or a buffer that is too small */
noshi_status noshi_tgc_turn_wrap(noshi_tgc_turn *t, uint32_t ip, uint16_t port, const uint8_t *payload, size_t len, uint8_t *out, size_t capacity,
                                     size_t *out_len);

#endif
