#include "noshi_mt_files.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "noshi_random.h"
#include "noshi_tl_ids.h"

#define FILE_SIZE_MAX UINT64_C(34359738368)
#define DOWNLOAD_PART (128u * 1024u)
#define FILE_RETRY_WAIT_MAX_SECONDS 300

uint64_t noshi_file_temporary_token(void) {
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static uint64_t counter;
    uint64_t result;
    pthread_mutex_lock(&lock);
    if (++counter == 0) ++counter;
    result = counter;
    pthread_mutex_unlock(&lock);
    return result;
}

noshi_status noshi_file_download_part(uint64_t offset, uint32_t preferred, uint32_t *limit) {
    if (limit) *limit = 0;
    if (!limit || offset > INT64_MAX || offset % 4096 || !preferred || preferred > NOSHI_FILE_RANGE_MAX ||
        preferred % 4096 || NOSHI_FILE_RANGE_MAX % preferred) return NOSHI_E_ARG;
    while ((offset % NOSHI_FILE_RANGE_MAX) + preferred > NOSHI_FILE_RANGE_MAX) preferred /= 2;
    *limit = preferred;
    return NOSHI_OK;
}

int noshi_file_retry_delay(const char *error_name, uint32_t retries, uint32_t *delay_ms) {
    char name[128];
    int32_t seconds;
    if (delay_ms) *delay_ms = 0;
    if (!error_name || !delay_ms || retries >= NOSHI_FILE_RETRIES_MAX) return 0;
    if (!strcmp(error_name, "TIMEOUT") || !strcmp(error_name, "OFFLINE")) {
        *delay_ms = 1000u << retries;
        return 1;
    }
    noshi_mt_rpc_error_split(error_name, name, sizeof(name), &seconds);
    if ((strcmp(name, "FLOOD_WAIT") && strcmp(name, "FLOOD_PREMIUM_WAIT")) || seconds <= 0 || seconds > FILE_RETRY_WAIT_MAX_SECONDS) return 0;
    *delay_ms = (uint32_t)seconds * 1000u;
    return 1;
}

noshi_status noshi_file_download_advance(uint64_t offset, uint64_t size, size_t received,
                                           uint32_t requested, uint64_t capacity,
                                           uint64_t *next, int *complete) {
    uint64_t end;
    if (next) *next = 0;
    if (complete) *complete = 0;
    if (!next || !complete || !requested || !capacity) return NOSHI_E_ARG;
    if (size > capacity || offset > capacity || received > capacity - offset) return NOSHI_E_LIMIT;
    if (received > requested || (size && (offset > size || received > size - offset))) return NOSHI_E_MALFORMED;
    end = offset + received;
    if (size && end < size && !received) return NOSHI_E_TRUNCATED;
    *next = end;
    *complete = size ? end == size : received < requested;
    return NOSHI_OK;
}

static void initialize(noshi_file_transfer *t) {
    memset(t, 0, sizeof(*t));
    t->fd = -1;
    noshi_writer_init(&t->location, 65536);
    noshi_writer_init(&t->chunk, NOSHI_FILE_RANGE_MAX);
}

static noshi_status file_read(int fd, uint8_t *out, size_t n, uint64_t offset) {
    while (n) {
        ssize_t got = pread(fd, out, n, (off_t)offset);
        if (got < 0) { if (errno == EINTR) continue; return NOSHI_E_IO; }
        if (!got) return NOSHI_E_TRUNCATED;
        out += got;
        offset += (uint64_t)got;
        n -= (size_t)got;
    }
    return NOSHI_OK;
}

static noshi_status file_write(int fd, const uint8_t *in, size_t n, uint64_t offset) {
    while (n) {
        ssize_t wrote = pwrite(fd, in, n, (off_t)offset);
        if (wrote < 0) { if (errno == EINTR) continue; return NOSHI_E_IO; }
        if (!wrote) return NOSHI_E_IO;
        in += wrote;
        offset += (uint64_t)wrote;
        n -= (size_t)wrote;
    }
    return NOSHI_OK;
}

