#ifndef NOSHI_APP_CONFIG_H
#define NOSHI_APP_CONFIG_H

#include "noshi_tl.h"

/* a nonnegative integer from help.appConfig; absent keys return NOSHI_E_NOTFOUND */
noshi_status noshi_app_config_i32(const noshi_tl_value *answer, const char *key, int32_t *out);

#endif
