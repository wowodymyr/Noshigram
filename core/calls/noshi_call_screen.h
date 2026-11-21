#ifndef NOSHI_CALL_SCREEN_H
#define NOSHI_CALL_SCREEN_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_welcome.h"

/* the geometry of the call screen and the colors behind it, kept out of UIKit so a table of screen sizes can check
   them */

#define NOSHI_CALL_SCREEN_MAX_BUTTONS 4
#define NOSHI_CALL_MESH_MAX_SIDE 64

typedef struct noshi_call_screen_metrics {
    double width;
    double height;
    double top_inset;
    double bottom_inset;
    /* an incoming call shows two answer buttons (decline, accept); any other phase shows button_count control
       buttons from 1 to NOSHI_CALL_SCREEN_MAX_BUTTONS, the last of them the one that ends the call */
    int incoming;
    int button_count;
    /* the picture of the other side fills the screen: the name and the status move to the top, out of the way of the picture */
    int video;
} noshi_call_screen_metrics;

typedef struct noshi_call_screen_layout {
    noshi_rect avatar;
    noshi_rect title;
    noshi_rect status;
    /* the pill with the four emoji of the key, and the card that explains them when the pill is tapped */
    noshi_rect emoji;
    noshi_rect card;
    /* the small view of the own camera, above the row of buttons at the right edge */
    noshi_rect preview;
    int button_count;
    noshi_rect buttons[NOSHI_CALL_SCREEN_MAX_BUTTONS];
    noshi_rect captions[NOSHI_CALL_SCREEN_MAX_BUTTONS];
    double title_size;
    double status_size;
    double caption_size;
} noshi_call_screen_layout;

/* fills out on every path; NOSHI_E_ARG for a size that is not finite and positive or a button count out of
   range; a screen too small for everything still gets a defined layout */
noshi_status noshi_call_screen_layout_compute(const noshi_call_screen_metrics *metrics,
                                                  noshi_call_screen_layout *out);

typedef enum noshi_call_mood {
    NOSHI_CALL_MOOD_CONNECTING,   /* the accent: ringing, key exchange, connecting */
    NOSHI_CALL_MOOD_TALKING,      /* the accent a little brighter: the audio is up */
    NOSHI_CALL_MOOD_WEAK,         /* the accent drained of color: the link broke while talking */
    NOSHI_CALL_MOOD_COUNT
} noshi_call_mood;

/* the four colors of a mood as 0xRRGGBB, top left, top right, bottom right, bottom left, all shades of accent (0xRRGGBB, the accent color of the theme).
   dark is the theme being dark: the shades are deeper there, so the white text and the buttons of the screen do not sit on a glaring field. E_ARG for an accent
   past 0xFFFFFF; out is zeroed on every failure */
noshi_status noshi_call_mood_colors(noshi_call_mood mood, uint32_t accent, int dark, uint32_t out[4]);

/* a width by height RGBA bitmap that blends the four corner colors bilinearly; every side from 2 to
   NOSHI_CALL_MESH_MAX_SIDE; capacity is the size of rgba in bytes and must hold width * height * 4 */
noshi_status noshi_call_mesh_fill(uint8_t *rgba, size_t capacity, int width, int height, const uint32_t colors[4]);

#endif