noshi_status noshi_file_upload(noshi_file_transfer *t, int fd, const char *name, int32_t dc,
                                  uint32_t part_size, uint32_t max_parts) {
    struct stat st;
    noshi_status status;
    uint64_t parts;
    if (!t) return NOSHI_E_ARG;
    initialize(t);
    if (fd < 0 || !name || !*name || strlen(name) >= sizeof(t->name) || strchr(name, '/') ||
        dc <= 0 || !part_size || part_size % 1024 || part_size > NOSHI_FILE_PART_MAX ||
        NOSHI_FILE_PART_MAX % part_size || !max_parts || max_parts > 65536) return NOSHI_E_ARG;
    if (fstat(fd, &st) < 0 || !S_ISREG(st.st_mode) || st.st_size <= 0 || (uint64_t)st.st_size > FILE_SIZE_MAX) return NOSHI_E_IO;
    t->size = (uint64_t)st.st_size;
    parts = (t->size + part_size - 1u) / part_size;
    if (parts > max_parts) return NOSHI_E_LIMIT;
    t->fd = dup(fd);
    if (t->fd < 0) return NOSHI_E_IO;
    if (fcntl(t->fd, F_SETFD, FD_CLOEXEC) < 0) { close(t->fd); t->fd = -1; return NOSHI_E_IO; }
    t->upload = 1;
    t->big = t->size > 10u * 1024u * 1024u;
    t->dc = dc;
    t->part_size = part_size;
    t->parts = (uint32_t)parts;
    memcpy(t->name, name, strlen(name) + 1);
    status = noshi_random_u64(&t->id);
    if (status != NOSHI_OK || !t->id) { noshi_file_close(t); return status == NOSHI_OK ? NOSHI_E_CRYPTO : status; }
    if (!t->big) {
        t->md5 = noshi_digest_new(0);
        if (!t->md5) { noshi_file_close(t); return NOSHI_E_CRYPTO; }
    }
    return NOSHI_OK;
}

noshi_status noshi_file_download(noshi_file_transfer *t, const char *temporary,
                                    const noshi_tl_value *location, int32_t dc,
                                    uint64_t size, uint64_t verified_offset) {
    struct stat st;
    noshi_status status;
    int flags;
    if (!t) return NOSHI_E_ARG;
    initialize(t);
    if (!temporary || !*temporary || strlen(temporary) >= sizeof(t->temporary) || !location || dc <= 0 ||
        !size || size > FILE_SIZE_MAX || verified_offset > size || (verified_offset != size && verified_offset % 4096)) return NOSHI_E_ARG;
    status = noshi_tl_encode(location, &t->location, NULL);
    if (status != NOSHI_OK) return status;
    flags = O_RDWR | O_NOFOLLOW;
    if (!verified_offset) flags |= O_CREAT | O_EXCL;
    t->fd = open(temporary, flags, 0600);
    if (t->fd < 0) { noshi_file_close(t); return NOSHI_E_IO; }
    if (fcntl(t->fd, F_SETFD, FD_CLOEXEC) < 0 || fstat(t->fd, &st) < 0 || !S_ISREG(st.st_mode) ||
        st.st_nlink != 1 || st.st_size < 0 || (uint64_t)st.st_size < verified_offset ||
        ftruncate(t->fd, (off_t)verified_offset) < 0) {
        noshi_file_close(t);
        return NOSHI_E_IO;
    }
    memcpy(t->temporary, temporary, strlen(temporary) + 1);
    t->size = size;
    t->offset = verified_offset;
    t->dc = dc;
    t->part_size = DOWNLOAD_PART;
    if (verified_offset == size) t->state = NOSHI_FILE_DONE;
    return NOSHI_OK;
}

