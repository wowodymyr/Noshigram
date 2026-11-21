#include "noshi_time_zone.h"
#include "test_util.h"

int main(void) {
    CHECK(noshi_time_zone_valid(NOSHI_TIME_ZONE_AUTO));
    for (int32_t minutes = NOSHI_TIME_ZONE_MIN; minutes <= NOSHI_TIME_ZONE_MAX; ++minutes)
        CHECK_EQ_INT(noshi_time_zone_valid(minutes), minutes % NOSHI_TIME_ZONE_STEP == 0);
    CHECK(noshi_time_zone_valid(0));
    CHECK(noshi_time_zone_valid(180));
    CHECK(noshi_time_zone_valid(345));
    CHECK(noshi_time_zone_valid(-210));
    CHECK(!noshi_time_zone_valid(NOSHI_TIME_ZONE_MIN - NOSHI_TIME_ZONE_STEP));
    CHECK(!noshi_time_zone_valid(NOSHI_TIME_ZONE_MAX + NOSHI_TIME_ZONE_STEP));
    CHECK(!noshi_time_zone_valid(INT32_MIN + 1));
    CHECK(!noshi_time_zone_valid(INT32_MAX));
    return test_finish("test_time_zone");
}
