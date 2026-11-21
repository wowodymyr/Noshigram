#include "noshi_client.h"

#include <string.h>

#include "noshi_tl_ids.h"

static void report(noshi_client *c, noshi_status status, const char *boundary) {
    if (status != NOSHI_OK && c->events.error) c->events.error(c->events.ctx, status, boundary);
}

static uint64_t request_id(noshi_client *c) {
    if (!++c->request_seq) ++c->request_seq;
    return c->request_seq;
}

static noshi_status send_bytes(void *ctx, const uint8_t *data, size_t len) {
    noshi_client *c = ctx;
    if (c->closing || c->session_error != NOSHI_OK) return NOSHI_E_STATE;
    return c->events.send(c->events.ctx, c->config.dc_id, data, len);
}

static void save_session(void *ctx, const noshi_mt_session_state *session) {
    noshi_client *c = ctx;
    c->session_error = c->events.save_session(c->events.ctx, c->config.dc_id, session);
    report(c, c->session_error, "session storage");
}

static noshi_status auth_submit(void *ctx, uint64_t id, const noshi_tl_value *request) {
    noshi_client *c = ctx;
    if (c->closing) return NOSHI_E_STATE;
    c->auth_local_id = id;
    c->auth_wire_id = request_id(c);
    noshi_status status = noshi_mt_client_submit(&c->mt, c->auth_wire_id, request, 60000);
    if (status != NOSHI_OK) {
        noshi_status cancelled = noshi_mt_client_cancel(&c->mt, c->auth_wire_id);
        if (cancelled != NOSHI_E_NOTFOUND) report(c, cancelled, "auth submit cleanup");
        c->auth_wire_id = 0;
    }
    return status;
}

static void auth_cancel(void *ctx, uint64_t id) {
    noshi_client *c = ctx;
    if (id == c->auth_local_id && c->auth_wire_id) {
        noshi_status status = noshi_mt_client_cancel(&c->mt, c->auth_wire_id);
        if (status != NOSHI_E_NOTFOUND) report(c, status, "auth cancel");
        c->auth_wire_id = 0;
    }
}

static void auth_changed(void *ctx, noshi_auth_state state, noshi_status status,
                          const noshi_tl_value *value, const char *error) {
    noshi_client *c = ctx;
    if (state == NOSHI_AUTH_AUTHORIZED) {
        int64_t account;
        if (noshi_tl_get_i64(noshi_tl_get(value, "user"), "id", &account) != NOSHI_OK || account <= 0 ||
            (c->store && c->account != account)) { report(c, NOSHI_E_SECURITY, "account identity"); return; }
        c->account = account;
        c->authorized = 1;
    }
    if (c->events.auth && !c->closing) c->events.auth(c->events.ctx, state, status, value, error);
}

static int is_updates(const noshi_tl_value *v) {
    const char *type;
    if (!v || v->kind != NOSHI_TL_V_OBJ) return 0;
    type = noshi_tl_result_type_name(v->u.obj.ctor);
    return type && !strcmp(type, "Updates");
}

static void deliver_signaling(noshi_client *c, const noshi_tl_value *update) {
    int64_t id = 0;
    const uint8_t *data = NULL;
    size_t len = 0;
    if (!c->events.phone_signaling) return;
    if (noshi_tl_get_i64(update, "phone_call_id", &id) != NOSHI_OK || noshi_tl_get_bytes(update, "data", &data, &len) != NOSHI_OK || !data || len == 0) return;
    c->events.phone_signaling(c->events.ctx, id, data, len);
}

static int group_call_update(const noshi_tl_value *item) {
    return noshi_tl_is(item, NOSHI_TL_ID_updateGroupCall) || noshi_tl_is(item, NOSHI_TL_ID_updateGroupCallParticipants) ||
           noshi_tl_is(item, NOSHI_TL_ID_updateGroupCallConnection);
}

static void deliver_group_call(noshi_client *c, const noshi_tl_value *item, const noshi_tl_value *container) {
    if (c->events.group_call && group_call_update(item)) c->events.group_call(c->events.ctx, item, container);
}