static noshi_file_hash *current_hash(noshi_file_transfer *t) {
    uint32_t i;
    for (i = 0; i < t->hash_count; ++i) if (t->hashes[i].offset == t->offset) return &t->hashes[i];
    return NULL;
}

static noshi_status read_location(noshi_file_transfer *t, noshi_arena *arena, noshi_tl_value **out) {
    return noshi_tl_decode_all(arena, NULL, NOSHI_TL_REF_ANY, t->location.data, t->location.len, out);
}

noshi_status noshi_file_next(noshi_file_transfer *t, uint64_t time_ms, noshi_arena *arena,
                                noshi_tl_value **request, uint64_t *id, int32_t *dc, int *cdn) {
    noshi_tl_value *v = NULL, *location;
    noshi_status status = NOSHI_OK;
    noshi_file_hash *hash;
    uint64_t offset;
    uint32_t limit;
    if (!request || !id || !dc || !cdn) return NOSHI_E_ARG;
    *request = NULL; *id = 0; *dc = 0; *cdn = 0;
    if (!t || !arena || t->fd < 0 || t->pending) return NOSHI_E_STATE;
    if (t->state == NOSHI_FILE_WAIT && time_ms >= t->wait_until) t->state = NOSHI_FILE_ACTIVE;
    if (t->state == NOSHI_FILE_WAIT) return NOSHI_E_RETRY;
    if (t->state != NOSHI_FILE_ACTIVE) return NOSHI_E_STATE;
    *dc = t->dc;
    if (t->upload) {
        uint64_t left = t->size - t->offset;
        limit = left < t->part_size ? (uint32_t)left : t->part_size;
        t->chunk.len = 0;
        status = noshi_wr_zero(&t->chunk, limit);
        if (status == NOSHI_OK) status = file_read(t->fd, t->chunk.data, limit, t->offset);
        v = noshi_tl_new_obj(arena, t->big ? "upload.saveBigFilePart" : "upload.saveFilePart");
        if (status == NOSHI_OK) status = v ? noshi_tl_set_i64(arena, v, "file_id", (int64_t)t->id) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, v, "file_part", (int32_t)(t->offset / t->part_size));
        if (status == NOSHI_OK && t->big) status = noshi_tl_set_i32(arena, v, "file_total_parts", (int32_t)t->parts);
        if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, v, "bytes", t->chunk.data, limit);
        t->requested = limit;
    } else if (t->request_token_len) {
        v = noshi_tl_new_obj(arena, "upload.reuploadCdnFile");
        status = v ? noshi_tl_set_bytes(arena, v, "file_token", t->token, t->token_len) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, v, "request_token", t->request_token, t->request_token_len);
    } else if (!(hash = current_hash(t))) {
        v = noshi_tl_new_obj(arena, t->cdn ? "upload.getCdnFileHashes" : "upload.getFileHashes");
        status = v ? NOSHI_OK : NOSHI_E_NOMEM;
        if (status == NOSHI_OK && t->cdn) status = noshi_tl_set_bytes(arena, v, "file_token", t->token, t->token_len);
        if (status == NOSHI_OK && !t->cdn) {
            status = read_location(t, arena, &location);
            if (status == NOSHI_OK) status = noshi_tl_set(v, "location", location);
        }
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, v, "offset", (int64_t)t->offset);
    } else {
        offset = t->offset + t->chunk.len;
        status = noshi_file_download_part(offset, t->part_size, &limit);
        if (status != NOSHI_OK) return status;
        if (hash->limit - t->chunk.len < limit) {
            uint64_t range_left = hash->limit - t->chunk.len;
            if (offset + range_left != t->size) while (limit > range_left && limit > 4096) limit /= 2;
        }
        if (t->cdn) { *dc = t->cdn_dc; *cdn = 1; }
        v = noshi_tl_new_obj(arena, t->cdn ? "upload.getCdnFile" : "upload.getFile");
        status = v ? NOSHI_OK : NOSHI_E_NOMEM;
        if (status == NOSHI_OK && t->cdn) status = noshi_tl_set_bytes(arena, v, "file_token", t->token, t->token_len);
        if (status == NOSHI_OK && !t->cdn) {
            status = read_location(t, arena, &location);
            if (status == NOSHI_OK) status = noshi_tl_set(v, "location", location);
            if (status == NOSHI_OK && !t->cdn_disabled) status = noshi_tl_set_flag(v, "cdn_supported");
        }
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, v, "offset", (int64_t)offset);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, v, "limit", (int32_t)limit);
        t->requested = limit;
    }
    if (status != NOSHI_OK) return status;
    *request = v;
    t->pending = ++t->generation;
    if (!t->pending) t->pending = ++t->generation;
    *id = t->pending;
    t->method = noshi_tl_id(v);
    return NOSHI_OK;
}

