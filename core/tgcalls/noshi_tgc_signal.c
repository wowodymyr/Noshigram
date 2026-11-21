#include "noshi_tgc_signal.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include "noshi_tgc_json.h"

/* copies a JSON string into a fixed field; false when it does not fit, so the caller decides whether that drops the entry or the message */
static int copy_string(char *dst, size_t cap, const noshi_json *node) {
    size_t len;
    const char *s = noshi_json_string(node, &len);
    if (!s || len >= cap) return 0;
    memcpy(dst, s, len + 1);
    return 1;
}

/* a decimal number in a string, or a JSON number, in 1 to 4294967295; zero is no ssrc and no usable exchange id either way */
static int read_u32(const noshi_json *node, uint32_t *out) {
    int64_t value = 0;
    if (noshi_json_kind(node) == NOSHI_JSON_STRING) {
        size_t len, i;
        const char *s = noshi_json_string(node, &len);
        if (!s || len == 0 || len > 10) return 0;
        for (i = 0; i < len; ++i) {
            if (s[i] < '0' || s[i] > '9') return 0;
            value = value * 10 + (s[i] - '0');
        }
    } else if (noshi_json_int(node, &value) != NOSHI_OK) {
        return 0;
    }
    if (value < 1 || value > 0xFFFFFFFFLL) return 0;
    *out = (uint32_t)value;
    return 1;
}

static int is_codec_we_use(const char *name) {
    size_t i;
    static const char *known[] = {"opus", "vp8"};
    for (i = 0; i < sizeof(known) / sizeof(known[0]); ++i) {
        const char *a = name, *b = known[i];
        while (*a && *b && tolower((unsigned char)*a) == *b) {
            ++a;
            ++b;
        }
        if (!*a && !*b) return 1;
    }
    return 0;
}

static noshi_status read_payload(const noshi_json *node, noshi_tgc_payload *p, int *keep) {
    const noshi_json *v, *item;
    int64_t i;
    *keep = 0;
    memset(p, 0, sizeof(*p));
    if (noshi_json_kind(node) != NOSHI_JSON_OBJECT) return NOSHI_E_MALFORMED;
    v = noshi_json_get(node, "id");
    if (noshi_json_int(v, &i) != NOSHI_OK || i < 0 || i > 127) return NOSHI_E_MALFORMED;
    p->id = (uint8_t)i;
    v = noshi_json_get(node, "name");
    if (noshi_json_kind(v) != NOSHI_JSON_STRING) return NOSHI_E_MALFORMED;
    v = noshi_json_get(node, "clockrate");
    if (noshi_json_int(v, &i) != NOSHI_OK || i < 0 || i > 0xFFFFFFFFLL) return NOSHI_E_MALFORMED;
    p->clockrate = (uint32_t)i;
    v = noshi_json_get(node, "channels");
    if (v) {
        if (noshi_json_int(v, &i) != NOSHI_OK || i < 0 || i > 64) return NOSHI_E_MALFORMED;
        p->channels = (uint32_t)i;
    }
    v = noshi_json_get(node, "feedbackTypes");
    if (v) {
        if (noshi_json_kind(v) != NOSHI_JSON_ARRAY) return NOSHI_E_MALFORMED;
        for (item = noshi_json_first(v); item; item = noshi_json_next(item)) {
            noshi_tgc_feedback f;
            memset(&f, 0, sizeof(f));
            if (noshi_json_kind(item) != NOSHI_JSON_OBJECT) return NOSHI_E_MALFORMED;
            if (noshi_json_kind(noshi_json_get(item, "type")) != NOSHI_JSON_STRING ||
                noshi_json_kind(noshi_json_get(item, "subtype")) != NOSHI_JSON_STRING) return NOSHI_E_MALFORMED;
            if (p->feedback_count >= NOSHI_TGC_MAX_FEEDBACK) continue;
            /* a name too long for the field is a kind of feedback this app does not know, so it is left out */
            if (!copy_string(f.type, sizeof(f.type), noshi_json_get(item, "type")) ||
                !copy_string(f.subtype, sizeof(f.subtype), noshi_json_get(item, "subtype"))) continue;
            p->feedback[p->feedback_count++] = f;
        }
    }
    v = noshi_json_get(node, "parameters");
    if (v) {
        if (noshi_json_kind(v) != NOSHI_JSON_OBJECT) return NOSHI_E_MALFORMED;
        for (item = noshi_json_first(v); item; item = noshi_json_next(item)) {
            noshi_tgc_param pr;
            const char *key = noshi_json_key(item);
            memset(&pr, 0, sizeof(pr));
            if (noshi_json_kind(item) != NOSHI_JSON_STRING) return NOSHI_E_MALFORMED;
            if (p->param_count >= NOSHI_TGC_MAX_PARAMS || !key || strlen(key) >= sizeof(pr.key)) continue;
            if (!copy_string(pr.value, sizeof(pr.value), item)) continue;
            memcpy(pr.key, key, strlen(key) + 1);
            p->params[p->param_count++] = pr;
        }
    }
    {
        size_t len;
        const char *name = noshi_json_string(noshi_json_get(node, "name"), &len);
        if (len < sizeof(p->name)) {
            memcpy(p->name, name, len + 1);
            *keep = is_codec_we_use(p->name);
        }
    }
    return NOSHI_OK;
}

