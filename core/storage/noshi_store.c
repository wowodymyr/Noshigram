#include "noshi_store.h"

#include <limits.h>
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>

#include "noshi_tl_ids.h"

#define RECORD_MAX (1024u * 1024u)
#define PAGE_MAX 512u

/* peers share these counters by a hash, so two chats may move one together but a write never goes unseen */
#define VERSION_BUCKETS 64u

struct noshi_store {
    sqlite3 *db;
    int64_t account;
    int transaction;
    uint64_t bucket_version[VERSION_BUCKETS];
    uint64_t people_version;
    uint64_t sweep_version;
};

static size_t version_bucket(noshi_peer peer) {
    return (size_t)(((uint64_t)peer.id * 0x9e3779b97f4a7c15ull >> 40) + (uint64_t)peer.kind) % VERSION_BUCKETS;
}

static void note_write(noshi_store *s, noshi_record_kind kind, noshi_peer peer) {
    s->bucket_version[version_bucket(peer)]++;
    if (kind == NOSHI_RECORD_USER || kind == NOSHI_RECORD_CHAT) s->people_version++;
}

uint64_t noshi_store_peer_version(const noshi_store *s, noshi_peer peer) {
    if (!s) return 0;
    return s->bucket_version[version_bucket(peer)] + s->people_version + s->sweep_version;
}

static noshi_status sql_status(int rc) {
    switch (rc) {
        case SQLITE_OK: case SQLITE_DONE: case SQLITE_ROW: return NOSHI_OK;
        case SQLITE_BUSY: case SQLITE_LOCKED: return NOSHI_E_RETRY;
        case SQLITE_NOMEM: return NOSHI_E_NOMEM;
        case SQLITE_TOOBIG: return NOSHI_E_LIMIT;
        default: return NOSHI_E_STORAGE;
    }
}

static noshi_status run(noshi_store *s, const char *sql) {
    return sql_status(sqlite3_exec(s->db, sql, NULL, NULL, NULL));
}

static noshi_status prepare(noshi_store *s, const char *sql, sqlite3_stmt **q) {
    *q = NULL;
    return sql_status(sqlite3_prepare_v2(s->db, sql, -1, q, NULL));
}

static noshi_status finish(sqlite3_stmt *q, noshi_status status) {
    int rc = sqlite3_finalize(q);
    return status != NOSHI_OK ? status : sql_status(rc);
}

static noshi_status bind_key(sqlite3_stmt *q, noshi_store *s, noshi_record_kind kind,
                              noshi_peer peer, int64_t id) {
    int rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, (int)kind);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, peer.kind);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 4, peer.id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 5, id);
    return sql_status(rc);
}

static int valid_key(noshi_store *s, noshi_record_kind kind, noshi_peer peer) {
    return s && kind >= NOSHI_RECORD_USER && kind <= NOSHI_RECORD_MESSAGE_EDIT &&
           peer.kind >= 0 && peer.kind <= 3 && (peer.kind == 0 ? peer.id == 0 : peer.id > 0);
}

