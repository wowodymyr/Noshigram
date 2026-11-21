#ifndef NOSHI_YUV_H
#define NOSHI_YUV_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_vp8.h"

/* the picture conversions of a video call, on plain buffers */

typedef struct noshi_yuv_target {
    uint8_t *plane[3];
    int stride[3];
    int width;
    int height;
} noshi_yuv_target;

typedef enum noshi_capture_orientation {
    NOSHI_CAPTURE_PORTRAIT,
    NOSHI_CAPTURE_PORTRAIT_UPSIDE_DOWN,
    NOSHI_CAPTURE_LANDSCAPE_LEFT,
    NOSHI_CAPTURE_LANDSCAPE_RIGHT
} noshi_capture_orientation;

/* output connections that rotate the buffers need no second turn */
noshi_status noshi_yuv_capture_rotation(noshi_capture_orientation orientation, int output_rotates, int *rotation);

/* the camera frame (NV12: a luma plane and one plane of interleaved U and V at half the size in each direction)
   rotated clockwise by rotation (0, 90, 180 or 270 degrees) */
noshi_status noshi_yuv_nv12_to_i420(const uint8_t *luma, int luma_stride, const uint8_t *chroma, int chroma_stride, int width, int height, int rotation,
                                        int mirror, const noshi_yuv_target *target);

/* an I420 picture as BGRA, scaled to out_width x out_height by nearest sampling (the pictures of the call are
   shown at about their own size); NOSHI_E_ARG for a picture or sizes that are not usable, NOSHI_E_LIMIT when
   stride is too small */
noshi_status noshi_yuv_i420_to_bgra(const noshi_i420 *src, uint8_t *out, int out_stride, int out_width, int out_height);

#endif
