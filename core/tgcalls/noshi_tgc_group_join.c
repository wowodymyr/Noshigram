#include "noshi_tgc_group_join.h"

#include <string.h>
#include <arpa/inet.h>
#include "noshi_tgc_json.h"

static int read_string(const noshi_json *object, const char *key, char *out, size_t cap) {
    size_t len = 0;
    const char *value = noshi_json_string(noshi_json_get(object, key), &len);
    if (!value || !len || len >= cap || strlen(value) != len) return 0;
    memcpy(out, value, len + 1);
    return 1;
}

static int read_decimal(const noshi_json *object, const char *key, uint32_t max, uint32_t *out) {
    char value[16];
    uint32_t n = 0;
    size_t i;
    if (!read_string(object, key, value, sizeof(value))) return 0;
    for (i = 0; value[i]; ++i) {
        unsigned digit;
        if (value[i] < '0' || value[i] > '9') return 0;
        digit = (unsigned)(value[i] - '0');
        if (n > (max - digit) / 10) return 0;
        n = n * 10 + digit;
    }
    *out = n;
    return 1;
}

static int valid_fingerprint(const char *fingerprint) {
    size_t i;
    if (strlen(fingerprint) != 95) return 0;
    for (i = 0; i < 95; ++i) {
        char c = fingerprint[i];
        if (i % 3 == 2) {
            if (c != ':') return 0;
        } else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return 0;
    }
    return 1;
}

#define DEFAULT_OPUS_PAYLOAD 111
#define DEFAULT_AUDIO_LEVEL_EXT 1
#define AUDIO_LEVEL_URI "urn:ietf:params:rtp-hdrext:ssrc-audio-level"

static int ieq(const char *a, const char *b) {
    for (; *a && *b; ++a, ++b) {
        char x = *a, y = *b;
        if (x >= 'A' && x <= 'Z') x = (char)(x - 'A' + 'a');
        if (y >= 'A' && y <= 'Z') y = (char)(y - 'A' + 'a');
        if (x != y) return 0;
    }
    return *a == *b;
}

/* the ids the server picked for Opus and for the audio level extension; anything missing or out of range keeps the default */
static void read_audio_description(const noshi_json *root, noshi_tgc_group_transport *out) {
    const noshi_json *audio = noshi_json_get(root, "audio"), *list, *item;
    out->audio_payload_type = DEFAULT_OPUS_PAYLOAD;
    out->audio_level_ext = DEFAULT_AUDIO_LEVEL_EXT;
    if (noshi_json_kind(audio) != NOSHI_JSON_OBJECT) return;
    list = noshi_json_get(audio, "payload-types");
    if (noshi_json_kind(list) == NOSHI_JSON_ARRAY) {
        for (item = noshi_json_first(list); item; item = noshi_json_next(item)) {
            size_t len = 0;
            const char *name = noshi_json_string(noshi_json_get(item, "name"), &len);
            int64_t id = 0;
            if (name && ieq(name, "opus") && noshi_json_int(noshi_json_get(item, "id"), &id) == NOSHI_OK && id > 0 && id < 128) {
                out->audio_payload_type = (uint8_t)id;
                break;
            }
        }
    }
    list = noshi_json_get(audio, "rtp-hdrexts");
    if (noshi_json_kind(list) == NOSHI_JSON_ARRAY) {
        for (item = noshi_json_first(list); item; item = noshi_json_next(item)) {
            size_t len = 0;
            const char *uri = noshi_json_string(noshi_json_get(item, "uri"), &len);
            int64_t id = 0;
            if (uri && !strcmp(uri, AUDIO_LEVEL_URI) && noshi_json_int(noshi_json_get(item, "id"), &id) == NOSHI_OK && id >= 1 && id <= 14) {
                out->audio_level_ext = (uint8_t)id;
                break;
            }
        }
    }
}