noshi_status noshi_store_open(noshi_store **out, const char *path, int64_t account_id) {
    noshi_store *s;
    sqlite3_stmt *q = NULL;
    noshi_status status;
    int version = -1;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!path || !*path || account_id <= 0) return NOSHI_E_ARG;
    s = calloc(1, sizeof(*s));
    if (!s) return NOSHI_E_NOMEM;
    s->account = account_id;
    status = sql_status(sqlite3_open_v2(path, &s->db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL));
    if (status != NOSHI_OK) goto fail;
    sqlite3_limit(s->db, SQLITE_LIMIT_LENGTH, (int)RECORD_MAX + 4096);
    /* WAL avoids two slow flash syncs per update on iphone 3gs and 4; after power loss the server can replay lost commits with their cursor */
    status = run(s, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA journal_size_limit=1048576; PRAGMA foreign_keys=ON");
    if (status != NOSHI_OK) goto fail;
    status = prepare(s, "PRAGMA user_version", &q);
    if (status != NOSHI_OK) goto fail;
    if (sqlite3_step(q) == SQLITE_ROW) version = sqlite3_column_int(q, 0);
    status = finish(q, version < 0 ? NOSHI_E_STORAGE : NOSHI_OK);
    q = NULL;
    if (status != NOSHI_OK) goto fail;
    if (version > 2) { status = NOSHI_E_UNSUPPORTED; goto fail; }
    if (version == 0) {
        status = run(s,
            "BEGIN IMMEDIATE;"
            "CREATE TABLE records(account INTEGER NOT NULL,kind INTEGER NOT NULL,peer_kind INTEGER NOT NULL,"
            "peer INTEGER NOT NULL,id INTEGER NOT NULL,data BLOB NOT NULL,PRIMARY KEY(account,kind,peer_kind,peer,id));"
            "CREATE TABLE cursors(account INTEGER NOT NULL,channel INTEGER NOT NULL,pts INTEGER NOT NULL,"
            "qts INTEGER NOT NULL,seq INTEGER NOT NULL,date INTEGER NOT NULL,PRIMARY KEY(account,channel));"
            "CREATE TABLE outbox(account INTEGER NOT NULL,random_id INTEGER NOT NULL,peer_kind INTEGER NOT NULL,"
            "peer INTEGER NOT NULL,state INTEGER NOT NULL,server_id INTEGER NOT NULL,error INTEGER NOT NULL,"
            "request BLOB NOT NULL,PRIMARY KEY(account,random_id));"
            "CREATE INDEX outbox_pending ON outbox(account,state,random_id);"
            "PRAGMA user_version=1; COMMIT");
        if (status != NOSHI_OK) goto fail;
    }
    if (version < 2) {
        status = run(s, "BEGIN IMMEDIATE; CREATE TABLE journal(id INTEGER PRIMARY KEY AUTOINCREMENT,"
                        "account INTEGER NOT NULL,data BLOB NOT NULL);"
                        "CREATE INDEX journal_account ON journal(account,id); PRAGMA user_version=2; COMMIT");
        if (status != NOSHI_OK) goto fail;
    }
    *out = s;
    return NOSHI_OK;
fail:
    sqlite3_finalize(q);
    if (s->db) sqlite3_close(s->db);
    free(s);
    return status;
}

noshi_status noshi_store_close(noshi_store *s) {
    noshi_status status;
    if (!s) return NOSHI_E_ARG;
    if (s->transaction) {
        status = noshi_store_rollback(s);
        if (status != NOSHI_OK) return status;
    }
    status = sql_status(sqlite3_close(s->db));
    if (status == NOSHI_OK) free(s);
    return status;
}

noshi_status noshi_store_begin(noshi_store *s) {
    noshi_status status;
    if (!s || s->transaction) return NOSHI_E_STATE;
    status = run(s, "BEGIN IMMEDIATE");
    if (status == NOSHI_OK) s->transaction = 1;
    return status;
}

noshi_status noshi_store_commit(noshi_store *s) {
    noshi_status status;
    if (!s || !s->transaction) return NOSHI_E_STATE;
    status = run(s, "COMMIT");
    if (status == NOSHI_OK) s->transaction = 0;
    return status;
}

noshi_status noshi_store_rollback(noshi_store *s) {
    noshi_status status;
    if (!s || !s->transaction) return NOSHI_E_STATE;
    status = run(s, "ROLLBACK");
    if (status == NOSHI_OK) s->transaction = 0;
    return status;
}

noshi_status noshi_store_cursor_get(noshi_store *s, int64_t channel_id, noshi_cursor *out) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!s || channel_id < 0) return NOSHI_E_ARG;
    status = prepare(s, "SELECT pts,qts,seq,date FROM cursors WHERE account=? AND channel=?", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, channel_id);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    if (rc == SQLITE_ROW) {
        out->pts = sqlite3_column_int(q, 0);
        out->qts = sqlite3_column_int(q, 1);
        out->seq = sqlite3_column_int(q, 2);
        out->date = sqlite3_column_int(q, 3);
    }
    return finish(q, rc == SQLITE_DONE ? NOSHI_E_NOTFOUND : sql_status(rc));
}

