#ifndef NOSHI_NAME_COLOR_H
#define NOSHI_NAME_COLOR_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_tl.h"

/* the color of a name in group chats, from the Change Name Color screen (PeerColorActivity) */

#define NOSHI_NAME_COLOR_MAX 20
#define NOSHI_NAME_COLORS_MAX 64

typedef struct noshi_name_color_option {
    int32_t id;
    uint32_t light;             /* 0xRRGGBB of the name on a light theme */
    uint32_t dark;              /* and on a dark one; the light color when the server gives none */
    uint8_t hidden;             /* the server keeps the color out of the list unless it is in use */
} noshi_name_color_option;

/* help.getPeerColors; the hash zero asks for the whole list */
noshi_status noshi_name_colors_request(noshi_arena *arena, noshi_tl_value **out);
/* the options of the answer, in server order, at most cap; the ones that carry no color (the profile palettes, ids
   it has no colors for) are left out */
noshi_status noshi_name_colors_parse(const noshi_tl_value *answer, noshi_name_color_option *rows, size_t cap, size_t *count);

/* account.updateColor for the name (not the profile): id 0 to NOSHI_NAME_COLOR_MAX */
noshi_status noshi_name_color_set_request(noshi_arena *arena, int32_t id, noshi_tl_value **out);
/* the Bool it answers: NOSHI_OK for true, NOSHI_E_STATE for false, NOSHI_E_MALFORMED otherwise */
noshi_status noshi_name_color_set_parse(const noshi_tl_value *answer);

#endif
