/* Generated test-only plane buffers, including sanitizer refusal boundaries. */
#define main sample_probe_main
#include "samples.c"
#undef main
#include <assert.h>
#include <stdlib.h>

static void put(uint8_t *p, uint16_t value) { p[0] = value & 255; p[1] = value >> 8; }
static void report(const SampleStats *s) {
    printf("{\"samples\":%"PRIu64",\"sum\":%"PRIu64",\"sum_squares\":%"PRIu64
        ",\"minimum\":%u,\"maximum\":%u,\"sha256\":\"%s\"}\n",
        s->samples, s->sum, s->sum_squares, s->minimum, s->maximum, s->sha256);
}
int main(void) {
    uint8_t bytes[80]; memset(bytes, 0xa5, sizeof(bytes));
    const uint16_t values[12] = { 0, 1, 1023, 3, 4, 512, 6, 7, 8, 9, 10, 11 };
    for (unsigned y = 0; y < 3; ++y) for (unsigned x = 0; x < 4; ++x)
        put(bytes + 1 + y * 13 + x * 2, values[y * 4 + x]);
    SamplePlane p = { bytes + 1, bytes, sizeof(bytes), 13, 4, 3 };
    SampleRect r = { 1, 1, 2, 2 }, full = { 0, 0, 4, 3 };
    SampleStats result;
    assert(sample_measure(&p, r, &result) == 0); report(&result);
    assert(sample_measure(&p, full, &result) == 0); report(&result);
    SampleStats untouched; memset(&untouched, 0x39, sizeof(untouched));
    SampleStats original = untouched;
    put(bytes + 1 + 13 + 2, 1024);
    assert(sample_measure(&p, r, &untouched) < 0);
    assert(memcmp(&original, &untouched, sizeof(original)) == 0);
    put(bytes + 1 + 13 + 2, 512);
    SamplePlane q = p;
    q.stride = -13; assert(sample_measure(&q, r, &result) < 0);
    q.stride = 7; assert(sample_measure(&q, r, &result) < 0);
    q.stride = INT64_MAX; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.storage_bytes = 34; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.data = bytes + sizeof(bytes); assert(sample_measure(&q, r, &result) < 0);
    q = p; q.storage = bytes + 2; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.storage = (void *)(UINTPTR_MAX - 1); q.data = q.storage;
    assert(sample_measure(&q, r, &result) < 0);
    q = p; q.storage_bytes = SAMPLE_STORAGE + 1; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.width = UINT32_MAX; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.height = UINT32_MAX; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.width = 8192; q.height = 8192; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.data = NULL; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.storage = NULL; assert(sample_measure(&q, r, &result) < 0);
    q = p; q.width = 0; assert(sample_measure(&q, r, &result) < 0);
    assert(sample_measure(NULL, r, &result) < 0);
    assert(sample_measure(&p, r, NULL) < 0);
    assert(sample_measure(&p, (SampleRect){0,0,0,1}, &result) < 0);
    assert(sample_measure(&p, (SampleRect){0,0,1,0}, &result) < 0);
    assert(sample_measure(&p, (SampleRect){4,0,1,1}, &result) < 0);
    assert(sample_measure(&p, (SampleRect){0,3,1,1}, &result) < 0);
    assert(sample_measure(&p, (SampleRect){1,1,UINT32_MAX,1}, &result) < 0);
    assert(sample_measure(&p, (SampleRect){1,1,1,UINT32_MAX}, &result) < 0);
    /* Largest admitted pixel count at maximum code value; no square-sum overflow. */
    uint8_t *large = malloc(SAMPLE_PIXELS * 2); assert(large);
    for (uint64_t i = 0; i < SAMPLE_PIXELS; ++i) put(large + 2*i, 1023);
    q = (SamplePlane){ large, large, SAMPLE_PIXELS * 2, 8192, 4096, 4096 };
    assert(sample_measure(&q, (SampleRect){0,0,4096,4096}, &result) == 0);
    report(&result); free(large);
    AVFrame *frame = av_frame_alloc(); assert(frame);
    frame->format = AV_PIX_FMT_YUV420P10LE; frame->width = 6; frame->height = 4;
    assert(av_frame_get_buffer(frame, 64) == 0);
    for (int i = 0; i < 3; ++i) {
        int width = i ? 3 : 6, height = i ? 2 : 4;
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x)
            put(frame->data[i] + y * frame->linesize[i] + 2*x, (uint16_t)(100*i + 10*y + x));
    }
    SampleStats coded[3], visible[3];
    frame->crop_left = 2; frame->crop_bottom = 2;
    assert(frame_samples(frame, coded, visible) == 0);
    assert(coded[0].samples == 24 && visible[0].samples == 8 && visible[1].samples == 2);
    assert(visible[0].sum == 68 && visible[1].sum == 203 && visible[2].sum == 403);
    frame->crop_left = 1; assert(frame_samples(frame, coded, visible) < 0);
    frame->crop_left = 2; frame->crop_right = 4; assert(frame_samples(frame, coded, visible) < 0);
    frame->crop_right = SIZE_MAX; assert(frame_samples(frame, coded, visible) < 0);
    frame->crop_right = 0; frame->flags |= AV_FRAME_FLAG_INTERLACED;
    assert(frame_samples(frame, coded, visible) < 0);
    frame->flags = 0; frame->format = AV_PIX_FMT_YUV420P;
    assert(frame_samples(frame, coded, visible) < 0);
    frame->format = AV_PIX_FMT_YUV420P10LE; frame->width = 5;
    assert(frame_samples(frame, coded, visible) < 0);
    frame->width = 6; frame->linesize[1] = -frame->linesize[1];
    assert(frame_samples(frame, coded, visible) < 0);
    av_frame_free(&frame);
    return 0;
}