static noshi_status read_content(const noshi_json *node, noshi_tgc_content *c) {
    const noshi_json *v, *item;
    size_t len;
    const char *type;
    int64_t i;
    memset(c, 0, sizeof(*c));
    if (noshi_json_kind(node) != NOSHI_JSON_OBJECT) return NOSHI_E_MALFORMED;
    type = noshi_json_string(noshi_json_get(node, "type"), &len);
    if (!type) return NOSHI_E_MALFORMED;
    if (strcmp(type, "audio") == 0) c->video = 0;
    else if (strcmp(type, "video") == 0) c->video = 1;
    else return NOSHI_E_MALFORMED;
    if (!read_u32(noshi_json_get(node, "ssrc"), &c->ssrc)) return NOSHI_E_MALFORMED;
    v = noshi_json_get(node, "ssrcGroups");
    if (v) {
        if (noshi_json_kind(v) != NOSHI_JSON_ARRAY) return NOSHI_E_MALFORMED;
        for (item = noshi_json_first(v); item; item = noshi_json_next(item)) {
            noshi_tgc_ssrc_group g;
            const noshi_json *ssrcs, *s;
            memset(&g, 0, sizeof(g));
            if (noshi_json_kind(item) != NOSHI_JSON_OBJECT) return NOSHI_E_MALFORMED;
            if (noshi_json_kind(noshi_json_get(item, "semantics")) != NOSHI_JSON_STRING) return NOSHI_E_MALFORMED;
            ssrcs = noshi_json_get(item, "ssrcs");
            if (noshi_json_kind(ssrcs) != NOSHI_JSON_ARRAY || noshi_json_count(ssrcs) == 0) return NOSHI_E_MALFORMED;
            for (s = noshi_json_first(ssrcs); s; s = noshi_json_next(s)) {
                uint32_t value;
                if (!read_u32(s, &value)) return NOSHI_E_MALFORMED;
                if (g.count < NOSHI_TGC_MAX_GROUP_SSRCS) g.ssrcs[g.count++] = value;
            }
            if (c->group_count < NOSHI_TGC_MAX_GROUPS && copy_string(g.semantics, sizeof(g.semantics), noshi_json_get(item, "semantics"))) {
                c->groups[c->group_count++] = g;
            }
        }
    }
    v = noshi_json_get(node, "payloadTypes");
    if (v) {
        if (noshi_json_kind(v) != NOSHI_JSON_ARRAY) return NOSHI_E_MALFORMED;
        for (item = noshi_json_first(v); item; item = noshi_json_next(item)) {
            noshi_tgc_payload p;
            int keep;
            noshi_status status = read_payload(item, &p, &keep);
            if (status != NOSHI_OK) return status;
            if (keep && c->payload_count < NOSHI_TGC_MAX_PAYLOADS) c->payloads[c->payload_count++] = p;
        }
    }
    v = noshi_json_get(node, "rtpExtensions");
    if (v) {
        if (noshi_json_kind(v) != NOSHI_JSON_ARRAY) return NOSHI_E_MALFORMED;
        for (item = noshi_json_first(v); item; item = noshi_json_next(item)) {
            noshi_tgc_extension e;
            memset(&e, 0, sizeof(e));
            if (noshi_json_kind(item) != NOSHI_JSON_OBJECT) return NOSHI_E_MALFORMED;
            if (noshi_json_int(noshi_json_get(item, "id"), &i) != NOSHI_OK || i < 0 || i > 255) return NOSHI_E_MALFORMED;
            if (noshi_json_kind(noshi_json_get(item, "uri")) != NOSHI_JSON_STRING) return NOSHI_E_MALFORMED;
            e.id = (uint8_t)i;
            if (c->extension_count >= NOSHI_TGC_MAX_EXTENSIONS || !copy_string(e.uri, sizeof(e.uri), noshi_json_get(item, "uri"))) continue;
            c->extensions[c->extension_count++] = e;
        }
    }
    return NOSHI_OK;
}

