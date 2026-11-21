#ifndef NOSHI_FORM_LAYOUT_H
#define NOSHI_FORM_LAYOUT_H

#include "noshi_welcome.h"

#define NOSHI_FORM_MAX_ROWS 3

typedef struct noshi_form_metrics {
    double width;
    double height;
    double top_inset;
    double bottom_inset;
    int wide;
    int rows;
} noshi_form_metrics;

typedef struct noshi_form_layout {
    noshi_rect back;
    noshi_rect next;
    noshi_rect art;
    noshi_rect title;
    noshi_rect message;
    noshi_rect card;
    noshi_rect rows[NOSHI_FORM_MAX_ROWS];
    noshi_rect error;
    noshi_rect action;
    double title_size;
    double message_size;
    double field_size;
    double note_size;
    double bar_size;
    double card_radius;
} noshi_form_layout;

/* the code, password and name screens: an animated sticker, a title, a message, a card of one to three fields, an
   error line and one action under it. height is what is left above the keyboard */
noshi_status noshi_form_layout_compute(const noshi_form_metrics *metrics, noshi_form_layout *out);

#endif
