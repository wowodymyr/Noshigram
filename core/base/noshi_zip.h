#ifndef NOSHI_ZIP_H
#define NOSHI_ZIP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* a reader for the zip of an ipa, kept to what `zip -qrX` writes: stored and deflate entries, no zip64, no encryption, no links.
   The archive is read from a file with explicit offsets and never held in memory; every name, size and offset is checked before use */

#define NOSHI_ZIP_MAX_ENTRIES 4096u
#define NOSHI_ZIP_NAME_MAX 256u
#define NOSHI_ZIP_MAX_ENTRY_SIZE (128u * 1024u * 1024u)
#define NOSHI_ZIP_MAX_TOTAL_SIZE (256u * 1024u * 1024u)

typedef struct noshi_zip noshi_zip;

typedef struct noshi_zip_entry {
    char name[NOSHI_ZIP_NAME_MAX];    /* relative, no "..", no leading slash; a directory ends with a slash */
    uint32_t crc32;
    uint32_t size;                      /* uncompressed */
    uint32_t packed;
    uint32_t mode;                      /* the unix permission bits, 0644 when the archive does not say */
    uint32_t offset;                    /* of the local header */
    int deflated;
    int is_dir;
} noshi_zip_entry;

/* NOSHI_E_MALFORMED for a broken or unsafe archive, NOSHI_E_UNSUPPORTED for a valid feature this reader leaves out */
noshi_status noshi_zip_open(const char *path, noshi_zip **out);
void noshi_zip_close(noshi_zip *zip);
size_t noshi_zip_count(const noshi_zip *zip);
const noshi_zip_entry *noshi_zip_entry_at(const noshi_zip *zip, size_t index);

/* inflates one file entry to dest, which must not exist, checking its length and crc; a partial file is removed on failure.
   progress, when set, gets the bytes written so far, and a return other than NOSHI_OK stops the extraction with that status */
typedef noshi_status (*noshi_zip_progress)(void *ctx, uint32_t written);
noshi_status noshi_zip_extract(const noshi_zip *zip, const noshi_zip_entry *entry, const char *dest, noshi_zip_progress progress, void *ctx);

/* 1 when the file at path has the entry's size and crc, 0 when it differs or is absent; a read failure is an error */
noshi_status noshi_zip_entry_matches(const noshi_zip_entry *entry, const char *path, int *same);

#endif
