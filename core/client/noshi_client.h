#ifndef NOSHI_CLIENT_H
#define NOSHI_CLIENT_H

#include "noshi_auth.h"
#include "noshi_people.h"
#include "noshi_typing.h"
#include "noshi_updates.h"

typedef struct noshi_client_events {
    void *ctx;
    noshi_status (*send)(void *ctx, int32_t dc, const uint8_t *data, size_t len);
    noshi_status (*load_session)(void *ctx, int32_t dc, noshi_mt_session_state *session);
    noshi_status (*save_session)(void *ctx, int32_t dc, const noshi_mt_session_state *session);
    void (*auth)(void *ctx, noshi_auth_state state, noshi_status status,
                 const noshi_tl_value *value, const char *error);
    void (*result)(void *ctx, uint64_t id, const noshi_mt_rpc_result *result);
    void (*changed)(void *ctx);
    void (*recover_history)(void *ctx, int64_t channel);
    /* a PhoneCall carried by an updatePhoneCall, in a push or in the answer to a call request; valid only during the callback */
    void (*phone_call)(void *ctx, const noshi_tl_value *phone_call);
    /* the signaling bytes of the other phone in an updatePhoneCallSignalingData; valid only during the callback */
    void (*phone_signaling)(void *ctx, int64_t phone_call_id, const uint8_t *data, size_t len);
    void (*error)(void *ctx, noshi_status status, const char *boundary);
    /* someone starts or stops typing, recording or sending something in a chat; live only, never kept */
    void (*typing)(void *ctx, const noshi_typing *typing);
    /* the other side read our messages of a chat up to max_id (updateReadHistoryOutbox, updateReadChannelOutbox);
       peer_kind is 1 for a user, 2 for a basic group, 3 for a channel; live only */
    void (*read_outbox)(void *ctx, int32_t peer_kind, int64_t peer_id, int32_t topic_id, int32_t max_id);
    /* a person came online or went offline (updateUserStatus); seen is the time they left, zero for any other state; live only, the stored user is updated by the updates layer */
    void (*user_status)(void *ctx, int64_t user_id, noshi_presence presence, int32_t seen);
    /* the draft of a chat changed, here or on another client (updateDraftMessage); read it with noshi_draft_update_read, valid only during the callback;
       live only, the account keeps the draft */
    void (*draft)(void *ctx, const noshi_tl_value *update);
    /* a message that arrived live (updateNewMessage, updateNewChannelMessage, or a short update turned into the message it stands for); users are those of the container
       it came in, or NULL when it came alone; both are valid only during the callback */
    void (*new_message)(void *ctx, const noshi_tl_value *message, const noshi_tl_value *users, const noshi_tl_value *chats);
    /* folder rules or their order changed on another client; one event per update container */
    void (*folders_changed)(void *ctx);
    /* an updateGroupCall, updateGroupCallParticipants or updateGroupCallConnection, in a push or in the answer to a request of the call; container is the Updates
       object it came in, which carries the users the participants refer to; both are valid only during the callback */
    void (*group_call)(void *ctx, const noshi_tl_value *update, const noshi_tl_value *container);
} noshi_client_events;

typedef struct noshi_client {
    noshi_mt_client mt;
    noshi_auth auth;
    noshi_updates updates;
    noshi_client_events events;
    noshi_mt_client_config config;
    noshi_store *store;
    int64_t account;
    uint64_t request_seq;
    uint64_t auth_wire_id;
    uint64_t auth_local_id;
    uint64_t sync_id;
    int64_t sync_channel;
    uint32_t sync_method;
    uint64_t outbox_id;
    int64_t outbox_random;
    int sync_suspended;
    /* the pause came from a failed request (flood wait, timeout, a link lost in flight), which a later try can pass; a pause without it needs the caller's resume */
    int sync_retry;
    int sync_again;
    /* set while the changed event of a quiet container runs (see noshi_updates_quiet); the event handler may read it */
    int change_quiet;
    /* set with change_quiet when the quiet container still moves the ticks of the chat list */
    int change_list;
    int change_rpc_cache;
    int authorized;
    int closing;
    noshi_status session_error;
} noshi_client;

noshi_status noshi_client_init(noshi_client *c, const noshi_mt_client_config *config,
                                  const char *api_hash, const noshi_client_events *events);
void noshi_client_free(noshi_client *c);
/* client callbacks can still access the store during teardown */
noshi_status noshi_client_attach_store(noshi_client *c, noshi_store *store, int64_t account_id);
noshi_status noshi_client_connect(noshi_client *c);
void noshi_client_disconnected(noshi_client *c);
noshi_status noshi_client_migrate(noshi_client *c, int32_t dc);
noshi_status noshi_client_feed(noshi_client *c, const uint8_t *data, size_t len);
noshi_status noshi_client_tick(noshi_client *c, uint32_t *next_ms);
noshi_status noshi_client_request(noshi_client *c, const noshi_tl_value *request,
                                     uint32_t timeout_ms, uint64_t *id);
noshi_status noshi_client_send(noshi_client *c, noshi_peer peer, const noshi_tl_value *request);
/* lifts a pause of the update sync; the owner calls it after a delay, since a failed difference left alone stops every new message of the account until restart */
void noshi_client_resume_sync(noshi_client *c);

#endif
