#ifndef NOSHI_TIME_ZONE_H
#define NOSHI_TIME_ZONE_H

#include <stdint.h>

#define NOSHI_TIME_ZONE_AUTO INT32_MIN
#define NOSHI_TIME_ZONE_MIN (-12 * 60)
#define NOSHI_TIME_ZONE_MAX (14 * 60)
#define NOSHI_TIME_ZONE_STEP 15

/* a fixed UTC offset in minutes, or the device's time zone */
int noshi_time_zone_valid(int32_t minutes);

#endif