noshi_status noshi_store_cursor_put(noshi_store *s, int64_t channel_id, const noshi_cursor *v) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!s || !s->transaction || !v || channel_id < 0 || v->pts < 0 || v->qts < 0 || v->seq < 0 || v->date < 0)
        return NOSHI_E_ARG;
    status = prepare(s, "INSERT OR REPLACE INTO cursors VALUES(?,?,?,?,?,?)", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, channel_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, v->pts);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 4, v->qts);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 5, v->seq);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 6, v->date);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    return finish(q, sql_status(rc));
}

noshi_status noshi_store_put(noshi_store *s, noshi_record_kind kind, noshi_peer peer,
                                int64_t id, const noshi_tl_value *value) {
    sqlite3_stmt *q;
    noshi_writer w;
    noshi_status status;
    if (!valid_key(s, kind, peer) || !value) return NOSHI_E_ARG;
    noshi_writer_init(&w, RECORD_MAX);
    status = noshi_tl_encode(value, &w, NULL);
    if (status != NOSHI_OK) goto done;
    status = prepare(s, "INSERT OR REPLACE INTO records VALUES(?,?,?,?,?,?)", &q);
    if (status != NOSHI_OK) goto done;
    status = bind_key(q, s, kind, peer, id);
    if (status == NOSHI_OK) status = sql_status(sqlite3_bind_blob(q, 6, w.data, (int)w.len, SQLITE_TRANSIENT));
    if (status == NOSHI_OK) status = sql_status(sqlite3_step(q));
    status = finish(q, status);
    if (status == NOSHI_OK) note_write(s, kind, peer);
done:
    noshi_writer_free(&w);
    return status;
}

static noshi_status decode_column(sqlite3_stmt *q, int column, noshi_arena *a, noshi_tl_value **out) {
    int len = sqlite3_column_bytes(q, column);
    if (len < 4 || (unsigned)len > RECORD_MAX) return NOSHI_E_STORAGE;
    return noshi_tl_decode_all(a, NULL, NOSHI_TL_REF_ANY, sqlite3_column_blob(q, column), (size_t)len, out);
}

noshi_status noshi_store_get(noshi_store *s, noshi_record_kind kind, noshi_peer peer,
                                int64_t id, noshi_arena *arena, noshi_tl_value **out) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!valid_key(s, kind, peer) || !arena) return NOSHI_E_ARG;
    status = prepare(s, "SELECT data FROM records WHERE account=? AND kind=? AND peer_kind=? AND peer=? AND id=?", &q);
    if (status != NOSHI_OK) return status;
    status = bind_key(q, s, kind, peer, id);
    if (status == NOSHI_OK) {
        rc = sqlite3_step(q);
        status = rc == SQLITE_ROW ? decode_column(q, 0, arena, out) :
                 rc == SQLITE_DONE ? NOSHI_E_NOTFOUND : sql_status(rc);
    }
    return finish(q, status);
}

noshi_status noshi_store_delete(noshi_store *s, noshi_record_kind kind, noshi_peer peer, int64_t id) {
    sqlite3_stmt *q;
    noshi_status status;
    if (!valid_key(s, kind, peer)) return NOSHI_E_ARG;
    status = prepare(s, "DELETE FROM records WHERE account=? AND kind=? AND peer_kind=? AND peer=? AND id=?", &q);
    if (status != NOSHI_OK) return status;
    status = bind_key(q, s, kind, peer, id);
    if (status == NOSHI_OK) status = sql_status(sqlite3_step(q));
    status = finish(q, status);
    if (status == NOSHI_OK) note_write(s, kind, peer);
    return status;
}

