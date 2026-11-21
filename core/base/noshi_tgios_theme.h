#ifndef NOSHI_TGIOS_THEME_H
#define NOSHI_TGIOS_THEME_H

#include <stddef.h>
#include <stdint.h>

#define NOSHI_TGIOS_MAX_BYTES (256u * 1024u)
#define NOSHI_TGIOS_MAX_FIELDS 512u

typedef enum {
    NOSHI_TGIOS_OK = 0,
    NOSHI_TGIOS_EMPTY,
    NOSHI_TGIOS_TOO_LARGE,
    NOSHI_TGIOS_TOO_DEEP,
    NOSHI_TGIOS_MALFORMED,
    NOSHI_TGIOS_TOO_MANY_FIELDS,
    NOSHI_TGIOS_INVALID_COLOR,
    NOSHI_TGIOS_INVALID_WALLPAPER
} noshi_tgios_status;

typedef struct {
    char key[160];
    char value[256];
} noshi_tgios_field;

typedef struct {
    noshi_tgios_field fields[NOSHI_TGIOS_MAX_FIELDS];
    size_t count;
} noshi_tgios_theme;

noshi_tgios_status noshi_tgios_parse(const uint8_t *data, size_t length, noshi_tgios_theme *theme);
const char *noshi_tgios_get(const noshi_tgios_theme *theme, const char *key);
/* RRGGBB, AARRGGBB (the alpha first, as telegram ios writes it) or clear, with one # allowed before the digits */
int noshi_tgios_color(const char *value, uint32_t *argb);

typedef enum { NOSHI_TGIOS_WALLPAPER_BUILTIN, NOSHI_TGIOS_WALLPAPER_COLOR,
               NOSHI_TGIOS_WALLPAPER_GRADIENT, NOSHI_TGIOS_WALLPAPER_FILE } noshi_tgios_wallpaper_kind;
typedef struct {
    noshi_tgios_wallpaper_kind kind;
    uint32_t colors[4];
    unsigned color_count;
    int rotation;
    int intensity;
    int blur;
    int motion;
    char slug[160];
} noshi_tgios_wallpaper;

int noshi_tgios_parse_wallpaper(const char *value, noshi_tgios_wallpaper *wallpaper);
noshi_tgios_status noshi_tgios_validate_applicable(const noshi_tgios_theme *theme);
/* the same, and for NOSHI_TGIOS_INVALID_COLOR the first field whose value is not a color, so the message can name it; NULL for any other status */
noshi_tgios_status noshi_tgios_validate_applicable_at(const noshi_tgios_theme *theme, const noshi_tgios_field **bad_field);

#endif