static noshi_status read_initial_setup(const noshi_json *root, noshi_tgc_initial_setup *s) {
    const noshi_json *v, *item;
    int flag;
    if (!copy_string(s->ufrag, sizeof(s->ufrag), noshi_json_get(root, "ufrag"))) return NOSHI_E_MALFORMED;
    if (!copy_string(s->pwd, sizeof(s->pwd), noshi_json_get(root, "pwd"))) return NOSHI_E_MALFORMED;
    v = noshi_json_get(root, "renomination");
    if (v && noshi_json_bool(v, &flag) == NOSHI_OK) s->renomination = (uint8_t)flag;
    v = noshi_json_get(root, "fingerprints");
    if (noshi_json_kind(v) != NOSHI_JSON_ARRAY) return NOSHI_E_MALFORMED;
    for (item = noshi_json_first(v); item; item = noshi_json_next(item)) {
        noshi_tgc_fingerprint f;
        memset(&f, 0, sizeof(f));
        if (noshi_json_kind(item) != NOSHI_JSON_OBJECT) return NOSHI_E_MALFORMED;
        if (!copy_string(f.hash, sizeof(f.hash), noshi_json_get(item, "hash")) ||
            !copy_string(f.setup, sizeof(f.setup), noshi_json_get(item, "setup")) ||
            !copy_string(f.value, sizeof(f.value), noshi_json_get(item, "fingerprint"))) return NOSHI_E_MALFORMED;
        if (s->fingerprint_count < NOSHI_TGC_MAX_FINGERPRINTS) s->fingerprints[s->fingerprint_count++] = f;
    }
    return NOSHI_OK;
}

static noshi_status read_negotiate(const noshi_json *root, noshi_tgc_negotiate *n) {
    const noshi_json *v, *item;
    if (!read_u32(noshi_json_get(root, "exchangeId"), &n->exchange_id)) return NOSHI_E_MALFORMED;
    v = noshi_json_get(root, "contents");
    if (!v) return NOSHI_OK;
    if (noshi_json_kind(v) != NOSHI_JSON_ARRAY) return NOSHI_E_MALFORMED;
    for (item = noshi_json_first(v); item; item = noshi_json_next(item)) {
        noshi_tgc_content c;
        noshi_status status = read_content(item, &c);
        if (status != NOSHI_OK) return status;
        if (n->content_count < NOSHI_TGC_MAX_CONTENTS) n->contents[n->content_count++] = c;
    }
    return NOSHI_OK;
}

static noshi_status read_candidates(const noshi_json *root, noshi_tgc_candidates *c) {
    const noshi_json *v = noshi_json_get(root, "candidates"), *item;
    if (noshi_json_kind(v) != NOSHI_JSON_ARRAY) return NOSHI_E_MALFORMED;
    for (item = noshi_json_first(v); item; item = noshi_json_next(item)) {
        const noshi_json *sdp;
        if (noshi_json_kind(item) != NOSHI_JSON_OBJECT) return NOSHI_E_MALFORMED;
        sdp = noshi_json_get(item, "sdpString");
        if (noshi_json_kind(sdp) != NOSHI_JSON_STRING) return NOSHI_E_MALFORMED;
        if (c->count >= NOSHI_TGC_MAX_CANDIDATES) continue;
        if (copy_string(c->sdp[c->count], sizeof(c->sdp[0]), sdp)) ++c->count;
    }
    return NOSHI_OK;
}