static noshi_status accept_hashes(noshi_file_transfer *t, const noshi_tl_value *vec) {
    noshi_file_hash hashes[NOSHI_FILE_HASH_MAX];
    uint32_t i, count = 0;
    if (!vec || vec->kind != NOSHI_TL_V_VEC || !vec->u.vec.count || vec->u.vec.count > NOSHI_FILE_HASH_MAX) return NOSHI_E_MALFORMED;
    for (i = 0; i < vec->u.vec.count; ++i) {
        const noshi_tl_value *v = vec->u.vec.items[i];
        const uint8_t *hash;
        size_t len;
        int64_t offset;
        int32_t limit;
        uint64_t effective;
        if (noshi_tl_get_i64(v, "offset", &offset) != NOSHI_OK || offset < 0 || (uint64_t)offset >= t->size ||
            noshi_tl_get_i32(v, "limit", &limit) != NOSHI_OK || limit <= 0 || (uint32_t)limit > NOSHI_FILE_RANGE_MAX ||
            noshi_tl_get_bytes(v, "hash", &hash, &len) != NOSHI_OK || len != 32) return NOSHI_E_MALFORMED;
        effective = (uint32_t)limit;
        if (effective > t->size - (uint64_t)offset) effective = t->size - (uint64_t)offset;
        if (((uint64_t)offset % 4096) || ((uint64_t)offset + effective < t->size && effective % 4096)) return NOSHI_E_MALFORMED;
        hashes[count].offset = (uint64_t)offset;
        hashes[count].limit = (uint32_t)effective;
        memcpy(hashes[count].hash, hash, 32);
        ++count;
    }
    for (i = 0; i < count; ++i) {
        uint32_t j;
        for (j = 0; j < i; ++j) if (hashes[i].offset < hashes[j].offset + hashes[j].limit &&
            hashes[j].offset < hashes[i].offset + hashes[i].limit) return NOSHI_E_SECURITY;
    }
    memcpy(t->hashes, hashes, count * sizeof(hashes[0]));
    t->hash_count = count;
    return current_hash(t) ? NOSHI_OK : NOSHI_E_MALFORMED;
}

static noshi_status redirect(noshi_file_transfer *t, const noshi_tl_value *v) {
    const uint8_t *key, *iv, *token;
    size_t key_len, iv_len, token_len;
    int32_t dc;
    noshi_status status;
    if (++t->redirects > 3 || t->cdn_disabled) return NOSHI_E_LIMIT;
    if (noshi_tl_get_i32(v, "dc_id", &dc) != NOSHI_OK || dc <= 0 ||
        noshi_tl_get_bytes(v, "encryption_key", &key, &key_len) != NOSHI_OK || key_len != 32 ||
        noshi_tl_get_bytes(v, "encryption_iv", &iv, &iv_len) != NOSHI_OK || iv_len != 16 ||
        noshi_tl_get_bytes(v, "file_token", &token, &token_len) != NOSHI_OK || !token_len || token_len > sizeof(t->token)) return NOSHI_E_MALFORMED;
    status = accept_hashes(t, noshi_tl_get(v, "file_hashes"));
    if (status != NOSHI_OK) return status;
    memcpy(t->cdn_key, key, 32); memcpy(t->cdn_iv, iv, 16); memcpy(t->token, token, token_len);
    t->token_len = token_len;
    t->cdn_dc = dc;
    t->cdn = 1;
    t->chunk.len = 0;
    return NOSHI_OK;
}

