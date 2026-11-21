#ifndef NOSHI_MEDIA_DRAG_H
#define NOSHI_MEDIA_DRAG_H

/* direction is selected before paging or dismissing, so one gesture cannot do both */
typedef enum noshi_media_drag_direction {
    NOSHI_MEDIA_DRAG_NONE,
    NOSHI_MEDIA_DRAG_HORIZONTAL,
    NOSHI_MEDIA_DRAG_VERTICAL
} noshi_media_drag_direction;

noshi_media_drag_direction noshi_media_drag_direction_for(double x, double y);
double noshi_media_drag_progress(double distance, double height);
int noshi_media_drag_should_close(double distance, double height, int ended);

#endif