static noshi_status read_video_state(const noshi_json *v, uint8_t *out) {
    size_t len;
    const char *s;
    if (!v) {
        *out = NOSHI_TGC_VIDEO_INACTIVE;
        return NOSHI_OK;
    }
    s = noshi_json_string(v, &len);
    if (!s) return NOSHI_E_MALFORMED;
    /* tgcalls logs a state it does not know and goes on with the default, so an unknown word is not an error */
    if (strcmp(s, "suspended") == 0) *out = NOSHI_TGC_VIDEO_SUSPENDED;
    else if (strcmp(s, "active") == 0) *out = NOSHI_TGC_VIDEO_ACTIVE;
    else *out = NOSHI_TGC_VIDEO_INACTIVE;
    return NOSHI_OK;
}

static noshi_status read_media_state(const noshi_json *root, noshi_tgc_media_state *m) {
    const noshi_json *v;
    int flag;
    int64_t rotation;
    v = noshi_json_get(root, "muted");
    if (v) {
        if (noshi_json_bool(v, &flag) != NOSHI_OK) return NOSHI_E_MALFORMED;
        m->muted = (uint8_t)flag;
    }
    v = noshi_json_get(root, "lowBattery");
    if (v) {
        if (noshi_json_bool(v, &flag) != NOSHI_OK) return NOSHI_E_MALFORMED;
        m->low_battery = (uint8_t)flag;
    }
    if (read_video_state(noshi_json_get(root, "videoState"), &m->video_state) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (read_video_state(noshi_json_get(root, "screencastState"), &m->screencast_state) != NOSHI_OK) return NOSHI_E_MALFORMED;
    v = noshi_json_get(root, "videoRotation");
    if (v) {
        if (noshi_json_int(v, &rotation) != NOSHI_OK) return NOSHI_E_MALFORMED;
        m->video_rotation = (rotation == 90 || rotation == 180 || rotation == 270) ? (uint16_t)rotation : 0;
    }
    return NOSHI_OK;
}

noshi_status noshi_tgc_message_parse(const char *text, size_t len, noshi_tgc_message *out) {
    noshi_json_doc *doc = NULL;
    const noshi_json *root;
    const char *type;
    size_t type_len;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!text) return NOSHI_E_ARG;
    status = noshi_json_parse(text, len, &doc);
    if (status != NOSHI_OK) return status == NOSHI_E_LIMIT ? status : NOSHI_E_MALFORMED;
    root = noshi_json_root(doc);
    if (noshi_json_kind(root) != NOSHI_JSON_OBJECT) {
        noshi_json_free(doc);
        return NOSHI_E_MALFORMED;
    }
    type = noshi_json_string(noshi_json_get(root, "@type"), &type_len);
    if (!type) {
        noshi_json_free(doc);
        return NOSHI_E_MALFORMED;
    }
    if (strcmp(type, "InitialSetup") == 0) {
        out->type = NOSHI_TGC_MESSAGE_INITIAL_SETUP;
        status = read_initial_setup(root, &out->u.initial_setup);
    } else if (strcmp(type, "NegotiateChannels") == 0) {
        out->type = NOSHI_TGC_MESSAGE_NEGOTIATE_CHANNELS;
        status = read_negotiate(root, &out->u.negotiate);
    } else if (strcmp(type, "Candidates") == 0) {
        out->type = NOSHI_TGC_MESSAGE_CANDIDATES;
        status = read_candidates(root, &out->u.candidates);
    } else if (strcmp(type, "MediaState") == 0) {
        out->type = NOSHI_TGC_MESSAGE_MEDIA_STATE;
        status = read_media_state(root, &out->u.media_state);
    } else {
        status = NOSHI_E_UNSUPPORTED;
    }
    noshi_json_free(doc);
    if (status != NOSHI_OK) memset(out, 0, sizeof(*out));
    return status;
}

/* writing */

