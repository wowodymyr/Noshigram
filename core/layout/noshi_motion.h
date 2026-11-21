#ifndef NOSHI_MOTION_H
#define NOSHI_MOTION_H

typedef enum noshi_motion_curve {
    NOSHI_MOTION_ENTER,
    NOSHI_MOTION_EXIT,
    NOSHI_MOTION_SPRING,
    NOSHI_MOTION_NAVIGATION,
    NOSHI_MOTION_LIST_MOVE,
    /* a card or a menu that goes away: it starts to leave at once and settles, where EXIT starts slowly and the card seems to hang for a moment */
    NOSHI_MOTION_DISMISS,
    /* the in-app browser sheet leaves on the same quint curve it arrives on, in 250 ms */
    NOSHI_MOTION_SHEET_DISMISS,
    /* the way every popup comes and goes, menus, dialogs and sheets, in the modern theme: the emphasized curves of material 3, a long deceleration in and a
       short sharp acceleration out */
    NOSHI_MOTION_POPUP_MODERN_ENTER,
    NOSHI_MOTION_POPUP_MODERN_EXIT,
    /* and in the classic theme: the ease out and the ease in of the system of the time, a little quicker and with no overshoot anywhere */
    NOSHI_MOTION_POPUP_CLASSIC_ENTER,
    NOSHI_MOTION_POPUP_CLASSIC_EXIT,
    /* the loose spring of the media editors: it overshoots by about a sixth and swings back twice, where SPRING overshoots by a tenth and settles in one swing */
    NOSHI_MOTION_WOBBLE
} noshi_motion_curve;

double noshi_motion_duration(noshi_motion_curve curve);
/* normalized time, with exact endpoints and bounded spring overshoot */
double noshi_motion_progress(noshi_motion_curve curve, double time);
/* callback frequency must not change playback speed or count time spent paused */
double noshi_motion_elapsed(double elapsed, double previous, double now, int paused);
/* one outgoing screen stays under the next one, at most four MiB of pixels */
double noshi_motion_snapshot_scale(double width, double height, double display_scale);
/* only a predominantly leftward gesture starts a reply; a reversed drag has no pull */
int noshi_motion_reply_swipe_begins(double velocity_x, double velocity_y);
double noshi_motion_reply_swipe_pull(double translation_x);

typedef struct noshi_motion_swipe {
    double progress;
    double duration;
    int completes;
} noshi_motion_swipe;

/* finish from the finger's bounded position, with a fast reversal cancelling the pop */
noshi_motion_swipe noshi_motion_back_swipe(double width, double translation, double velocity, int ended);

/* absolute media time keeps ambient wave motion continuous across view rebuilds */
double noshi_motion_alternating(double time, double seconds);

#endif
