#ifndef NOSHI_HELLO_H
#define NOSHI_HELLO_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* cuts the first TLS record in two records inside the server name, the tlsrec strategy of byebyedpi; it helps against a network that reads the
   name of the server from one record or one segment. a filter that reads the SNI of one record or one segment never sees the whole name. the bytes after the two record headers are the original bytes, so the handshake transcript stays intact

   midpoint 0 cuts one byte into the name, 1 cuts at its middle. *record_cut is the offset of the second record header in output, where the caller also
   cuts the TCP stream. input must be exactly one ClientHello record with a server name of at least two bytes (NOSHI_E_MALFORMED otherwise), capacity
   at least length + NOSHI_HELLO_GROWTH (NOSHI_E_LIMIT). outputs are zeroed on failure */
#define NOSHI_HELLO_GROWTH 5u

noshi_status noshi_hello_split(const uint8_t *input, size_t length, uint8_t *output, size_t capacity,
                               size_t *output_length, size_t *record_cut, int midpoint);

#endif