static void write_u32_string(noshi_json_out *o, uint32_t value) {
    char text[16];
    snprintf(text, sizeof(text), "%lu", (unsigned long)value);
    noshi_json_out_string(o, text);
}

static void write_content(noshi_json_out *o, const noshi_tgc_content *c) {
    unsigned i, j;
    noshi_json_out_object(o);
    noshi_json_out_key(o, "type");
    noshi_json_out_string(o, c->video ? "video" : "audio");
    noshi_json_out_key(o, "ssrc");
    write_u32_string(o, c->ssrc);
    if (c->group_count) {
        noshi_json_out_key(o, "ssrcGroups");
        noshi_json_out_array(o);
        for (i = 0; i < c->group_count; ++i) {
            noshi_json_out_object(o);
            noshi_json_out_key(o, "semantics");
            noshi_json_out_string(o, c->groups[i].semantics);
            noshi_json_out_key(o, "ssrcs");
            noshi_json_out_array(o);
            for (j = 0; j < c->groups[i].count; ++j) write_u32_string(o, c->groups[i].ssrcs[j]);
            noshi_json_out_end(o);
            noshi_json_out_end(o);
        }
        noshi_json_out_end(o);
    }
    if (c->payload_count) {
        noshi_json_out_key(o, "payloadTypes");
        noshi_json_out_array(o);
        for (i = 0; i < c->payload_count; ++i) {
            const noshi_tgc_payload *p = &c->payloads[i];
            noshi_json_out_object(o);
            noshi_json_out_key(o, "id");
            noshi_json_out_int(o, p->id);
            noshi_json_out_key(o, "name");
            noshi_json_out_string(o, p->name);
            noshi_json_out_key(o, "clockrate");
            noshi_json_out_int(o, p->clockrate);
            noshi_json_out_key(o, "channels");
            noshi_json_out_int(o, p->channels);
            noshi_json_out_key(o, "feedbackTypes");
            noshi_json_out_array(o);
            for (j = 0; j < p->feedback_count; ++j) {
                noshi_json_out_object(o);
                noshi_json_out_key(o, "type");
                noshi_json_out_string(o, p->feedback[j].type);
                noshi_json_out_key(o, "subtype");
                noshi_json_out_string(o, p->feedback[j].subtype);
                noshi_json_out_end(o);
            }
            noshi_json_out_end(o);
            noshi_json_out_key(o, "parameters");
            noshi_json_out_object(o);
            for (j = 0; j < p->param_count; ++j) {
                noshi_json_out_key(o, p->params[j].key);
                noshi_json_out_string(o, p->params[j].value);
            }
            noshi_json_out_end(o);
            noshi_json_out_end(o);
        }
        noshi_json_out_end(o);
    }
    noshi_json_out_key(o, "rtpExtensions");
    noshi_json_out_array(o);
    for (i = 0; i < c->extension_count; ++i) {
        noshi_json_out_object(o);
        noshi_json_out_key(o, "id");
        noshi_json_out_int(o, c->extensions[i].id);
        noshi_json_out_key(o, "uri");
        noshi_json_out_string(o, c->extensions[i].uri);
        noshi_json_out_end(o);
    }
    noshi_json_out_end(o);
    noshi_json_out_end(o);
}

static const char *video_state_word(uint8_t state) {
    return state == NOSHI_TGC_VIDEO_ACTIVE ? "active" : state == NOSHI_TGC_VIDEO_SUSPENDED ? "suspended" : "inactive";
}

