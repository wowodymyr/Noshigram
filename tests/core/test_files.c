#include "test_util.h"
#include "noshi_mt_files.h"
#include "noshi_tl_ids.h"

#include <fcntl.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>

#define TOKEN_THREADS 4
#define TOKENS_PER_THREAD 256
static void *make_tokens(void *context) {
    uint64_t *tokens = context;
    for (size_t i = 0; i < TOKENS_PER_THREAD; ++i) tokens[i] = noshi_file_temporary_token();
    return NULL;
}

static void test_temporary_tokens(void) {
    uint64_t tokens[TOKEN_THREADS][TOKENS_PER_THREAD];
    pthread_t threads[TOKEN_THREADS];
    for (size_t i = 0; i < TOKEN_THREADS; ++i) CHECK_EQ_INT(pthread_create(&threads[i], NULL, make_tokens, tokens[i]), 0);
    for (size_t i = 0; i < TOKEN_THREADS; ++i) CHECK_EQ_INT(pthread_join(threads[i], NULL), 0);
    for (size_t i = 0; i < TOKEN_THREADS * TOKENS_PER_THREAD; ++i) {
        uint64_t token = tokens[i / TOKENS_PER_THREAD][i % TOKENS_PER_THREAD];
        CHECK(token != 0);
        for (size_t j = 0; j < i; ++j) CHECK(token != tokens[j / TOKENS_PER_THREAD][j % TOKENS_PER_THREAD]);
    }
}

static noshi_tl_value *location(noshi_arena *a, int64_t id) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "inputDocumentFileLocation");
    CHECK_EQ_INT(noshi_tl_set_i64(a, v, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(a, v, "access_hash", 500), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_bytes(a, v, "file_reference", "ref", 3), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(a, v, "thumb_size", ""), NOSHI_OK);
    return v;
}
static noshi_tl_value *hashes(noshi_arena *a, const uint8_t *data, size_t len) {
    noshi_tl_value *v = noshi_tl_new_obj(a, "fileHash"), *vec = noshi_tl_new_vec(a, 1);
    uint8_t hash[32];
    CHECK_EQ_INT(noshi_sha256_one(data, len, hash), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(a, v, "offset", 0), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(a, v, "limit", (int32_t)len), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_bytes(a, v, "hash", hash, 32), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_vec_set(vec, 0, v), NOSHI_OK);
    return vec;
}
static noshi_status reply(noshi_file_transfer *t, uint64_t id, int32_t dc, int cdn,
                           const noshi_tl_value *v, noshi_status status, const char *error) {
    noshi_mt_rpc_result r;
    memset(&r, 0, sizeof(r));
    r.status = status; r.value = v; r.error_text = error;
    return noshi_file_result(t, id, dc, cdn, 1000, &r);
}
static uint64_t next(noshi_file_transfer *t, noshi_arena *a, noshi_tl_value **request, int32_t *dc, int *cdn) {
    uint64_t id = 0;
    noshi_writer w;
    CHECK_EQ_INT(noshi_file_next(t, 1000, a, request, &id, dc, cdn), NOSHI_OK);
    noshi_writer_init(&w, 2u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_tl_encode(*request, &w, NULL), NOSHI_OK);
    noshi_writer_free(&w);
    return id;
}

