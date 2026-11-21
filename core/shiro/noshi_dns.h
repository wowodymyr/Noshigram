#ifndef NOSHI_DNS_H
#define NOSHI_DNS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the largest query this builds, and the largest answer the caller should read: a name of 253 characters and the header fit in the first,
   and the answers of the names the app asks for fit in the second */
#define NOSHI_DNS_QUERY_MAX 300
#define NOSHI_DNS_ANSWER_MAX 1500

/* a query for the A record of host, recursion desired, with the given id. host is a name of letters, digits, hyphens and underscores in labels of 1
   to 63 characters, 253 in all, with at most one trailing dot; anything else is NOSHI_E_ARG. NOSHI_E_LIMIT when cap is too small */
noshi_status noshi_dns_query_a(const char *host, uint16_t id, uint8_t *out, size_t cap, size_t *len);

/* the first IPv4 address of an answer to such a query, in host order, and its time to live in seconds. NOSHI_E_MALFORMED for a message that is
   cut off or does not follow the format or does not answer id, NOSHI_E_NOTFOUND for a name the server does not have or an answer without an A
   record, NOSHI_E_RETRY for a truncated answer, NOSHI_E_IO for any other server failure */
noshi_status noshi_dns_answer_a(const uint8_t *msg, size_t len, uint16_t id, uint32_t *ip, uint32_t *ttl);

#endif
