#include "noshi_call_log.h"

#include <stdlib.h>
#include <string.h>

#include "noshi_store.h"
#include "noshi_tl_ids.h"

noshi_status noshi_call_log_request(noshi_arena *arena, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request, *filter, *empty;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || limit < 1 || limit > NOSHI_CALL_LOG_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.search");
    filter = noshi_tl_new_obj(arena, "inputMessagesFilterPhoneCalls");
    empty = noshi_tl_new_obj(arena, "inputPeerEmpty");
    if (!request || !filter || !empty) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "q", "");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "filter", filter);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "min_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", empty);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "add_offset", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "min_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static const noshi_tl_value *find_user(const noshi_tl_value *users, int64_t id) {
    uint32_t i;
    for (i = 0; i < users->u.vec.count; ++i) {
        int64_t found;
        const noshi_tl_value *user = users->u.vec.items[i];
        if (noshi_tl_get_i64(user, "id", &found) == NOSHI_OK && found == id) return user;
    }
    return NULL;
}

noshi_status noshi_call_log_parse(const noshi_tl_value *answer, noshi_call_log_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *messages, *users;
    noshi_message_row *message;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_messages) && !noshi_tl_is(answer, NOSHI_TL_ID_messages_messagesSlice) &&
        !noshi_tl_is(answer, NOSHI_TL_ID_messages_channelMessages)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "messages", &messages) != NOSHI_OK || noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK) return NOSHI_E_MALFORMED;
    /* a message row is large, so it is made once on the heap for all of them */
    message = malloc(sizeof(*message));
    if (!message) return NOSHI_E_NOMEM;
    for (i = 0; i < messages->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *m = messages->u.vec.items[i], *user;
        noshi_peer peer;
        noshi_person_row person;
        noshi_call_log_row *row = &rows[n];
        if (noshi_peer_from_tl(noshi_tl_get(m, "peer_id"), &peer) != NOSHI_OK || peer.kind != 1) continue;
        memset(message, 0, sizeof(*message));
        if (noshi_message_read(m, message) != NOSHI_OK || message->service != NOSHI_SERVICE_CALL + 1) continue;
        user = find_user(users, peer.id);
        if (!user || noshi_person_parse(user, &person) != NOSHI_OK) continue;
        memset(row, 0, sizeof(*row));
        row->message_id = message->id;
        row->date = message->date;
        row->duration = message->service_value;
        row->outgoing = message->out;
        row->video = message->call_video;
        row->outcome = message->call_reason;
        row->user_id = person.id;
        row->access_hash = person.access_hash;
        row->deleted = person.deleted;
        row->photo = person.photo;
        memcpy(row->name, person.name, sizeof(row->name));
        ++n;
    }
    free(message);
    *count = n;
    return NOSHI_OK;
}