static void test_upload(void) {
    char path[] = "/tmp/noshigram-upload-XXXXXX";
    int fd = mkstemp(path), cdn;
    int32_t dc;
    noshi_file_transfer t;
    noshi_arena a;
    noshi_tl_value *v;
    uint64_t id;
    uint8_t bytes[3073], sum[16];
    const uint8_t *part, *md5;
    size_t len, md5_len, i;
    char expected[33];
    CHECK(fd >= 0);
    for (i = 0; i < sizeof(bytes); ++i) bytes[i] = (uint8_t)i;
    CHECK_EQ_INT(write(fd, bytes, sizeof(bytes)), sizeof(bytes));
    noshi_arena_init(&a, 4u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_file_upload(&t, fd, "voice.ogg", 2, 1024, 3000), NOSHI_OK);
    close(fd);
    id = next(&t, &a, &v, &dc, &cdn);
    CHECK_EQ_INT(reply(&t, id, dc, cdn, NULL, NOSHI_E_TIMEOUT, NULL), NOSHI_E_RETRY);
    CHECK_EQ_INT(t.offset, 0);
    for (i = 0; t.state != NOSHI_FILE_DONE; ++i) {
        id = next(&t, &a, &v, &dc, &cdn);
        CHECK(noshi_tl_is(v, NOSHI_TL_ID_upload_saveFilePart));
        CHECK_EQ_INT(noshi_tl_get_bytes(v, "bytes", &part, &len), NOSHI_OK);
        CHECK_MEM(part, bytes + i * 1024, len);
        CHECK_EQ_INT(reply(&t, id, dc, cdn, noshi_tl_new_obj(&a, "boolTrue"), NOSHI_OK, NULL), NOSHI_OK);
    }
    CHECK_EQ_INT(t.offset, sizeof(bytes));
    CHECK_EQ_INT(noshi_file_uploaded(&t, &a, &v), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_get_bytes(v, "md5_checksum", &md5, &md5_len), NOSHI_OK);
    { noshi_slice slice = {bytes, sizeof(bytes)}; CHECK_EQ_INT(noshi_md5(&slice, 1, sum), NOSHI_OK); }
    for (i = 0; i < 16; ++i) snprintf(expected + i * 2, 3, "%02x", sum[i]);
    CHECK_EQ_INT(md5_len, 32);
    CHECK_MEM(md5, expected, 32);
    CHECK_EQ_INT(noshi_file_close(&t), NOSHI_OK);
    unlink(path);
    noshi_arena_free(&a);
}

static void test_download(int corrupt, int use_cdn) {
    char temporary[] = "/tmp/noshigram-download-XXXXXX";
    char final[] = "/tmp/noshigram-final-XXXXXX";
    int fd = mkstemp(temporary), final_fd = mkstemp(final), cdn;
    int32_t dc;
    noshi_file_transfer t;
    noshi_arena a;
    noshi_tl_value *v, *request, *vec;
    uint64_t id;
    uint8_t bytes[8193], encrypted[8193], key[32], iv[16], got[8193];
    struct stat st;
    size_t i;
    for (i = 0; i < sizeof(bytes); ++i) bytes[i] = (uint8_t)(i * 7u);
    memset(key, 17, sizeof(key)); memset(iv, 0, sizeof(iv));
    CHECK(fd >= 0 && final_fd >= 0);
    close(fd); close(final_fd); unlink(temporary);
    noshi_arena_init(&a, 8u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_file_download(&t, temporary, location(&a, 100), 2, sizeof(bytes), 0), NOSHI_OK);
    id = next(&t, &a, &request, &dc, &cdn);
    CHECK(noshi_tl_is(request, NOSHI_TL_ID_upload_getFileHashes));
    vec = hashes(&a, bytes, sizeof(bytes));
    CHECK_EQ_INT(reply(&t, id, 2, 1, vec, NOSHI_OK, NULL), NOSHI_E_SECURITY);
    CHECK_EQ_INT(reply(&t, id, dc, cdn, vec, NOSHI_OK, NULL), NOSHI_OK);
    id = next(&t, &a, &request, &dc, &cdn);
    if (use_cdn) {
        v = noshi_tl_new_obj(&a, "upload.fileCdnRedirect");
        CHECK_EQ_INT(noshi_tl_set_i32(&a, v, "dc_id", 5), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_bytes(&a, v, "file_token", "token", 5), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_bytes(&a, v, "encryption_key", key, 32), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set_bytes(&a, v, "encryption_iv", iv, 16), NOSHI_OK);
        CHECK_EQ_INT(noshi_tl_set(v, "file_hashes", vec), NOSHI_OK);
        CHECK_EQ_INT(reply(&t, id, dc, cdn, v, NOSHI_OK, NULL), NOSHI_OK);
        id = next(&t, &a, &request, &dc, &cdn);
        CHECK_EQ_INT(dc, 5); CHECK_EQ_INT(cdn, 1);
        {
            noshi_aes_ctr *ctr = noshi_aes_ctr_new(key, iv);
            CHECK(ctr != NULL);
            CHECK_EQ_INT(noshi_aes_ctr_apply(ctr, bytes, encrypted, sizeof(bytes)), NOSHI_OK);
            noshi_aes_ctr_free(ctr);
        }
    } else memcpy(encrypted, bytes, sizeof(bytes));
    if (corrupt) encrypted[sizeof(encrypted) - 1] ^= 1;
    v = noshi_tl_new_obj(&a, use_cdn ? "upload.cdnFile" : "upload.file");
    CHECK_EQ_INT(noshi_tl_set_bytes(&a, v, "bytes", encrypted, sizeof(encrypted)), NOSHI_OK);
    CHECK_EQ_INT(reply(&t, id, dc, cdn, v, NOSHI_OK, NULL), corrupt ? NOSHI_E_SECURITY : NOSHI_OK);
    CHECK_EQ_INT(fstat(t.fd, &st), 0);
    CHECK_EQ_INT(st.st_size, corrupt ? 0 : sizeof(bytes));
    CHECK_EQ_INT(t.offset, corrupt ? 0 : sizeof(bytes));
    if (!corrupt) {
        CHECK_EQ_INT(noshi_file_publish(&t, final), NOSHI_OK);
        fd = open(final, O_RDONLY);
        CHECK(fd >= 0);
        CHECK_EQ_INT(read(fd, got, sizeof(got)), sizeof(got));
        CHECK_MEM(got, bytes, sizeof(got));
        close(fd);
        CHECK_EQ_INT(noshi_file_close(&t), NOSHI_OK);
    } else {
        CHECK_EQ_INT(noshi_file_cancel(&t), NOSHI_OK);
        CHECK_EQ_INT(access(temporary, F_OK), -1);
        CHECK_EQ_INT(noshi_file_close(&t), NOSHI_OK);
    }
    unlink(final);
    noshi_arena_free(&a);
}

