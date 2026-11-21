#ifndef NOSHI_ICON_ENVIRONMENT_H
#define NOSHI_ICON_ENVIRONMENT_H

#include <stddef.h>

/* the ios 7 uicache reads HOME instead of the app's sandbox directory */
int noshi_icon_cache_environment(char *const *source, char **out, size_t capacity);

#endif
