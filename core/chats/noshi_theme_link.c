#include "noshi_theme_link.h"

#include <string.h>

#include "noshi_tl_ids.h"

static int slug_ok(const char *s) {
    size_t i;
    if (!s || !s[0]) return 0;
    for (i = 0; s[i]; ++i) {
        char c = s[i];
        int letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        int extra = (c >= '0' && c <= '9') || c == '-' || c == '_';
        if (i >= NOSHI_THEME_SLUG_MAX || !(letter || extra)) return 0;
    }
    return 1;
}

noshi_status noshi_theme_link_request(noshi_arena *arena, const char *slug, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !slug_ok(slug)) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.getTheme");
    input = noshi_tl_new_obj(arena, "inputThemeSlug");
    if (!request || !input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, input, "slug", slug);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "format", "ios");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "theme", input);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* a theme made in an app with accent colors carries them as a list of settings, one for each base look it was made for; the first one stands for the theme. A list that does
   not read is no colors, and the theme is then judged by its file alone */
static void read_colors(const noshi_tl_value *theme, noshi_theme_link_info *out) {
    const noshi_tl_value *list, *settings, *base;
    int32_t accent = 0;
    uint32_t id;
    if (noshi_tl_get_vec(theme, "settings", &list) != NOSHI_OK || list->u.vec.count == 0) return;
    settings = list->u.vec.items[0];
    if (!noshi_tl_is(settings, NOSHI_TL_ID_themeSettings) || noshi_tl_get_i32(settings, "accent_color", &accent) != NOSHI_OK) return;
    base = noshi_tl_get(settings, "base_theme");
    id = noshi_tl_id(base);
    if (id != NOSHI_TL_ID_baseThemeClassic && id != NOSHI_TL_ID_baseThemeDay && id != NOSHI_TL_ID_baseThemeNight && id != NOSHI_TL_ID_baseThemeTinted &&
        id != NOSHI_TL_ID_baseThemeArctic) return;
    out->has_colors = 1;
    out->dark = id == NOSHI_TL_ID_baseThemeNight || id == NOSHI_TL_ID_baseThemeTinted;
    out->accent = (uint32_t)accent & 0xFFFFFFu;
}

noshi_status noshi_theme_link_parse(const noshi_tl_value *answer, noshi_theme_link_info *out) {
    const uint8_t *data;
    size_t len;
    const noshi_tl_value *document;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_theme)) return NOSHI_E_MALFORMED;
    if (noshi_tl_get_bytes(answer, "title", &data, &len) != NOSHI_OK || (!data && len)) return NOSHI_E_MALFORMED;
    if (len >= sizeof(out->title)) {
        len = sizeof(out->title) - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    if (len) memcpy(out->title, data, len);
    out->title[len] = 0;
    read_colors(answer, out);
    if (!noshi_tl_has(answer, "document")) return NOSHI_OK;
    if (noshi_tl_get_obj(answer, "document", &document) != NOSHI_OK) goto malformed;
    noshi_document_read(document, &out->file);
    if (out->file.ref.source != NOSHI_MEDIA_SOURCE_DOCUMENT) goto malformed;
    out->has_file = 1;
    return NOSHI_OK;
malformed:
    memset(out, 0, sizeof(*out));
    return NOSHI_E_MALFORMED;
}
