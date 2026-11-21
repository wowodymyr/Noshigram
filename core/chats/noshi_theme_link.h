#ifndef NOSHI_THEME_LINK_H
#define NOSHI_THEME_LINK_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_media.h"
#include "noshi_status.h"
#include "noshi_tl.h"

/* what a t.me/addtheme link names: account.getTheme on a slug, and the theme that comes back with its .tgios-theme file, or with colors only */

#define NOSHI_THEME_SLUG_MAX 128
#define NOSHI_THEME_TITLE_MAX 128

typedef struct noshi_theme_link_info {
    char title[NOSHI_THEME_TITLE_MAX];
    /* the theme file of the ios format; has_file is zero for a theme that only carries accent colors (settings), which this client cannot apply */
    int has_file;
    noshi_media_info file;
    /* the first of the theme's settings: the base look (dark for the night and tinted bases) and the accent as 0xRRGGBB; has_colors is zero for a theme that has none */
    int has_colors;
    int dark;
    uint32_t accent;
} noshi_theme_link_info;

/* account.getTheme in the "ios" format for a slug (letters, digits, dash and underscore, 1 to 128); anything else is NOSHI_E_ARG */
noshi_status noshi_theme_link_request(noshi_arena *arena, const char *slug, noshi_tl_value **out);

/* a Theme. a missing slug or title, or a document that is not a fetchable file, is NOSHI_E_MALFORMED, with out zeroed; a long title is cut at a
   character boundary */
noshi_status noshi_theme_link_parse(const noshi_tl_value *answer, noshi_theme_link_info *out);

#endif