static void test_resume_refresh(void) {
    char path[] = "/tmp/noshigram-resume-XXXXXX";
    int fd = mkstemp(path), cdn;
    int32_t dc;
    uint64_t id;
    noshi_file_transfer t;
    noshi_arena a;
    noshi_tl_value *v;
    struct stat st;
    CHECK(fd >= 0);
    CHECK_EQ_INT(ftruncate(fd, 8192), 0);
    close(fd);
    noshi_arena_init(&a, 1024u * 1024u);
    CHECK_EQ_INT(noshi_file_download(&t, path, location(&a, 123), 2, 16384, 4096), NOSHI_OK);
    CHECK_EQ_INT(fstat(t.fd, &st), 0);
    CHECK_EQ_INT(st.st_size, 4096);
    id = next(&t, &a, &v, &dc, &cdn);
    CHECK_EQ_INT(reply(&t, id, dc, cdn, NULL, NOSHI_E_RPC, "FILE_REFERENCE_EXPIRED"), NOSHI_E_RETRY);
    CHECK_EQ_INT(noshi_file_refresh(&t, location(&a, 124)), NOSHI_E_SECURITY);
    CHECK_EQ_INT(noshi_file_refresh(&t, location(&a, 123)), NOSHI_OK);
    id = next(&t, &a, &v, &dc, &cdn);
    CHECK_EQ_INT(reply(&t, id, dc, cdn, NULL, NOSHI_E_RPC, "FILE_MIGRATE_4"), NOSHI_E_RETRY);
    id = next(&t, &a, &v, &dc, &cdn);
    CHECK_EQ_INT(dc, 4);
    CHECK_EQ_INT(reply(&t, id, dc, cdn, NULL, NOSHI_E_RPC, "FLOOD_WAIT_5"), NOSHI_E_RETRY);
    CHECK_EQ_INT(noshi_file_next(&t, 5999, &a, &v, &id, &dc, &cdn), NOSHI_E_RETRY);
    CHECK_EQ_INT(noshi_file_next(&t, 6000, &a, &v, &id, &dc, &cdn), NOSHI_OK);
    CHECK_EQ_INT(noshi_file_cancel(&t), NOSHI_OK);
    CHECK_EQ_INT(noshi_file_close(&t), NOSHI_OK);
    noshi_arena_free(&a);
}

