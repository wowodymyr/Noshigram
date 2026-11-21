#include "noshi_messages.h"

#include <stdio.h>
#include <string.h>

#include "noshi_store.h"
#include "noshi_tl_ids.h"

/* the largest size worth a bubble on a small screen; a photo goes for the smallest size that covers it */
#define PHOTO_TARGET 640
#define STICKER_PREVIEW_TARGET 100
#define AUDIO_COVER_TARGET 300

static void copy_text(char *dst, size_t cap, const noshi_tl_value *object, const char *field, int keep_lines) {
    const uint8_t *data;
    size_t len, i;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK) return;
    if (len >= cap) {
        len = cap - 1;
        /* a sequence that did not fit whole goes with its lead byte */
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    for (i = 0; i < len; ++i) {
        uint8_t c = data[i];
        if (!keep_lines && (c == '\n' || c == '\r' || c == '\t')) c = ' ';
        dst[i] = (char)c;
    }
    dst[len] = 0;
}

static int is_vec(const noshi_tl_value *v) {
    return v && v->kind == NOSHI_TL_V_VEC;
}

/* a type letter such as "m" or "x"; longer ones are not photo sizes */
static int size_type(const noshi_tl_value *size, char *type, size_t cap) {
    const uint8_t *data;
    size_t len;
    if (noshi_tl_get_bytes(size, "type", &data, &len) != NOSHI_OK || len == 0 || len >= cap) return 0;
    memcpy(type, data, len);
    type[len] = 0;
    return 1;
}

/* picks the size of a photo or document thumbnail list that suits target pixels: the smallest that covers it, else
   the largest there is */
static int pick_size(const noshi_tl_value *sizes, int32_t target, char *type, int32_t *w, int32_t *h, int64_t *bytes) {
    uint32_t i;
    int found = 0;
    int32_t best_side = 0;
    if (!is_vec(sizes)) return 0;
    for (i = 0; i < sizes->u.vec.count; ++i) {
        const noshi_tl_value *s = sizes->u.vec.items[i];
        char t[8];
        int32_t sw = 0, sh = 0, side;
        int64_t sb = 0;
        if (noshi_tl_is(s, NOSHI_TL_ID_photoSize)) {
            int32_t v = 0;
            if (noshi_tl_get_i32(s, "size", &v) == NOSHI_OK) sb = v;
        } else if (noshi_tl_is(s, NOSHI_TL_ID_photoSizeProgressive)) {
            const noshi_tl_value *list = noshi_tl_get(s, "sizes");
            if (is_vec(list) && list->u.vec.count > 0 && list->u.vec.items[list->u.vec.count - 1]->kind == NOSHI_TL_V_I32)
                sb = list->u.vec.items[list->u.vec.count - 1]->u.i32;
        } else {
            continue;
        }
        if (!size_type(s, t, sizeof(t)) || noshi_tl_get_i32(s, "w", &sw) != NOSHI_OK ||
            noshi_tl_get_i32(s, "h", &sh) != NOSHI_OK || sw <= 0 || sh <= 0) continue;
        side = sw > sh ? sw : sh;
        if (!found || (best_side < target && side > best_side) || (best_side >= target && side >= target && side < best_side)) {
            found = 1;
            best_side = side;
            memcpy(type, t, strlen(t) + 1);
            *w = sw;
            *h = sh;
            *bytes = sb;
        }
    }
    return found;
}

/* the same pick over the video thumbnails of a document (type "v"); a gif or a video that Telegram stores with
   only a stripped picture and one of these has no photo size, and the clip is then the only file there is to make
   a picture of */
static int pick_video_size(const noshi_tl_value *sizes, int32_t target, char *type) {
    uint32_t i;
    int found = 0;
    int32_t best_side = 0;
    if (!is_vec(sizes)) return 0;
    for (i = 0; i < sizes->u.vec.count; ++i) {
        const noshi_tl_value *s = sizes->u.vec.items[i];
        char t[8];
        int32_t sw = 0, sh = 0, side;
        if (!noshi_tl_is(s, NOSHI_TL_ID_videoSize) || !size_type(s, t, sizeof(t)) || noshi_tl_get_i32(s, "w", &sw) != NOSHI_OK ||
            noshi_tl_get_i32(s, "h", &sh) != NOSHI_OK || sw <= 0 || sh <= 0) continue;
        side = sw > sh ? sw : sh;
        if (!found || (best_side < target && side > best_side) || (best_side >= target && side >= target && side < best_side)) {
            found = 1;
            best_side = side;
            memcpy(type, t, strlen(t) + 1);
        }
    }
    return found;
}

static void ref_from(noshi_media_ref *ref, noshi_media_source source, const noshi_tl_value *object, int32_t dc, const char *thumb) {
    const uint8_t *data;
    size_t len;
    memset(ref, 0, sizeof(*ref));
    if (noshi_tl_get_i64(object, "id", &ref->id) != NOSHI_OK ||
        noshi_tl_get_i64(object, "access_hash", &ref->access_hash) != NOSHI_OK ||
        noshi_tl_get_bytes(object, "file_reference", &data, &len) != NOSHI_OK || len > NOSHI_MEDIA_REF_MAX || dc <= 0) {
        memset(ref, 0, sizeof(*ref));
        return;
    }
    memcpy(ref->file_ref, data, len);
    ref->ref_len = (uint8_t)len;
    ref->dc = dc;
    ref->source = (uint8_t)source;
    if (thumb) {
        strncpy(ref->thumb, thumb, sizeof(ref->thumb) - 1);
        ref->thumb[sizeof(ref->thumb) - 1] = 0;
    }
}

static void read_photo(const noshi_tl_value *photo, int32_t target, noshi_media_info *out) {
    int32_t dc = 0, w = 0, h = 0;
    int64_t bytes = 0;
    char type[8];
    out->kind = NOSHI_PREVIEW_PHOTO;
    if (!noshi_tl_is(photo, NOSHI_TL_ID_photo)) return;
    if (noshi_tl_get_i32(photo, "date", &out->date) != NOSHI_OK || out->date < 0) out->date = 0;
    if (noshi_tl_get_i32(photo, "dc_id", &dc) != NOSHI_OK) return;
    if (!pick_size(noshi_tl_get(photo, "sizes"), target, type, &w, &h, &bytes)) return;
    ref_from(&out->ref, NOSHI_MEDIA_SOURCE_PHOTO, photo, dc, type);
    out->width = w;
    out->height = h;
    out->size = bytes;
    /* the viewer needs the largest file when zoomed, while bubbles keep a retina-sized thumbnail */
    if (pick_size(noshi_tl_get(photo, "sizes"), INT32_MAX, type, &w, &h, &bytes)) {
        ref_from(&out->full_photo, NOSHI_MEDIA_SOURCE_PHOTO, photo, dc, type);
        out->full_photo_size = bytes;
    }
}

static int flac_document(const noshi_media_info *media) {
    size_t n = strlen(media->name);
    if (!strcmp(media->mime, "audio/flac") || !strcmp(media->mime, "audio/x-flac")) return 1;
    return n >= 5 && media->name[n - 5] == '.' &&
           (media->name[n - 4] == 'f' || media->name[n - 4] == 'F') && (media->name[n - 3] == 'l' || media->name[n - 3] == 'L') &&
           (media->name[n - 2] == 'a' || media->name[n - 2] == 'A') && (media->name[n - 1] == 'c' || media->name[n - 1] == 'C');
}

static void read_document(const noshi_tl_value *document, const noshi_tl_value *media, noshi_media_info *out) {
    const noshi_tl_value *attributes = noshi_tl_get(document, "attributes");
    int32_t dc = 0, w = 0, h = 0;
    int64_t bytes = 0;
    int animated = 0, sticker = 0, voice = media && noshi_tl_has(media, "voice"), round = media && noshi_tl_has(media, "round");
    char type[8];
    uint32_t i;
    const uint8_t *wave;
    size_t wave_len;
    out->kind = NOSHI_PREVIEW_FILE;
    if (!noshi_tl_is(document, NOSHI_TL_ID_document)) {
        /* an expired or empty document still says what it was through the media flags */
        if (voice) out->kind = NOSHI_PREVIEW_VOICE;
        else if (round) out->kind = NOSHI_PREVIEW_VIDEO_MESSAGE;
        else if (media && noshi_tl_has(media, "video")) out->kind = NOSHI_PREVIEW_VIDEO;
        return;
    }
    noshi_tl_get_i32(document, "dc_id", &dc);
    noshi_tl_get_i64(document, "size", &out->size);
    copy_text(out->mime, sizeof(out->mime), document, "mime_type", 0);
    ref_from(&out->ref, NOSHI_MEDIA_SOURCE_DOCUMENT, document, dc, "");
    if (is_vec(attributes)) {
        for (i = 0; i < attributes->u.vec.count; ++i) {
            const noshi_tl_value *a = attributes->u.vec.items[i];
            if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeSticker)) {
                const noshi_tl_value *named = noshi_tl_get(a, "stickerset");
                if (!noshi_tl_has(a, "mask")) sticker = 1;
                copy_text(out->alt, sizeof(out->alt), a, "alt", 0);
                if (named && noshi_tl_is(named, NOSHI_TL_ID_inputStickerSetID)) {
                    noshi_tl_get_i64(named, "id", &out->sticker_set_id);
                    noshi_tl_get_i64(named, "access_hash", &out->sticker_set_hash);
                }
            } else if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeAnimated)) {
                animated = 1;
            } else if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeImageSize)) {
                noshi_tl_get_i32(a, "w", &out->width);
                noshi_tl_get_i32(a, "h", &out->height);
            } else if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeVideo)) {
                double seconds = 0;
                out->kind = NOSHI_PREVIEW_VIDEO;
                if (noshi_tl_has(a, "round_message")) round = 1;
                noshi_tl_get_i32(a, "w", &out->width);
                noshi_tl_get_i32(a, "h", &out->height);
                if (noshi_tl_get_f64(a, "duration", &seconds) == NOSHI_OK && seconds > 0 && seconds < 2147483647.0) out->duration = (int32_t)seconds;
            } else if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeAudio)) {
                if (noshi_tl_has(a, "voice")) voice = 1;
                if (out->kind == NOSHI_PREVIEW_FILE) out->kind = NOSHI_PREVIEW_AUDIO;
                noshi_tl_get_i32(a, "duration", &out->duration);
                copy_text(out->title, sizeof(out->title), a, "title", 0);
                copy_text(out->performer, sizeof(out->performer), a, "performer", 0);
                if (noshi_tl_get_bytes(a, "waveform", &wave, &wave_len) == NOSHI_OK && wave && wave_len > 0 && wave_len <= sizeof(out->waveform)) {
                    memcpy(out->waveform, wave, wave_len);
                    out->waveform_len = (uint16_t)wave_len;
                }
            } else if (noshi_tl_is(a, NOSHI_TL_ID_documentAttributeFilename)) {
                copy_text(out->name, sizeof(out->name), a, "file_name", 0);
            }
        }
    }
    if (out->kind == NOSHI_PREVIEW_FILE && flac_document(out)) out->kind = NOSHI_PREVIEW_AUDIO;
    if (sticker) {
        out->kind = NOSHI_PREVIEW_STICKER;
        if (!strcmp(out->mime, "application/x-tgsticker")) out->sticker = NOSHI_STICKER_ANIMATED;
        else if (!strcmp(out->mime, "video/webm")) out->sticker = NOSHI_STICKER_VIDEO;
        else out->sticker = NOSHI_STICKER_STATIC;
    } else if (voice) {
        out->kind = NOSHI_PREVIEW_VOICE;
    } else if (round) {
        out->kind = NOSHI_PREVIEW_VIDEO_MESSAGE;
    } else if (animated) {
        out->kind = NOSHI_PREVIEW_GIF;
    }
    if (pick_size(noshi_tl_get(document, "thumbs"), out->kind == NOSHI_PREVIEW_AUDIO ? AUDIO_COVER_TARGET : STICKER_PREVIEW_TARGET, type, &w, &h, &bytes))
        ref_from(&out->preview, NOSHI_MEDIA_SOURCE_DOCUMENT, document, dc, type);
    else if ((out->kind == NOSHI_PREVIEW_GIF || out->kind == NOSHI_PREVIEW_VIDEO) && pick_video_size(noshi_tl_get(document, "video_thumbs"), STICKER_PREVIEW_TARGET, type))
        ref_from(&out->preview, NOSHI_MEDIA_SOURCE_DOCUMENT, document, dc, type);
}

static int document_is_avc(const noshi_tl_value *document) {
    const noshi_tl_value *attributes = noshi_tl_get(document, "attributes");
    if (!is_vec(attributes)) return 0;
    for (uint32_t i = 0; i < attributes->u.vec.count; ++i) {
        const noshi_tl_value *attribute = attributes->u.vec.items[i];
        const uint8_t *codec;
        size_t length;
        if (!noshi_tl_is(attribute, NOSHI_TL_ID_documentAttributeVideo) ||
            noshi_tl_get_bytes(attribute, "video_codec", &codec, &length) != NOSHI_OK) continue;
        if ((length == 3 && !memcmp(codec, "avc", 3)) || (length == 4 && !memcmp(codec, "h264", 4))) return 1;
    }
    return 0;
}

static void read_video_variant(const noshi_tl_value *media, int32_t target, noshi_media_info *out) {
    const noshi_tl_value *alternatives = noshi_tl_get(media, "alt_documents");
    int32_t best_side = 0;
    if (out->kind != NOSHI_PREVIEW_VIDEO || document_is_avc(noshi_tl_get(media, "document")) ||
        !is_vec(alternatives) || alternatives->u.vec.count > 64) return;
    /* ios 5 through 10 cannot decode HEVC, Telegram supplies AVC in alt_documents */
    for (uint32_t i = 0; i < alternatives->u.vec.count; ++i) {
        const noshi_tl_value *document = alternatives->u.vec.items[i];
        noshi_media_info candidate;
        if (!document_is_avc(document)) continue;
        memset(&candidate, 0, sizeof(candidate));
        read_document(document, media, &candidate);
        if (candidate.kind != NOSHI_PREVIEW_VIDEO || candidate.ref.source != NOSHI_MEDIA_SOURCE_DOCUMENT ||
            candidate.size <= 0 || candidate.width <= 0 || candidate.height <= 0 || strcmp(candidate.mime, "video/mp4")) continue;
        int32_t side = candidate.width > candidate.height ? candidate.width : candidate.height;
        if (!best_side || (best_side < target && side > best_side) ||
            (best_side >= target && side >= target && side < best_side)) {
            best_side = side;
            *out = candidate;
        }
    }
}

