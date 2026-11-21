#ifndef NOSHI_MT_FILES_H
#define NOSHI_MT_FILES_H

#include "noshi_crypto.h"
#include "noshi_mt_client.h"

#define NOSHI_FILE_HASH_MAX 32u
#define NOSHI_FILE_PART_MAX (512u * 1024u)
#define NOSHI_FILE_RANGE_MAX (1024u * 1024u)
#define NOSHI_FILE_RETRIES_MAX 5u

/* unique within the process, including across media cache instances */
uint64_t noshi_file_temporary_token(void);

typedef enum noshi_file_state {
    NOSHI_FILE_ACTIVE = 0,
    NOSHI_FILE_REFRESH,
    NOSHI_FILE_WAIT,
    NOSHI_FILE_DONE,
    NOSHI_FILE_FAILED,
    NOSHI_FILE_CANCELLED
} noshi_file_state;

typedef struct noshi_file_hash {
    uint64_t offset;
    uint32_t limit;
    uint8_t hash[32];
} noshi_file_hash;

typedef struct noshi_file_transfer {
    int fd;
    int upload;
    int big;
    int32_t dc;
    int32_t cdn_dc;
    int cdn;
    int cdn_disabled;
    noshi_file_state state;
    uint64_t size;
    uint64_t offset;
    uint64_t id;
    uint64_t generation;
    uint64_t pending;
    uint64_t wait_until;
    uint32_t method;
    uint32_t part_size;
    uint32_t parts;
    uint32_t attempts;
    uint32_t references;
    uint32_t redirects;
    uint32_t requested;
    char name[256];
    char temporary[1024];
    noshi_writer location;
    noshi_writer chunk;
    uint8_t token[4096];
    size_t token_len;
    uint8_t request_token[4096];
    size_t request_token_len;
    uint8_t cdn_key[32];
    uint8_t cdn_iv[16];
    noshi_file_hash hashes[NOSHI_FILE_HASH_MAX];
    uint32_t hash_count;
    noshi_digest *md5;
    uint8_t md5_sum[16];
} noshi_file_transfer;

/* keeps each getFile request inside one mebibyte after a short response changes the next offset */
noshi_status noshi_file_download_part(uint64_t offset, uint32_t preferred, uint32_t *limit);

/* size zero uses a short reply as EOF; a known size accepts progress until its last byte */
noshi_status noshi_file_download_advance(uint64_t offset, uint64_t size, size_t received,
                                           uint32_t requested, uint64_t capacity,
                                           uint64_t *next, int *complete);

/* bounded repeats of a failed part; flood errors keep the server's requested wait */
int noshi_file_retry_delay(const char *error_name, uint32_t retries, uint32_t *delay_ms);

/* a transfer must survive its caller closing the source descriptor */
noshi_status noshi_file_upload(noshi_file_transfer *t, int fd, const char *name, int32_t dc,
                                  uint32_t part_size, uint32_t max_parts);
noshi_status noshi_file_download(noshi_file_transfer *t, const char *temporary,
                                    const noshi_tl_value *location, int32_t dc,
                                    uint64_t size, uint64_t verified_offset);
noshi_status noshi_file_next(noshi_file_transfer *t, uint64_t time_ms, noshi_arena *arena,
                                noshi_tl_value **request, uint64_t *id, int32_t *dc, int *cdn);
noshi_status noshi_file_result(noshi_file_transfer *t, uint64_t id, int32_t dc, int cdn,
                                  uint64_t time_ms, const noshi_mt_rpc_result *result);
noshi_status noshi_file_refresh(noshi_file_transfer *t, const noshi_tl_value *location);
noshi_status noshi_file_uploaded(noshi_file_transfer *t, noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_file_publish(noshi_file_transfer *t, const char *destination);
noshi_status noshi_file_cancel(noshi_file_transfer *t);
noshi_status noshi_file_close(noshi_file_transfer *t);

#endif