static void fill_file_bytes(uint8_t *bytes, size_t length, uint64_t offset) {
    for (size_t i = 0; i < length; ++i) {
        uint64_t position = offset + i;
        bytes[i] = (uint8_t)((position * 7u) ^ (position >> 13));
    }
}

static void test_large_download_with_short_part(void) {
    char path[] = "/tmp/noshigram-large-download-XXXXXX";
    const uint64_t size = 13u * 1024u * 1024u + 123u;
    uint8_t *bytes = malloc(NOSHI_FILE_RANGE_MAX);
    int fd = mkstemp(path), cdn;
    int32_t dc;
    int shortened = 0, timed_out = 0;
    noshi_file_transfer transfer;
    noshi_arena arena;
    struct stat st;
    CHECK(bytes && fd >= 0);
    if (!bytes || fd < 0) { free(bytes); if (fd >= 0) close(fd); unlink(path); return; }
    close(fd);
    unlink(path);
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    CHECK_EQ_INT(noshi_file_download(&transfer, path, location(&arena, 123), 2, size, 0), NOSHI_OK);
    for (unsigned step = 0; step < 1024 && transfer.state == NOSHI_FILE_ACTIVE; ++step) {
        noshi_tl_value *request, *value;
        int64_t offset = 0;
        int32_t limit = 0;
        size_t length;
        noshi_arena_free(&arena);
        noshi_arena_init(&arena, 4u * 1024u * 1024u);
        uint64_t id = next(&transfer, &arena, &request, &dc, &cdn);
        CHECK_EQ_INT(noshi_tl_get_i64(request, "offset", &offset), NOSHI_OK);
        if (noshi_tl_is(request, NOSHI_TL_ID_upload_getFileHashes)) {
            length = (size_t)(size - (uint64_t)offset);
            if (length > NOSHI_FILE_RANGE_MAX) length = NOSHI_FILE_RANGE_MAX;
            fill_file_bytes(bytes, length, (uint64_t)offset);
            value = hashes(&arena, bytes, length);
            CHECK_EQ_INT(noshi_tl_set_i64(&arena, value->u.vec.items[0], "offset", offset), NOSHI_OK);
        } else {
            CHECK(noshi_tl_is(request, NOSHI_TL_ID_upload_getFile));
            CHECK_EQ_INT(noshi_tl_get_i32(request, "limit", &limit), NOSHI_OK);
            CHECK_EQ_INT(offset % 4096, 0);
            CHECK_EQ_INT(NOSHI_FILE_RANGE_MAX % (uint32_t)limit, 0);
            CHECK_EQ_INT((uint64_t)offset / NOSHI_FILE_RANGE_MAX, ((uint64_t)offset + (uint32_t)limit - 1) / NOSHI_FILE_RANGE_MAX);
            if (!timed_out && (uint64_t)offset >= 10u * 1024u * 1024u) {
                uint64_t committed = transfer.offset;
                CHECK_EQ_INT(reply(&transfer, id, dc, cdn, NULL, NOSHI_E_TIMEOUT, NULL), NOSHI_E_RETRY);
                CHECK_EQ_INT(transfer.offset, committed);
                timed_out = 1;
                continue;
            }
            length = (size_t)(size - (uint64_t)offset);
            if (length > (size_t)limit) length = (size_t)limit;
            if (!shortened && (uint64_t)offset >= 12u * 1024u * 1024u) {
                length /= 2;
                shortened = 1;
            }
            fill_file_bytes(bytes, length, (uint64_t)offset);
            value = noshi_tl_new_obj(&arena, "upload.file");
            CHECK_EQ_INT(noshi_tl_set_bytes(&arena, value, "bytes", bytes, length), NOSHI_OK);
        }
        noshi_status status = reply(&transfer, id, dc, cdn, value, NOSHI_OK, NULL);
        CHECK_EQ_INT(status, NOSHI_OK);
        if (status != NOSHI_OK) break;
    }
    CHECK(shortened && timed_out);
    CHECK_EQ_INT(transfer.state, NOSHI_FILE_DONE);
    CHECK_EQ_INT(transfer.offset, size);
    CHECK_EQ_INT(fstat(transfer.fd, &st), 0);
    CHECK_EQ_INT(st.st_size, size);
    if (transfer.state == NOSHI_FILE_DONE) {
        uint8_t readback[16384];
        for (uint64_t offset = 0; offset < size; offset += sizeof(readback)) {
            size_t length = (size_t)(size - offset);
            if (length > sizeof(readback)) length = sizeof(readback);
            fill_file_bytes(bytes, length, offset);
            CHECK_EQ_INT(pread(transfer.fd, readback, length, (off_t)offset), length);
            CHECK_MEM(bytes, readback, length);
        }
    }
    CHECK_EQ_INT(noshi_file_cancel(&transfer), NOSHI_OK);
    CHECK_EQ_INT(noshi_file_close(&transfer), NOSHI_OK);
    noshi_arena_free(&arena);
    free(bytes);
    unlink(path);
}