/* a negative or missing value is ordinary media: a hostile server cannot make a message look timed with a bad number */
static void read_ttl(const noshi_tl_value *media, noshi_media_info *out) {
    int32_t ttl = 0;
    if (noshi_tl_has(media, "ttl_seconds") && noshi_tl_get_i32(media, "ttl_seconds", &ttl) == NOSHI_OK && ttl > 0) out->ttl_seconds = ttl;
}

void noshi_media_classify_sized(const noshi_tl_value *media, int32_t photo_target, noshi_media_info *out) {
    memset(out, 0, sizeof(*out));
    out->kind = NOSHI_PREVIEW_TEXT;
    if (!media || noshi_tl_is(media, NOSHI_TL_ID_messageMediaEmpty) ||
        noshi_tl_is(media, NOSHI_TL_ID_messageMediaWebPage)) return;
    if (noshi_tl_is(media, NOSHI_TL_ID_messageMediaPhoto)) {
        read_photo(noshi_tl_get(media, "photo"), photo_target, out);
        out->spoiler = noshi_tl_has(media, "spoiler") ? 1 : 0;
        read_ttl(media, out);
    } else if (noshi_tl_is(media, NOSHI_TL_ID_messageMediaDocument)) {
        read_document(noshi_tl_get(media, "document"), media, out);
        read_video_variant(media, photo_target, out);
        out->spoiler = noshi_tl_has(media, "spoiler") ? 1 : 0;
        read_ttl(media, out);
    } else if (noshi_tl_is(media, NOSHI_TL_ID_messageMediaGeo) || noshi_tl_is(media, NOSHI_TL_ID_messageMediaGeoLive) ||
               noshi_tl_is(media, NOSHI_TL_ID_messageMediaVenue)) {
        out->kind = NOSHI_PREVIEW_LOCATION;
        noshi_geo_read(noshi_tl_get(media, "geo"), noshi_tl_is(media, NOSHI_TL_ID_messageMediaVenue) ? media : NULL, &out->location);
        out->width = 320;
        out->height = 180;
    } else if (noshi_tl_is(media, NOSHI_TL_ID_messageMediaPaidMedia)) {
        /* only the first item is shown: a bought one is read as the media it is, a locked one keeps its size and waits for the payment */
        const noshi_tl_value *items = noshi_tl_get(media, "extended_media"), *first;
        int64_t stars = 0;
        out->kind = NOSHI_PREVIEW_PAID;
        if (noshi_tl_get_i64(media, "stars_amount", &stars) != NOSHI_OK || stars <= 0) stars = 0;
        first = is_vec(items) && items->u.vec.count ? items->u.vec.items[0] : NULL;
        if (first && noshi_tl_is(first, NOSHI_TL_ID_messageExtendedMedia)) {
            noshi_media_classify_sized(noshi_tl_get(first, "media"), photo_target, out);
        } else if (first && noshi_tl_is(first, NOSHI_TL_ID_messageExtendedMediaPreview)) {
            noshi_tl_get_i32(first, "w", &out->width);
            noshi_tl_get_i32(first, "h", &out->height);
            if (noshi_tl_has(first, "video_duration")) noshi_tl_get_i32(first, "video_duration", &out->duration);
        }
        out->paid_stars = stars;
    } else if (noshi_tl_is(media, NOSHI_TL_ID_messageMediaDice)) {
        const uint8_t *emoticon = NULL;
        size_t length = 0;
        int32_t value = 0;
        out->kind = NOSHI_PREVIEW_DICE;
        /* the emoji comes from the server, so it is kept only when it is one of the games the client draws; anything else stays an unknown media */
        if (noshi_tl_get_bytes(media, "emoticon", &emoticon, &length) != NOSHI_OK || !length || length >= sizeof(out->alt) || memchr(emoticon, 0, length)) {
            out->kind = NOSHI_PREVIEW_OTHER;
            return;
        }
        memcpy(out->alt, emoticon, length);
        if (!noshi_dice_emoticon(out->alt)) {
            memset(out->alt, 0, sizeof(out->alt));
            out->kind = NOSHI_PREVIEW_OTHER;
            return;
        }
        if (noshi_tl_get_i32(media, "value", &value) == NOSHI_OK && value > 0 && value <= NOSHI_DICE_VALUE_MAX) out->dice_value = value;
        out->width = 512;
        out->height = 512;
    } else if (noshi_tl_is(media, NOSHI_TL_ID_messageMediaStory)) {
        out->kind = NOSHI_PREVIEW_STORY;
    } else if (noshi_tl_is(media, NOSHI_TL_ID_messageMediaContact)) {
        out->kind = NOSHI_PREVIEW_CONTACT;
    } else if (noshi_tl_is(media, NOSHI_TL_ID_messageMediaPoll)) {
        out->kind = NOSHI_PREVIEW_POLL;
    } else {
        out->kind = NOSHI_PREVIEW_OTHER;
    }
}

void noshi_media_classify(const noshi_tl_value *media, noshi_media_info *out) {
    noshi_media_classify_sized(media, PHOTO_TARGET, out);
}

int noshi_media_uses_picture(noshi_preview_kind kind, int has_file, int has_preview, int has_local_preview) {
    if (kind == NOSHI_PREVIEW_PHOTO) return has_file || has_local_preview;
    if (kind == NOSHI_PREVIEW_VIDEO || kind == NOSHI_PREVIEW_VIDEO_MESSAGE || kind == NOSHI_PREVIEW_GIF)
        return has_file || has_preview || has_local_preview;
    return 0;
}

int noshi_media_opens_viewer(noshi_preview_kind kind) {
    return kind == NOSHI_PREVIEW_PHOTO || kind == NOSHI_PREVIEW_VIDEO;
}


void noshi_photo_read(const noshi_tl_value *photo, int32_t target, noshi_media_info *out) {
    memset(out, 0, sizeof(*out));
    read_photo(photo, target, out);
}

void noshi_document_read(const noshi_tl_value *document, noshi_media_info *out) {
    memset(out, 0, sizeof(*out));
    out->kind = NOSHI_PREVIEW_FILE;
    read_document(document, NULL, out);
}

noshi_status noshi_sticker_read(const noshi_tl_value *document, noshi_sticker_row *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    read_document(document, NULL, &out->media);
    if (out->media.kind != NOSHI_PREVIEW_STICKER || out->media.ref.source == NOSHI_MEDIA_SOURCE_NONE) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    return NOSHI_OK;
}

static noshi_entity_kind entity_kind(const noshi_tl_value *e) {
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityBold)) return NOSHI_ENTITY_BOLD;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityItalic)) return NOSHI_ENTITY_ITALIC;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityUnderline)) return NOSHI_ENTITY_UNDERLINE;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityStrike)) return NOSHI_ENTITY_STRIKE;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityCode)) return NOSHI_ENTITY_CODE;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityPre)) return NOSHI_ENTITY_PRE;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntitySpoiler)) return NOSHI_ENTITY_SPOILER;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityBlockquote)) return NOSHI_ENTITY_BLOCKQUOTE;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityMentionName)) return NOSHI_ENTITY_MENTION_NAME;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityFormattedDate)) return NOSHI_ENTITY_FORMATTED_DATE;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityUrl)) return NOSHI_ENTITY_URL;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityTextUrl)) return NOSHI_ENTITY_TEXT_URL;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityEmail)) return NOSHI_ENTITY_EMAIL;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityMention)) return NOSHI_ENTITY_MENTION;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityHashtag)) return NOSHI_ENTITY_HASHTAG;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityCustomEmoji)) return NOSHI_ENTITY_CUSTOM_EMOJI;
    if (noshi_tl_is(e, NOSHI_TL_ID_messageEntityBotCommand)) return NOSHI_ENTITY_BOT_COMMAND;
    return (noshi_entity_kind)0;
}

void noshi_entities_read(const noshi_tl_value *message, noshi_entity *entities, size_t capacity,
                           char *urls, size_t urls_capacity, uint8_t *count) {
    const noshi_tl_value *list = noshi_tl_get(message, "entities");
    size_t pool = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!count || !entities || !urls || capacity > NOSHI_MESSAGE_ENTITIES_MAX || urls_capacity > INT16_MAX) return;
    if (!is_vec(list)) return;
    for (i = 0; i < list->u.vec.count && *count < capacity; ++i) {
        const noshi_tl_value *e = list->u.vec.items[i];
        noshi_entity *out = &entities[*count];
        noshi_entity_kind kind = entity_kind(e);
        int32_t offset, length;
        if (!kind || noshi_tl_get_i32(e, "offset", &offset) != NOSHI_OK || noshi_tl_get_i32(e, "length", &length) != NOSHI_OK ||
            offset < 0 || length <= 0) continue;
        out->kind = (uint8_t)kind;
        out->offset = offset;
        out->length = length;
        out->url_offset = -1;
        out->url_length = 0;
        out->document_id = 0;
        out->user_id = 0;
        out->date = 0;
        out->flags = 0;
        /* an emoji without its document has nothing to draw, so the plain text stays */
        if (kind == NOSHI_ENTITY_CUSTOM_EMOJI && (noshi_tl_get_i64(e, "document_id", &out->document_id) != NOSHI_OK || out->document_id == 0)) continue;
        /* a name that points at nobody opens nothing, so it stays plain text */
        if (kind == NOSHI_ENTITY_MENTION_NAME && (noshi_tl_get_i64(e, "user_id", &out->user_id) != NOSHI_OK || out->user_id <= 0)) continue;
        if (kind == NOSHI_ENTITY_BLOCKQUOTE && noshi_tl_has(e, "collapsed")) out->flags |= NOSHI_ENTITY_COLLAPSED;
        if (kind == NOSHI_ENTITY_FORMATTED_DATE) {
            static const char *const names[] = {"relative", "short_time", "long_time", "short_date", "long_date", "day_of_week"};
            size_t k;
            if (noshi_tl_get_i32(e, "date", &out->date) != NOSHI_OK) continue;
            for (k = 0; k < sizeof(names) / sizeof(names[0]); ++k) {
                if (noshi_tl_has(e, names[k])) out->flags |= (uint8_t)(1u << k);
            }
        }
        if (kind == NOSHI_ENTITY_PRE) {
            const uint8_t *language;
            size_t len;
            /* a block of code without a readable language is still a block of code */
            if (noshi_tl_get_bytes(e, "language", &language, &len) == NOSHI_OK && len > 0 && len < urls_capacity - pool) {
                memcpy(urls + pool, language, len);
                urls[pool + len] = 0;
                out->url_offset = (int16_t)pool;
                out->url_length = (int16_t)len;
                pool += len + 1;
            }
        }
        if (kind == NOSHI_ENTITY_TEXT_URL) {
            const uint8_t *url;
            size_t len;
            /* a link whose address does not fit the pool is shown as plain text, not with a wrong target */
            if (noshi_tl_get_bytes(e, "url", &url, &len) != NOSHI_OK || len == 0 || len >= urls_capacity - pool) continue;
            memcpy(urls + pool, url, len);
            urls[pool + len] = 0;
            out->url_offset = (int16_t)pool;
            out->url_length = (int16_t)len;
            pool += len + 1;
        }
        ++*count;
    }
}

static noshi_service_kind service_kind(const noshi_tl_value *action) {
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChatCreate)) return NOSHI_SERVICE_CHAT_CREATE;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChatEditTitle)) return NOSHI_SERVICE_TITLE;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChatEditPhoto)) return NOSHI_SERVICE_PHOTO_CHANGED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChatDeletePhoto)) return NOSHI_SERVICE_PHOTO_DELETED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChatAddUser)) return NOSHI_SERVICE_USER_ADDED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChatDeleteUser)) return NOSHI_SERVICE_USER_REMOVED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChatJoinedByLink) ||
        noshi_tl_is(action, NOSHI_TL_ID_messageActionChatJoinedByRequest)) return NOSHI_SERVICE_JOINED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChannelCreate)) return NOSHI_SERVICE_CHANNEL_CREATE;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionPinMessage)) return NOSHI_SERVICE_PIN;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionPhoneCall)) return NOSHI_SERVICE_CALL;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionStarGift) || noshi_tl_is(action, NOSHI_TL_ID_messageActionStarGiftUnique))
        return NOSHI_SERVICE_GIFT;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionContactSignUp)) return NOSHI_SERVICE_CONTACT_JOINED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionScreenshotTaken)) return NOSHI_SERVICE_SCREENSHOT;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionHistoryClear)) return NOSHI_SERVICE_HISTORY_CLEAR;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChatMigrateTo) ||
        noshi_tl_is(action, NOSHI_TL_ID_messageActionChannelMigrateFrom)) return NOSHI_SERVICE_MIGRATED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionCustomAction)) return NOSHI_SERVICE_CUSTOM;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionGroupCall) ||
        noshi_tl_is(action, NOSHI_TL_ID_messageActionGroupCallScheduled)) return NOSHI_SERVICE_VIDEO_CHAT;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionInviteToGroupCall)) return NOSHI_SERVICE_VIDEO_CHAT_INVITE;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionTopicCreate)) return NOSHI_SERVICE_TOPIC_CREATE;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionTopicEdit)) return NOSHI_SERVICE_TOPIC_EDIT;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionSetMessagesTTL)) return NOSHI_SERVICE_TTL;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionBoostApply)) return NOSHI_SERVICE_BOOST;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionPaymentSent) || noshi_tl_is(action, NOSHI_TL_ID_messageActionPaymentSentMe))
        return NOSHI_SERVICE_PAYMENT;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionBotAllowed)) return NOSHI_SERVICE_BOT_ALLOWED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionGiftPremium) || noshi_tl_is(action, NOSHI_TL_ID_messageActionGiftCode))
        return NOSHI_SERVICE_PREMIUM_GIFT;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionSetChatTheme)) return NOSHI_SERVICE_THEME;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionSetChatWallPaper)) return NOSHI_SERVICE_WALLPAPER;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionSuggestProfilePhoto)) return NOSHI_SERVICE_PHOTO_SUGGESTED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionGameScore)) return NOSHI_SERVICE_GAME_SCORE;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionGiveawayLaunch)) return NOSHI_SERVICE_GIVEAWAY;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionGiveawayResults)) return NOSHI_SERVICE_GIVEAWAY_RESULTS;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionPaymentRefunded)) return NOSHI_SERVICE_PAYMENT_REFUNDED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionNoForwardsRequest)) return NOSHI_SERVICE_SHARING_REQUEST;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionNoForwardsToggle)) return NOSHI_SERVICE_SHARING_TOGGLE;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionPollAppendAnswer)) return NOSHI_SERVICE_POLL_ANSWER_ADDED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionPollDeleteAnswer)) return NOSHI_SERVICE_POLL_ANSWER_REMOVED;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionChangeCommunity)) return NOSHI_SERVICE_COMMUNITY;
    if (noshi_tl_is(action, NOSHI_TL_ID_messageActionGiftStars)) return NOSHI_SERVICE_STARS_GIFT;
    return NOSHI_SERVICE_OTHER;
}

