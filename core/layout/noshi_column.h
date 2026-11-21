#ifndef NOSHI_COLUMN_H
#define NOSHI_COLUMN_H

#include "noshi_status.h"

typedef struct noshi_column {
    double x;
    double width;
} noshi_column;

/* the strip of a screen that content stands in */
noshi_status noshi_column_place(double width, double left_inset, double right_inset, double max_width, noshi_column *out);

#endif
