#ifndef NOSHI_RELEASE_H
#define NOSHI_RELEASE_H

#include <stddef.h>
#include <stdint.h>
#include "noshi_status.h"

#define NOSHI_RELEASE_TAG_MAX 80
#define NOSHI_RELEASE_BODY_MAX 16384

#define NOSHI_RELEASE_URL_MAX 384
/* the only place an update is fetched from; a url from the release json that does not start with it is never taken */
#define NOSHI_RELEASE_DOWNLOAD_PREFIX "https://github.com/wowodymyr/Noshigram/releases/download/"

typedef struct noshi_release {
    char tag[NOSHI_RELEASE_TAG_MAX];
    char body[NOSHI_RELEASE_BODY_MAX];
    /* the assets Noshigram-<tag>.ipa and Noshigram-<tag>.ipa.sha256, empty when the release lacks one or its url is foreign */
    char ipa_url[NOSHI_RELEASE_URL_MAX];
    char sha_url[NOSHI_RELEASE_URL_MAX];
    uint64_t ipa_size;
} noshi_release;

#define NOSHI_RELEASE_HOST_MAX 64

/* splits an absolute https url of the release download path or of the hosts GitHub redirects it to (github.com and githubusercontent.com),
   with no credentials and no port other than 443; a relative url, plain http or any other host is NOSHI_E_SECURITY. path keeps the query */
noshi_status noshi_release_url_split(const char *url, char *host, size_t host_cap, char *path, size_t path_cap);

/* the digest from a .sha256 asset: 64 hex digits, as `sha256sum` writes them (followed by a name) or alone, with an optional line end */
noshi_status noshi_release_parse_sha256(const char *text, size_t length, uint8_t out[32]);

noshi_status noshi_release_parse(const char *json, size_t length, noshi_release *out);
/* the release named by the answer of https://github.com/wowodymyr/Noshigram/releases/latest, a redirect to .../releases/tag/<tag> (headers is the header block of
   that answer). only the tag is known then: the notes stay empty, the size is 0 and the asset urls are the project's download path for that tag.
   NOSHI_E_MALFORMED for a missing or foreign location or a tag with characters outside letters, digits and ._-+ */
noshi_status noshi_release_from_redirect(const char *headers, noshi_release *out);
noshi_status noshi_release_compare(const char *remote, const char *installed, int *newer);

#endif
