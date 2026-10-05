/* Test-only concrete AVFrame plane storage and atomic ROI refusal. */
#include "roi.h"
#include <assert.h>
#include <stdlib.h>
static void put(uint8_t *p, uint16_t v) { p[0] = v & 255; p[1] = v >> 8; }
int main(void) {
    AVFrame *f = av_frame_alloc(); assert(f);
    f->format = AV_PIX_FMT_YUV420P10LE; f->width = 8; f->height = 6;
    assert(av_frame_get_buffer(f, 64) == 0);
    for (int i = 0; i < 3; ++i) for (int y = 0; y < (f->height >> !!i); ++y)
        for (int x = 0; x < (f->width >> !!i); ++x) put(f->data[i] + y*f->linesize[i] + 2*x, 100*i+10*y+x);
    f->crop_left = 2; f->crop_right = 2; f->crop_top = 2;
    SampleRect r = {0,0,2,2}, absolute;
    SampleStats s[3];
    assert(crop_measure(f, SAMPLE_CODEC_VISIBLE, r, &absolute, s) == 0);
    assert(absolute.x == 2 && absolute.y == 2 && absolute.width == 2 && absolute.height == 2);
    assert(s[0].samples == 4 && s[0].sum == 110 && s[0].minimum == 22 && s[0].maximum == 33);
    assert(s[1].samples == 1 && s[1].sum == 111 && s[2].sum == 211);
    printf("{\"luma_sha256\":\"%s\",\"u_sha256\":\"%s\",\"v_sha256\":\"%s\"}\n", s[0].sha256,s[1].sha256,s[2].sha256);
    assert(crop_measure(f, SAMPLE_CODED, (SampleRect){2,2,2,2}, &absolute, s) == 0 && s[0].sum == 110);
    SampleRect saved = {19,20,21,22}; absolute = saved;
    memset(s, 0x39, sizeof(s)); SampleStats original[3]; memcpy(original,s,sizeof(s));
    // A late chroma refusal cannot return a valid first-plane result.
    int stride = f->linesize[2]; f->linesize[2] = -stride;
    assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0);
    assert(memcmp(s,original,sizeof(s)) == 0 && memcmp(&absolute,&saved,sizeof(saved)) == 0);
    f->linesize[2] = stride;
    put(f->data[2],1024); assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); put(f->data[2],200);
    const SampleRect odd[] = {{1,0,2,2},{0,1,2,2},{0,0,3,2},{0,0,2,3}};
    for (unsigned i = 0; i < 4; ++i) assert(crop_measure(f,SAMPLE_CODED,odd[i],&absolute,s) < 0);
    assert(crop_measure(f,SAMPLE_CODED,(SampleRect){0,0,0,2},&absolute,s) < 0);
    assert(crop_measure(f,SAMPLE_CODED,(SampleRect){8,0,2,2},&absolute,s) < 0);
    assert(crop_measure(f,SAMPLE_CODEC_VISIBLE,(SampleRect){4,0,2,2},&absolute,s) < 0);
    assert(crop_measure(f,SAMPLE_CODED,(SampleRect){UINT32_MAX-1,0,2,2},&absolute,s) < 0);
    assert(crop_measure(f,SAMPLE_CODED,(SampleRect){2,0,UINT32_MAX-1,2},&absolute,s) < 0);
    assert(crop_measure(f,(SampleSpace)99,r,&absolute,s) < 0);
    assert(crop_measure(NULL,SAMPLE_CODED,r,&absolute,s) < 0);
    assert(crop_measure(f,SAMPLE_CODED,r,NULL,s) < 0);
    assert(crop_measure(f,SAMPLE_CODED,r,&absolute,NULL) < 0);
    f->crop_left = SIZE_MAX; assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->crop_left = 2;
    f->crop_left = 1; assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->crop_left = 2;
    f->crop_right = 6; assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->crop_right = 2;
    f->flags |= AV_FRAME_FLAG_INTERLACED; assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->flags = 0;
    f->format = AV_PIX_FMT_YUV420P; assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->format = AV_PIX_FMT_YUV420P10LE;
    f->width = -2; assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->width = 7;
    assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->width = 8192; f->height = 8192;
    assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->width = 8; f->height = 6;
    uint8_t *data = f->data[1]; f->data[1] = (uint8_t *)((uintptr_t)data + 1000000);
    assert(crop_measure(f,SAMPLE_CODED,r,&absolute,s) < 0); f->data[1] = data;
    av_frame_free(&f); return 0;
}
