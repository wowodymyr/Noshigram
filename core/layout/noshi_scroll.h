#ifndef NOSHI_SCROLL_H
#define NOSHI_SCROLL_H

#include "noshi_status.h"

/* how fast a list moves, from the offsets its scroll events report */
typedef struct noshi_scroll_state {
    /* points per second, positive while the offset grows */
    double velocity;
    double last_offset;
    double last_time;
    int sampled;
} noshi_scroll_state;

/* the span of a list that is worth preparing: rows that reach into it get their pictures ready */
typedef struct noshi_scroll_window {
    double min_y;
    double max_y;
} noshi_scroll_window;

/* only user movement changes whether new messages follow the end; moving up stops following at once */
int noshi_scroll_tracks_bottom(int following, int user_scrolling, double previous_offset, double offset, double end);

/* keeps the same content beside the input after a height change, using the offset from before UIKit resized the list */
noshi_status noshi_scroll_resize(double offset, double old_height, double new_height,
                                     double min_offset, double max_offset, double *next);

/* a touch went down: the speed starts again from rest at this offset */
noshi_status noshi_scroll_begin(noshi_scroll_state *state, double offset, double now);

/* one scroll event; a gap longer than a quarter second or a jump of two screens is no movement the finger made */
noshi_status noshi_scroll_sample(noshi_scroll_state *state, double offset, double now, double viewport);

/* where the list will be in a moment: the end point the system promised when the finger lifted (has_target), else
   the speed carried for 0.18 s and held to three screens */
noshi_status noshi_scroll_predict(const noshi_scroll_state *state, double offset, double viewport, int has_target,
                                      double target, double min_offset, double max_offset, double *predicted);

/* whether the next page of older history should be asked for. distance is the room left between the top of the
   loaded rows and the highest point the view is about to show */
int noshi_scroll_wants_older(double distance, double velocity, double viewport);

/* the span to prepare around the view: more ahead of the direction of travel than behind it, and an even span when the
   list rests */
noshi_status noshi_scroll_prepare_window(double offset, double predicted, double velocity, double viewport,
                                             noshi_scroll_window *window);

/* one frame toward the current end, so new messages can move the target without restarting a scroll animation */
noshi_status noshi_scroll_follow(double offset, double target, double elapsed, double *next);

#endif