noshi_status noshi_store_page(noshi_store *s, noshi_record_kind kind, noshi_peer peer,
                                 int64_t before_id, uint32_t limit, noshi_record_visit visit, void *ctx) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!valid_key(s, kind, peer) || !visit || limit == 0 || limit > PAGE_MAX) return NOSHI_E_ARG;
    status = prepare(s, "SELECT id,data FROM records WHERE account=? AND kind=? AND peer_kind=? AND peer=? "
                        "AND id<? ORDER BY id DESC LIMIT ?", &q);
    if (status != NOSHI_OK) return status;
    status = bind_key(q, s, kind, peer, before_id);
    if (status == NOSHI_OK) status = sql_status(sqlite3_bind_int(q, 6, (int)limit));
    while (status == NOSHI_OK && (rc = sqlite3_step(q)) == SQLITE_ROW) {
        noshi_arena a;
        noshi_tl_value *v = NULL;
        noshi_arena_init(&a, 8u * RECORD_MAX);
        status = decode_column(q, 1, &a, &v);
        if (status == NOSHI_OK) status = visit(ctx, sqlite3_column_int64(q, 0), v);
        noshi_arena_free(&a);
    }
    if (status == NOSHI_OK) status = sql_status(rc);
    return finish(q, status);
}

noshi_status noshi_store_outbox_add(noshi_store *s, noshi_peer peer, const noshi_tl_value *request) {
    sqlite3_stmt *q;
    noshi_writer w;
    noshi_status status;
    int64_t random_id;
    noshi_peer target;
    int rc;
    if (!s || !request || (noshi_tl_id(request) != NOSHI_TL_ID_messages_sendMessage &&
        noshi_tl_id(request) != NOSHI_TL_ID_messages_sendMedia)) return NOSHI_E_ARG;
    if (noshi_tl_get_i64(request, "random_id", &random_id) != NOSHI_OK || random_id == 0 ||
        noshi_peer_from_tl(noshi_tl_get(request, "peer"), &target) != NOSHI_OK ||
        peer.kind != target.kind || peer.id != target.id) return NOSHI_E_ARG;
    noshi_writer_init(&w, RECORD_MAX);
    status = noshi_tl_encode(request, &w, NULL);
    if (status != NOSHI_OK) goto done;
    /* a reused random_id must retain the original request, replace would send different text after a crash */
    status = prepare(s, "INSERT INTO outbox VALUES(?,?,?,?,0,0,0,?)", &q);
    if (status != NOSHI_OK) goto done;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, random_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, peer.kind);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 4, peer.id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_blob(q, 5, w.data, (int)w.len, SQLITE_TRANSIENT);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = finish(q, sql_status(rc));
done:
    noshi_writer_free(&w);
    return status;
}

noshi_status noshi_store_outbox_next(noshi_store *s, noshi_arena *arena, noshi_outbox_item *out) {
    sqlite3_stmt *q;
    noshi_status status;
    noshi_tl_value *v = NULL;
    int rc;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!s || !arena) return NOSHI_E_ARG;
    status = prepare(s, "SELECT random_id,peer_kind,peer,state,server_id,error,request FROM outbox "
                        "WHERE account=? AND state=0 ORDER BY random_id LIMIT 1", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = rc == SQLITE_ROW ? decode_column(q, 6, arena, &v) :
             rc == SQLITE_DONE ? NOSHI_E_NOTFOUND : sql_status(rc);
    if (status == NOSHI_OK) {
        out->random_id = sqlite3_column_int64(q, 0);
        out->peer.kind = sqlite3_column_int(q, 1);
        out->peer.id = sqlite3_column_int64(q, 2);
        out->state = (noshi_outbox_state)sqlite3_column_int(q, 3);
        out->server_id = sqlite3_column_int(q, 4);
        out->error = sqlite3_column_int(q, 5);
        out->request = v;
    }
    return finish(q, status);
}

noshi_status noshi_store_outbox_set(noshi_store *s, int64_t random_id, noshi_outbox_state state,
                                       int32_t server_id, int32_t error) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!s || !random_id || state < NOSHI_OUTBOX_PENDING || state > NOSHI_OUTBOX_FAILED ||
        server_id < 0 || (state == NOSHI_OUTBOX_SENT && !server_id)) return NOSHI_E_ARG;
    status = prepare(s, "UPDATE outbox SET state=?,server_id=?,error=? WHERE account=? AND random_id=? "
                        "AND (state<>2 OR ?=2)", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int(q, 1, (int)state);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, server_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, error);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 4, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 5, random_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 6, (int)state);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = sql_status(rc);
    if (status == NOSHI_OK && sqlite3_changes(s->db) == 0) status = NOSHI_E_NOTFOUND;
    return finish(q, status);
}