/* "messageActionGiftPremium" as "Gift premium": the app has no wording for the action, so it says what the server called it */
static void humanize_action(const noshi_tl_value *action, char *text, size_t cap) {
    static const char prefix[] = "messageAction";
    const char *name;
    size_t at = 0;
    if (!text || !cap || !action || action->kind != NOSHI_TL_V_OBJ || !action->u.obj.ctor || !action->u.obj.ctor->name) return;
    name = action->u.obj.ctor->name;
    if (strncmp(name, prefix, sizeof(prefix) - 1) == 0) name += sizeof(prefix) - 1;
    for (; *name && at + 2 < cap; ++name) {
        if (at && *name >= 'A' && *name <= 'Z') {
            text[at++] = ' ';
            text[at++] = (char)(*name - 'A' + 'a');
        } else text[at++] = *name;
    }
    text[at] = 0;
}

uint8_t noshi_service_summary(const noshi_tl_value *action, char *text, size_t cap, int32_t *value, int64_t *target) {
    noshi_service_kind kind = service_kind(action);
    const noshi_tl_value *users;
    if (text && cap) text[0] = 0;
    if (value) *value = 0;
    if (target) *target = 0;
    if (!action) return (uint8_t)(NOSHI_SERVICE_OTHER + 1);
    if (text && cap) {
        if (kind == NOSHI_SERVICE_TITLE || kind == NOSHI_SERVICE_CHAT_CREATE || kind == NOSHI_SERVICE_CHANNEL_CREATE ||
            kind == NOSHI_SERVICE_TOPIC_CREATE || kind == NOSHI_SERVICE_MIGRATED) copy_text(text, cap, action, "title", 0);
        if (kind == NOSHI_SERVICE_TOPIC_EDIT && noshi_tl_has(action, "title")) copy_text(text, cap, action, "title", 0);
        if (kind == NOSHI_SERVICE_CUSTOM) copy_text(text, cap, action, "message", 1);
        if (kind == NOSHI_SERVICE_POLL_ANSWER_ADDED || kind == NOSHI_SERVICE_POLL_ANSWER_REMOVED) {
            /* the answer is a pollAnswer whose text is a textWithEntities; the line quotes the words only */
            const noshi_tl_value *answer = noshi_tl_get(action, "answer"), *words = answer ? noshi_tl_get(answer, "text") : NULL;
            if (words) copy_text(text, cap, words, "text", 0);
        }
        if (kind == NOSHI_SERVICE_THEME) {
            const noshi_tl_value *theme = noshi_tl_get(action, "theme");
            if (theme) copy_text(text, cap, theme, "emoticon", 0);
        }
    }
    if (target) {
        if (kind == NOSHI_SERVICE_USER_REMOVED) noshi_tl_get_i64(action, "user_id", target);
        if (kind == NOSHI_SERVICE_JOINED) noshi_tl_get_i64(action, "inviter_id", target);
        users = noshi_tl_get(action, "users");
        if ((kind == NOSHI_SERVICE_USER_ADDED || kind == NOSHI_SERVICE_VIDEO_CHAT_INVITE) && is_vec(users) && users->u.vec.count > 0 &&
            users->u.vec.items[0]->kind == NOSHI_TL_V_I64) *target = users->u.vec.items[0]->u.i64;
    }
    if (value) {
        if (kind == NOSHI_SERVICE_SHARING_REQUEST || kind == NOSHI_SERVICE_SHARING_TOGGLE) {
            if (noshi_tl_is(noshi_tl_get(action, "prev_value"), NOSHI_TL_ID_boolTrue)) *value |= 1;
            if (noshi_tl_is(noshi_tl_get(action, "new_value"), NOSHI_TL_ID_boolTrue)) *value |= 2;
            if (kind == NOSHI_SERVICE_SHARING_REQUEST && noshi_tl_has(action, "expired")) *value |= 4;
        }
        if (kind == NOSHI_SERVICE_VIDEO_CHAT) noshi_tl_get_i32(action, "duration", value);
        if (kind == NOSHI_SERVICE_TTL) noshi_tl_get_i32(action, "period", value);
        if (kind == NOSHI_SERVICE_BOOST) noshi_tl_get_i32(action, "boosts", value);
        if (kind == NOSHI_SERVICE_CALL) noshi_tl_get_i32(action, "duration", value);
        if (kind == NOSHI_SERVICE_PREMIUM_GIFT) {
            /* the layers count the subscription in days now, and older ones in months; the line says months */
            int32_t days = 0;
            if (noshi_tl_get_i32(action, "days", &days) == NOSHI_OK && days > 0) *value = (days + 15) / 30;
            else noshi_tl_get_i32(action, "months", value);
        }
        if (kind == NOSHI_SERVICE_STARS_GIFT) {
            int64_t stars = 0;
            if (noshi_tl_get_i64(action, "stars", &stars) == NOSHI_OK && stars > 0) *value = stars > INT32_MAX ? INT32_MAX : (int32_t)stars;
        }
        /* no community_id means the chat left its community */
        if (kind == NOSHI_SERVICE_COMMUNITY && !noshi_tl_has(action, "community_id")) *value |= 1;
        if (kind == NOSHI_SERVICE_GAME_SCORE) noshi_tl_get_i32(action, "score", value);
        if (kind == NOSHI_SERVICE_GIVEAWAY_RESULTS) noshi_tl_get_i32(action, "winners_count", value);
        if (kind == NOSHI_SERVICE_TOPIC_EDIT) {
            if (noshi_tl_is(noshi_tl_get(action, "closed"), NOSHI_TL_ID_boolTrue)) *value = 1;
            else if (noshi_tl_is(noshi_tl_get(action, "closed"), NOSHI_TL_ID_boolFalse)) *value = 2;
        }
        if (*value < 0) *value = 0;
    }
    if (kind == NOSHI_SERVICE_OTHER) humanize_action(action, text, cap);
    return (uint8_t)(kind + 1);
}

static void read_service(const noshi_tl_value *action, noshi_message_row *row) {
    row->service = noshi_service_summary(action, row->text, sizeof(row->text), &row->service_value, &row->target_id);
    if (row->service - 1 == NOSHI_SERVICE_CALL) {
        const noshi_tl_value *reason = noshi_tl_get(action, "reason");
        row->call_video = noshi_tl_has(action, "video") ? 1 : 0;
        if (noshi_tl_is(reason, NOSHI_TL_ID_phoneCallDiscardReasonMissed)) row->call_reason = NOSHI_OUTCOME_MISSED;
        else if (noshi_tl_is(reason, NOSHI_TL_ID_phoneCallDiscardReasonBusy)) row->call_reason = NOSHI_OUTCOME_BUSY;
        else if (noshi_tl_is(reason, NOSHI_TL_ID_phoneCallDiscardReasonDisconnect)) row->call_reason = NOSHI_OUTCOME_DISCONNECTED;
    }
    if (row->service - 1 == NOSHI_SERVICE_COMMUNITY) {
        noshi_tl_get_i64(action, "community_id", &row->service_community);
        /* a service line written in the name of the chat itself, or a channel post, has no person behind it */
        if (!row->from_id && !row->from_channel) row->service_value |= 2;
    }
    if (row->service - 1 == NOSHI_SERVICE_GIFT) {
        const noshi_tl_value *note = noshi_tl_get(action, "message");
        /* a gift that cannot be read stays a plain service line without a picture */
        if (noshi_gift_read(noshi_tl_get(action, "gift"), &row->gift) != NOSHI_OK) memset(&row->gift, 0, sizeof(row->gift));
        if (note) copy_text(row->text, sizeof(row->text), note, "text", 1);
    }
}

/* a messageReplies of a post: the comment count and the first few commenters who are users */
static void read_comments(const noshi_tl_value *replies, noshi_message_row *out) {
    const noshi_tl_value *list;
    uint32_t i;
    int32_t count = 0;
    if (!noshi_tl_is(replies, NOSHI_TL_ID_messageReplies) || !noshi_tl_has(replies, "comments")) return;
    noshi_tl_get_i32(replies, "replies", &count);
    out->has_comments = 1;
    out->comments = count > 0 ? count : 0;
    noshi_tl_get_i64(replies, "channel_id", &out->discussion_id);
    list = noshi_tl_get(replies, "recent_repliers");
    for (i = 0; list && list->kind == NOSHI_TL_V_VEC && i < list->u.vec.count && out->commenter_count < 3; ++i) {
        noshi_peer who;
        if (noshi_peer_from_tl(list->u.vec.items[i], &who) == NOSHI_OK && who.kind == 1) out->commenters[out->commenter_count++] = who.id;
    }
}

/* UTF-16 units of a UTF-8 string, which is how entity offsets count */
static int32_t utf16_units(const char *s) {
    int32_t units = 0;
    for (; *s; ++s) {
        unsigned char c = (unsigned char)*s;
        if ((c & 0xC0u) == 0x80u) continue;
        units += c >= 0xF0u ? 2 : 1;
    }
    return units;
}

/* a bot's invoice has no text of its own: the title in bold, the description and, for an invoice in stars, the price take its place, so the
   bubble says what it sells above the button that pays */
static void read_invoice(const noshi_tl_value *media, noshi_message_row *row) {
    char title[256], description[NOSHI_MESSAGE_TEXT_MAX / 2];
    const uint8_t *currency;
    size_t currency_len, used;
    int64_t total = 0;
    if (!noshi_tl_is(media, NOSHI_TL_ID_messageMediaInvoice) || row->text[0]) return;
    copy_text(title, sizeof(title), media, "title", 0);
    copy_text(description, sizeof(description), media, "description", 1);
    if (!title[0] && !description[0]) return;
    used = (size_t)snprintf(row->text, sizeof(row->text), "%s%s%s", title, title[0] && description[0] ? "\n" : "", description);
    if (used >= sizeof(row->text)) used = sizeof(row->text) - 1;
    if (title[0] && row->entity_count < NOSHI_MESSAGE_ENTITIES_MAX) {
        noshi_entity *bold = &row->entities[row->entity_count++];
        memset(bold, 0, sizeof(*bold));
        bold->kind = NOSHI_ENTITY_BOLD;
        bold->offset = 0;
        bold->length = utf16_units(title);
        bold->url_offset = -1;
    }
    if (noshi_tl_get_bytes(media, "currency", &currency, &currency_len) == NOSHI_OK && currency_len == 3 && !memcmp(currency, "XTR", 3) &&
        noshi_tl_get_i64(media, "total_amount", &total) == NOSHI_OK && total > 0 && used + 24 < sizeof(row->text))
        snprintf(row->text + used, sizeof(row->text) - used, "\n\n\xE2\xAD\x90 %lld", (long long)total);
}

typedef struct {
    char *buf;
    size_t cap;
    size_t len;
} rich_out;

#define RICH_DEPTH_MAX 16
#define RICH_ITEMS_MAX 512