static void deliver_typing(noshi_client *c, const noshi_tl_value *item) {
    noshi_typing typing;
    if (c->events.typing && noshi_typing_read(item, &typing)) c->events.typing(c->events.ctx, &typing);
}

static void deliver_read_outbox(noshi_client *c, const noshi_tl_value *item) {
    noshi_peer peer;
    int32_t max_id = 0, topic_id = 0;
    int64_t channel = 0;
    if (!c->events.read_outbox) return;
    if (noshi_tl_is(item, NOSHI_TL_ID_updateReadHistoryOutbox)) {
        if (noshi_peer_from_tl(noshi_tl_get(item, "peer"), &peer) != NOSHI_OK || noshi_tl_get_i32(item, "max_id", &max_id) != NOSHI_OK) return;
    } else if (noshi_tl_is(item, NOSHI_TL_ID_updateReadChannelOutbox)) {
        if (noshi_tl_get_i64(item, "channel_id", &channel) != NOSHI_OK || noshi_tl_get_i32(item, "max_id", &max_id) != NOSHI_OK) return;
        peer.kind = 3;
        peer.id = channel;
    } else if (noshi_tl_is(item, NOSHI_TL_ID_updateReadChannelDiscussionOutbox)) {
        /* a forum reports what was read of one topic here, with the id of the topic as top_msg_id; the channel wide update says nothing of a single topic */
        if (noshi_tl_get_i64(item, "channel_id", &channel) != NOSHI_OK || noshi_tl_get_i32(item, "top_msg_id", &topic_id) != NOSHI_OK ||
            noshi_tl_get_i32(item, "read_max_id", &max_id) != NOSHI_OK || topic_id <= 0) return;
        peer.kind = 3;
        peer.id = channel;
    } else return;
    if (max_id > 0 && peer.id > 0) c->events.read_outbox(c->events.ctx, peer.kind, peer.id, topic_id, max_id);
}

/* a read receipt that came while the socket was down arrives in the other_updates of the difference, not as a live update */
static void deliver_difference_reads(noshi_client *c, const noshi_tl_value *difference) {
    const noshi_tl_value *vec = noshi_tl_get(difference, "other_updates");
    uint32_t i;
    for (i = 0; vec && vec->kind == NOSHI_TL_V_VEC && i < vec->u.vec.count; ++i) deliver_read_outbox(c, vec->u.vec.items[i]);
}

static void deliver_new_message(noshi_client *c, const noshi_tl_value *item, const noshi_tl_value *container) {
    const noshi_tl_value *users = container ? noshi_tl_get(container, "users") : NULL;
    const noshi_tl_value *chats = container ? noshi_tl_get(container, "chats") : NULL;
    if (!c->events.new_message) return;
    if (noshi_tl_is(item, NOSHI_TL_ID_updateNewMessage) || noshi_tl_is(item, NOSHI_TL_ID_updateNewChannelMessage)) {
        c->events.new_message(c->events.ctx, noshi_tl_get(item, "message"), users, chats);
    } else if (noshi_tl_is(item, NOSHI_TL_ID_updateShortMessage) || noshi_tl_is(item, NOSHI_TL_ID_updateShortChatMessage)) {
        noshi_arena arena;
        noshi_tl_value *message = NULL;
        noshi_arena_init(&arena, 65536);
        if (noshi_updates_short_to_message(&arena, c->updates.account, item, &message) == NOSHI_OK) c->events.new_message(c->events.ctx, message, NULL, NULL);
        noshi_arena_free(&arena);
    }
}

static void deliver_user_status(noshi_client *c, const noshi_tl_value *item) {
    noshi_presence presence;
    int64_t user_id;
    int32_t seen;
    if (!c->events.user_status || !noshi_tl_is(item, NOSHI_TL_ID_updateUserStatus)) return;
    if (noshi_tl_get_i64(item, "user_id", &user_id) != NOSHI_OK || user_id <= 0) return;
    noshi_presence_read(noshi_tl_get(item, "status"), &presence, &seen);
    c->events.user_status(c->events.ctx, user_id, presence, seen);
}

