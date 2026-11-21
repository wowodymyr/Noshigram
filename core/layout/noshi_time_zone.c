#include "noshi_time_zone.h"

int noshi_time_zone_valid(int32_t minutes) {
    return minutes == NOSHI_TIME_ZONE_AUTO ||
           (minutes >= NOSHI_TIME_ZONE_MIN && minutes <= NOSHI_TIME_ZONE_MAX && minutes % NOSHI_TIME_ZONE_STEP == 0);
}