static void rich_put(rich_out *o, const uint8_t *data, size_t len) {
    size_t room = o->cap - 1 - o->len;
    if (len > room) {
        len = room;
        /* a sequence that did not fit whole goes with its lead byte */
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(o->buf + o->len, data, len);
    o->len += len;
    o->buf[o->len] = 0;
}

/* a block ends with a line break, and a paragraph with a blank line; nothing is added before the first block */
static void rich_break(rich_out *o, size_t lines) {
    size_t have = 0;
    if (!o->len) return;
    while (have < o->len && o->buf[o->len - 1 - have] == '\n') ++have;
    for (; have < lines; ++have) rich_put(o, (const uint8_t *)"\n", 1);
}

static void rich_text(rich_out *o, const noshi_tl_value *v, unsigned depth) {
    const uint8_t *data;
    size_t len;
    if (!v || depth > RICH_DEPTH_MAX) return;
    if (noshi_tl_is(v, NOSHI_TL_ID_textPlain)) {
        if (noshi_tl_get_bytes(v, "text", &data, &len) == NOSHI_OK) rich_put(o, data, len);
    } else if (noshi_tl_is(v, NOSHI_TL_ID_textConcat)) {
        const noshi_tl_value *parts = noshi_tl_get(v, "texts");
        if (!is_vec(parts)) return;
        for (uint32_t i = 0; i < parts->u.vec.count && i < RICH_ITEMS_MAX; ++i) rich_text(o, parts->u.vec.items[i], depth + 1);
    } else if (noshi_tl_is(v, NOSHI_TL_ID_textCustomEmoji)) {
        if (noshi_tl_get_bytes(v, "alt", &data, &len) == NOSHI_OK) rich_put(o, data, len);
    } else if (noshi_tl_is(v, NOSHI_TL_ID_textMath)) {
        if (noshi_tl_get_bytes(v, "source", &data, &len) == NOSHI_OK) rich_put(o, data, len);
    } else if (!noshi_tl_is(v, NOSHI_TL_ID_textButton) && !noshi_tl_is(v, NOSHI_TL_ID_textImage)) {
        /* bold, links, dates and the rest wrap one more text */
        rich_text(o, noshi_tl_get(v, "text"), depth + 1);
    }
}

static void rich_blocks(rich_out *o, const noshi_tl_value *blocks, unsigned depth);

static void rich_list(rich_out *o, const noshi_tl_value *items, int ordered, unsigned depth) {
    if (!is_vec(items)) return;
    for (uint32_t i = 0; i < items->u.vec.count && i < RICH_ITEMS_MAX; ++i) {
        const noshi_tl_value *item = items->u.vec.items[i];
        const uint8_t *num;
        size_t num_len;
        char label[24];
        if (ordered && noshi_tl_get_bytes(item, "num", &num, &num_len) == NOSHI_OK && num_len > 0 && num_len < sizeof(label) - 2) {
            memcpy(label, num, num_len);
            memcpy(label + num_len, " ", 2);
        } else if (ordered) {
            snprintf(label, sizeof(label), "%u. ", (unsigned)(i + 1));
        } else {
            snprintf(label, sizeof(label), "\xE2\x80\xA2 ");
        }
        rich_put(o, (const uint8_t *)label, strlen(label));
        if (noshi_tl_is(item, NOSHI_TL_ID_pageListItemText) || noshi_tl_is(item, NOSHI_TL_ID_pageListOrderedItemText)) rich_text(o, noshi_tl_get(item, "text"), depth + 1);
        else rich_blocks(o, noshi_tl_get(item, "blocks"), depth + 1);
        rich_break(o, 1);
    }
}

static void rich_blocks(rich_out *o, const noshi_tl_value *blocks, unsigned depth) {
    if (!is_vec(blocks) || depth > RICH_DEPTH_MAX) return;
    for (uint32_t i = 0; i < blocks->u.vec.count && i < RICH_ITEMS_MAX; ++i) {
        const noshi_tl_value *b = blocks->u.vec.items[i];
        if (noshi_tl_is(b, NOSHI_TL_ID_pageBlockList)) {
            rich_list(o, noshi_tl_get(b, "items"), 0, depth);
            rich_break(o, 2);
        } else if (noshi_tl_is(b, NOSHI_TL_ID_pageBlockOrderedList)) {
            rich_list(o, noshi_tl_get(b, "items"), 1, depth);
            rich_break(o, 2);
        } else if (noshi_tl_is(b, NOSHI_TL_ID_pageBlockDetails)) {
            rich_text(o, noshi_tl_get(b, "title"), depth + 1);
            rich_break(o, 1);
            rich_blocks(o, noshi_tl_get(b, "blocks"), depth + 1);
        } else if (noshi_tl_is(b, NOSHI_TL_ID_pageBlockTitle) || noshi_tl_is(b, NOSHI_TL_ID_pageBlockSubtitle) ||
                   noshi_tl_is(b, NOSHI_TL_ID_pageBlockHeader) || noshi_tl_is(b, NOSHI_TL_ID_pageBlockSubheader) ||
                   noshi_tl_is(b, NOSHI_TL_ID_pageBlockParagraph) || noshi_tl_is(b, NOSHI_TL_ID_pageBlockPreformatted) ||
                   noshi_tl_is(b, NOSHI_TL_ID_pageBlockFooter) || noshi_tl_is(b, NOSHI_TL_ID_pageBlockKicker) ||
                   noshi_tl_is(b, NOSHI_TL_ID_pageBlockBlockquote) || noshi_tl_is(b, NOSHI_TL_ID_pageBlockPullquote)) {
            size_t before = o->len;
            rich_text(o, noshi_tl_get(b, "text"), depth + 1);
            if (o->len > before) rich_break(o, 2);
        }
    }
}

/* a bot that answers in blocks sends an empty "message" and the words in rich_message; the blocks are shown as plain text, without their styling */
static void read_rich_message(const noshi_tl_value *m, noshi_message_row *out) {
    const noshi_tl_value *rich = noshi_tl_get(m, "rich_message");
    rich_out o;
    if (!rich || !noshi_tl_is(rich, NOSHI_TL_ID_richMessage)) return;
    o.buf = out->text;
    o.cap = sizeof(out->text);
    o.len = 0;
    out->text[0] = 0;
    rich_blocks(&o, noshi_tl_get(rich, "blocks"), 0);
    while (o.len > 0 && out->text[o.len - 1] == '\n') out->text[--o.len] = 0;
}

noshi_status noshi_message_read(const noshi_tl_value *m, noshi_message_row *out) {
    noshi_peer from;
    const noshi_tl_value *header;
    int service;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(m, NOSHI_TL_ID_messageEmpty)) return NOSHI_E_NOTFOUND;
    service = noshi_tl_is(m, NOSHI_TL_ID_messageService);
    if ((!service && !noshi_tl_is(m, NOSHI_TL_ID_message)) || noshi_tl_get_i32(m, "id", &out->id) != NOSHI_OK ||
        out->id <= 0 || noshi_tl_get_i32(m, "date", &out->date) != NOSHI_OK) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    {
        noshi_status status = noshi_reactions_read(noshi_tl_get(m, "reactions"), &out->reactions);
        if (status != NOSHI_OK) { memset(out, 0, sizeof(*out)); return status; }
    }
    out->has_reactions = noshi_tl_has(m, "reactions") ? 1 : 0;
    out->reactions_possible = !service || noshi_tl_has(m, "reactions_are_possible");
    out->out = noshi_tl_has(m, "out") ? 1 : 0;
    out->noforwards = noshi_tl_has(m, "noforwards") ? 1 : 0;
    out->invert_media = noshi_tl_has(m, "invert_media") ? 1 : 0;
    out->unread_mention = noshi_tl_has(m, "mentioned") && noshi_tl_has(m, "media_unread") ? 1 : 0;
    out->media_unread = noshi_tl_has(m, "media_unread") ? 1 : 0;
    out->post = noshi_tl_has(m, "post") ? 1 : 0;
    if (noshi_peer_from_tl(noshi_tl_get(m, "from_id"), &from) == NOSHI_OK) {
        if (from.kind == 1) out->from_id = from.id;
        else if (from.kind == 3) out->from_channel = from.id;
    }
    header = noshi_tl_get(m, "reply_to");
    if (header && noshi_tl_is(header, NOSHI_TL_ID_messageReplyStoryHeader)) {
        /* an answer to a story has no message to name, only the story */
        noshi_tl_get_i32(header, "story_id", &out->reply_story);
        header = NULL;
    }
    if (header) {
        noshi_tl_get_i32(header, "reply_to_msg_id", &out->reply_to);
        if (noshi_tl_get_i32(header, "reply_to_top_id", &out->thread_id) != NOSHI_OK || out->thread_id <= 0) out->thread_id = out->reply_to;
        const noshi_tl_value *reply_peer = noshi_tl_get(header, "reply_to_peer_id");
        if (reply_peer) {
            noshi_peer origin;
            if (noshi_peer_from_tl(reply_peer, &origin) != NOSHI_OK) {
                memset(out, 0, sizeof(*out));
                return NOSHI_E_MALFORMED;
            }
            out->reply_peer_kind = origin.kind;
            out->reply_peer_id = origin.id;
        }
        copy_text(out->reply_quote, sizeof(out->reply_quote), header, "quote_text", 0);
    }
    out->topic_id = 1;
    if (header && noshi_tl_has(header, "forum_topic")) {
        /* inside a topic the thread root is in reply_to_top_id, or in reply_to_msg_id for a message that answers the root itself */
        int32_t top = 0;
        if (noshi_tl_get_i32(header, "reply_to_top_id", &top) != NOSHI_OK || top <= 0) top = out->reply_to;
        if (top > 0) out->topic_id = top;
        if (out->reply_to == out->topic_id) out->reply_to = 0;
    }
    if (header && !noshi_tl_has(header, "forum_topic") && !noshi_tl_get(header, "reply_to_peer_id")) {
        /* a comment in the chat of a channel answers the post it hangs under, which the server writes as both the target and the top of the thread; every row of the
           chat quoting the same post says nothing the thread does not, so the quote is left out, as it is for the root of a topic */
        int32_t top = 0;
        if (noshi_tl_get_i32(header, "reply_to_top_id", &top) == NOSHI_OK && top > 0 && top == out->reply_to) out->reply_to = 0;
    }
    out->media.kind = NOSHI_PREVIEW_TEXT;
    if (service) {
        read_service(noshi_tl_get(m, "action"), out);
        out->media.kind = NOSHI_PREVIEW_SERVICE;
        return NOSHI_OK;
    }
    noshi_tl_get_i32(m, "edit_date", &out->edit_date);
    out->edit_hide = noshi_tl_has(m, "edit_hide") ? 1 : 0;
    copy_text(out->from_rank, sizeof(out->from_rank), m, "from_rank", 0);
    copy_text(out->post_author, sizeof(out->post_author), m, "post_author", 0);
    noshi_tl_get_i32(m, "views", &out->views);
    if (out->views < 0) out->views = 0;
    noshi_tl_get_i32(m, "forwards", &out->forwards);
    if (out->forwards < 0) out->forwards = 0;
    read_comments(noshi_tl_get(m, "replies"), out);
    if (noshi_tl_has(m, "via_bot_id")) noshi_tl_get_i64(m, "via_bot_id", &out->via_bot_id);
    if (noshi_tl_has(m, "effect")) noshi_tl_get_i64(m, "effect", &out->effect_id);
    out->has_markup = noshi_tl_has(m, "reply_markup") ? 1 : 0;
    {
        noshi_peer origin;
        if (noshi_peer_from_tl(noshi_tl_get(m, "saved_peer_id"), &origin) == NOSHI_OK) {
            out->saved_peer_kind = origin.kind;
            out->saved_peer_id = origin.id;
        }
    }
    header = noshi_tl_get(m, "fwd_from");
    if (header) {
        noshi_peer origin;
        out->forwarded = 1;
        out->forward_saved_out = noshi_tl_has(header, "saved_out") ? 1 : 0;
        copy_text(out->forward_name, sizeof(out->forward_name), header, "from_name", 0);
        noshi_tl_get_i32(header, "date", &out->forward_date);
        if (noshi_peer_from_tl(noshi_tl_get(header, "saved_from_peer"), &origin) == NOSHI_OK) {
            out->forward_origin_kind = origin.kind;
            out->forward_origin_id = origin.id;
            noshi_tl_get_i32(header, "saved_from_msg_id", &out->forward_origin_message);
        }
        if (noshi_peer_from_tl(noshi_tl_get(header, "from_id"), &origin) == NOSHI_OK) {
            if (origin.kind == 1) out->forward_from = origin.id;
            else if (origin.kind == 3) out->forward_from = -origin.id;
        }
    }
    if (noshi_tl_has(m, "grouped_id")) noshi_tl_get_i64(m, "grouped_id", &out->grouped_id);
    copy_text(out->text, sizeof(out->text), m, "message", 1);
    if (!out->text[0]) read_rich_message(m, out);
    noshi_media_classify(noshi_tl_get(m, "media"), &out->media);
    noshi_entities_read(m, out->entities, NOSHI_MESSAGE_ENTITIES_MAX, out->urls, sizeof(out->urls), &out->entity_count);
    read_invoice(noshi_tl_get(m, "media"), out);
    noshi_poll_read(noshi_tl_get(m, "media"), &out->poll);
    return NOSHI_OK;
}

noshi_status noshi_messages_parse_counted(const noshi_tl_value *answer, noshi_message_row *rows, size_t cap, size_t *count, noshi_messages_dropped *dropped) {
    const noshi_tl_value *messages;
    uint32_t i;
    size_t n = 0;
    if (dropped) memset(dropped, 0, sizeof(*dropped));
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_messagesNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_messages) && !noshi_tl_is(answer, NOSHI_TL_ID_messages_messagesSlice) &&
        !noshi_tl_is(answer, NOSHI_TL_ID_messages_channelMessages)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "messages", &messages) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (i = 0; i < messages->u.vec.count && n < cap; ++i) {
        noshi_status status = noshi_message_read(messages->u.vec.items[i], &rows[n]);
        if (status == NOSHI_OK) {
            ++n;
        } else if (status != NOSHI_E_NOTFOUND && dropped) {
            /* a deleted message (messageEmpty) is no loss; any other message that did not read vanishes from the chat, and an album loses its pictures and files with it */
            if (!dropped->count) {
                noshi_tl_get_i32(messages->u.vec.items[i], "id", &dropped->first_id);
                dropped->first_status = status;
            }
            ++dropped->count;
        }
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_messages_parse(const noshi_tl_value *answer, noshi_message_row *rows, size_t cap, size_t *count) {
    return noshi_messages_parse_counted(answer, rows, cap, count, NULL);
}

noshi_status noshi_history_page_read(const noshi_tl_value *answer, noshi_history_page *page) {
    const noshi_tl_value *messages;
    if (!page) return NOSHI_E_ARG;
    memset(page, 0, sizeof(*page));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_messages) && !noshi_tl_is(answer, NOSHI_TL_ID_messages_messagesSlice) &&
        !noshi_tl_is(answer, NOSHI_TL_ID_messages_channelMessages)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_vec(answer, "messages", &messages) != NOSHI_OK || messages->u.vec.count > NOSHI_MESSAGES_MAX) return NOSHI_E_MALFORMED;
    for (uint32_t i = 0; i < messages->u.vec.count; ++i) {
        const noshi_tl_value *message = messages->u.vec.items[i];
        int32_t id = 0;
        if ((!noshi_tl_is(message, NOSHI_TL_ID_message) && !noshi_tl_is(message, NOSHI_TL_ID_messageService) &&
             !noshi_tl_is(message, NOSHI_TL_ID_messageEmpty)) || noshi_tl_get_i32(message, "id", &id) != NOSHI_OK || id <= 0) {
            memset(page, 0, sizeof(*page));
            return NOSHI_E_MALFORMED;
        }
        if (!page->oldest_id || id < page->oldest_id) page->oldest_id = id;
        if (id > page->newest_id) page->newest_id = id;
    }
    page->count = messages->u.vec.count;
    return NOSHI_OK;
}

noshi_status noshi_history_cursor_advance(int32_t previous, const noshi_history_page *page, uint32_t limit, int32_t *cursor, int *more) {
    if (!cursor || !more) return NOSHI_E_ARG;
    *cursor = previous;
    *more = 0;
    if (!page || !limit || previous < 0 || page->count > limit || (page->count && page->oldest_id <= 0)) return NOSHI_E_MALFORMED;
    if (!page->count) return NOSHI_OK;
    if (previous > 0 && page->oldest_id >= previous) return page->count >= limit ? NOSHI_E_MALFORMED : NOSHI_OK;
    *cursor = page->oldest_id;
    *more = page->count >= limit && page->oldest_id > 1;
    return NOSHI_OK;
}

static void read_set(const noshi_tl_value *s, noshi_sticker_set_row *set) {
    int32_t value;
    const noshi_tl_value *thumbs;
    memset(set, 0, sizeof(*set));
    noshi_tl_get_i64(s, "id", &set->id);
    noshi_tl_get_i64(s, "access_hash", &set->access_hash);
    if (noshi_tl_get_i32(s, "count", &value) == NOSHI_OK) set->count = value;
    if (noshi_tl_get_i32(s, "hash", &value) == NOSHI_OK) set->hash = value;
    set->official = noshi_tl_has(s, "official") ? 1 : 0;
    set->installed = noshi_tl_has(s, "installed_date") ? 1 : 0;
    noshi_tl_get_i64(s, "thumb_document_id", &set->thumb_document_id);
    copy_text(set->title, sizeof(set->title), s, "title", 0);
    copy_text(set->short_name, sizeof(set->short_name), s, "short_name", 0);
    thumbs = noshi_tl_get(s, "thumbs");
    if (is_vec(thumbs) && thumbs->u.vec.count > 0) {
        if (noshi_tl_get_i32(s, "thumb_dc_id", &value) == NOSHI_OK) set->thumb_dc = value;
        if (noshi_tl_get_i32(s, "thumb_version", &value) == NOSHI_OK) set->thumb_version = value;
    }
}

