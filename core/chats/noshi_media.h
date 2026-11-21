#ifndef NOSHI_MEDIA_H
#define NOSHI_MEDIA_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_dialogs.h"
#include "noshi_media_ref.h"
#include "noshi_tl.h"
#include "noshi_geo.h"

#define NOSHI_MEDIA_NAME_MAX 256
#define NOSHI_MEDIA_ALT_MAX 32
/* type and subtype can each hold 127 bytes, plus slash and terminator */
#define NOSHI_MEDIA_MIME_MAX 256
#define NOSHI_MEDIA_TAG_MAX 96
/* the packed waveform of a voice note; a longer one than this is dropped, since the picture is only decoration */
#define NOSHI_MEDIA_WAVEFORM_MAX 256

/* the ttl_seconds of media the server removes once the other side has looked at it */
#define NOSHI_VIEW_ONCE_TTL 0x7FFFFFFF

typedef enum noshi_sticker_format {
    NOSHI_STICKER_STATIC = 0,     /* webp */
    NOSHI_STICKER_ANIMATED,       /* gzip lottie, application/x-tgsticker */
    NOSHI_STICKER_VIDEO           /* webm, only its thumbnail can be shown on old systems */
} noshi_sticker_format;

typedef struct noshi_media_info {
    noshi_preview_kind kind;
    noshi_geo_point location;
    noshi_media_ref ref;          /* the file the bubble shows or the download saves */
    noshi_media_ref full_photo;
    int64_t full_photo_size;
    noshi_media_ref preview;      /* a thumbnail while the file loads, or the only picture of a video sticker */
    noshi_sticker_format sticker;
    int32_t width;
    int32_t height;
    int32_t duration;               /* seconds */
    int64_t size;                   /* bytes of ref */
    char name[NOSHI_MEDIA_NAME_MAX];
    char alt[NOSHI_MEDIA_ALT_MAX];    /* the emoji a sticker stands for */
    int64_t sticker_set_id;         /* the set a sticker belongs to, zero when the document names none by id */
    int64_t sticker_set_hash;
    int32_t dice_value;             /* a dice media: the result the server threw, zero while it is not known; slots count 1 to 64 */
    int64_t paid_stars;             /* the price in stars of paid media, locked or already bought; zero for ordinary media */
    uint8_t spoiler;                /* a photo or a video the sender asked to show blurred until it is tapped */
    int32_t date;                   /* unix seconds a photo was set, when the photo says so (a profile photo does), zero otherwise */
    int32_t ttl_seconds;            /* zero for ordinary media; NOSHI_VIEW_ONCE_TTL for media that is gone after one view, and any other positive value is a timed one */
    char mime[NOSHI_MEDIA_MIME_MAX];
    char title[NOSHI_MEDIA_TAG_MAX];      /* the song title of an audio file, empty when the tags have none */
    char performer[NOSHI_MEDIA_TAG_MAX];
    uint16_t waveform_len;                  /* bytes of waveform in use, zero when the note has none */
    uint8_t waveform[NOSHI_MEDIA_WAVEFORM_MAX];
} noshi_media_info;

/* the largest result a game emoji throws: slots show one of 64 combinations, the others up to 6 */
#define NOSHI_DICE_VALUE_MAX 64

/* 1 when text is exactly one game emoji the server throws as an animation (dice, darts, basketball, football, bowling, slots), with or without the variation selector U+FE0F
   after it; 0 for anything else, including text with a second character */
int noshi_dice_emoticon(const char *text);

/* playable videos and animations keep their picture area even when telegram supplies no thumbnail */
int noshi_media_uses_picture(noshi_preview_kind kind, int has_file, int has_preview, int has_local_preview);

/* animations play inside the message and stay out of the photo and video gallery */
int noshi_media_opens_viewer(noshi_preview_kind kind);

/* reads the media of a message and says what it is; a media whose file cannot be fetched (no usable reference, an
   unknown constructor) still names its kind with a source of none */
void noshi_media_classify(const noshi_tl_value *media, noshi_media_info *out);

/* the same with the photo size picked nearest to photo_target pixels on the long side; a screen that shows the
   photo full size asks for a larger one than a message bubble does */
void noshi_media_classify_sized(const noshi_tl_value *media, int32_t photo_target, noshi_media_info *out);

/* one Photo object read as a picture, the size picked as noshi_media_classify_sized does; a photo that cannot be
   fetched leaves a media of kind photo with no source. out is always initialised */
void noshi_photo_read(const noshi_tl_value *photo, int32_t target, noshi_media_info *out);

/* one Document read as a file: its dc, size, mime, name, thumbnail and what it is; a sticker attribute makes it a
   sticker; a document that is not a Document object leaves a media with no source. out is always initialised */
void noshi_document_read(const noshi_tl_value *document, noshi_media_info *out);

#endif
