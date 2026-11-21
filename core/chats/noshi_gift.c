#include "noshi_gift.h"

#include <string.h>

#include "noshi_tl_ids.h"

static void copy_string(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

/* the animation of a gift is a tgs document; a gift document that lacks the sticker attribute is still one */
static void read_picture(const noshi_tl_value *document, noshi_media_info *out) {
    noshi_document_read(document, out);
    if (out->ref.source != NOSHI_MEDIA_SOURCE_DOCUMENT) return;
    out->kind = NOSHI_PREVIEW_STICKER;
    if (!strcmp(out->mime, "application/x-tgsticker")) out->sticker = NOSHI_STICKER_ANIMATED;
    else if (!strcmp(out->mime, "video/webm")) out->sticker = NOSHI_STICKER_VIDEO;
    else out->sticker = NOSHI_STICKER_STATIC;
}

static uint32_t rgb(int32_t color) {
    return (uint32_t)color & 0xffffffu;
}

/* a starGiftAttributeRarity holds thousandths only in its plain form; the ranked forms (uncommon, rare, epic) carry none */
static int32_t read_permille(const noshi_tl_value *attribute) {
    int32_t permille = 0;
    const noshi_tl_value *rarity = noshi_tl_get(attribute, "rarity");
    if (!noshi_tl_is(rarity, NOSHI_TL_ID_starGiftAttributeRarity) || noshi_tl_get_i32(rarity, "permille", &permille) != NOSHI_OK ||
        permille < 0) return 0;
    return permille;
}

static void read_attributes(const noshi_tl_value *list, noshi_gift *out) {
    uint32_t i;
    int have_model = 0, have_pattern = 0;
    if (!list || list->kind != NOSHI_TL_V_VEC) return;
    for (i = 0; i < list->u.vec.count; ++i) {
        const noshi_tl_value *a = list->u.vec.items[i];
        if (noshi_tl_is(a, NOSHI_TL_ID_starGiftAttributeModel) && !have_model) {
            copy_string(out->model, sizeof(out->model), a, "name");
            read_picture(noshi_tl_get(a, "document"), &out->sticker);
            out->model_permille = read_permille(a);
            have_model = 1;
        } else if (noshi_tl_is(a, NOSHI_TL_ID_starGiftAttributePattern) && !have_pattern) {
            copy_string(out->pattern, sizeof(out->pattern), a, "name");
            read_picture(noshi_tl_get(a, "document"), &out->pattern_sticker);
            out->pattern_permille = read_permille(a);
            have_pattern = 1;
        } else if (noshi_tl_is(a, NOSHI_TL_ID_starGiftAttributeBackdrop) && !out->has_backdrop) {
            int32_t center, edge, text, pattern_color;
            copy_string(out->backdrop, sizeof(out->backdrop), a, "name");
            if (noshi_tl_get_i32(a, "center_color", &center) == NOSHI_OK && noshi_tl_get_i32(a, "edge_color", &edge) == NOSHI_OK &&
                noshi_tl_get_i32(a, "text_color", &text) == NOSHI_OK) {
                out->backdrop_center = rgb(center);
                out->backdrop_edge = rgb(edge);
                out->backdrop_text = rgb(text);
                if (noshi_tl_get_i32(a, "pattern_color", &pattern_color) == NOSHI_OK) out->backdrop_pattern = rgb(pattern_color);
                else out->backdrop_pattern = rgb(text);
                out->backdrop_permille = read_permille(a);
                out->has_backdrop = 1;
            }
        }
    }
}

static noshi_status read_unique(const noshi_tl_value *gift, noshi_gift *out) {
    if (noshi_tl_get_i64(gift, "id", &out->id) != NOSHI_OK || out->id <= 0) return NOSHI_E_MALFORMED;
    out->unique = 1;
    if (noshi_tl_get_i64(gift, "gift_id", &out->catalog_id) != NOSHI_OK) out->catalog_id = 0;
    copy_string(out->title, sizeof(out->title), gift, "title");
    copy_string(out->slug, sizeof(out->slug), gift, "slug");
    copy_string(out->owner_name, sizeof(out->owner_name), gift, "owner_name");
    if (!out->title[0] || noshi_tl_get_i32(gift, "num", &out->num) != NOSHI_OK || out->num <= 0) return NOSHI_E_MALFORMED;
    noshi_tl_get_i32(gift, "availability_issued", &out->remains);
    noshi_tl_get_i32(gift, "availability_total", &out->total);
    if (noshi_tl_has(gift, "owner_id")) {
        const noshi_tl_value *owner = noshi_tl_get(gift, "owner_id");
        if (noshi_tl_is(owner, NOSHI_TL_ID_peerUser)) noshi_tl_get_i64(owner, "user_id", &out->owner_id);
    }
    out->require_premium = noshi_tl_has(gift, "require_premium") ? 1 : 0;
    read_attributes(noshi_tl_get(gift, "attributes"), out);
    return NOSHI_OK;
}

noshi_status noshi_gift_read(const noshi_tl_value *gift, noshi_gift *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    out->sticker.kind = NOSHI_PREVIEW_STICKER;
    if (gift && noshi_tl_is(gift, NOSHI_TL_ID_starGiftUnique)) {
        noshi_status status = read_unique(gift, out);
        if (status != NOSHI_OK) memset(out, 0, sizeof(*out));
        return status;
    }
    if (!gift || !noshi_tl_is(gift, NOSHI_TL_ID_starGift) || noshi_tl_get_i64(gift, "id", &out->id) != NOSHI_OK ||
        out->id <= 0 || noshi_tl_get_i64(gift, "stars", &out->stars) != NOSHI_OK || out->stars < 0) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    out->catalog_id = out->id;
    out->limited = noshi_tl_has(gift, "limited") ? 1 : 0;
    out->sold_out = noshi_tl_has(gift, "sold_out") ? 1 : 0;
    out->birthday = noshi_tl_has(gift, "birthday") ? 1 : 0;
    out->require_premium = noshi_tl_has(gift, "require_premium") ? 1 : 0;
    out->auction = noshi_tl_has(gift, "auction") ? 1 : 0;
    noshi_tl_get_i64(gift, "convert_stars", &out->convert_stars);
    noshi_tl_get_i64(gift, "upgrade_stars", &out->upgrade_stars);
    if (out->limited) {
        noshi_tl_get_i32(gift, "availability_remains", &out->remains);
        noshi_tl_get_i32(gift, "availability_total", &out->total);
    }
    copy_string(out->title, sizeof(out->title), gift, "title");
    read_picture(noshi_tl_get(gift, "sticker"), &out->sticker);
    return NOSHI_OK;
}
