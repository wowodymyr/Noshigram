#ifndef NOSHI_MT_CLIENT_H
#define NOSHI_MT_CLIENT_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_arena.h"
#include "noshi_bytes.h"
#include "noshi_clock.h"
#include "noshi_mt_handshake.h"
#include "noshi_mt_msg.h"
#include "noshi_mt_transport.h"
#include "noshi_status.h"
#include "noshi_tl.h"

#define NOSHI_MT_ACK_MAX 256
#define NOSHI_MT_SEEN_MAX 1024
#define NOSHI_MT_CONTAINER_RING 16
#define NOSHI_MT_CONTAINER_INNER 64

typedef enum noshi_mt_client_state {
    NOSHI_MT_CLIENT_DISCONNECTED = 0,
    NOSHI_MT_CLIENT_HANDSHAKE,
    NOSHI_MT_CLIENT_READY,
    NOSHI_MT_CLIENT_DEAD
} noshi_mt_client_state;

typedef struct noshi_mt_session_state {
    uint8_t auth_key[NOSHI_MT_AUTH_KEY_LEN];
    uint64_t server_salt;
    int64_t time_offset_ms;
} noshi_mt_session_state;

typedef struct noshi_mt_rpc_result {
    noshi_status status;
    const noshi_tl_value *value;
    int32_t error_code;
    const char *error_text;
    uint64_t msg_id;
} noshi_mt_rpc_result;

typedef struct noshi_mt_client_events {
    void *ctx;
    void (*send)(void *ctx, const uint8_t *data, size_t len);
    void (*rpc_result)(void *ctx, uint64_t request_id, const noshi_mt_rpc_result *result);
    /* the decode arena is freed after delivery, retained updates need a copy */
    void (*update)(void *ctx, const noshi_tl_value *updates);
    /* an undecodable update leaves a gap that needs a difference request */
    void (*update_lost)(void *ctx, noshi_status reason);
    /* the server started a fresh session for this key, events sent before it may be missing */
    void (*new_session)(void *ctx);
    void (*state)(void *ctx, noshi_mt_client_state state, noshi_status reason);
    /* reconnect must restore the same key, salt and clock offset */
    void (*session_changed)(void *ctx, const noshi_mt_session_state *session);
    noshi_status (*send_checked)(void *ctx, const uint8_t *data, size_t len);
} noshi_mt_client_events;

typedef struct noshi_mt_client_config {
    int dc_id;
    int is_test;
    noshi_mt_transport_kind transport;
    noshi_mt_obfuscation obfuscation;
    const noshi_clock *clock;
    const noshi_mt_rsa_key *keys;
    size_t key_count;
    const noshi_mt_session_state *restore;
    int32_t api_id;
    const char *device_model;
    const char *system_version;
    const char *app_version;
    const char *system_lang_code;
    const char *lang_pack;
    const char *lang_code;
    uint32_t max_pending;
    uint32_t result_arena_limit;
    uint32_t ping_interval_ms;
    uint32_t pong_timeout_ms;
} noshi_mt_client_config;

typedef struct noshi_mt_pending noshi_mt_pending;

typedef struct noshi_mt_container_rec {
    uint64_t id;
    uint32_t count;
    uint64_t inner[NOSHI_MT_CONTAINER_INNER];
} noshi_mt_container_rec;

typedef struct noshi_mt_salt {
    int32_t since;
    int32_t until;
    uint64_t value;
} noshi_mt_salt;

typedef struct noshi_mt_client {
    noshi_mt_client_config config;
    noshi_mt_client_events events;
    noshi_mt_client_state state;
    noshi_mt_transport transport;
    noshi_mt_handshake handshake;
    noshi_mt_auth_key key;
    int has_key;
    uint64_t salt;
    noshi_mt_salt salts[64];
    uint32_t salt_count;
    int64_t time_offset_ms;
    uint64_t session_id;
    uint64_t last_msg_id;
    uint32_t seq_count;
    noshi_mt_pending *pending;
    uint32_t pending_count;
    uint32_t pending_cap;
    uint64_t acks[NOSHI_MT_ACK_MAX];
    uint32_t ack_count;
    uint64_t seen[NOSHI_MT_SEEN_MAX];
    uint32_t seen_pos;
    noshi_mt_container_rec containers[NOSHI_MT_CONTAINER_RING];
    uint32_t container_pos;
    int init_confirmed;
    uint8_t *init_prefix;
    size_t init_prefix_len;
    uint64_t last_rx_ms;
    uint64_t ping_id;
    uint64_t ping_sent_ms;
    int awaiting_pong;
    int32_t transport_error;
    /* the constructor of the message being handled when the link last failed, for the log */
    uint32_t last_ctor;
    /* why the last frame from the server was refused, and a number that goes with it (the gap to the server's clock in
       milliseconds for a message time, otherwise zero), for the log */
    const char *security_note;
    int64_t security_value;
    /* set once a frame of this link has been accepted, which tells a link that works from one that connects and fails */
    int heard;
    int in_feed;
    int flush_wanted;
    unsigned operation_depth;
    int closing;
} noshi_mt_client;

noshi_status noshi_mt_client_init(noshi_mt_client *c, const noshi_mt_client_config *config,
                                      const noshi_mt_client_events *events);
/* teardown must resolve pending requests instead of leaving their owners waiting */
void noshi_mt_client_free(noshi_mt_client *c);

/* the longest device model, system version or app version, in bytes */
#define NOSHI_MT_DEVICE_TEXT_MAX 128
/* tells the server another device model, system version and app version, with the next request that goes out. the strings are borrowed like the ones
   of the config and must outlive the client or the next call; a model or system version that is empty or longer than NOSHI_MT_DEVICE_TEXT_MAX is
   NOSHI_E_ARG and leaves the old ones in force. a client made without an api_id sends no metadata, so this changes nothing there */
noshi_status noshi_mt_client_set_device(noshi_mt_client *c, const char *device_model, const char *system_version, const char *app_version);
noshi_status noshi_mt_client_connect(noshi_mt_client *c);
/* a socket failure must not discard requests needed after reconnect */
void noshi_mt_client_disconnected(noshi_mt_client *c);
noshi_status noshi_mt_client_feed(noshi_mt_client *c, const uint8_t *data, size_t len);

noshi_status noshi_mt_client_submit(noshi_mt_client *c, uint64_t request_id, const noshi_tl_value *request,
                                        uint32_t timeout_ms);
noshi_status noshi_mt_client_cancel(noshi_mt_client *c, uint64_t request_id);

uint32_t noshi_mt_client_tick(noshi_mt_client *c);

int noshi_mt_client_get_session(const noshi_mt_client *c, noshi_mt_session_state *out);
int32_t noshi_mt_client_transport_error(const noshi_mt_client *c);
uint32_t noshi_mt_client_last_ctor(const noshi_mt_client *c);
/* the reason the last frame was refused as unsafe, null when none was, and its number */
const char *noshi_mt_client_security_note(const noshi_mt_client *c, int64_t *value);
/* whether this link has accepted a frame from the server since it connected */
int noshi_mt_client_heard(const noshi_mt_client *c);
#define NOSHI_MT_PING_INTERVAL_DEFAULT 30000u
/* how long a quiet link waits before it pings, kept between 10 and 300 seconds */
void noshi_mt_client_set_ping_interval(noshi_mt_client *c, uint32_t interval_ms);
uint32_t noshi_mt_client_ping_interval(const noshi_mt_client *c);
uint32_t noshi_mt_client_pending_count(const noshi_mt_client *c);

void noshi_mt_rpc_error_split(const char *text, char *name, size_t name_cap, int32_t *number);

#endif