static void test_download_advance(void) {
    static const struct {
        uint64_t offset, size;
        size_t received;
        uint32_t requested;
        uint64_t capacity;
        noshi_status status;
        uint64_t next;
        int complete;
    } cases[] = {
        {0, 1024, 512, 512, 4096, NOSHI_OK, 512, 0},
        {512, 1024, 512, 512, 4096, NOSHI_OK, 1024, 1},
        {512, 700, 188, 512, 4096, NOSHI_OK, 700, 1},
        {0, 700, 188, 512, 4096, NOSHI_OK, 188, 0},
        {512, 1024, 0, 512, 4096, NOSHI_E_TRUNCATED, 0, 0},
        {512, 700, 189, 512, 4096, NOSHI_E_MALFORMED, 0, 0},
        {701, 700, 0, 512, 4096, NOSHI_E_MALFORMED, 0, 0},
        {0, 0, 512, 512, 4096, NOSHI_OK, 512, 0},
        {512, 0, 0, 512, 4096, NOSHI_OK, 512, 1},
        {512, 0, 188, 512, 4096, NOSHI_OK, 700, 1},
        {0, 0, 513, 512, 4096, NOSHI_E_MALFORMED, 0, 0},
        {0, 4096, 512, 512, 4096, NOSHI_OK, 512, 0},
        {3584, 4096, 512, 512, 4096, NOSHI_OK, 4096, 1},
        {4096, 0, 0, 512, 4096, NOSHI_OK, 4096, 1},
        {4096, 0, 1, 512, 4096, NOSHI_E_LIMIT, 0, 0},
        {0, 4097, 512, 512, 4096, NOSHI_E_LIMIT, 0, 0},
        {4097, 0, 0, 512, 4096, NOSHI_E_LIMIT, 0, 0},
        {UINT64_MAX, 0, 1, 512, UINT64_MAX, NOSHI_E_LIMIT, 0, 0},
        {UINT64_MAX - 511, UINT64_MAX, 511, 512, UINT64_MAX, NOSHI_OK, UINT64_MAX, 1},
        {0, 0, 0, 0, 4096, NOSHI_E_ARG, 0, 0},
        {0, 0, 0, 512, 0, NOSHI_E_ARG, 0, 0}
    };
    size_t i;
    uint64_t end = 99;
    int complete = 99;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        end = 99;
        complete = 99;
        CHECK_EQ_INT(noshi_file_download_advance(cases[i].offset, cases[i].size, cases[i].received,
                                                  cases[i].requested, cases[i].capacity, &end, &complete), cases[i].status);
        CHECK(end == cases[i].next);
        CHECK_EQ_INT(complete, cases[i].complete);
    }
    CHECK_EQ_INT(noshi_file_download_advance(0, 0, 0, 512, 4096, NULL, &complete), NOSHI_E_ARG);
    CHECK_EQ_INT(complete, 0);
    CHECK_EQ_INT(noshi_file_download_advance(0, 0, 0, 512, 4096, &end, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(end, 0);
}

static void test_download_part_boundaries(void) {
    const uint32_t preferred = 512u * 1024u;
    uint32_t limit = 0;
    /* short aligned replies can leave the next request close to a mebibyte boundary */
    for (uint64_t offset = 0; offset < 3u * NOSHI_FILE_RANGE_MAX; offset += 4096) {
        CHECK_EQ_INT(noshi_file_download_part(offset, preferred, &limit), NOSHI_OK);
        CHECK(limit > 0 && limit <= preferred);
        CHECK_EQ_INT(limit % 4096, 0);
        CHECK_EQ_INT(NOSHI_FILE_RANGE_MAX % limit, 0);
        CHECK_EQ_INT(offset / NOSHI_FILE_RANGE_MAX, (offset + limit - 1) / NOSHI_FILE_RANGE_MAX);
    }
    CHECK_EQ_INT(noshi_file_download_part(0, preferred, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_file_download_part(1, preferred, &limit), NOSHI_E_ARG);
    CHECK_EQ_INT(limit, 0);
    CHECK_EQ_INT(noshi_file_download_part(0, 0, &limit), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_file_download_part(0, 4095, &limit), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_file_download_part(0, 12288, &limit), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_file_download_part(0, NOSHI_FILE_RANGE_MAX + 4096, &limit), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_file_download_part(UINT64_MAX, preferred, &limit), NOSHI_E_ARG);
    CHECK_EQ_INT(limit, 0);
}

static void test_retry_delays(void) {
    uint32_t delay = 99;
    const char *terminal[] = {NULL, "", "INTERNAL", "FILE_REFERENCE_EXPIRED", "FILE_REFERENCE_INVALID", "OFFSET_INVALID",
                              "AUTH_KEY_UNREGISTERED", "FLOOD_WAIT", "FLOOD_WAIT_0", "FLOOD_WAIT_-1", "FLOOD_WAIT_301",
                              "FLOOD_WAIT_9999999999", "FLOOD_WAIT_1x", "FLOOD_PREMIUM_WAIT_301"};
    for (uint32_t retries = 0; retries < NOSHI_FILE_RETRIES_MAX; ++retries) {
        CHECK(noshi_file_retry_delay("TIMEOUT", retries, &delay));
        CHECK_EQ_INT(delay, 1000u << retries);
        CHECK(noshi_file_retry_delay("OFFLINE", retries, &delay));
        CHECK_EQ_INT(delay, 1000u << retries);
        CHECK(noshi_file_retry_delay("FLOOD_WAIT_7", retries, &delay));
        CHECK_EQ_INT(delay, 7000);
        CHECK(noshi_file_retry_delay("FLOOD_PREMIUM_WAIT_300", retries, &delay));
        CHECK_EQ_INT(delay, 300000);
    }
    for (size_t i = 0; i < sizeof(terminal) / sizeof(terminal[0]); ++i) {
        delay = 99;
        CHECK(!noshi_file_retry_delay(terminal[i], 0, &delay));
        CHECK_EQ_INT(delay, 0);
    }
    CHECK(!noshi_file_retry_delay("TIMEOUT", NOSHI_FILE_RETRIES_MAX, &delay));
    CHECK_EQ_INT(delay, 0);
    CHECK(!noshi_file_retry_delay("OFFLINE", UINT32_MAX, &delay));
    CHECK(!noshi_file_retry_delay("FLOOD_WAIT_1", NOSHI_FILE_RETRIES_MAX, &delay));
    CHECK(!noshi_file_retry_delay("TIMEOUT", 0, NULL));
}

int main(void) {
    test_temporary_tokens();
    test_download_part_boundaries();
    test_retry_delays();
    test_large_download_with_short_part();
    test_download_advance();
    test_upload();
    test_download(0, 0);
    test_download(1, 0);
    test_download(0, 1);
    test_download(1, 1);
    test_resume_refresh();
    return test_finish("test_files");
}