static void deliver_draft(noshi_client *c, const noshi_tl_value *item) {
    if (c->events.draft && noshi_tl_is(item, NOSHI_TL_ID_updateDraftMessage)) c->events.draft(c->events.ctx, item);
}

static int folder_update(const noshi_tl_value *value) {
    return noshi_tl_is(value, NOSHI_TL_ID_updateDialogFilter) || noshi_tl_is(value, NOSHI_TL_ID_updateDialogFilterOrder) ||
           noshi_tl_is(value, NOSHI_TL_ID_updateDialogFilters);
}

/* calls, typing and folder changes have no stored message row */
static void dispatch_live_updates(noshi_client *c, const noshi_tl_value *v) {
    const noshi_tl_value *one = noshi_tl_get(v, "update"), *vec = noshi_tl_get(v, "updates");
    uint32_t i;
    int folders = folder_update(one);
    if (c->closing) return;
    if (noshi_tl_is(one, NOSHI_TL_ID_updatePhoneCall) && c->events.phone_call) c->events.phone_call(c->events.ctx, noshi_tl_get(one, "phone_call"));
    if (noshi_tl_is(one, NOSHI_TL_ID_updatePhoneCallSignalingData)) deliver_signaling(c, one);
    deliver_typing(c, one);
    deliver_read_outbox(c, one);
    deliver_new_message(c, one, NULL);
    deliver_new_message(c, v, NULL);
    deliver_user_status(c, one);
    deliver_draft(c, one);
    deliver_group_call(c, one, v);
    for (i = 0; vec && vec->kind == NOSHI_TL_V_VEC && i < vec->u.vec.count; ++i) {
        const noshi_tl_value *item = vec->u.vec.items[i];
        if (noshi_tl_is(item, NOSHI_TL_ID_updatePhoneCall) && c->events.phone_call) c->events.phone_call(c->events.ctx, noshi_tl_get(item, "phone_call"));
        if (noshi_tl_is(item, NOSHI_TL_ID_updatePhoneCallSignalingData)) deliver_signaling(c, item);
        deliver_typing(c, item);
        deliver_read_outbox(c, item);
        deliver_new_message(c, item, v);
        deliver_user_status(c, item);
        deliver_draft(c, item);
        deliver_group_call(c, item, v);
        if (folder_update(item)) folders = 1;
    }
    if (folders && c->events.folders_changed) c->events.folders_changed(c->events.ctx);
}

static void notify_changed(noshi_client *c) {
    if (c->events.changed && !c->closing) c->events.changed(c->events.ctx);
}

static void notify_changed_quiet(noshi_client *c, int quiet, int list) {
    c->change_quiet = quiet;
    c->change_list = list;
    notify_changed(c);
    c->change_quiet = 0;
    c->change_list = 0;
}

static void rpc_result(void *ctx, uint64_t id, const noshi_mt_rpc_result *r) {
    noshi_client *c = ctx;
    noshi_status status;
    if (c->closing) return;
    if (id == c->auth_wire_id) {
        uint64_t local_id = c->auth_local_id;
        c->auth_wire_id = 0;
        c->auth.server_time_offset_ms = c->mt.time_offset_ms;
        status = noshi_auth_result(&c->auth, local_id, r);
        if (status != NOSHI_E_RPC) report(c, status, "auth");
    } else if (id == c->sync_id) {
        c->sync_id = 0;
        status = r->status;
        if (status == NOSHI_OK) status = c->sync_method == NOSHI_TL_ID_updates_getState ?
            noshi_updates_state(&c->updates, r->value) : noshi_updates_difference(&c->updates, c->sync_channel, r->value);
        if (status != NOSHI_OK) {
            c->sync_suspended = 1;
            c->sync_retry = 1;
            report(c, status, "updates difference");
        } else {
            if (c->sync_again) {
                c->sync_again = 0;
                report(c, noshi_updates_need(&c->updates, 0), "updates recovery");
            }
            notify_changed(c);
            if (c->sync_method != NOSHI_TL_ID_updates_getState) deliver_difference_reads(c, r->value);
            if (c->updates.needs_history && c->events.recover_history) c->events.recover_history(c->events.ctx, c->sync_channel);
        }
    } else if (id == c->outbox_id) {
        c->outbox_id = 0;
        status = r->status;
        if (status == NOSHI_OK) status = noshi_updates_sent(&c->updates, c->outbox_random, r->value);
        if (status != NOSHI_OK && status != NOSHI_E_RETRY) {
            noshi_status saved = noshi_store_outbox_set(c->store, c->outbox_random, NOSHI_OUTBOX_FAILED, 0, (int32_t)status);
            report(c, saved, "outbox storage");
            report(c, status, "outbox send");
        }
        notify_changed(c);
    } else {
        if (c->store && r->status == NOSHI_OK) {
            status = is_updates(r->value) ? noshi_updates_apply(&c->updates, r->value) :
                                          noshi_updates_cache(&c->updates, r->value);
            if (status != NOSHI_E_RETRY) report(c, status, "rpc cache");
            if (status == NOSHI_OK) {
                c->change_rpc_cache = !is_updates(r->value);
                notify_changed(c);
                c->change_rpc_cache = 0;
            }
            if (is_updates(r->value)) dispatch_live_updates(c, r->value);
        }
        if (c->events.result) c->events.result(c->events.ctx, id, r);
    }
}

