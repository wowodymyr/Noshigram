#ifndef NOSHI_WELCOME_H
#define NOSHI_WELCOME_H

#include "noshi_status.h"

#define NOSHI_WELCOME_MAX_PAGES 16

typedef struct noshi_rect {
    double x;
    double y;
    double width;
    double height;
} noshi_rect;

typedef struct noshi_welcome_metrics {
    double width;
    double height;
    double top_inset;
    double bottom_inset;
    int wide;
    int pages;
} noshi_welcome_metrics;

typedef struct noshi_welcome_layout {
    noshi_rect art;
    noshi_rect title;
    noshi_rect message;
    noshi_rect dots;
    noshi_rect button;
    double title_size;
    double message_size;
    double button_size;
    double button_radius;
    double dot_diameter;
} noshi_welcome_layout;

/* fills out on every path; NOSHI_E_LIMIT means the stack overflows the stage at the smallest art */
noshi_status noshi_welcome_layout_compute(const noshi_welcome_metrics *metrics,
                                              noshi_welcome_layout *out);

double noshi_pager_progress(double offset, double page_width, int pages);
int noshi_pager_page(double offset, double page_width, int pages);
double noshi_pager_dot_weight(double progress, int dot);

#endif
