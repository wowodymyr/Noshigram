#include "noshi_media_drag.h"

#include <math.h>

noshi_media_drag_direction noshi_media_drag_direction_for(double x, double y) {
    if (!isfinite(x) || !isfinite(y) || (x == 0 && y == 0)) return NOSHI_MEDIA_DRAG_NONE;
    return fabs(y) > fabs(x) ? NOSHI_MEDIA_DRAG_VERTICAL : NOSHI_MEDIA_DRAG_HORIZONTAL;
}

double noshi_media_drag_progress(double distance, double height) {
    if (!isfinite(distance) || !isfinite(height) || height <= 0) return 0;
    double progress = fabs(distance) * 2 / height;
    return progress < 1 ? progress : 1;
}

int noshi_media_drag_should_close(double distance, double height, int ended) {
    return ended && isfinite(distance) && isfinite(height) && height > 0 && fabs(distance) > height / 6;
}
