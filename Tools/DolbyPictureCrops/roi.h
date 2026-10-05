/* Explicit DEVELOPMENT luma ROI; no container/user-origin or edit authority. */
#ifndef STAXRIP_CROP_ROI_H
#define STAXRIP_CROP_ROI_H
#include "../DolbyPictureSamples/measure.h"
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
#include <string.h>
typedef enum { SAMPLE_CODED, SAMPLE_CODEC_VISIBLE } SampleSpace;
static int crop_resolve(const AVFrame *f, SampleSpace space, SampleRect requested, SampleRect *out) {
    if (!f || !out || f->format != AV_PIX_FMT_YUV420P10LE || f->flags & AV_FRAME_FLAG_INTERLACED
        || f->width <= 0 || f->height <= 0 || f->width > 8192 || f->height > 8192
        || (uint64_t)f->width * f->height > SAMPLE_PIXELS || ((f->width | f->height) & 1)
        || f->crop_left >= (size_t)f->width || f->crop_right >= (size_t)f->width - f->crop_left
        || f->crop_top >= (size_t)f->height || f->crop_bottom >= (size_t)f->height - f->crop_top
        || ((f->crop_left | f->crop_right | f->crop_top | f->crop_bottom) & 1)) return -1;
    uint32_t x = 0, y = 0, w = (uint32_t)f->width, h = (uint32_t)f->height;
    if (space == SAMPLE_CODEC_VISIBLE) {
        x = (uint32_t)f->crop_left; y = (uint32_t)f->crop_top;
        w -= x + (uint32_t)f->crop_right; h -= y + (uint32_t)f->crop_bottom;
    } else if (space != SAMPLE_CODED) return -1;
    if (!requested.width || !requested.height || requested.x >= w || requested.y >= h
        || requested.width > w - requested.x || requested.height > h - requested.y
        || ((requested.x | requested.y | requested.width | requested.height) & 1)) return -1;
    // Bounds above prove these additions fit the coded raster, without overflow.
    *out = (SampleRect){x + requested.x, y + requested.y, requested.width, requested.height};
    return 0;
}
static int crop_measure(AVFrame *f, SampleSpace space, SampleRect requested, SampleRect *absolute, SampleStats out[3]) {
    if (!absolute || !out) return -1;
    SampleRect resolved;
    if (crop_resolve(f, space, requested, &resolved) < 0) return -1;
    SampleStats result[3];
    for (int i = 0; i < 3; ++i) {
        AVBufferRef *buffer = av_frame_get_plane_buffer(f, i);
        if (!buffer) return -1;
        unsigned shift = i ? 1 : 0;
        SamplePlane plane = {f->data[i], buffer->data, buffer->size, f->linesize[i],
            (uint32_t)f->width >> shift, (uint32_t)f->height >> shift};
        SampleRect r = {resolved.x >> shift, resolved.y >> shift, resolved.width >> shift, resolved.height >> shift};
        if (sample_measure(&plane, r, &result[i]) < 0) return -1;
    }
    // No partial observation escapes if any later plane refuses.
    memcpy(out, result, sizeof(result)); *absolute = resolved;
    return 0;
}
#endif