static noshi_status sets_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count, int emojis) {
    const noshi_tl_value *list;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !sets || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_allStickersNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_allStickers) || noshi_tl_get_vec(answer, "sets", &list) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *s = list->u.vec.items[i];
        if (!noshi_tl_is(s, NOSHI_TL_ID_stickerSet) || noshi_tl_has(s, "masks") || noshi_tl_has(s, "archived") ||
            (noshi_tl_has(s, "emojis") ? 1 : 0) != emojis) continue;
        read_set(s, &sets[n]);
        if (sets[n].id == 0) continue;
        ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_sticker_sets_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count) {
    return sets_parse(answer, sets, cap, count, 0);
}

noshi_status noshi_emoji_sets_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count) {
    return sets_parse(answer, sets, cap, count, 1);
}

/* the sets of a list of StickerSetCovered, every constructor of which carries its header in "set" */
static noshi_status covered_parse(const noshi_tl_value *list, noshi_sticker_set_row *sets, size_t cap, size_t *count, int archive) {
    uint32_t i;
    size_t n = 0;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *s = noshi_tl_get(list->u.vec.items[i], "set");
        if (!noshi_tl_is(s, NOSHI_TL_ID_stickerSet) || noshi_tl_has(s, "masks") || noshi_tl_has(s, "emojis")) continue;
        read_set(s, &sets[n]);
        if (sets[n].id == 0) continue;
        /* a set in the archive has an installed date too, and is not among the ones the panel shows */
        if (noshi_tl_has(s, "archived") || archive) sets[n].installed = 0;
        ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_featured_stickers_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getFeaturedStickers");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_featured_stickers_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count) {
    const noshi_tl_value *list;
    if (count) *count = 0;
    if (!answer || !sets || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_featuredStickersNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_featuredStickers) || noshi_tl_get_vec(answer, "sets", &list) != NOSHI_OK) return NOSHI_E_MALFORMED;
    return covered_parse(list, sets, cap, count, 0);
}

noshi_status noshi_archived_stickers_request(noshi_arena *arena, int64_t offset_id, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || limit < 1 || limit > 100 || offset_id < 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getArchivedStickers");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, request, "offset_id", offset_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_archived_stickers_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count, int32_t *total) {
    const noshi_tl_value *list;
    int32_t all = 0;
    noshi_status status;
    if (count) *count = 0;
    if (total) *total = 0;
    if (!answer || !sets || !count || cap == 0) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_archivedStickers) || noshi_tl_get_vec(answer, "sets", &list) != NOSHI_OK) return NOSHI_E_MALFORMED;
    status = covered_parse(list, sets, cap, count, 1);
    if (status == NOSHI_OK && total) {
        if (noshi_tl_get_i32(answer, "count", &all) != NOSHI_OK || all < 0) all = (int32_t)*count;
        *total = all;
    }
    return status;
}

noshi_status noshi_emoji_sets_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!arena || !out) return NOSHI_E_ARG;
    *out = NULL;
    request = noshi_tl_new_obj(arena, "messages.getEmojiStickers");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_emoji_set_parse(const noshi_tl_value *answer, noshi_sticker_set_row *set, noshi_custom_emoji *rows,
                                       size_t cap, size_t *count) {
    const noshi_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !set || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSetNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSet) || !noshi_tl_is(noshi_tl_get(answer, "set"), NOSHI_TL_ID_stickerSet) ||
        noshi_tl_get_vec(answer, "documents", &documents) != NOSHI_OK) return NOSHI_E_MALFORMED;
    read_set(noshi_tl_get(answer, "set"), set);
    return noshi_custom_emoji_parse(documents, rows, cap, count);
}

static size_t read_stickers(const noshi_tl_value *documents, noshi_sticker_row *stickers, size_t cap) {
    uint32_t i;
    size_t n = 0;
    for (i = 0; i < documents->u.vec.count && n < cap; ++i) {
        if (noshi_sticker_read(documents->u.vec.items[i], &stickers[n]) == NOSHI_OK) ++n;
    }
    return n;
}

noshi_status noshi_sticker_set_parse(const noshi_tl_value *answer, noshi_sticker_set_row *set,
                                         noshi_sticker_row *stickers, size_t cap, size_t *count) {
    const noshi_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !set || !stickers || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSetNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSet) || !noshi_tl_is(noshi_tl_get(answer, "set"), NOSHI_TL_ID_stickerSet) ||
        noshi_tl_get_vec(answer, "documents", &documents) != NOSHI_OK) return NOSHI_E_MALFORMED;
    read_set(noshi_tl_get(answer, "set"), set);
    *count = read_stickers(documents, stickers, cap);
    return NOSHI_OK;
}

noshi_status noshi_sticker_set_by_name_request(noshi_arena *arena, const char *short_name, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !short_name || !out) return NOSHI_E_ARG;
    for (i = 0; short_name[i]; ++i) {
        char c = short_name[i];
        if (i >= 64 || !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) return NOSHI_E_ARG;
    }
    if (i == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getStickerSet");
    input = noshi_tl_new_obj(arena, "inputStickerSetShortName");
    if (!request || !input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, input, "short_name", short_name);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stickerset", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_animated_emoji_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getStickerSet");
    input = noshi_tl_new_obj(arena, "inputStickerSetAnimatedEmoji");
    if (!request || !input) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "stickerset", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_animated_emoji_parse(const noshi_tl_value *answer, noshi_sticker_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *packs, *documents;
    size_t written = 0;
    if (count) *count = 0;
    if (!answer || !rows || !cap || !count) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSetNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSet) ||
        !noshi_tl_is(noshi_tl_get(answer, "set"), NOSHI_TL_ID_stickerSet) ||
        noshi_tl_get_vec(answer, "packs", &packs) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "documents", &documents) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (packs->u.vec.count > NOSHI_ANIMATED_EMOJI_MAX || documents->u.vec.count > NOSHI_ANIMATED_EMOJI_MAX) return NOSHI_E_LIMIT;
    for (uint32_t i = 0; i < packs->u.vec.count && written < cap; ++i) {
        const noshi_tl_value *pack = packs->u.vec.items[i], *ids;
        const uint8_t *emoticon;
        size_t length;
        if (!noshi_tl_is(pack, NOSHI_TL_ID_stickerPack) ||
            noshi_tl_get_bytes(pack, "emoticon", &emoticon, &length) != NOSHI_OK || !length ||
            length >= sizeof(rows[0].media.alt) || memchr(emoticon, 0, length) ||
            noshi_tl_get_vec(pack, "documents", &ids) != NOSHI_OK || !ids->u.vec.count) continue;
        const noshi_tl_value *first = ids->u.vec.items[0];
        if (!first || first->kind != NOSHI_TL_V_I64 || first->u.i64 <= 0) continue;
        for (uint32_t j = 0; j < documents->u.vec.count; ++j) {
            int64_t id = 0;
            const noshi_tl_value *document = documents->u.vec.items[j];
            if (noshi_tl_get_i64(document, "id", &id) != NOSHI_OK || id != first->u.i64) continue;
            noshi_sticker_row row;
            if (noshi_sticker_read(document, &row) != NOSHI_OK || row.media.sticker != NOSHI_STICKER_ANIMATED ||
                row.media.size <= 0 || row.media.size > NOSHI_ANIMATED_EMOJI_BYTES_MAX) break;
            memcpy(row.media.alt, emoticon, length);
            row.media.alt[length] = 0;
            rows[written++] = row;
            break;
        }
    }
    *count = written;
    return NOSHI_OK;
}

noshi_status noshi_recent_stickers_parse(const noshi_tl_value *answer, noshi_sticker_row *stickers, size_t cap, size_t *count) {
    const noshi_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !stickers || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_recentStickersNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_recentStickers) || noshi_tl_get_vec(answer, "stickers", &documents) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    *count = read_stickers(documents, stickers, cap);
    return NOSHI_OK;
}

static int sent_in_update(const noshi_tl_value *update, int64_t random_id, int32_t *id) {
    int64_t random;
    if (!noshi_tl_is(update, NOSHI_TL_ID_updateMessageID) || noshi_tl_get_i64(update, "random_id", &random) != NOSHI_OK ||
        random != random_id) return 0;
    return noshi_tl_get_i32(update, "id", id) == NOSHI_OK && *id > 0;
}

noshi_status noshi_sent_parse(const noshi_tl_value *updates, int64_t random_id, int32_t *id) {
    const noshi_tl_value *list;
    uint32_t i;
    if (!updates || !id) return NOSHI_E_ARG;
    *id = 0;
    if (noshi_tl_is(updates, NOSHI_TL_ID_updateShortSentMessage)) {
        return noshi_tl_get_i32(updates, "id", id) == NOSHI_OK && *id > 0 ? NOSHI_OK : NOSHI_E_MALFORMED;
    }
    if (noshi_tl_is(updates, NOSHI_TL_ID_updateShort)) return sent_in_update(noshi_tl_get(updates, "update"), random_id, id) ? NOSHI_OK : NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(updates, NOSHI_TL_ID_updates) && !noshi_tl_is(updates, NOSHI_TL_ID_updatesCombined)) return NOSHI_E_NOTFOUND;
    list = noshi_tl_get(updates, "updates");
    if (!is_vec(list)) return NOSHI_E_MALFORMED;
    for (i = 0; i < list->u.vec.count; ++i) if (sent_in_update(list->u.vec.items[i], random_id, id)) return NOSHI_OK;
    return NOSHI_E_NOTFOUND;
}

noshi_status noshi_input_peer(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    noshi_tl_value *v;
    noshi_status status;
    if (!arena || !peer || !out) return NOSHI_E_ARG;
    *out = NULL;
    if (peer->self) {
        v = noshi_tl_new_obj(arena, "inputPeerSelf");
        if (!v) return NOSHI_E_NOMEM;
        *out = v;
        return NOSHI_OK;
    }
    if (peer->id <= 0 || peer->kind < 1 || peer->kind > 3 || (peer->kind != 2 && peer->access_hash == 0)) return NOSHI_E_ARG;
    v = noshi_tl_new_obj(arena, peer->kind == 1 ? "inputPeerUser" : peer->kind == 2 ? "inputPeerChat" : "inputPeerChannel");
    if (!v) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, v, peer->kind == 1 ? "user_id" : peer->kind == 2 ? "chat_id" : "channel_id", peer->id);
    if (status == NOSHI_OK && peer->kind != 2) status = noshi_tl_set_i64(arena, v, "access_hash", peer->access_hash);
    if (status == NOSHI_OK) *out = v;
    return status;
}

noshi_status noshi_peer_dialogs_request(noshi_arena *arena, const noshi_peer_ref *peers, size_t count, noshi_tl_value **out) {
    noshi_tl_value *call, *list;
    noshi_status status = NOSHI_OK;
    if (out) *out = NULL;
    if (!arena || !peers || !out || count == 0 || count > 100) return NOSHI_E_ARG;
    call = noshi_tl_new_obj(arena, "messages.getPeerDialogs");
    list = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!call || !list) return NOSHI_E_NOMEM;
    for (size_t i = 0; i < count && status == NOSHI_OK; ++i) {
        noshi_tl_value *input = NULL;
        noshi_tl_value *entry = noshi_tl_new_obj(arena, "inputDialogPeer");
        if (!entry) return NOSHI_E_NOMEM;
        status = noshi_input_peer(arena, &peers[i], &input);
        if (status == NOSHI_OK) status = noshi_tl_set(entry, "peer", input);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(list, (uint32_t)i, entry);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(call, "peers", list);
    if (status == NOSHI_OK) *out = call;
    return status;
}

/* a message sent into a topic answers the topic root, which is how the server files it; General has no root to answer */
noshi_status noshi_set_topic_reply(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *peer) {
    noshi_tl_value *reply;
    noshi_status status;
    if (peer->topic_id <= 1) return NOSHI_OK;
    reply = noshi_tl_new_obj(arena, "inputReplyToMessage");
    if (!reply) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, reply, "reply_to_msg_id", peer->topic_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, reply, "top_msg_id", peer->topic_id);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "reply_to", reply);
    return status;
}

/* a reply names the message it answers; inside a topic it also names the topic, so the server files the reply there */
noshi_status noshi_set_reply(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *peer, int32_t reply_to) {
    return noshi_set_reply_quote(arena, request, peer, reply_to, NULL, -1);
}

/* the same, with a quote: the words of the answered message that the reply is about; offset is where they start in UTF-16 units, or negative when unknown */
noshi_status noshi_set_reply_quote(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *peer, int32_t reply_to,
                                       const char *quote, int32_t offset) {
    noshi_tl_value *reply;
    noshi_status status;
    if (!arena || !request || !peer || reply_to < 0) return NOSHI_E_ARG;
    if (reply_to == 0) return noshi_set_topic_reply(arena, request, peer);
    reply = noshi_tl_new_obj(arena, "inputReplyToMessage");
    if (!reply) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, reply, "reply_to_msg_id", reply_to);
    if (status == NOSHI_OK && peer->topic_id > 1) status = noshi_tl_set_i32(arena, reply, "top_msg_id", peer->topic_id);
    if (status == NOSHI_OK && quote && quote[0]) {
        status = noshi_tl_set_str(arena, reply, "quote_text", quote);
        if (status == NOSHI_OK && offset >= 0) status = noshi_tl_set_i32(arena, reply, "quote_offset", offset);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "reply_to", reply);
    return status;
}

noshi_status noshi_stickers_request(noshi_arena *arena, const char *emoticon, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !emoticon || !out || !emoticon[0] || strlen(emoticon) > NOSHI_STICKER_EMOTICON_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getStickers");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "emoticon", emoticon);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status != NOSHI_OK) return status;
    *out = request;
    return NOSHI_OK;
}

noshi_status noshi_stickers_parse(const noshi_tl_value *answer, noshi_sticker_row *stickers, size_t cap, size_t *count) {
    const noshi_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !stickers || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_stickersNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_stickers) || noshi_tl_get_vec(answer, "stickers", &documents) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    *count = read_stickers(documents, stickers, cap);
    return NOSHI_OK;
}