noshi_status noshi_tgc_group_transport_parse(const char *json, size_t len, noshi_tgc_group_transport *out) {
    noshi_tgc_group_transport result;
    noshi_json_doc *doc = NULL;
    const noshi_json *transport, *list, *item;
    noshi_status status;
    char hash[16], component[8];
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!json) return NOSHI_E_ARG;
    memset(&result, 0, sizeof(result));
    status = noshi_json_parse(json, len, &doc);
    if (status != NOSHI_OK) return status;
    status = NOSHI_E_MALFORMED;
    transport = noshi_json_get(noshi_json_root(doc), "transport");
    if (noshi_json_kind(transport) != NOSHI_JSON_OBJECT ||
        !read_string(transport, "ufrag", result.ufrag, sizeof(result.ufrag)) || strlen(result.ufrag) < 4 ||
        !read_string(transport, "pwd", result.pwd, sizeof(result.pwd)) || strlen(result.pwd) < 22) goto done;
    list = noshi_json_get(transport, "fingerprints");
    if (noshi_json_kind(list) != NOSHI_JSON_ARRAY || noshi_json_count(list) != 1) goto done;
    item = noshi_json_first(list);
    if (!read_string(item, "hash", hash, sizeof(hash)) || strcmp(hash, "sha-256") ||
        !read_string(item, "fingerprint", result.fingerprint, sizeof(result.fingerprint)) || !valid_fingerprint(result.fingerprint) ||
        !read_string(item, "setup", result.setup, sizeof(result.setup))) goto done;
    list = noshi_json_get(transport, "candidates");
    if (noshi_json_kind(list) != NOSHI_JSON_ARRAY) goto done;
    if (noshi_json_count(list) > NOSHI_TGC_GROUP_CANDIDATES_MAX) { status = NOSHI_E_LIMIT; goto done; }
    for (item = noshi_json_first(list); item; item = noshi_json_next(item)) {
        noshi_tgc_group_candidate *candidate = &result.candidates[result.candidate_count];
        uint32_t port;
        unsigned char address[16];
        if (!read_string(item, "ip", candidate->ip, sizeof(candidate->ip)) ||
            (inet_pton(AF_INET, candidate->ip, address) != 1 && inet_pton(AF_INET6, candidate->ip, address) != 1) ||
            !read_string(item, "protocol", candidate->protocol, sizeof(candidate->protocol)) ||
            !read_string(item, "type", candidate->type, sizeof(candidate->type)) ||
            !read_string(item, "component", component, sizeof(component)) || strcmp(component, "1") ||
            !read_decimal(item, "port", 65535, &port) || !port ||
            !read_decimal(item, "priority", UINT32_MAX, &candidate->priority)) goto done;
        candidate->port = (uint16_t)port;
        ++result.candidate_count;
    }
    read_audio_description(noshi_json_root(doc), &result);
    *out = result;
    status = NOSHI_OK;
done:
    noshi_json_free(doc);
    return status;
}

noshi_status noshi_tgc_group_join_json(uint32_t audio_ssrc, const char *ufrag, const char *pwd,
                                          const char *fingerprint, char *out, size_t cap, size_t *len) {
    noshi_json_out json;
    int64_t signed_ssrc;
    if (len) *len = 0;
    if (out && cap) out[0] = 0;
    if (!audio_ssrc || !ufrag || !pwd || !fingerprint || !out || !cap || !len) return NOSHI_E_ARG;
    if (strlen(ufrag) < 4 || strlen(ufrag) >= 64 || strlen(pwd) < 22 || strlen(pwd) >= 128 || !valid_fingerprint(fingerprint))
        return NOSHI_E_ARG;
    signed_ssrc = audio_ssrc <= INT32_MAX ? (int64_t)audio_ssrc : (int64_t)audio_ssrc - 4294967296LL;
    noshi_json_out_init(&json, out, cap);
    noshi_json_out_object(&json);
    noshi_json_out_key(&json, "ssrc"); noshi_json_out_int(&json, signed_ssrc);
    noshi_json_out_key(&json, "ufrag"); noshi_json_out_string(&json, ufrag);
    noshi_json_out_key(&json, "pwd"); noshi_json_out_string(&json, pwd);
    noshi_json_out_key(&json, "fingerprints"); noshi_json_out_array(&json);
    noshi_json_out_object(&json);
    noshi_json_out_key(&json, "hash"); noshi_json_out_string(&json, "sha-256");
    noshi_json_out_key(&json, "fingerprint"); noshi_json_out_string(&json, fingerprint);
    noshi_json_out_key(&json, "setup"); noshi_json_out_string(&json, "passive");
    noshi_json_out_end(&json);
    noshi_json_out_end(&json);
    noshi_json_out_end(&json);
    return noshi_json_out_finish(&json, len);
}
