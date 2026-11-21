#ifndef NOSHI_BYTES_H
#define NOSHI_BYTES_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

typedef struct noshi_slice {
    const uint8_t *data;
    size_t len;
} noshi_slice;

typedef struct noshi_reader {
    const uint8_t *data;
    size_t len;
    size_t pos;
    noshi_status status;
} noshi_reader;

void noshi_reader_init(noshi_reader *r, const uint8_t *data, size_t len);
size_t noshi_reader_left(const noshi_reader *r);
uint8_t noshi_rd_u8(noshi_reader *r);
uint32_t noshi_rd_u32le(noshi_reader *r);
uint64_t noshi_rd_u64le(noshi_reader *r);
uint32_t noshi_rd_u32be(noshi_reader *r);
const uint8_t *noshi_rd_bytes(noshi_reader *r, size_t n);

typedef struct noshi_writer {
    uint8_t *data;
    size_t len;
    size_t cap;
    size_t max;
    noshi_status status;
} noshi_writer;

void noshi_writer_init(noshi_writer *w, size_t max);
void noshi_writer_free(noshi_writer *w);
uint8_t *noshi_writer_take(noshi_writer *w, size_t *len);
noshi_status noshi_wr_reserve(noshi_writer *w, size_t extra);
noshi_status noshi_wr_bytes(noshi_writer *w, const void *data, size_t n);
noshi_status noshi_wr_zero(noshi_writer *w, size_t n);
noshi_status noshi_wr_u8(noshi_writer *w, uint8_t v);
noshi_status noshi_wr_u32le(noshi_writer *w, uint32_t v);
noshi_status noshi_wr_u64le(noshi_writer *w, uint64_t v);
noshi_status noshi_wr_u32be(noshi_writer *w, uint32_t v);

void noshi_put_u32le(uint8_t *out, uint32_t v);
void noshi_put_u64le(uint8_t *out, uint64_t v);
void noshi_put_u32be(uint8_t *out, uint32_t v);
void noshi_put_u64be(uint8_t *out, uint64_t v);
uint32_t noshi_get_u32le(const uint8_t *in);
uint64_t noshi_get_u64le(const uint8_t *in);
uint32_t noshi_get_u32be(const uint8_t *in);
uint64_t noshi_get_u64be(const uint8_t *in);

int noshi_ct_equal(const void *a, const void *b, size_t n);
/* a plain memset on a dead buffer is removed by the optimizer, key material would stay in memory */
void noshi_wipe(void *p, size_t n);

#endif
