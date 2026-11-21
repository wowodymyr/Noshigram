#ifndef NOSHI_STORE_H
#define NOSHI_STORE_H

#include "noshi_tl.h"

typedef struct noshi_store noshi_store;

typedef enum noshi_record_kind {
    NOSHI_RECORD_USER = 1,
    NOSHI_RECORD_CHAT,
    NOSHI_RECORD_DIALOG,
    NOSHI_RECORD_MESSAGE,
    NOSHI_RECORD_MEDIA,
    NOSHI_RECORD_FOLDER,
    NOSHI_RECORD_DRAFT,
    NOSHI_RECORD_FILE_JOB,
    /* a message the other side deleted, kept as it was: the same object as a message, under the same chat and id */
    NOSHI_RECORD_DELETED_MESSAGE,
    /* what a message said before an edit; the id is the id of the message times a thousand plus the number of the version, 1 for the oldest */
    NOSHI_RECORD_MESSAGE_EDIT
} noshi_record_kind;

#define NOSHI_EDIT_VERSIONS 1000

typedef struct noshi_peer {
    int32_t kind;
    int64_t id;
} noshi_peer;

typedef struct noshi_cursor {
    int32_t pts;
    int32_t qts;
    int32_t seq;
    int32_t date;
} noshi_cursor;

typedef enum noshi_outbox_state {
    NOSHI_OUTBOX_PENDING = 0,
    NOSHI_OUTBOX_SENDING,
    NOSHI_OUTBOX_SENT,
    NOSHI_OUTBOX_FAILED
} noshi_outbox_state;

typedef struct noshi_outbox_item {
    int64_t random_id;
    noshi_peer peer;
    int32_t server_id;
    noshi_outbox_state state;
    int32_t error;
    const noshi_tl_value *request;
} noshi_outbox_item;

typedef noshi_status (*noshi_record_visit)(void *ctx, int64_t id, const noshi_tl_value *value);

noshi_status noshi_store_open(noshi_store **out, const char *path, int64_t account_id);
noshi_status noshi_store_close(noshi_store *s);
noshi_status noshi_store_begin(noshi_store *s);
noshi_status noshi_store_commit(noshi_store *s);
noshi_status noshi_store_rollback(noshi_store *s);
noshi_status noshi_store_cursor_get(noshi_store *s, int64_t channel_id, noshi_cursor *out);
noshi_status noshi_store_cursor_put(noshi_store *s, int64_t channel_id, const noshi_cursor *value);
noshi_status noshi_store_put(noshi_store *s, noshi_record_kind kind, noshi_peer peer,
                                int64_t id, const noshi_tl_value *value);
noshi_status noshi_store_get(noshi_store *s, noshi_record_kind kind, noshi_peer peer,
                                int64_t id, noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_store_delete(noshi_store *s, noshi_record_kind kind, noshi_peer peer, int64_t id);
noshi_status noshi_store_delete_common_message(noshi_store *s, int32_t id);
/* puts a record under another kind, replacing one that is there; NOSHI_E_NOTFOUND when the first is not */
noshi_status noshi_store_move(noshi_store *s, noshi_record_kind from, noshi_record_kind to, noshi_peer peer, int64_t id);
/* the chat of a message of the common numbering (a private chat or a basic group), which updateDeleteMessages names by its id alone; NOSHI_E_NOTFOUND when the
   store has no such message */
noshi_status noshi_store_find_common_message(noshi_store *s, int32_t id, noshi_peer *peer);
/* how many records of the kind the account has, and the removal of all of them */
noshi_status noshi_store_count(noshi_store *s, noshi_record_kind kind, int64_t *count);
noshi_status noshi_store_clear(noshi_store *s, noshi_record_kind kind);
noshi_status noshi_store_page(noshi_store *s, noshi_record_kind kind, noshi_peer peer,
                                 int64_t before_id, uint32_t limit, noshi_record_visit visit, void *ctx);
noshi_status noshi_store_outbox_add(noshi_store *s, noshi_peer peer, const noshi_tl_value *request);
noshi_status noshi_store_outbox_next(noshi_store *s, noshi_arena *arena, noshi_outbox_item *out);
noshi_status noshi_store_outbox_set(noshi_store *s, int64_t random_id, noshi_outbox_state state,
                                       int32_t server_id, int32_t error);
noshi_status noshi_store_outbox_recover(noshi_store *s);
noshi_status noshi_store_journal_add(noshi_store *s, const noshi_tl_value *value);
noshi_status noshi_store_journal_page(noshi_store *s, int64_t after_id, uint32_t limit,
                                         noshi_record_visit visit, void *ctx);
noshi_status noshi_store_journal_ack(noshi_store *s, int64_t through_id);
/* a number that grows whenever a write could change what a reader of the chat's records sees: a record of the
   chat, a user or chat record (names and photos), or a sweep over every chat */
uint64_t noshi_store_peer_version(const noshi_store *s, noshi_peer peer);
noshi_status noshi_peer_from_tl(const noshi_tl_value *value, noshi_peer *out);

#endif