static noshi_status receive_chunk(noshi_file_transfer *t, const uint8_t *bytes, size_t len) {
    noshi_file_hash *hash = current_hash(t);
    uint8_t digest[32], iv[16];
    size_t mark = t->chunk.len;
    uint64_t next;
    int complete;
    noshi_status status;
    if (!hash || !len || mark > hash->limit || len > hash->limit - mark)
        return NOSHI_E_MALFORMED;
    status = noshi_file_download_advance(t->offset + mark, t->size, len, t->requested, FILE_SIZE_MAX, &next, &complete);
    if (status != NOSHI_OK) return status;
    status = noshi_wr_bytes(&t->chunk, bytes, len);
    if (status != NOSHI_OK) return status;
    if (t->cdn) {
        noshi_aes_ctr *ctr;
        uint64_t counter = (t->offset + mark) / 16u;
        if (counter > UINT32_MAX) return NOSHI_E_LIMIT;
        memcpy(iv, t->cdn_iv, 16);
        noshi_put_u32be(iv + 12, (uint32_t)counter);
        ctr = noshi_aes_ctr_new(t->cdn_key, iv);
        if (!ctr) return NOSHI_E_CRYPTO;
        status = noshi_aes_ctr_apply(ctr, t->chunk.data + mark, t->chunk.data + mark, len);
        noshi_aes_ctr_free(ctr);
        if (status != NOSHI_OK) return status;
    }
    if (t->chunk.len < hash->limit) return NOSHI_OK;
    status = noshi_sha256_one(t->chunk.data, t->chunk.len, digest);
    if (status == NOSHI_OK && !noshi_ct_equal(digest, hash->hash, 32)) status = NOSHI_E_SECURITY;
    if (status == NOSHI_OK) status = file_write(t->fd, t->chunk.data, t->chunk.len, t->offset);
    if (status == NOSHI_OK && fsync(t->fd) != 0) status = NOSHI_E_IO;
    if (status == NOSHI_OK) {
        t->offset = next;
        t->chunk.len = 0;
        if (complete) t->state = NOSHI_FILE_DONE;
    }
    return status;
}