static void update(void *ctx, const noshi_tl_value *v) {
    noshi_client *c = ctx;
    noshi_status status;
    const noshi_tl_value *vec = noshi_tl_get(v, "updates");
    const noshi_tl_value *one = noshi_tl_get(v, "update");
    uint32_t i;
    if (c->auth.qr) {
        int token = noshi_tl_is(one, NOSHI_TL_ID_updateLoginToken);
        if (vec && vec->kind == NOSHI_TL_V_VEC)
            for (i = 0; i < vec->u.vec.count; ++i) if (noshi_tl_is(vec->u.vec.items[i], NOSHI_TL_ID_updateLoginToken)) token = 1;
        if (token) report(c, noshi_auth_qr_refresh(&c->auth), "qr refresh");
    }
    if (!c->store || !c->authorized || c->closing) return;
    if (c->sync_id) c->sync_again = 1;
    status = noshi_updates_apply(&c->updates, v);
    if (status != NOSHI_E_RETRY) report(c, status, "updates transaction");
    if (status == NOSHI_OK) notify_changed_quiet(c, noshi_updates_quiet(v), noshi_updates_list_visible(v));
    dispatch_live_updates(c, v);
}

static void lost(void *ctx, noshi_status reason) {
    noshi_client *c = ctx;
    report(c, noshi_updates_need(&c->updates, 0), "updates recovery");
    report(c, reason, "updates decode");
}

static void new_session(void *ctx) {
    noshi_client *c = ctx;
    report(c, noshi_updates_need(&c->updates, 0), "updates recovery");
}

static noshi_status init_transport(noshi_client *c) {
    noshi_mt_session_state restored;
    noshi_mt_client_events events;
    noshi_mt_client_config config = c->config;
    noshi_status status;
    memset(&events, 0, sizeof(events));
    memset(&restored, 0, sizeof(restored));
    events.ctx = c;
    events.send_checked = send_bytes;
    events.rpc_result = rpc_result;
    events.update = update;
    events.update_lost = lost;
    events.new_session = new_session;
    events.session_changed = save_session;
    status = c->events.load_session(c->events.ctx, c->config.dc_id, &restored);
    if (status != NOSHI_OK && status != NOSHI_E_NOTFOUND) { noshi_wipe(&restored, sizeof(restored)); return status; }
    config.restore = status == NOSHI_OK ? &restored : NULL;
    status = noshi_mt_client_init(&c->mt, &config, &events);
    noshi_wipe(&restored, sizeof(restored));
    return status;
}