/* messages.search of one chat with a filter and a text; everything else of the request stays at its neutral value */
static noshi_status chat_search_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_peer_ref *from, const char *query,
                                          const char *filter_name, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *filter, *sender = NULL;
    noshi_status status;
    if (!arena || !out || limit < 1 || limit > NOSHI_MESSAGES_MAX) return NOSHI_E_ARG;
    *out = NULL;
    status = noshi_input_peer(arena, peer, &input);
    if (status == NOSHI_OK && from) status = noshi_input_peer(arena, from, &sender);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.search");
    filter = noshi_tl_new_obj(arena, filter_name);
    if (!request || !filter) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "q", query);
    if (status == NOSHI_OK && sender) status = noshi_tl_set(request, "from_id", sender);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "filter", filter);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "min_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "add_offset", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "min_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_pinned_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!peer || !out || peer->topic_id < 0 || (peer->topic_id > 0 && peer->kind != 3)) return NOSHI_E_ARG;
    status = chat_search_request(arena, peer, NULL, "", "inputMessagesFilterPinned", limit, &request);
    if (status == NOSHI_OK && peer->topic_id > 0) status = noshi_tl_set_i32(arena, request, "top_msg_id", peer->topic_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* messages.getUnreadReactions or messages.readReactions of a chat or its topic; the history one takes the newest limit and nothing else */
static noshi_status reactions_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *name, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || peer->topic_id < 0 || (peer->topic_id > 0 && peer->kind != 3)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, name);
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK && peer->topic_id > 0) status = noshi_tl_set_i32(arena, request, "top_msg_id", peer->topic_id);
    if (status == NOSHI_OK && limit > 0) status = noshi_tl_set_i32(arena, request, "offset_id", 0);
    if (status == NOSHI_OK && limit > 0) status = noshi_tl_set_i32(arena, request, "add_offset", 0);
    if (status == NOSHI_OK && limit > 0) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK && limit > 0) status = noshi_tl_set_i32(arena, request, "max_id", 0);
    if (status == NOSHI_OK && limit > 0) status = noshi_tl_set_i32(arena, request, "min_id", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_unread_reactions_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t limit, noshi_tl_value **out) {
    if (limit < 1 || limit > NOSHI_MESSAGES_MAX) return NOSHI_E_ARG;
    return reactions_request(arena, peer, "messages.getUnreadReactions", limit, out);
}

noshi_status noshi_read_reactions_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    return reactions_request(arena, peer, "messages.readReactions", 0, out);
}

noshi_status noshi_chat_photos_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t limit, noshi_tl_value **out) {
    return chat_search_request(arena, peer, NULL, "", "inputMessagesFilterChatPhotos", limit, out);
}

noshi_status noshi_chat_search_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *query, int32_t limit,
                                           noshi_tl_value **out) {
    size_t len;
    if (out) *out = NULL;
    if (!query) return NOSHI_E_ARG;
    len = strlen(query);
    if (len == 0) return NOSHI_E_ARG;
    if (len > NOSHI_CHAT_SEARCH_QUERY_MAX) return NOSHI_E_LIMIT;
    return chat_search_request(arena, peer, NULL, query, "inputMessagesFilterEmpty", limit, out);
}

noshi_status noshi_chat_from_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_peer_ref *from, int32_t limit,
                                         noshi_tl_value **out) {
    if (out) *out = NULL;
    /* only a person can be searched for; a channel or a group has no history of its own in a chat it speaks in */
    if (!from || from->kind != 1) return NOSHI_E_ARG;
    return chat_search_request(arena, peer, from, "", "inputMessagesFilterEmpty", limit, out);
}

noshi_status noshi_messages_by_id_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count, noshi_tl_value **out) {
    noshi_tl_value *request, *list, *channel = NULL;
    noshi_status status = NOSHI_OK;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !peer || !out || !ids || count < 1 || count > NOSHI_MESSAGES_MAX || peer->self) return NOSHI_E_ARG;
    if (peer->kind == 3) {
        if (peer->id <= 0 || peer->access_hash == 0) return NOSHI_E_ARG;
        channel = noshi_tl_new_obj(arena, "inputChannel");
        if (!channel) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i64(arena, channel, "channel_id", peer->id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", peer->access_hash);
    } else if (peer->kind != 1 && peer->kind != 2) {
        return NOSHI_E_ARG;
    }
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, channel ? "channels.getMessages" : "messages.getMessages");
    list = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!request || !list) return NOSHI_E_NOMEM;
    for (i = 0; i < count && status == NOSHI_OK; ++i) {
        noshi_tl_value *item;
        if (ids[i] <= 0) return NOSHI_E_ARG;
        item = noshi_tl_new_obj(arena, "inputMessageID");
        if (!item) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i32(arena, item, "id", ids[i]);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(list, (uint32_t)i, item);
    }
    if (status == NOSHI_OK && channel) status = noshi_tl_set(request, "channel", channel);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_history_window_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t add_offset, int32_t limit,
                                              noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !peer || offset_id < 0 || limit < 1 || limit > NOSHI_MESSAGES_MAX || add_offset > 0 || -add_offset >= limit) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, peer->topic_id > 0 ? "messages.getReplies" : "messages.getHistory");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK && peer->topic_id > 0) status = noshi_tl_set_i32(arena, request, "msg_id", peer->topic_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "add_offset", add_offset);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "min_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_history_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit,
                                      noshi_tl_value **out) {
    return noshi_history_window_request(arena, peer, offset_id, 0, limit, out);
}

noshi_status noshi_saved_history_window_request(noshi_arena *arena, const noshi_peer_ref *source, int32_t offset_id, int32_t add_offset, int32_t limit,
                                                    noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || offset_id < 0 || limit < 1 || limit > NOSHI_MESSAGES_MAX || add_offset > 0 || -add_offset >= limit) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, source, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.getSavedHistory");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "add_offset", add_offset);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "min_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_saved_history_request(noshi_arena *arena, const noshi_peer_ref *source, int32_t offset_id, int32_t limit,
                                             noshi_tl_value **out) {
    return noshi_saved_history_window_request(arena, source, offset_id, 0, limit, out);
}

noshi_status noshi_set_schedule(noshi_arena *arena, noshi_tl_value *request, int32_t date) {
    if (!arena || !request || date <= 0) return NOSHI_E_ARG;
    return noshi_tl_set_i32(arena, request, "schedule_date", date);
}

noshi_status noshi_message_link_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t id, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !channel || !out || id <= 0 || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return NOSHI_E_ARG;
    input = noshi_tl_new_obj(arena, "inputChannel");
    request = noshi_tl_new_obj(arena, "channels.exportMessageLink");
    if (!input || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "channel_id", channel->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", channel->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "channel", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "id", id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_message_link_parse(const noshi_tl_value *answer, char *link, size_t cap) {
    const uint8_t *data;
    size_t len;
    if (link && cap) link[0] = 0;
    if (!link || cap < 2) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_exportedMessageLink) || noshi_tl_get_bytes(answer, "link", &data, &len) != NOSHI_OK || !len) return NOSHI_E_MALFORMED;
    if (len >= cap || len > 255) return NOSHI_E_LIMIT;
    memcpy(link, data, len);
    link[len] = 0;
    return NOSHI_OK;
}

/* the TL constructor of an entity the client sends, NULL for the kinds the server finds in the text by itself */
static const char *send_entity_name(uint8_t kind) {
    switch (kind) {
    case NOSHI_ENTITY_BOLD: return "messageEntityBold";
    case NOSHI_ENTITY_ITALIC: return "messageEntityItalic";
    case NOSHI_ENTITY_UNDERLINE: return "messageEntityUnderline";
    case NOSHI_ENTITY_STRIKE: return "messageEntityStrike";
    case NOSHI_ENTITY_CODE: return "messageEntityCode";
    case NOSHI_ENTITY_PRE: return "messageEntityPre";
    case NOSHI_ENTITY_SPOILER: return "messageEntitySpoiler";
    case NOSHI_ENTITY_BLOCKQUOTE: return "messageEntityBlockquote";
    case NOSHI_ENTITY_TEXT_URL: return "messageEntityTextUrl";
    case NOSHI_ENTITY_MENTION_NAME: return "inputMessageEntityMentionName";
    case NOSHI_ENTITY_FORMATTED_DATE: return "messageEntityFormattedDate";
    case NOSHI_ENTITY_CUSTOM_EMOJI: return "messageEntityCustomEmoji";
    default: return NULL;
    }
}

/* what the server would reject the whole message for: a range outside the text, or a kind without what it points at */
static int send_entity_valid(const noshi_send_entity *e, size_t units) {
    if (e->offset < 0 || e->length <= 0 || (size_t)e->offset + (size_t)e->length > units) return 0;
    switch (e->kind) {
    case NOSHI_ENTITY_CUSTOM_EMOJI: return e->id != 0;
    case NOSHI_ENTITY_TEXT_URL: return e->text && e->text[0];
    case NOSHI_ENTITY_MENTION_NAME: return e->id > 0 && e->access_hash != 0;
    case NOSHI_ENTITY_FORMATTED_DATE: return e->date > 0;
    default: return 1;
    }
}

static noshi_status build_send_entity(noshi_arena *arena, const noshi_send_entity *e, noshi_tl_value **out) {
    static const char *const date_flags[] = {"relative", "short_time", "long_time", "short_date", "long_date", "day_of_week"};
    noshi_tl_value *entity = noshi_tl_new_obj(arena, send_entity_name(e->kind)), *user;
    noshi_status status;
    size_t k;
    if (!entity) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, entity, "offset", e->offset);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, entity, "length", e->length);
    if (status != NOSHI_OK) return status;
    switch (e->kind) {
    case NOSHI_ENTITY_CUSTOM_EMOJI:
        status = noshi_tl_set_i64(arena, entity, "document_id", e->id);
        break;
    case NOSHI_ENTITY_TEXT_URL:
        status = noshi_tl_set_str(arena, entity, "url", e->text);
        break;
    case NOSHI_ENTITY_PRE:
        status = noshi_tl_set_str(arena, entity, "language", e->text ? e->text : "");
        break;
    case NOSHI_ENTITY_BLOCKQUOTE:
        if (e->flags & NOSHI_ENTITY_COLLAPSED) status = noshi_tl_set_flag(entity, "collapsed");
        break;
    case NOSHI_ENTITY_MENTION_NAME:
        user = noshi_tl_new_obj(arena, "inputUser");
        if (!user) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i64(arena, user, "user_id", e->id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, user, "access_hash", e->access_hash);
        if (status == NOSHI_OK) status = noshi_tl_set(entity, "user_id", user);
        break;
    case NOSHI_ENTITY_FORMATTED_DATE:
        status = noshi_tl_set_i32(arena, entity, "date", e->date);
        for (k = 0; k < sizeof(date_flags) / sizeof(date_flags[0]) && status == NOSHI_OK; ++k) {
            if (e->flags & (1u << k)) status = noshi_tl_set_flag(entity, date_flags[k]);
        }
        break;
    default:
        break;
    }
    if (status == NOSHI_OK) *out = entity;
    return status;
}

/* the entity vector of a text being sent or kept as a draft; *out stays NULL when no entity is one the client sends. A range outside the text, or a kind
   without what it points at, would make the server reject the whole message, so it is NOSHI_E_ARG here */
noshi_status noshi_send_entities_build(noshi_arena *arena, const char *text, const noshi_send_entity *entities, size_t entity_count,
                                          noshi_tl_value **out) {
    noshi_tl_value *list;
    noshi_status status = NOSHI_OK;
    size_t i, at = 0, sent = 0, units = 0;
    if (out) *out = NULL;
    if (!arena || !text || !out || (entity_count && !entities) || entity_count > NOSHI_MESSAGE_ENTITIES_MAX) return NOSHI_E_ARG;
    for (i = 0; text[i]; ++i) {
        unsigned char c = (unsigned char)text[i];
        if ((c & 0xC0u) == 0x80u) continue;
        units += c >= 0xF0u ? 2 : 1;
    }
    for (i = 0; i < entity_count; ++i) {
        if (!send_entity_name(entities[i].kind)) continue;
        if (!send_entity_valid(&entities[i], units)) return NOSHI_E_ARG;
        ++sent;
    }
    if (!sent) return NOSHI_OK;
    list = noshi_tl_new_vec(arena, (uint32_t)sent);
    if (!list) return NOSHI_E_NOMEM;
    for (i = 0; i < entity_count && status == NOSHI_OK; ++i) {
        noshi_tl_value *entity = NULL;
        if (!send_entity_name(entities[i].kind)) continue;
        status = build_send_entity(arena, &entities[i], &entity);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(list, (uint32_t)at++, entity);
    }
    if (status == NOSHI_OK) *out = list;
    return status;
}

static noshi_status send_text(noshi_arena *arena, const noshi_peer_ref *peer, const char *text, const noshi_send_entity *entities,
                                size_t entity_count, int64_t random_id, int32_t reply_to, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *list = NULL;
    noshi_status status;
    if (!arena || !text || !out || !text[0] || random_id == 0 || strlen(text) > NOSHI_MESSAGE_TEXT_MAX - 4) return NOSHI_E_ARG;
    *out = NULL;
    status = noshi_send_entities_build(arena, text, entities, entity_count, &list);
    if (status != NOSHI_OK) return status;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.sendMessage");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_reply(arena, request, peer, reply_to);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", text);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK && list) status = noshi_tl_set(request, "entities", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_send_text_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *text,
                                        const noshi_send_entity *entities, size_t entity_count, int64_t random_id, noshi_tl_value **out) {
    return send_text(arena, peer, text, entities, entity_count, random_id, 0, out);
}

noshi_status noshi_send_text_reply_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *text,
                                               const noshi_send_entity *entities, size_t entity_count, int64_t random_id, int32_t reply_to,
                                               noshi_tl_value **out) {
    if (reply_to < 0) return NOSHI_E_ARG;
    return send_text(arena, peer, text, entities, entity_count, random_id, reply_to, out);
}

static noshi_status document_input(noshi_arena *arena, const noshi_media_ref *ref, noshi_tl_value **out) {
    noshi_tl_value *document = noshi_tl_new_obj(arena, "inputDocument");
    noshi_status status;
    if (!document) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, document, "id", ref->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, document, "access_hash", ref->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, document, "file_reference", ref->file_ref, ref->ref_len);
    if (status == NOSHI_OK) *out = document;
    return status;
}

