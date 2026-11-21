#include "noshi_sticker_make.h"

#include <string.h>

#include "noshi_tl_ids.h"

/* the length of the UTF-8 sequence at s and its code point, or zero when the bytes are not well formed */
static size_t decode(const unsigned char *s, size_t left, uint32_t *cp) {
    if (left >= 1 && s[0] < 0x80u) {
        *cp = s[0];
        return 1;
    }
    if (left >= 2 && (s[0] & 0xE0u) == 0xC0u && (s[1] & 0xC0u) == 0x80u) {
        *cp = ((uint32_t)(s[0] & 0x1Fu) << 6) | (s[1] & 0x3Fu);
        return *cp >= 0x80u ? 2 : 0;
    }
    if (left >= 3 && (s[0] & 0xF0u) == 0xE0u && (s[1] & 0xC0u) == 0x80u && (s[2] & 0xC0u) == 0x80u) {
        *cp = ((uint32_t)(s[0] & 0x0Fu) << 12) | ((uint32_t)(s[1] & 0x3Fu) << 6) | (s[2] & 0x3Fu);
        return *cp >= 0x800u && (*cp < 0xD800u || *cp > 0xDFFFu) ? 3 : 0;
    }
    if (left >= 4 && (s[0] & 0xF8u) == 0xF0u && (s[1] & 0xC0u) == 0x80u && (s[2] & 0xC0u) == 0x80u && (s[3] & 0xC0u) == 0x80u) {
        *cp = ((uint32_t)(s[0] & 0x07u) << 18) | ((uint32_t)(s[1] & 0x3Fu) << 12) | ((uint32_t)(s[2] & 0x3Fu) << 6) | (s[3] & 0x3Fu);
        return *cp >= 0x10000u && *cp <= 0x10FFFFu ? 4 : 0;
    }
    return 0;
}

int noshi_sticker_title_valid(const char *title) {
    const unsigned char *s = (const unsigned char *)title;
    size_t len, at = 0, chars = 0;
    int visible = 0;
    if (!title) return 0;
    len = strlen(title);
    while (at < len) {
        uint32_t cp = 0;
        size_t n = decode(s + at, len - at, &cp);
        if (!n || cp < 0x20u || cp == 0x7Fu) return 0;
        if (cp != ' ') visible = 1;
        ++chars;
        at += n;
    }
    return visible && chars >= 1 && chars <= NOSHI_STICKER_TITLE_MAX;
}

int noshi_sticker_short_name_valid(const char *name) {
    size_t len, i;
    if (!name) return 0;
    len = strlen(name);
    if (len < 1 || len > NOSHI_STICKER_SHORT_NAME_MAX) return 0;
    if (!((name[0] >= 'a' && name[0] <= 'z') || (name[0] >= 'A' && name[0] <= 'Z'))) return 0;
    if (name[len - 1] == '_') return 0;
    for (i = 0; i < len; ++i) {
        char c = name[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) return 0;
        if (c == '_' && i + 1 < len && name[i + 1] == '_') return 0;
    }
    return 1;
}

int noshi_sticker_emoji_valid(const char *emoji) {
    const unsigned char *s = (const unsigned char *)emoji;
    size_t len, at = 0;
    int pictorial = 0;
    if (!emoji) return 0;
    len = strlen(emoji);
    if (len < 1 || len > NOSHI_STICKER_EMOJI_MAX) return 0;
    while (at < len) {
        uint32_t cp = 0;
        size_t n = decode(s + at, len - at, &cp);
        if (!n) return 0;
        /* a plain ASCII letter, digit or blank is not an emoji; the digits that start a keycap sequence ride with U+20E3 and are allowed there */
        if (cp < 0x80u && !((cp >= '0' && cp <= '9') || cp == '#' || cp == '*')) return 0;
        if (cp >= 0x2190u) pictorial = 1;
        at += n;
    }
    return pictorial;
}