noshi_status noshi_client_init(noshi_client *c, const noshi_mt_client_config *config,
                                  const char *api_hash, const noshi_client_events *events) {
    noshi_auth_events auth_events;
    noshi_status status;
    if (!c) return NOSHI_E_ARG;
    memset(c, 0, sizeof(*c));
    if (!config || config->api_id <= 0 || config->dc_id <= 0 || !events || !events->send ||
        !events->load_session || !events->save_session) return NOSHI_E_ARG;
    c->config = *config;
    c->config.restore = NULL;
    c->events = *events;
    if (!c->config.clock) c->config.clock = &noshi_system_clock;
    auth_events.ctx = c;
    auth_events.submit = auth_submit;
    auth_events.cancel = auth_cancel;
    auth_events.changed = auth_changed;
    status = noshi_auth_init(&c->auth, config->api_id, api_hash, config->clock, &auth_events);
    if (status == NOSHI_OK) status = init_transport(c);
    if (status != NOSHI_OK) noshi_client_free(c);
    return status;
}

void noshi_client_free(noshi_client *c) {
    if (!c || c->closing) return;
    c->closing = 1;
    noshi_auth_free(&c->auth);
    noshi_mt_client_free(&c->mt);
    c->store = NULL;
    c->authorized = 0;
}

noshi_status noshi_client_attach_store(noshi_client *c, noshi_store *store, int64_t account_id) {
    noshi_status status;
    if (!c || !store || account_id <= 0 || c->closing || c->outbox_id || c->sync_id ||
        (c->account && c->account != account_id)) return NOSHI_E_STATE;
    status = noshi_store_outbox_recover(store);
    if (status == NOSHI_OK) status = noshi_updates_init(&c->updates, store, account_id);
    if (status == NOSHI_OK) { c->store = store; c->account = account_id; c->authorized = 1; }
    return status;
}

noshi_status noshi_client_connect(noshi_client *c) {
    if (!c || c->closing || c->session_error != NOSHI_OK) return NOSHI_E_STATE;
    noshi_status status = noshi_mt_client_connect(&c->mt);
    if (status == NOSHI_OK && c->mt.state == NOSHI_MT_CLIENT_READY &&
        c->auth.state == NOSHI_AUTH_MIGRATE && c->config.dc_id == c->auth.migrate_dc)
        status = noshi_auth_resume(&c->auth);
    return status;
}

void noshi_client_disconnected(noshi_client *c) {
    if (!c || c->closing) return;
    noshi_mt_client_disconnected(&c->mt);
    new_session(c);
}

noshi_status noshi_client_migrate(noshi_client *c, int32_t dc) {
    noshi_status status;
    if (!c || dc <= 0 || c->closing || c->mt.operation_depth || c->auth.state != NOSHI_AUTH_MIGRATE ||
        dc != c->auth.migrate_dc) return NOSHI_E_STATE;
    c->auth_wire_id = 0;
    noshi_mt_client_free(&c->mt);
    c->config.dc_id = dc;
    /* the obfuscation header names the data center it is sent to */
    if (c->config.obfuscation.enabled) c->config.obfuscation.dc_id = (int16_t)dc;
    c->session_error = NOSHI_OK;
    status = init_transport(c);
    return status;
}

noshi_status noshi_client_feed(noshi_client *c, const uint8_t *data, size_t len) {
    noshi_status status;
    if (!c || c->closing) return NOSHI_E_STATE;
    status = noshi_mt_client_feed(&c->mt, data, len);
    if (c->session_error != NOSHI_OK) { noshi_client_disconnected(c); return c->session_error; }
    if (status == NOSHI_OK && c->mt.state == NOSHI_MT_CLIENT_READY &&
        c->auth.state == NOSHI_AUTH_MIGRATE && c->config.dc_id == c->auth.migrate_dc)
        status = noshi_auth_resume(&c->auth);
    return status;
}

noshi_status noshi_client_request(noshi_client *c, const noshi_tl_value *request,
                                     uint32_t timeout_ms, uint64_t *id) {
    if (!id) return NOSHI_E_ARG;
    *id = 0;
    if (!c || c->closing || !request) return NOSHI_E_STATE;
    *id = request_id(c);
    return noshi_mt_client_submit(&c->mt, *id, request, timeout_ms);
}

