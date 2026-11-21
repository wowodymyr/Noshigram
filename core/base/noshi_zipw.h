#ifndef NOSHI_ZIPW_H
#define NOSHI_ZIPW_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* a writer for the zip that the logs of the app are exported in: stored entries only, no zip64, no encryption, so what it writes is what
   noshi_zip_open reads and what every unzip tool takes. an entry is added whole from memory; the archive is on disk only after finish */

typedef struct noshi_zipw noshi_zipw;

/* creates the file, which must not exist yet (NOSHI_E_STATE when it does) */
noshi_status noshi_zipw_begin(const char *path, noshi_zipw **out);
/* name is relative with no "..", no leading slash and no backslash, shorter than NOSHI_ZIP_NAME_MAX; NOSHI_E_LIMIT past 65534 entries or 4 GB */
noshi_status noshi_zipw_add(noshi_zipw *zip, const char *name, const uint8_t *data, size_t len, uint32_t mode);
/* writes the directory and closes the file; the writer is gone afterwards, whatever the result, and a failed archive is removed */
noshi_status noshi_zipw_finish(noshi_zipw *zip);
/* drops an archive that is not wanted: closes and removes the file */
void noshi_zipw_abort(noshi_zipw *zip);

#endif
