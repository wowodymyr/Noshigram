#ifndef NOSHI_PHONE_LAYOUT_H
#define NOSHI_PHONE_LAYOUT_H

#include "noshi_welcome.h"

typedef struct noshi_phone_metrics {
    double width;
    double height;
    double top_inset;
    double bottom_inset;
    int wide;
} noshi_phone_metrics;

typedef struct noshi_phone_layout {
    noshi_rect back;
    noshi_rect next;
    noshi_rect art;
    noshi_rect title;
    noshi_rect message;
    noshi_rect card;
    noshi_rect country_row;
    noshi_rect code_cell;
    noshi_rect number_cell;
    double title_size;
    double message_size;
    double field_size;
    double bar_size;
    double card_radius;
    double flag_width;
    double flag_height;
} noshi_phone_layout;

/* height is what is left above the keyboard; the sticker, then the text, make room for the card first.
   fills out on every path; NOSHI_E_LIMIT means even the bare card does not fit */
noshi_status noshi_phone_layout_compute(const noshi_phone_metrics *metrics,
                                            noshi_phone_layout *out);

#endif
