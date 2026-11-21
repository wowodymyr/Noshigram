#ifndef NOSHI_GIFT_H
#define NOSHI_GIFT_H

#include <stdint.h>

#include "noshi_media.h"
#include "noshi_tl.h"

#define NOSHI_GIFT_TITLE_MAX 64
#define NOSHI_GIFT_SLUG_MAX 64
#define NOSHI_GIFT_ATTR_MAX 48

/* a StarGift of either kind: a catalog gift sold for stars, or a unique one that was upgraded and has a number,
   a model, a pattern and a backdrop */
typedef struct noshi_gift {
    int64_t id;
    int64_t catalog_id;         /* the id of the catalog gift a unique one came from, id otherwise */
    uint8_t unique;
    uint8_t limited;
    uint8_t sold_out;
    uint8_t birthday;
    uint8_t require_premium;
    uint8_t auction;            /* sold by bidding, which this client does not do */
    uint8_t has_backdrop;
    int64_t stars;              /* price of a catalog gift */
    int64_t convert_stars;      /* what the receiver gets when turning it into stars */
    int64_t upgrade_stars;      /* price of the upgrade to a unique gift, zero when it cannot be upgraded */
    int32_t remains;            /* a limited gift: left to sell; a unique one: the copies made so far */
    int32_t total;
    int32_t num;                /* the number of a unique gift */
    uint32_t backdrop_center;   /* 0xRRGGBB */
    uint32_t backdrop_edge;
    uint32_t backdrop_text;
    uint32_t backdrop_pattern;  /* the color the pattern symbols are drawn in */
    int32_t model_permille;     /* how rare each attribute is, in thousandths; zero when the server named a rank or nothing */
    int32_t pattern_permille;
    int32_t backdrop_permille;
    int64_t owner_id;           /* the user a unique gift belongs to, zero when unknown */
    noshi_media_info sticker; /* the animated picture; the model of a unique gift */
    noshi_media_info pattern_sticker; /* the symbol repeated over the backdrop of a unique gift */
    char title[NOSHI_GIFT_TITLE_MAX];
    char slug[NOSHI_GIFT_SLUG_MAX];
    char model[NOSHI_GIFT_ATTR_MAX];
    char pattern[NOSHI_GIFT_ATTR_MAX];
    char backdrop[NOSHI_GIFT_ATTR_MAX];
    char owner_name[NOSHI_GIFT_TITLE_MAX];
} noshi_gift;

/* reads a starGift or starGiftUnique; a gift without an id, a price, or (unique) a title is NOSHI_E_MALFORMED;
   its picture may be missing, then sticker has no source. out is always initialised */
noshi_status noshi_gift_read(const noshi_tl_value *gift, noshi_gift *out);

#endif
