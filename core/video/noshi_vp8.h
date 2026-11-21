#ifndef NOSHI_VP8_H
#define NOSHI_VP8_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

/* the VP8 encoder and decoder of the video call, over libvpx */

#define NOSHI_VP8_MAX_SIDE 1280
#define NOSHI_VP8_MIN_SIDE 16

typedef struct noshi_i420 {
    const uint8_t *plane[3];    /* y, u, v */
    int stride[3];
    int width;
    int height;
} noshi_i420;

typedef struct noshi_vp8_encoder noshi_vp8_encoder;
typedef struct noshi_vp8_decoder noshi_vp8_decoder;

/* real time, constant bit rate, one thread, no frame look-ahead */
noshi_status noshi_vp8_encoder_open(noshi_vp8_encoder **out, int width, int height, int fps, int bitrate_kbps);

/* encodes one picture of exactly the opened size and writes the frame to out (up to capacity bytes), its length to
   length and whether it is a key frame to key_frame. force_key asks for a key frame */
noshi_status noshi_vp8_encoder_encode(noshi_vp8_encoder *enc, const noshi_i420 *image, int64_t pts, int force_key,
                                          uint8_t *out, size_t capacity, size_t *length, int *key_frame);

/* the average rate the encoder aims for, changed while it runs */
noshi_status noshi_vp8_encoder_set_bitrate(noshi_vp8_encoder *enc, int bitrate_kbps);

void noshi_vp8_encoder_close(noshi_vp8_encoder *enc);

/* max_pixels caps the picture area the decoder accepts, so a key frame that announces a huge picture is refused
   before libvpx allocates for it */
noshi_status noshi_vp8_decoder_open(noshi_vp8_decoder **out, size_t max_pixels);

/* decodes one frame as the depacketizer hands it over; on NOSHI_OK the picture in image points into the decoder
   and is good until the next call; image is left empty when the frame made no picture */
noshi_status noshi_vp8_decoder_decode(noshi_vp8_decoder *dec, const uint8_t *data, size_t length, noshi_i420 *image);

void noshi_vp8_decoder_close(noshi_vp8_decoder *dec);

#endif
