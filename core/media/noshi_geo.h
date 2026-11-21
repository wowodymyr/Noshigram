#ifndef NOSHI_GEO_H
#define NOSHI_GEO_H

#include <stddef.h>
#include <stdint.h>
#include "noshi_status.h"
#include "noshi_tl.h"

#define NOSHI_MAP_TILE_SIZE 256
#define NOSHI_MAP_MAX_TILES 64
#define NOSHI_MAP_MAX_ZOOM 19
#define NOSHI_MAP_MAX_LATITUDE 85.0511287798066
#define NOSHI_MAP_TILE_BYTES_MAX (256u * 1024u)

typedef struct noshi_geo_point {
    uint8_t valid;
    uint8_t venue;
    double latitude;
    double longitude;
    double accuracy;
    char title[128];
    char address[256];
    char provider[32];
    char venue_id[128];
    char venue_type[96];
} noshi_geo_point;

typedef struct noshi_map_tile {
    uint32_t x, y;
    uint8_t zoom;
    double left, top, side;
} noshi_map_tile;

int noshi_geo_valid(double latitude, double longitude);
/* check the PNG header before handing bytes to the image decoder */
int noshi_map_png_header(const uint8_t *bytes, size_t length);
/* normalized world coordinates, with mercator's polar limit and longitude wrapping */
noshi_status noshi_map_project(double latitude, double longitude, double *x, double *y);
noshi_status noshi_map_unproject(double x, double y, double *latitude, double *longitude);
noshi_status noshi_map_tiles(double latitude, double longitude, double zoom, double width, double height,
                                noshi_map_tile *tiles, size_t cap, size_t *count);
/* reads GeoPoint plus the optional venue fields of its containing media */
noshi_status noshi_geo_read(const noshi_tl_value *point, const noshi_tl_value *venue, noshi_geo_point *out);
noshi_status noshi_geo_input(noshi_arena *arena, const noshi_geo_point *point, noshi_tl_value **out);

#endif
