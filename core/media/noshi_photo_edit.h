#ifndef NOSHI_PHOTO_EDIT_H
#define NOSHI_PHOTO_EDIT_H

#include <stddef.h>
#include <stdint.h>
#include "noshi_status.h"

#define NOSHI_PHOTO_SIDE_MAX 2560
#define NOSHI_PHOTO_TOOLS 10
#define NOSHI_PHOTO_BLUR_RADIUS_MAX 64

typedef enum {
    NOSHI_PHOTO_EXPOSURE,
    NOSHI_PHOTO_CONTRAST,
    NOSHI_PHOTO_SATURATION,
    NOSHI_PHOTO_WARMTH,
    NOSHI_PHOTO_FADE,
    NOSHI_PHOTO_SHADOWS,
    NOSHI_PHOTO_HIGHLIGHTS,
    NOSHI_PHOTO_VIGNETTE,
    NOSHI_PHOTO_GRAIN,
    NOSHI_PHOTO_SHARPEN
} noshi_photo_tool;

typedef struct { float values[NOSHI_PHOTO_TOOLS]; } noshi_photo_adjustments;
typedef struct { uint32_t x, y, width, height; } noshi_photo_crop;
typedef struct { uint32_t x, y, width, height; } noshi_photo_region;

/* normalized crop coordinates must describe a rectangle wholly inside the image */
noshi_status noshi_photo_crop_pixels(uint32_t width, uint32_t height, double x, double y,
                                       double crop_width, double crop_height, noshi_photo_crop *out);
/* opaque rgba pixels, row padding and alpha are preserved; invalid inputs leave pixels untouched */
noshi_status noshi_photo_adjust(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height,
                                  size_t stride, const noshi_photo_adjustments *adjustments);

/* the part of the image a blur of radius reads and writes for a stroke whose pixels span [left, right] x [top, bottom]: the box grown by three radii (the three passes of the
   blur), cut to the image. the stroke itself stays at least a radius inside it, so the edge of the region never shows through the clip of the stroke */
noshi_status noshi_photo_blur_region(uint32_t width, uint32_t height, double left, double top, double right, double bottom,
                                       uint32_t radius, noshi_photo_region *out);
/* three box passes over the region, which approach a gaussian of the same reach; pixels beyond the region count as its edge pixel. radius runs from 1 to
   NOSHI_PHOTO_BLUR_RADIUS_MAX, and the region lies wholly in the image. alpha is blurred with the colors, so opaque pixels stay opaque */
noshi_status noshi_photo_blur(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height, size_t stride,
                                const noshi_photo_region *region, uint32_t radius);
/* the radius for a strength from 0 to 1 on an image whose short side is short_side pixels, so the preview and the export of one edit look the same */
uint32_t noshi_photo_blur_radius(double strength, uint32_t short_side);

#endif