noshi_status noshi_store_outbox_recover(noshi_store *s) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!s) return NOSHI_E_ARG;
    status = prepare(s, "UPDATE outbox SET state=0 WHERE account=? AND state=1", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    return finish(q, sql_status(rc));
}

noshi_status noshi_peer_from_tl(const noshi_tl_value *v, noshi_peer *out) {
    uint32_t id;
    const char *field;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!v) return NOSHI_E_ARG;
    id = noshi_tl_id(v);
    if (id == NOSHI_TL_ID_peerUser || id == NOSHI_TL_ID_inputPeerUser) { out->kind = 1; field = "user_id"; }
    else if (id == NOSHI_TL_ID_peerChat || id == NOSHI_TL_ID_inputPeerChat) { out->kind = 2; field = "chat_id"; }
    else if (id == NOSHI_TL_ID_peerChannel || id == NOSHI_TL_ID_inputPeerChannel) { out->kind = 3; field = "channel_id"; }
    else return NOSHI_E_UNSUPPORTED;
    if (noshi_tl_get_i64(v, field, &out->id) != NOSHI_OK || out->id <= 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    return NOSHI_OK;
}

/* the entries the journal keeps for an account */
#define JOURNAL_MAX 8192

noshi_status noshi_store_journal_add(noshi_store *s, const noshi_tl_value *value) {
    sqlite3_stmt *q;
    noshi_writer w;
    noshi_status status;
    int rc, full;
    if (!s || !s->transaction || !value) return NOSHI_E_STATE;
    status = prepare(s, "SELECT COUNT(*) FROM journal WHERE account=?", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    full = rc == SQLITE_ROW && sqlite3_column_int(q, 0) >= JOURNAL_MAX;
    status = rc == SQLITE_ROW ? NOSHI_OK : sql_status(rc);
    status = finish(q, status);
    if (status != NOSHI_OK) return status;
    if (full) {
        /* no feature acknowledges the journal yet, so a full one makes room by dropping its oldest entries; refusing instead stopped every later update of
           the account, once a few thousand of them had come */
        status = prepare(s, "DELETE FROM journal WHERE account=?1 AND id IN (SELECT id FROM journal WHERE account=?1 ORDER BY id LIMIT ?2)", &q);
        if (status != NOSHI_OK) return status;
        rc = sqlite3_bind_int64(q, 1, s->account);
        if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, JOURNAL_MAX / 4);
        if (rc == SQLITE_OK) rc = sqlite3_step(q);
        status = finish(q, sql_status(rc));
        if (status != NOSHI_OK) return status;
    }
    noshi_writer_init(&w, RECORD_MAX);
    status = noshi_tl_encode(value, &w, NULL);
    if (status != NOSHI_OK) goto done;
    status = prepare(s, "INSERT INTO journal(account,data) VALUES(?,?)", &q);
    if (status != NOSHI_OK) goto done;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_blob(q, 2, w.data, (int)w.len, SQLITE_TRANSIENT);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = finish(q, sql_status(rc));
done:
    noshi_writer_free(&w);
    return status;
}

noshi_status noshi_store_journal_page(noshi_store *s, int64_t after_id, uint32_t limit,
                                         noshi_record_visit visit, void *ctx) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!s || !visit || after_id < 0 || !limit || limit > PAGE_MAX) return NOSHI_E_ARG;
    status = prepare(s, "SELECT id,data FROM journal WHERE account=? AND id>? ORDER BY id LIMIT ?", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, after_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, (int)limit);
    status = sql_status(rc);
    while (status == NOSHI_OK && (rc = sqlite3_step(q)) == SQLITE_ROW) {
        noshi_arena arena;
        noshi_tl_value *v = NULL;
        noshi_arena_init(&arena, 8u * RECORD_MAX);
        status = decode_column(q, 1, &arena, &v);
        if (status == NOSHI_OK) status = visit(ctx, sqlite3_column_int64(q, 0), v);
        noshi_arena_free(&arena);
    }
    if (status == NOSHI_OK) status = sql_status(rc);
    return finish(q, status);
}