noshi_status noshi_faved_stickers_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getFavedStickers");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_saved_gifs_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getSavedGifs");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_faved_stickers_parse(const noshi_tl_value *answer, noshi_sticker_row *stickers, size_t cap, size_t *count) {
    const noshi_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !stickers || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_favedStickersNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_favedStickers) || noshi_tl_get_vec(answer, "stickers", &documents) != NOSHI_OK) return NOSHI_E_MALFORMED;
    *count = read_stickers(documents, stickers, cap);
    return NOSHI_OK;
}

noshi_status noshi_saved_gifs_parse(const noshi_tl_value *answer, noshi_sticker_row *gifs, size_t cap, size_t *count) {
    const noshi_tl_value *documents;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !gifs || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_savedGifsNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_savedGifs) || noshi_tl_get_vec(answer, "gifs", &documents) != NOSHI_OK) return NOSHI_E_MALFORMED;
    for (i = 0; i < documents->u.vec.count && n < cap; ++i) {
        noshi_sticker_row *row = &gifs[n];
        memset(row, 0, sizeof(*row));
        read_document(documents->u.vec.items[i], NULL, &row->media);
        /* a document the server still lists but no longer has, or one that is no animation, has nothing to play */
        if (row->media.kind == NOSHI_PREVIEW_GIF && row->media.ref.source == NOSHI_MEDIA_SOURCE_DOCUMENT) ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_fave_sticker_request(noshi_arena *arena, const noshi_media_ref *sticker, int unfave, noshi_tl_value **out) {
    noshi_tl_value *request, *document, *flag;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !sticker || !out || sticker->source != NOSHI_MEDIA_SOURCE_DOCUMENT || sticker->thumb[0] || sticker->id == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.faveSticker");
    flag = noshi_tl_new_obj(arena, unfave ? "boolTrue" : "boolFalse");
    if (!request || !flag) return NOSHI_E_NOMEM;
    status = document_input(arena, sticker, &document);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "id", document);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "unfave", flag);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_clear_recent_stickers_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.clearRecentStickers");
    if (!request) return NOSHI_E_NOMEM;
    *out = request;
    return NOSHI_OK;
}

/* the six games of messages.sendMedia with inputMediaDice, as the client of the server's config names them */
static const char *const dice_games[] = {"\xf0\x9f\x8e\xb2", "\xf0\x9f\x8e\xaf", "\xf0\x9f\x8f\x80", "\xe2\x9a\xbd", "\xf0\x9f\x8e\xb3", "\xf0\x9f\x8e\xb0"};

int noshi_dice_emoticon(const char *text) {
    size_t length;
    if (!text) return 0;
    length = strlen(text);
    /* U+FE0F asks for the emoji look of a character that also has a text look, as the football does */
    if (length >= 3 && !memcmp(text + length - 3, "\xef\xb8\x8f", 3)) length -= 3;
    for (size_t i = 0; i < sizeof(dice_games) / sizeof(dice_games[0]); ++i) {
        if (strlen(dice_games[i]) == length && !memcmp(text, dice_games[i], length)) return 1;
    }
    return 0;
}

noshi_status noshi_send_dice_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *text, int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *media;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || random_id == 0 || !noshi_dice_emoticon(text)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    media = noshi_tl_new_obj(arena, "inputMediaDice");
    request = noshi_tl_new_obj(arena, "messages.sendMedia");
    if (!media || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, media, "emoticon", text);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_topic_reply(arena, request, peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", "");
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_dice_set_request(noshi_arena *arena, const char *emoticon, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !noshi_dice_emoticon(emoticon)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "messages.getStickerSet");
    input = noshi_tl_new_obj(arena, "inputStickerSetDice");
    if (!request || !input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, input, "emoticon", emoticon);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stickerset", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_dice_set_parse(const noshi_tl_value *answer, noshi_sticker_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSetNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_stickerSet) || noshi_tl_get_vec(answer, "documents", &documents) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (documents->u.vec.count > NOSHI_DICE_STICKERS_MAX || documents->u.vec.count > cap) return NOSHI_E_LIMIT;
    for (uint32_t i = 0; i < documents->u.vec.count; ++i) {
        memset(&rows[i], 0, sizeof(rows[i]));
        if (noshi_sticker_read(documents->u.vec.items[i], &rows[i]) != NOSHI_OK) memset(&rows[i], 0, sizeof(rows[i]));
    }
    *count = documents->u.vec.count;
    return NOSHI_OK;
}

noshi_status noshi_send_sticker_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_media_ref *sticker,
                                           int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *media, *document;
    noshi_status status;
    if (!arena || !sticker || !out || random_id == 0 || sticker->source != NOSHI_MEDIA_SOURCE_DOCUMENT || sticker->thumb[0]) return NOSHI_E_ARG;
    *out = NULL;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    media = noshi_tl_new_obj(arena, "inputMediaDocument");
    request = noshi_tl_new_obj(arena, "messages.sendMedia");
    if (!media || !request) return NOSHI_E_NOMEM;
    status = document_input(arena, sticker, &document);
    if (status == NOSHI_OK) status = noshi_tl_set(media, "id", document);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_topic_reply(arena, request, peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", "");
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* the document attributes of a kind, or NULL when the spec does not carry what the kind needs */
static noshi_tl_value *upload_attribute(noshi_arena *arena, const noshi_upload_spec *spec, noshi_status *status) {
    noshi_tl_value *attribute = NULL;
    *status = NOSHI_E_ARG;
    switch (spec->kind) {
    case NOSHI_UPLOAD_VOICE:
        if (spec->duration_ms <= 0 || !spec->waveform || spec->waveform_len != NOSHI_WAVEFORM_BYTES) return NULL;
        attribute = noshi_tl_new_obj(arena, "documentAttributeAudio");
        *status = attribute ? noshi_tl_set_flag(attribute, "voice") : NOSHI_E_NOMEM;
        if (*status == NOSHI_OK) *status = noshi_tl_set_i32(arena, attribute, "duration", (spec->duration_ms + 500) / 1000);
        if (*status == NOSHI_OK) *status = noshi_tl_set_bytes(arena, attribute, "waveform", spec->waveform, spec->waveform_len);
        break;
    case NOSHI_UPLOAD_ROUND:
    case NOSHI_UPLOAD_VIDEO:
        if (spec->duration_ms <= 0 || spec->width <= 0 || (spec->kind == NOSHI_UPLOAD_VIDEO && spec->height <= 0) || spec->waveform_len) return NULL;
        attribute = noshi_tl_new_obj(arena, "documentAttributeVideo");
        *status = attribute ? noshi_tl_set_flag(attribute, spec->kind == NOSHI_UPLOAD_ROUND ? "round_message" : "supports_streaming") : NOSHI_E_NOMEM;
        if (*status == NOSHI_OK) *status = noshi_tl_set_f64(arena, attribute, "duration", (double)spec->duration_ms / 1000.0);
        if (*status == NOSHI_OK) *status = noshi_tl_set_i32(arena, attribute, "w", spec->width);
        if (*status == NOSHI_OK) *status = noshi_tl_set_i32(arena, attribute, "h", spec->kind == NOSHI_UPLOAD_ROUND ? spec->width : spec->height);
        break;
    case NOSHI_UPLOAD_FILE:
        if (!spec->name[0] || !spec->mime[0]) return NULL;
        attribute = noshi_tl_new_obj(arena, "documentAttributeFilename");
        *status = attribute ? noshi_tl_set_str(arena, attribute, "file_name", spec->name) : NOSHI_E_NOMEM;
        break;
    case NOSHI_UPLOAD_PHOTO:
        break;
    }
    return attribute;
}

/* the input media a spec and an uploaded file make: a photo, or a document with the attributes of its kind */
static noshi_status upload_media(noshi_arena *arena, noshi_tl_value *file, const noshi_upload_spec *spec, noshi_tl_value **out) {
    noshi_tl_value *media, *attributes = NULL, *attribute = NULL;
    noshi_status status;
    const char *mime;
    *out = NULL;
    if (spec->kind == NOSHI_UPLOAD_PHOTO) {
        media = noshi_tl_new_obj(arena, "inputMediaUploadedPhoto");
        if (!media) return NOSHI_E_NOMEM;
        status = noshi_tl_set(media, "file", file);
        if (status == NOSHI_OK && spec->spoiler) status = noshi_tl_set_flag(media, "spoiler");
        if (status == NOSHI_OK && spec->view_once) status = noshi_tl_set_i32(arena, media, "ttl_seconds", NOSHI_VIEW_ONCE_TTL);
    } else {
        attribute = upload_attribute(arena, spec, &status);
        if (!attribute) return status == NOSHI_OK ? NOSHI_E_ARG : status;
        mime = spec->kind == NOSHI_UPLOAD_VOICE ? "audio/ogg" : (spec->kind == NOSHI_UPLOAD_FILE ? spec->mime : "video/mp4");
        media = noshi_tl_new_obj(arena, "inputMediaUploadedDocument");
        attributes = noshi_tl_new_vec(arena, (spec->animated || spec->music) ? 2 : 1);
        if (!media || !attributes) return NOSHI_E_NOMEM;
        status = noshi_tl_vec_set(attributes, 0, attribute);
        if (status == NOSHI_OK && spec->animated) {
            noshi_tl_value *animated = noshi_tl_new_obj(arena, "documentAttributeAnimated");
            status = animated ? noshi_tl_vec_set(attributes, 1, animated) : NOSHI_E_NOMEM;
        }
        if (status == NOSHI_OK && spec->music) {
            /* not a voice note: the server lists it as a song, which is what the saved music of a profile takes */
            noshi_tl_value *song = noshi_tl_new_obj(arena, "documentAttributeAudio");
            status = song ? noshi_tl_set_i32(arena, song, "duration", (spec->duration_ms + 500) / 1000) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK && spec->title[0]) status = noshi_tl_set_str(arena, song, "title", spec->title);
            if (status == NOSHI_OK && spec->performer[0]) status = noshi_tl_set_str(arena, song, "performer", spec->performer);
            if (status == NOSHI_OK) status = noshi_tl_vec_set(attributes, 1, song);
        }
        if (status == NOSHI_OK) status = noshi_tl_set(media, "file", file);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "mime_type", mime);
        if (status == NOSHI_OK) status = noshi_tl_set(media, "attributes", attributes);
        /* a sent video is not played in a circle, and a file is never turned into a picture on the other side */
        if (status == NOSHI_OK && spec->kind == NOSHI_UPLOAD_FILE && !spec->animated && !spec->music) status = noshi_tl_set_flag(media, "force_file");
        if (status == NOSHI_OK && spec->kind == NOSHI_UPLOAD_VIDEO && spec->spoiler) status = noshi_tl_set_flag(media, "spoiler");
        if (status == NOSHI_OK && spec->view_once) status = noshi_tl_set_i32(arena, media, "ttl_seconds", NOSHI_VIEW_ONCE_TTL);
    }
    if (status == NOSHI_OK) *out = media;
    return status;
}

static int upload_spec_valid(const noshi_upload_spec *spec) {
    /* a document sent as a file keeps its bytes for good, so a one-time file is a mistake of the caller */
    return spec->kind >= NOSHI_UPLOAD_VOICE && spec->kind <= NOSHI_UPLOAD_FILE && !(spec->animated && (spec->kind != NOSHI_UPLOAD_FILE || strcmp(spec->mime, "image/gif"))) &&
           !(spec->music && (spec->kind != NOSHI_UPLOAD_FILE || spec->animated || strncmp(spec->mime, "audio/", 6))) && spec->duration_ms >= 0 &&
           memchr(spec->title, 0, sizeof(spec->title)) != NULL && memchr(spec->performer, 0, sizeof(spec->performer)) != NULL &&
           !(spec->view_once && spec->kind == NOSHI_UPLOAD_FILE) && memchr(spec->name, 0, sizeof(spec->name)) != NULL &&
           memchr(spec->mime, 0, sizeof(spec->mime)) != NULL && memchr(spec->caption, 0, sizeof(spec->caption)) != NULL;
}

noshi_status noshi_send_upload_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value *file,
                                           const noshi_upload_spec *spec, int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *media;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !file || !spec || !out || random_id == 0 || !upload_spec_valid(spec)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    status = upload_media(arena, file, spec, &media);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.sendMedia");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_reply(arena, request, peer, spec->reply_to);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", spec->caption);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_album_upload_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value *file, const noshi_upload_spec *spec,
                                            noshi_tl_value **out) {
    noshi_tl_value *request, *input, *media;
    noshi_status status;
    if (out) *out = NULL;
    /* only a photo or a video goes into an album */
    if (!arena || !file || !spec || !out || !upload_spec_valid(spec) || (spec->kind != NOSHI_UPLOAD_PHOTO && spec->kind != NOSHI_UPLOAD_VIDEO)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    status = upload_media(arena, file, spec, &media);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.uploadMedia");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_album_media_parse(const noshi_tl_value *answer, noshi_album_media *out) {
    const noshi_tl_value *object;
    const uint8_t *reference;
    size_t length;
    int photo;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    photo = noshi_tl_is(answer, NOSHI_TL_ID_messageMediaPhoto);
    if (!photo && !noshi_tl_is(answer, NOSHI_TL_ID_messageMediaDocument)) return NOSHI_E_MALFORMED;
    object = noshi_tl_get(answer, photo ? "photo" : "document");
    if (!noshi_tl_is(object, photo ? NOSHI_TL_ID_photo : NOSHI_TL_ID_document) || noshi_tl_get_i64(object, "id", &out->id) != NOSHI_OK ||
        noshi_tl_get_i64(object, "access_hash", &out->access_hash) != NOSHI_OK ||
        noshi_tl_get_bytes(object, "file_reference", &reference, &length) != NOSHI_OK || length > NOSHI_ALBUM_REF_MAX || out->id == 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    memcpy(out->file_reference, reference, length);
    out->file_reference_len = length;
    out->is_photo = photo ? 1 : 0;
    return NOSHI_OK;
}

noshi_status noshi_album_send_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_album_media *items, const int64_t *random_ids,
                                          const char *const *captions, size_t count, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *list;
    noshi_status status;
    size_t i, j;
    if (out) *out = NULL;
    if (!arena || !peer || !items || !random_ids || !out || count < 2 || count > NOSHI_ALBUM_ITEMS_MAX) return NOSHI_E_ARG;
    for (i = 0; i < count; ++i) {
        if (random_ids[i] == 0 || items[i].id == 0) return NOSHI_E_ARG;
        for (j = 0; j < i; ++j) if (random_ids[j] == random_ids[i]) return NOSHI_E_ARG;
    }
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.sendMultiMedia");
    list = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!request || !list) return NOSHI_E_NOMEM;
    for (i = 0; i < count && status == NOSHI_OK; ++i) {
        noshi_tl_value *single = noshi_tl_new_obj(arena, "inputSingleMedia");
        noshi_tl_value *media = noshi_tl_new_obj(arena, items[i].is_photo ? "inputMediaPhoto" : "inputMediaDocument");
        noshi_tl_value *reference = noshi_tl_new_obj(arena, items[i].is_photo ? "inputPhoto" : "inputDocument");
        const char *caption = captions && captions[i] ? captions[i] : "";
        if (!single || !media || !reference) return NOSHI_E_NOMEM;
        if (strlen(caption) >= NOSHI_UPLOAD_CAPTION_MAX) return NOSHI_E_LIMIT;
        status = noshi_tl_set_i64(arena, reference, "id", items[i].id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, reference, "access_hash", items[i].access_hash);
        if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, reference, "file_reference", items[i].file_reference, items[i].file_reference_len);
        if (status == NOSHI_OK) status = noshi_tl_set(media, "id", reference);
        if (status == NOSHI_OK && items[i].spoiler) status = noshi_tl_set_flag(media, "spoiler");
        if (status == NOSHI_OK) status = noshi_tl_set(single, "media", media);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, single, "random_id", random_ids[i]);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, single, "message", caption);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(list, (uint32_t)i, single);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_topic_reply(arena, request, peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "multi_media", list);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_shared_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_shared_kind kind, int32_t offset_id, int32_t limit, noshi_tl_value **out) {
    static const char *const filters[] = {"inputMessagesFilterPhotoVideo", "inputMessagesFilterDocument", "inputMessagesFilterUrl", "inputMessagesFilterMusic", "inputMessagesFilterRoundVoice"};
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || (unsigned)kind > NOSHI_SHARED_VOICE || offset_id < 0) return NOSHI_E_ARG;
    status = chat_search_request(arena, peer, NULL, "", filters[kind], limit, out);
    /* a topic of a forum is a thread of the group, so without top_msg_id the tabs list the media of the whole group */
    if (status == NOSHI_OK && peer->topic_id > 1) status = noshi_tl_set_i32(arena, *out, "top_msg_id", peer->topic_id);
    if (status == NOSHI_OK && offset_id) status = noshi_tl_set_i32(arena, *out, "offset_id", offset_id);
    if (status != NOSHI_OK) *out = NULL;
    return status;
}