noshi_status noshi_client_send(noshi_client *c, noshi_peer peer, const noshi_tl_value *request) {
    noshi_status status;
    if (!c || !c->store || !c->authorized || c->closing) return NOSHI_E_STATE;
    status = noshi_store_outbox_add(c->store, peer, request);
    if (status == NOSHI_OK) notify_changed(c);
    return status;
}

void noshi_client_resume_sync(noshi_client *c) {
    if (!c) return;
    c->sync_suspended = 0;
    c->sync_retry = 0;
}

static noshi_status sync_start(noshi_client *c, noshi_arena *arena) {
    noshi_tl_value *channel = NULL, *request, *chat;
    noshi_status status;
    int64_t hash;
    int64_t id = c->updates.gap_channel;
    if (id) {
        noshi_peer peer = {3, id};
        status = noshi_store_get(c->store, NOSHI_RECORD_CHAT, peer, id, arena, &chat);
        if (status == NOSHI_OK) status = noshi_tl_get_i64(chat, "access_hash", &hash);
        if (status != NOSHI_OK) return status;
        channel = noshi_tl_new_obj(arena, "inputChannel");
        status = channel ? noshi_tl_set_i64(arena, channel, "channel_id", id) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", hash);
        if (status != NOSHI_OK) return status;
    }
    status = noshi_updates_request(&c->updates, id, channel, arena, &request);
    if (status != NOSHI_OK) return status;
    c->sync_channel = id;
    c->sync_method = noshi_tl_id(request);
    c->sync_id = request_id(c);
    status = noshi_mt_client_submit(&c->mt, c->sync_id, request, 60000);
    if (status != NOSHI_OK) c->sync_id = 0;
    return status;
}

static noshi_status outbox_start(noshi_client *c, noshi_arena *arena) {
    noshi_outbox_item item;
    noshi_status status = noshi_store_outbox_next(c->store, arena, &item);
    if (status == NOSHI_E_NOTFOUND) return NOSHI_OK;
    if (status != NOSHI_OK) return status;
    status = noshi_store_outbox_set(c->store, item.random_id, NOSHI_OUTBOX_SENDING, 0, 0);
    if (status != NOSHI_OK) return status;
    c->outbox_random = item.random_id;
    c->outbox_id = request_id(c);
    status = noshi_mt_client_submit(&c->mt, c->outbox_id, item.request, 60000);
    if (status != NOSHI_OK) {
        c->outbox_id = 0;
        noshi_status saved = noshi_store_outbox_set(c->store, item.random_id, NOSHI_OUTBOX_PENDING, 0, 0);
        if (saved != NOSHI_OK) return saved;
    }
    return status;
}

noshi_status noshi_client_tick(noshi_client *c, uint32_t *next_ms) {
    noshi_arena arena;
    noshi_status status;
    if (!next_ms) return NOSHI_E_ARG;
    *next_ms = UINT32_MAX;
    if (!c || c->closing) return NOSHI_E_STATE;
    *next_ms = noshi_mt_client_tick(&c->mt);
    status = noshi_auth_tick(&c->auth);
    if (status != NOSHI_OK) return status;
    {
        uint32_t auth_next = noshi_auth_next_ms(&c->auth);
        if (auth_next < *next_ms) *next_ms = auth_next;
    }
    if (c->closing || c->session_error != NOSHI_OK) return NOSHI_E_STATE;
    if (c->mt.state == NOSHI_MT_CLIENT_READY && c->store && c->authorized) {
        noshi_arena_init(&arena, 16u * 1024u * 1024u);
        if (c->updates.needs_difference && !c->sync_id && !c->sync_suspended) {
            status = sync_start(c, &arena);
            if (status != NOSHI_OK) {
                c->sync_suspended = 1;
                if (status == NOSHI_E_NOTFOUND && c->events.recover_history) c->events.recover_history(c->events.ctx, c->updates.gap_channel);
                else {
                    c->sync_retry = 1;
                    report(c, status, "updates request");
                }
            }
        }
        if (status == NOSHI_OK && !c->outbox_id) status = outbox_start(c, &arena);
        noshi_arena_free(&arena);
    }
    return status;
}
