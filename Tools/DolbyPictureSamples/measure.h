/* Development-only raw code-value measurements. No luminance/color conversion. */
#ifndef STAXRIP_SAMPLE_MEASURE_H
#define STAXRIP_SAMPLE_MEASURE_H
#include <libavutil/sha.h>
#include <libavutil/mem.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <limits.h>
#define SAMPLE_PIXELS (UINT64_C(4096) * 4096)
#define SAMPLE_STORAGE (UINT64_C(64) * 1024 * 1024)
_Static_assert(SAMPLE_PIXELS <= UINT64_MAX / (UINT64_C(1023) * 1023), "Sample sum-square bound");
typedef struct {
    const uint8_t *data, *storage;
    size_t storage_bytes;
    int64_t stride;
    uint32_t width, height;
} SamplePlane;
typedef struct { uint32_t x, y, width, height; } SampleRect;
typedef struct {
    uint64_t samples, sum, sum_squares;
    uint16_t minimum, maximum;
    char sha256[65];
} SampleStats;
static int sample_measure(const SamplePlane *p, SampleRect r, SampleStats *out) {
    if (!p || !out || !p->data || !p->storage || !p->storage_bytes
        || p->storage_bytes > SAMPLE_STORAGE || !p->width || !p->height
        || p->width > 8192 || p->height > 8192
        || (uint64_t)p->width * p->height > SAMPLE_PIXELS
        || p->stride < (int64_t)p->width * 2 || p->stride > 128 * 1024
        || !r.width || !r.height || r.x >= p->width || r.y >= p->height
        || r.width > p->width - r.x || r.height > p->height - r.y) return -1;
    uintptr_t base = (uintptr_t)p->storage, data = (uintptr_t)p->data;
    uint64_t extent = (uint64_t)(p->height - 1) * (uint64_t)p->stride + (uint64_t)p->width * 2;
    if (p->storage_bytes > UINTPTR_MAX - base || data < base
        || data > base + p->storage_bytes || extent > base + p->storage_bytes - data) return -1;
    struct AVSHA *sha = av_sha_alloc();
    if (!sha || av_sha_init(sha, 256) < 0) { av_free(sha); return -1; }
    SampleStats result = { .minimum = 1023 };
    for (uint32_t y = 0; y < r.height; ++y) {
        const uint8_t *row = (const uint8_t *)(data + (uint64_t)(r.y + y) * (uint64_t)p->stride + (uint64_t)r.x * 2);
        for (uint32_t x = 0; x < r.width; ++x) {
            uint16_t v = (uint16_t)row[2*x] | (uint16_t)((uint16_t)row[2*x+1] << 8);
            if (v > 1023) { av_free(sha); return -1; }
            if (v < result.minimum) result.minimum = v;
            if (v > result.maximum) result.maximum = v;
            ++result.samples; result.sum += v; result.sum_squares += (uint64_t)v * v;
        }
        av_sha_update(sha, row, (size_t)r.width * 2);
    }
    uint8_t digest[32]; av_sha_final(sha, digest); av_free(sha);
    for (int i = 0; i < 32; ++i) snprintf(result.sha256 + 2*i, 3, "%02x", digest[i]);
    *out = result;
    return 0;
}
#endif