noshi_status noshi_store_journal_ack(noshi_store *s, int64_t through_id) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!s || !s->transaction || through_id < 0) return NOSHI_E_STATE;
    status = prepare(s, "DELETE FROM journal WHERE account=? AND id<=?", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, through_id);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    return finish(q, sql_status(rc));
}

noshi_status noshi_store_delete_common_message(noshi_store *s, int32_t id) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!s || id <= 0) return NOSHI_E_ARG;
    status = prepare(s, "DELETE FROM records WHERE account=? AND kind=4 AND peer_kind IN (1,2) AND id=?", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, id);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = finish(q, sql_status(rc));
    /* the sweep reaches every chat of the account, so it moves every version */
    if (status == NOSHI_OK) s->sweep_version++;
    return status;
}

noshi_status noshi_store_move(noshi_store *s, noshi_record_kind from, noshi_record_kind to, noshi_peer peer, int64_t id) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc, found;
    if (!valid_key(s, from, peer) || !valid_key(s, to, peer)) return NOSHI_E_ARG;
    status = prepare(s, "INSERT OR REPLACE INTO records(account,kind,peer_kind,peer,id,data) "
                        "SELECT account,?6,peer_kind,peer,id,data FROM records WHERE account=?1 AND kind=?2 AND peer_kind=?3 AND peer=?4 AND id=?5", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, (int)from);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, peer.kind);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 4, peer.id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 5, id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 6, (int)to);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    found = sqlite3_changes(s->db) > 0;
    status = finish(q, sql_status(rc));
    if (status != NOSHI_OK) return status;
    if (!found) return NOSHI_E_NOTFOUND;
    status = noshi_store_delete(s, from, peer, id);
    if (status == NOSHI_OK) note_write(s, to, peer);
    return status;
}

noshi_status noshi_store_find_common_message(noshi_store *s, int32_t id, noshi_peer *peer) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!s || !peer || id <= 0) return NOSHI_E_ARG;
    status = prepare(s, "SELECT peer_kind,peer FROM records WHERE account=? AND kind=4 AND peer_kind IN (1,2) AND id=? LIMIT 1", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, id);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    if (rc == SQLITE_ROW) {
        peer->kind = sqlite3_column_int(q, 0);
        peer->id = sqlite3_column_int64(q, 1);
        return finish(q, NOSHI_OK);
    }
    return finish(q, rc == SQLITE_DONE ? NOSHI_E_NOTFOUND : sql_status(rc));
}

noshi_status noshi_store_count(noshi_store *s, noshi_record_kind kind, int64_t *count) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (count) *count = 0;
    if (!s || !count || kind < NOSHI_RECORD_USER || kind > NOSHI_RECORD_MESSAGE_EDIT) return NOSHI_E_ARG;
    status = prepare(s, "SELECT COUNT(*) FROM records WHERE account=? AND kind=?", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, (int)kind);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    if (rc == SQLITE_ROW) *count = sqlite3_column_int64(q, 0);
    return finish(q, rc == SQLITE_ROW ? NOSHI_OK : sql_status(rc));
}

noshi_status noshi_store_clear(noshi_store *s, noshi_record_kind kind) {
    sqlite3_stmt *q;
    noshi_status status;
    int rc;
    if (!s || kind < NOSHI_RECORD_USER || kind > NOSHI_RECORD_MESSAGE_EDIT) return NOSHI_E_ARG;
    status = prepare(s, "DELETE FROM records WHERE account=? AND kind=?", &q);
    if (status != NOSHI_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, (int)kind);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = finish(q, sql_status(rc));
    if (status == NOSHI_OK) s->sweep_version++;
    return status;
}