noshi_status noshi_tgc_message_write(const noshi_tgc_message *m, char *out, size_t capacity, size_t *len) {
    noshi_json_out o;
    unsigned i;
    if (len) *len = 0;
    if (!m || !out || !len) return NOSHI_E_ARG;
    noshi_json_out_init(&o, out, capacity);
    switch (m->type) {
    case NOSHI_TGC_MESSAGE_INITIAL_SETUP: {
        const noshi_tgc_initial_setup *s = &m->u.initial_setup;
        if (!s->ufrag[0] || !s->pwd[0] || s->fingerprint_count > NOSHI_TGC_MAX_FINGERPRINTS) return NOSHI_E_ARG;
        noshi_json_out_object(&o);
        noshi_json_out_key(&o, "@type");
        noshi_json_out_string(&o, "InitialSetup");
        noshi_json_out_key(&o, "ufrag");
        noshi_json_out_string(&o, s->ufrag);
        noshi_json_out_key(&o, "pwd");
        noshi_json_out_string(&o, s->pwd);
        noshi_json_out_key(&o, "renomination");
        noshi_json_out_bool(&o, s->renomination);
        noshi_json_out_key(&o, "fingerprints");
        noshi_json_out_array(&o);
        for (i = 0; i < s->fingerprint_count; ++i) {
            noshi_json_out_object(&o);
            noshi_json_out_key(&o, "hash");
            noshi_json_out_string(&o, s->fingerprints[i].hash);
            noshi_json_out_key(&o, "setup");
            noshi_json_out_string(&o, s->fingerprints[i].setup);
            noshi_json_out_key(&o, "fingerprint");
            noshi_json_out_string(&o, s->fingerprints[i].value);
            noshi_json_out_end(&o);
        }
        noshi_json_out_end(&o);
        noshi_json_out_end(&o);
        break;
    }
    case NOSHI_TGC_MESSAGE_NEGOTIATE_CHANNELS: {
        const noshi_tgc_negotiate *n = &m->u.negotiate;
        if (n->exchange_id == 0 || n->content_count > NOSHI_TGC_MAX_CONTENTS) return NOSHI_E_ARG;
        for (i = 0; i < n->content_count; ++i) {
            if (n->contents[i].ssrc == 0 || n->contents[i].payload_count > NOSHI_TGC_MAX_PAYLOADS ||
                n->contents[i].extension_count > NOSHI_TGC_MAX_EXTENSIONS || n->contents[i].group_count > NOSHI_TGC_MAX_GROUPS) return NOSHI_E_ARG;
        }
        noshi_json_out_object(&o);
        noshi_json_out_key(&o, "@type");
        noshi_json_out_string(&o, "NegotiateChannels");
        noshi_json_out_key(&o, "exchangeId");
        write_u32_string(&o, n->exchange_id);
        noshi_json_out_key(&o, "contents");
        noshi_json_out_array(&o);
        for (i = 0; i < n->content_count; ++i) write_content(&o, &n->contents[i]);
        noshi_json_out_end(&o);
        noshi_json_out_end(&o);
        break;
    }
    case NOSHI_TGC_MESSAGE_CANDIDATES: {
        const noshi_tgc_candidates *c = &m->u.candidates;
        if (c->count > NOSHI_TGC_MAX_CANDIDATES) return NOSHI_E_ARG;
        noshi_json_out_object(&o);
        noshi_json_out_key(&o, "@type");
        noshi_json_out_string(&o, "Candidates");
        noshi_json_out_key(&o, "candidates");
        noshi_json_out_array(&o);
        for (i = 0; i < c->count; ++i) {
            noshi_json_out_object(&o);
            noshi_json_out_key(&o, "sdpString");
            noshi_json_out_string(&o, c->sdp[i]);
            noshi_json_out_end(&o);
        }
        noshi_json_out_end(&o);
        noshi_json_out_end(&o);
        break;
    }
    case NOSHI_TGC_MESSAGE_MEDIA_STATE: {
        const noshi_tgc_media_state *s = &m->u.media_state;
        noshi_json_out_object(&o);
        noshi_json_out_key(&o, "@type");
        noshi_json_out_string(&o, "MediaState");
        noshi_json_out_key(&o, "muted");
        noshi_json_out_bool(&o, s->muted);
        noshi_json_out_key(&o, "lowBattery");
        noshi_json_out_bool(&o, s->low_battery);
        noshi_json_out_key(&o, "videoState");
        noshi_json_out_string(&o, video_state_word(s->video_state));
        noshi_json_out_key(&o, "videoRotation");
        noshi_json_out_int(&o, s->video_rotation);
        noshi_json_out_key(&o, "screencastState");
        noshi_json_out_string(&o, video_state_word(s->screencast_state));
        noshi_json_out_end(&o);
        break;
    }
    default:
        return NOSHI_E_ARG;
    }
    return noshi_json_out_finish(&o, len);
}