noshi_status noshi_file_result(noshi_file_transfer *t, uint64_t id, int32_t dc, int cdn,
                                  uint64_t time_ms, const noshi_mt_rpc_result *r) {
    noshi_status status;
    int expected_cdn;
    int32_t expected_dc;
    if (!t || !r) return NOSHI_E_ARG;
    if (!id || id != t->pending || t->state != NOSHI_FILE_ACTIVE) return NOSHI_E_NOTFOUND;
    expected_cdn = t->method == NOSHI_TL_ID_upload_getCdnFile;
    expected_dc = expected_cdn ? t->cdn_dc : t->dc;
    if (cdn != expected_cdn || dc != expected_dc) return NOSHI_E_SECURITY;
    t->pending = 0;
    if (r->status != NOSHI_OK) {
        char name[128];
        int32_t number;
        noshi_mt_rpc_error_split(r->error_text, name, sizeof(name), &number);
        if (++t->attempts > NOSHI_FILE_RETRIES_MAX) { t->state = NOSHI_FILE_FAILED; return NOSHI_E_LIMIT; }
        if (r->status == NOSHI_E_RPC && (!strcmp(name, "FLOOD_WAIT") || !strcmp(name, "FLOOD_PREMIUM_WAIT")) && number > 0) {
            t->wait_until = time_ms + (uint64_t)number * 1000u;
            t->state = NOSHI_FILE_WAIT;
            return NOSHI_E_RETRY;
        }
        if (r->status == NOSHI_E_RPC && !strcmp(name, "FILE_MIGRATE") && number > 0 && !cdn) {
            t->dc = number;
            return NOSHI_E_RETRY;
        }
        if (r->status == NOSHI_E_RPC && (!strcmp(name, "FILE_REFERENCE_EXPIRED") || !strcmp(name, "FILE_REFERENCE_EMPTY"))) {
            t->state = NOSHI_FILE_REFRESH;
            return NOSHI_E_RETRY;
        }
        if (r->status == NOSHI_E_RPC && t->cdn && (!strcmp(name, "FILE_TOKEN_INVALID") || !strcmp(name, "REQUEST_TOKEN_INVALID"))) {
            t->cdn = 0;
            t->cdn_disabled = 1;
            t->chunk.len = 0;
            t->hash_count = 0;
            t->request_token_len = 0;
            noshi_wipe(t->cdn_key, 32);
            return NOSHI_E_RETRY;
        }
        if (r->status == NOSHI_E_TIMEOUT || r->status == NOSHI_E_IO || r->status == NOSHI_E_RETRY) return NOSHI_E_RETRY;
        t->state = NOSHI_FILE_FAILED;
        return r->status;
    }
    if (t->upload) {
        if (!noshi_tl_is(r->value, NOSHI_TL_ID_boolTrue)) status = NOSHI_E_RPC;
        else {
            status = t->big ? NOSHI_OK : noshi_digest_update(t->md5, t->chunk.data, t->chunk.len);
            if (status == NOSHI_OK) {
                t->offset += t->chunk.len;
                t->chunk.len = 0;
                if (t->offset == t->size) {
                    status = t->big ? NOSHI_OK : noshi_digest_finish(t->md5, t->md5_sum, sizeof(t->md5_sum));
                    if (status == NOSHI_OK) t->state = NOSHI_FILE_DONE;
                }
            }
        }
    } else if (t->method == NOSHI_TL_ID_upload_getFileHashes || t->method == NOSHI_TL_ID_upload_getCdnFileHashes ||
               t->method == NOSHI_TL_ID_upload_reuploadCdnFile) {
        status = accept_hashes(t, r->value);
        if (status == NOSHI_OK) t->request_token_len = 0;
    } else if (!cdn && noshi_tl_is(r->value, NOSHI_TL_ID_upload_fileCdnRedirect)) status = redirect(t, r->value);
    else if (cdn && noshi_tl_is(r->value, NOSHI_TL_ID_upload_cdnFileReuploadNeeded)) {
        const uint8_t *token;
        size_t len;
        status = noshi_tl_get_bytes(r->value, "request_token", &token, &len);
        if (status == NOSHI_OK && (!len || len > sizeof(t->request_token) || ++t->redirects > 3)) status = NOSHI_E_LIMIT;
        if (status == NOSHI_OK) { memcpy(t->request_token, token, len); t->request_token_len = len; }
    } else if (noshi_tl_is(r->value, cdn ? NOSHI_TL_ID_upload_cdnFile : NOSHI_TL_ID_upload_file)) {
        const uint8_t *bytes;
        size_t len;
        status = noshi_tl_get_bytes(r->value, "bytes", &bytes, &len);
        if (status == NOSHI_OK) status = receive_chunk(t, bytes, len);
    } else status = NOSHI_E_MALFORMED;
    if (status == NOSHI_OK) t->attempts = 0;
    else t->state = NOSHI_FILE_FAILED;
    return status;
}