noshi_status noshi_sticker_upload_request(noshi_arena *arena, noshi_tl_value *file, const char *file_name, noshi_tl_value **out) {
    noshi_tl_value *request, *media, *peer, *attributes, *name_attribute;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !file || !file_name || !file_name[0] || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.uploadMedia");
    media = noshi_tl_new_obj(arena, "inputMediaUploadedDocument");
    peer = noshi_tl_new_obj(arena, "inputPeerSelf");
    attributes = noshi_tl_new_vec(arena, 1);
    name_attribute = noshi_tl_new_obj(arena, "documentAttributeFilename");
    if (!request || !media || !peer || !attributes || !name_attribute) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, name_attribute, "file_name", file_name);
    if (status == NOSHI_OK) status = noshi_tl_vec_set(attributes, 0, name_attribute);
    if (status == NOSHI_OK) status = noshi_tl_set(media, "file", file);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "mime_type", "image/png");
    if (status == NOSHI_OK) status = noshi_tl_set(media, "attributes", attributes);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_sticker_upload_parse(const noshi_tl_value *answer, noshi_input_document *out) {
    const noshi_tl_value *document;
    const uint8_t *reference;
    size_t length;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messageMediaDocument)) return NOSHI_E_MALFORMED;
    document = noshi_tl_get(answer, "document");
    if (!noshi_tl_is(document, NOSHI_TL_ID_document) || noshi_tl_get_i64(document, "id", &out->id) != NOSHI_OK ||
        noshi_tl_get_i64(document, "access_hash", &out->access_hash) != NOSHI_OK ||
        noshi_tl_get_bytes(document, "file_reference", &reference, &length) != NOSHI_OK || length > NOSHI_STICKER_REF_MAX || out->id == 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    memcpy(out->file_reference, reference, length);
    out->file_reference_len = length;
    return NOSHI_OK;
}

static noshi_status input_document(noshi_arena *arena, const noshi_input_document *document, noshi_tl_value **out) {
    noshi_tl_value *input = noshi_tl_new_obj(arena, "inputDocument");
    noshi_status status;
    *out = NULL;
    if (!input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "id", document->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", document->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, input, "file_reference", document->file_reference, document->file_reference_len);
    if (status == NOSHI_OK) *out = input;
    return status;
}

/* the inputStickerSetItem both calls carry */
static noshi_status set_item(noshi_arena *arena, const noshi_input_document *document, const char *emoji, noshi_tl_value **out) {
    noshi_tl_value *item, *input;
    noshi_status status;
    *out = NULL;
    if (!document || document->id == 0 || !noshi_sticker_emoji_valid(emoji)) return NOSHI_E_ARG;
    status = input_document(arena, document, &input);
    if (status != NOSHI_OK) return status;
    item = noshi_tl_new_obj(arena, "inputStickerSetItem");
    if (!item) return NOSHI_E_NOMEM;
    status = noshi_tl_set(item, "document", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, item, "emoji", emoji);
    if (status == NOSHI_OK) *out = item;
    return status;
}

noshi_status noshi_sticker_create_request(noshi_arena *arena, const char *title, const char *short_name, const noshi_input_document *document,
                                              const char *emoji, noshi_tl_value **out) {
    noshi_tl_value *request, *item, *list, *user;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !noshi_sticker_title_valid(title) || !noshi_sticker_short_name_valid(short_name)) return NOSHI_E_ARG;
    status = set_item(arena, document, emoji, &item);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "stickers.createStickerSet");
    user = noshi_tl_new_obj(arena, "inputUserSelf");
    list = noshi_tl_new_vec(arena, 1);
    if (!request || !user || !list) return NOSHI_E_NOMEM;
    status = noshi_tl_vec_set(list, 0, item);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "user_id", user);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "title", title);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "short_name", short_name);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stickers", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_sticker_add_request(noshi_arena *arena, const char *short_name, const noshi_input_document *document, const char *emoji,
                                           noshi_tl_value **out) {
    noshi_tl_value *request, *item, *set;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !noshi_sticker_short_name_valid(short_name)) return NOSHI_E_ARG;
    status = set_item(arena, document, emoji, &item);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "stickers.addStickerToSet");
    set = noshi_tl_new_obj(arena, "inputStickerSetShortName");
    if (!request || !set) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, set, "short_name", short_name);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stickerset", set);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "sticker", item);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_sticker_check_request(noshi_arena *arena, const char *short_name, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !noshi_sticker_short_name_valid(short_name)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "stickers.checkShortName");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "short_name", short_name);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_sticker_check_parse(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolTrue)) return NOSHI_OK;
    if (noshi_tl_is(answer, NOSHI_TL_ID_boolFalse)) return NOSHI_E_STATE;
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_sticker_set_name_parse(const noshi_tl_value *answer, char *short_name, size_t cap) {
    const noshi_tl_value *set;
    const uint8_t *data;
    size_t length;
    if (short_name && cap) short_name[0] = 0;
    if (!short_name || cap < 2) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSet)) return NOSHI_E_MALFORMED;
    set = noshi_tl_get(answer, "set");
    if (!noshi_tl_is(set, NOSHI_TL_ID_stickerSet) || noshi_tl_get_bytes(set, "short_name", &data, &length) != NOSHI_OK || !length || length >= cap) return NOSHI_E_MALFORMED;
    memcpy(short_name, data, length);
    short_name[length] = 0;
    return NOSHI_OK;
}