noshi_status noshi_own_messages_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit, noshi_tl_value **out) {
    noshi_tl_value *request = NULL, *sender;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !peer || offset_id < 0) return NOSHI_E_ARG;
    /* chat_search_request sends the filter of the kind named; the empty filter lets every message of the account through */
    status = chat_search_request(arena, peer, NULL, "", "inputMessagesFilterEmpty", limit, &request);
    sender = status == NOSHI_OK ? noshi_tl_new_obj(arena, "inputPeerSelf") : NULL;
    if (status == NOSHI_OK && !sender) status = NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set(request, "from_id", sender);
    if (status == NOSHI_OK && offset_id) status = noshi_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == NOSHI_OK && peer->topic_id > 1) status = noshi_tl_set_i32(arena, request, "top_msg_id", peer->topic_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_shared_oldest_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_shared_kind kind, int32_t limit, noshi_tl_value **out) {
    noshi_status status = noshi_shared_request(arena, peer, kind, 1, limit, out);
    /* offset_id 1 with a negative add_offset reads forward from the first message: the server returns the limit messages after id 1 */
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, *out, "add_offset", -limit);
    if (status != NOSHI_OK && out) *out = NULL;
    return status;
}

noshi_status noshi_send_geo_request(noshi_arena *arena, const noshi_peer_ref *peer, double latitude, double longitude,
                                        int64_t random_id, noshi_tl_value **out) {
    noshi_geo_point location;
    memset(&location, 0, sizeof(location));
    location.valid = 1;
    location.latitude = latitude;
    location.longitude = longitude;
    return noshi_send_location_request(arena, peer, &location, random_id, out);
}

noshi_status noshi_send_location_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_geo_point *location,
                                            int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *media, *point;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !location || random_id == 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status == NOSHI_OK) status = noshi_geo_input(arena, location, &point);
    if (status != NOSHI_OK) return status;
    media = noshi_tl_new_obj(arena, location->venue ? "inputMediaVenue" : "inputMediaGeoPoint");
    request = noshi_tl_new_obj(arena, "messages.sendMedia");
    if (!point || !media || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(media, "geo_point", point);
    if (location->venue) {
        if (!memchr(location->title, 0, sizeof(location->title)) || !memchr(location->address, 0, sizeof(location->address)) ||
            !memchr(location->provider, 0, sizeof(location->provider)) || !memchr(location->venue_id, 0, sizeof(location->venue_id)) ||
            !memchr(location->venue_type, 0, sizeof(location->venue_type))) return NOSHI_E_ARG;
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "title", location->title);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "address", location->address);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "provider", location->provider);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "venue_id", location->venue_id);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, media, "venue_type", location->venue_type);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_topic_reply(arena, request, peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", "");
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_custom_emoji_request(noshi_arena *arena, const int64_t *ids, size_t count, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!arena || !ids || !out || count < 1 || count > NOSHI_CUSTOM_EMOJI_MAX) return NOSHI_E_ARG;
    *out = NULL;
    request = noshi_tl_new_obj(arena, "messages.getCustomEmojiDocuments");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64_vec(arena, request, "document_id", ids, (uint32_t)count);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_document_picture_read(const noshi_tl_value *document, const char *alt, noshi_custom_emoji *out) {
    noshi_media_info info;
    int64_t id;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!alt) return NOSHI_E_ARG;
    if (!noshi_tl_is(document, NOSHI_TL_ID_document) || noshi_tl_get_i64(document, "id", &id) != NOSHI_OK || id == 0) return NOSHI_E_NOTFOUND;
    memset(&info, 0, sizeof(info));
    read_document(document, NULL, &info);
    out->id = id;
    snprintf(out->alt, sizeof(out->alt), "%s", alt);
    out->ref = info.ref;
    out->preview = info.preview;
    out->format = !strcmp(info.mime, "application/x-tgsticker") ? NOSHI_STICKER_ANIMATED
                  : !strcmp(info.mime, "video/webm") ? NOSHI_STICKER_VIDEO : NOSHI_STICKER_STATIC;
    return NOSHI_OK;
}

noshi_status noshi_custom_emoji_parse(const noshi_tl_value *answer, noshi_custom_emoji *rows, size_t cap, size_t *count) {
    uint32_t i, j;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || cap == 0) return NOSHI_E_ARG;
    if (!is_vec(answer)) return NOSHI_E_MALFORMED;
    for (i = 0; i < answer->u.vec.count && n < cap; ++i) {
        const noshi_tl_value *document = answer->u.vec.items[i];
        const noshi_tl_value *attributes;
        int64_t id;
        if (!noshi_tl_is(document, NOSHI_TL_ID_document) || noshi_tl_get_i64(document, "id", &id) != NOSHI_OK) continue;
        attributes = noshi_tl_get(document, "attributes");
        if (!is_vec(attributes)) continue;
        for (j = 0; j < attributes->u.vec.count; ++j) {
            const noshi_tl_value *a = attributes->u.vec.items[j];
            if (!noshi_tl_is(a, NOSHI_TL_ID_documentAttributeCustomEmoji)) continue;
            memset(&rows[n], 0, sizeof(rows[n]));
            rows[n].id = id;
            copy_text(rows[n].alt, sizeof(rows[n].alt), a, "alt", 0);
            if (!rows[n].alt[0]) break;
            {
                noshi_media_info info;
                memset(&info, 0, sizeof(info));
                read_document(document, NULL, &info);
                rows[n].ref = info.ref;
                rows[n].preview = info.preview;
                rows[n].format = !strcmp(info.mime, "application/x-tgsticker") ? NOSHI_STICKER_ANIMATED
                                 : !strcmp(info.mime, "video/webm") ? NOSHI_STICKER_VIDEO : NOSHI_STICKER_STATIC;
            }
            ++n;
            break;
        }
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_search_request(noshi_arena *arena, const char *query, noshi_search_kind kind, int32_t offset_rate,
                                      int32_t limit, noshi_tl_value **out) {
    static const char *const filters[] = {"inputMessagesFilterEmpty", "inputMessagesFilterEmpty", "inputMessagesFilterPhotoVideo",
                                          "inputMessagesFilterUrl", "inputMessagesFilterDocument", "inputMessagesFilterMusic",
                                          "inputMessagesFilterVoice"};
    noshi_tl_value *request, *filter, *empty;
    noshi_status status;
    if (!arena || !query || !out || kind < NOSHI_SEARCH_ALL || kind > NOSHI_SEARCH_VOICE || offset_rate < 0 || limit < 1 ||
        limit > NOSHI_MESSAGES_MAX || strlen(query) > 256) return NOSHI_E_ARG;
    *out = NULL;
    request = noshi_tl_new_obj(arena, "messages.searchGlobal");
    filter = noshi_tl_new_obj(arena, filters[kind]);
    empty = noshi_tl_new_obj(arena, "inputPeerEmpty");
    if (!request || !filter || !empty) return NOSHI_E_NOMEM;
    status = NOSHI_OK;
    if (kind == NOSHI_SEARCH_POSTS) status = noshi_tl_set_flag(request, "broadcasts_only");
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "q", query);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "filter", filter);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "min_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_rate", offset_rate);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "offset_peer", empty);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_upload_fit_name(const char *name, char *out, size_t capacity) {
    size_t length, extension = 0, base, keep;
    const char *dot;
    if (out && capacity) out[0] = 0;
    if (!name || !out || capacity < 2) return NOSHI_E_ARG;
    length = strlen(name);
    if (length < capacity) {
        memcpy(out, name, length + 1);
        return NOSHI_OK;
    }
    /* the extension is what follows the last dot, which is a name's own only when something comes before it, and an extension that takes half the room is part of the junk */
    dot = strrchr(name, '.');
    if (dot && dot != name) extension = length - (size_t)(dot - name);
    if (extension >= capacity / 2) extension = 0;
    base = length - extension;
    keep = capacity - 1 - extension;
    if (keep > base) keep = base;
    /* a byte that continues a character (10xxxxxx) cannot start the part that is dropped, so the cut steps back to where the character began */
    while (keep > 0 && ((unsigned char)name[keep] & 0xC0u) == 0x80u) --keep;
    if (keep == 0) return NOSHI_E_ARG;
    memcpy(out, name, keep);
    memcpy(out + keep, name + base, extension);
    out[keep + extension] = 0;
    return NOSHI_OK;
}

int noshi_read_history_answer_valid(const noshi_peer_ref *peer, const noshi_tl_value *answer) {
    if (!peer || !answer) return 0;
    if (peer->topic_id > 0 || (peer->kind == 3 && !peer->self))
        return noshi_tl_is(answer, NOSHI_TL_ID_boolTrue);
    return noshi_tl_is(answer, NOSHI_TL_ID_messages_affectedMessages);
}

noshi_status noshi_read_history_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t max_id,
                                           noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!arena || !peer || !out || max_id <= 0) return NOSHI_E_ARG;
    *out = NULL;
    if (peer->topic_id > 0) {
        status = noshi_input_peer(arena, peer, &input);
        if (status != NOSHI_OK) return status;
        request = noshi_tl_new_obj(arena, "messages.readDiscussion");
        if (!request) return NOSHI_E_NOMEM;
        status = noshi_tl_set(request, "peer", input);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", peer->topic_id);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "read_max_id", max_id);
        if (status == NOSHI_OK) *out = request;
        return status;
    }
    if (peer->kind == 3 && !peer->self) {
        noshi_tl_value *channel = noshi_tl_new_obj(arena, "inputChannel");
        request = noshi_tl_new_obj(arena, "channels.readHistory");
        if (!channel || !request) return NOSHI_E_NOMEM;
        if (peer->id <= 0 || peer->access_hash == 0) return NOSHI_E_ARG;
        status = noshi_tl_set_i64(arena, channel, "channel_id", peer->id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", peer->access_hash);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "channel", channel);
    } else {
        status = noshi_input_peer(arena, peer, &input);
        if (status != NOSHI_OK) return status;
        request = noshi_tl_new_obj(arena, "messages.readHistory");
        if (!request) return NOSHI_E_NOMEM;
        status = noshi_tl_set(request, "peer", input);
    }
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_id", max_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_media_location(noshi_arena *arena, const noshi_media_ref *ref, noshi_tl_value **out) {
    noshi_tl_value *location;
    noshi_status status;
    if (!arena || !ref || !out || ref->source == NOSHI_MEDIA_SOURCE_NONE) return NOSHI_E_ARG;
    *out = NULL;
    location = noshi_tl_new_obj(arena, ref->source == NOSHI_MEDIA_SOURCE_PHOTO ? "inputPhotoFileLocation" : "inputDocumentFileLocation");
    if (!location) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, location, "id", ref->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, location, "access_hash", ref->access_hash);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(arena, location, "file_reference", ref->file_ref, ref->ref_len);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, location, "thumb_size", ref->thumb);
    if (status == NOSHI_OK) *out = location;
    return status;
}

static noshi_status set_input(noshi_arena *arena, const noshi_sticker_set_row *set, noshi_tl_value **out) {
    noshi_tl_value *input = noshi_tl_new_obj(arena, "inputStickerSetID");
    noshi_status status;
    if (!input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, input, "id", set->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", set->access_hash);
    if (status == NOSHI_OK) *out = input;
    return status;
}

noshi_status noshi_sticker_set_thumb_location(noshi_arena *arena, const noshi_sticker_set_row *set, noshi_tl_value **out) {
    noshi_tl_value *location, *input;
    noshi_status status;
    if (!arena || !set || !out || set->id == 0 || set->thumb_dc <= 0) return NOSHI_E_ARG;
    *out = NULL;
    location = noshi_tl_new_obj(arena, "inputStickerSetThumb");
    if (!location) return NOSHI_E_NOMEM;
    status = set_input(arena, set, &input);
    if (status == NOSHI_OK) status = noshi_tl_set(location, "stickerset", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, location, "thumb_version", set->thumb_version);
    if (status == NOSHI_OK) *out = location;
    return status;
}

noshi_status noshi_sticker_set_request(noshi_arena *arena, const noshi_sticker_set_row *set, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!arena || !set || !out || set->id == 0) return NOSHI_E_ARG;
    *out = NULL;
    request = noshi_tl_new_obj(arena, "messages.getStickerSet");
    if (!request) return NOSHI_E_NOMEM;
    status = set_input(arena, set, &input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stickerset", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}