noshi_status noshi_file_refresh(noshi_file_transfer *t, const noshi_tl_value *location) {
    noshi_arena arena;
    noshi_tl_value *old;
    noshi_writer encoded;
    noshi_status status;
    int64_t old_id, new_id;
    const uint8_t *old_thumb, *new_thumb;
    size_t old_len, new_len;
    if (!t || !location || t->state != NOSHI_FILE_REFRESH) return NOSHI_E_STATE;
    if (++t->references > 3) return NOSHI_E_LIMIT;
    noshi_arena_init(&arena, 256u * 1024u);
    noshi_writer_init(&encoded, 65536);
    status = read_location(t, &arena, &old);
    if (status == NOSHI_OK && (noshi_tl_id(old) != noshi_tl_id(location) ||
        noshi_tl_get_i64(old, "id", &old_id) != NOSHI_OK ||
        noshi_tl_get_i64(location, "id", &new_id) != NOSHI_OK || old_id != new_id ||
        noshi_tl_get_bytes(old, "thumb_size", &old_thumb, &old_len) != NOSHI_OK ||
        noshi_tl_get_bytes(location, "thumb_size", &new_thumb, &new_len) != NOSHI_OK ||
        old_len != new_len || !noshi_ct_equal(old_thumb, new_thumb, old_len))) status = NOSHI_E_SECURITY;
    if (status == NOSHI_OK) status = noshi_tl_encode(location, &encoded, NULL);
    if (status == NOSHI_OK) {
        noshi_writer_free(&t->location);
        t->location = encoded;
        memset(&encoded, 0, sizeof(encoded));
        t->state = NOSHI_FILE_ACTIVE;
    }
    noshi_writer_free(&encoded);
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_file_uploaded(noshi_file_transfer *t, noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *v;
    noshi_status status;
    char md5[33];
    size_t i;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!t || !arena || !t->upload || t->state != NOSHI_FILE_DONE) return NOSHI_E_STATE;
    v = noshi_tl_new_obj(arena, t->big ? "inputFileBig" : "inputFile");
    status = v ? noshi_tl_set_i64(arena, v, "id", (int64_t)t->id) : NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, v, "parts", (int32_t)t->parts);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, v, "name", t->name);
    if (!t->big) {
        for (i = 0; i < 16; ++i) snprintf(md5 + i * 2, 3, "%02x", t->md5_sum[i]);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, v, "md5_checksum", md5);
    }
    if (status == NOSHI_OK) *out = v;
    return status;
}

noshi_status noshi_file_publish(noshi_file_transfer *t, const char *destination) {
    if (!t || t->upload || t->state != NOSHI_FILE_DONE || !destination || !*destination || !t->temporary[0]) return NOSHI_E_STATE;
    if (t->fd >= 0 && fsync(t->fd) != 0) return NOSHI_E_IO;
    if (rename(t->temporary, destination) != 0) return NOSHI_E_IO;
    t->temporary[0] = 0;
    return NOSHI_OK;
}

noshi_status noshi_file_cancel(noshi_file_transfer *t) {
    noshi_status status = NOSHI_OK;
    if (!t) return NOSHI_E_ARG;
    t->pending = 0;
    t->state = NOSHI_FILE_CANCELLED;
    if (t->fd >= 0) { if (close(t->fd) != 0) status = NOSHI_E_IO; t->fd = -1; }
    if (t->temporary[0] && unlink(t->temporary) != 0 && errno != ENOENT) status = NOSHI_E_IO;
    if (status == NOSHI_OK) t->temporary[0] = 0;
    return status;
}

noshi_status noshi_file_close(noshi_file_transfer *t) {
    noshi_status status = NOSHI_OK;
    if (!t) return NOSHI_E_ARG;
    if (t->fd >= 0 && close(t->fd) != 0) status = NOSHI_E_IO;
    t->fd = -1;
    noshi_writer_free(&t->location);
    if (t->chunk.data) noshi_wipe(t->chunk.data, t->chunk.cap);
    noshi_writer_free(&t->chunk);
    noshi_digest_free(t->md5);
    t->md5 = NULL;
    noshi_wipe(t->cdn_key, sizeof(t->cdn_key));
    noshi_wipe(t->token, sizeof(t->token));
    return status;
}
