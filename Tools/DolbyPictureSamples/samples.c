/* Separate DEVELOPMENT sample probe. Derived from the local metadata reference.
 * Original reference and frozen candidate are unchanged; no pixel payload emitted. */
#include "measure.h"
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/sha.h>
#include <libavutil/pixdesc.h>
#include <libavutil/mem.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define COUNT_LIMIT 2000000
#define PACKET_LIMIT (16 * 1024 * 1024)
#define RPU_LIMIT 65536
#define PIXEL_LIMIT (4096 * 4096)
typedef struct { int64_t index, pos, size, pts; } Provenance;
typedef struct { int fd; int failed; } Input;
static int read_bytes(void *opaque, uint8_t *bytes, int count) {
    Input *input = opaque;
    ssize_t n;
    do { n = read(input->fd, bytes, (size_t)count); } while (n < 0 && errno == EINTR);
    if (n < 0) { input->failed = 1; return AVERROR(errno); }
    return n == 0 ? AVERROR_EOF : (int)n;
}
static int64_t seek_bytes(void *opaque, int64_t offset, int whence) {
    Input *input = opaque;
    if (whence == AVSEEK_SIZE) {
        struct stat s;
        return fstat(input->fd, &s) == 0 ? s.st_size : AVERROR(errno);
    }
    off_t result = lseek(input->fd, offset, whence & ~AVSEEK_FORCE);
    if (result < 0) { input->failed = 1; return AVERROR(errno); }
    return result;
}
static int digest(const uint8_t *data, size_t size, char out[65]) {
    struct AVSHA *sha = av_sha_alloc();
    uint8_t hash[32];
    if (!sha || av_sha_init(sha, 256) < 0) { av_free(sha); return -1; }
    av_sha_update(sha, data, size);
    av_sha_final(sha, hash);
    av_free(sha);
    for (int i = 0; i < 32; ++i) snprintf(out + 2*i, 3, "%02x", hash[i]);
    return 0;
}
static int emit_stats(const SampleStats *s, uint32_t width, uint32_t height) {
    return printf("{\"width\":%u,\"height\":%u,\"samples\":%"PRIu64
        ",\"minimum\":%u,\"maximum\":%u,\"sum\":%"PRIu64",\"sum_squares\":%"PRIu64
        ",\"sha256\":\"%s\"}", width, height, s->samples, s->minimum, s->maximum,
        s->sum, s->sum_squares, s->sha256) < 0 ? -1 : 0;
}
static int frame_samples(AVFrame *frame, SampleStats coded[3], SampleStats visible[3]) {
    if (frame->format != AV_PIX_FMT_YUV420P10LE || frame->flags & AV_FRAME_FLAG_INTERLACED
        || (frame->width & 1) || (frame->height & 1)
        || frame->crop_left >= (size_t)frame->width || frame->crop_right >= (size_t)frame->width - frame->crop_left
        || frame->crop_top >= (size_t)frame->height || frame->crop_bottom >= (size_t)frame->height - frame->crop_top
        || ((frame->crop_left | frame->crop_right | frame->crop_top | frame->crop_bottom) & 1)) return -1;
    for (int i = 0; i < 3; ++i) {
        AVBufferRef *buffer = av_frame_get_plane_buffer(frame, i);
        if (!buffer) return -1;
        unsigned shift = i ? 1 : 0;
        SamplePlane plane = { frame->data[i], buffer->data, buffer->size, frame->linesize[i],
            (uint32_t)frame->width >> shift, (uint32_t)frame->height >> shift };
        SampleRect full = { 0, 0, plane.width, plane.height };
        SampleRect crop = { (uint32_t)frame->crop_left >> shift, (uint32_t)frame->crop_top >> shift,
            (uint32_t)((size_t)frame->width - frame->crop_left - frame->crop_right) >> shift,
            (uint32_t)((size_t)frame->height - frame->crop_top - frame->crop_bottom) >> shift };
        if (sample_measure(&plane, full, &coded[i]) < 0 || sample_measure(&plane, crop, &visible[i]) < 0) return -1;
    }
    return 0;
}
static int emit_frame(AVFrame *frame, int64_t *count) {
    if (*count >= COUNT_LIMIT || !frame->opaque_ref || frame->opaque_ref->size != sizeof(Provenance)
        || frame->decode_error_flags || (frame->flags & AV_FRAME_FLAG_CORRUPT)
        || frame->pts == AV_NOPTS_VALUE || frame->width <= 0 || frame->height <= 0
        || (int64_t)frame->width * frame->height > PIXEL_LIMIT) return -1;
    Provenance p;
    memcpy(&p, frame->opaque_ref->data, sizeof(p));
    const AVFrameSideData *rpu = NULL;
    int rpus = 0;
    for (int i = 0; i < frame->nb_side_data; ++i) {
        if (frame->side_data[i]->type == AV_FRAME_DATA_DOVI_RPU_BUFFER) {
            rpu = frame->side_data[i]; ++rpus;
        }
    }
    const char *pixel = av_get_pix_fmt_name(frame->format);
    char hash[65];
    if (rpus != 1 || !rpu || !rpu->size || rpu->size > RPU_LIMIT || !pixel
        || digest(rpu->data, rpu->size, hash) < 0) return -1;
    SampleStats coded[3], visible[3];
    if (frame_samples(frame, coded, visible) < 0) return -1;
    if (printf("{\"kind\":\"sample-frame\",\"index\":%"PRId64",\"packet_index\":%"PRId64
        ",\"block_input_byte_offset\":%"PRId64",\"packet_size\":%"PRId64
        ",\"packet_pts\":%"PRId64",\"pts\":%"PRId64",\"best_effort_pts\":%"PRId64
        ",\"width\":%d,\"height\":%d,\"pixel_format\":\"%s\",\"interlaced\":%s"
        ",\"codec_crop_left_right_top_bottom\":[%zu,%zu,%zu,%zu]"
        ",\"sample_aspect_ratio\":[%d,%d],\"rpu_bytes\":%zu,\"rpu_sha256\":\"%s\",",
        (*count)++, p.index, p.pos, p.size, p.pts, frame->pts, frame->best_effort_timestamp,
        frame->width, frame->height, pixel, (frame->flags & AV_FRAME_FLAG_INTERLACED) ? "true" : "false",
        frame->crop_left, frame->crop_right, frame->crop_top, frame->crop_bottom,
        frame->sample_aspect_ratio.num, frame->sample_aspect_ratio.den, rpu->size, hash) < 0) return -1;
    if (printf("\"sample_encoding\":\"little-endian-uint16-code-values\",\"color_range\":%d,"
        "\"color_primaries\":%d,\"color_transfer\":%d,\"color_matrix\":%d,\"chroma_location\":%d,"
        "\"container_crop_applied\":false,\"edited_picture_semantics_verified\":false,\"coded\":[",
        frame->color_range, frame->color_primaries, frame->color_trc, frame->colorspace, frame->chroma_location) < 0) return -1;
    for (int i = 0; i < 3; ++i) {
        if (i && printf(",") < 0) return -1;
        if (emit_stats(&coded[i], (uint32_t)frame->width >> (i ? 1 : 0), (uint32_t)frame->height >> (i ? 1 : 0)) < 0) return -1;
    }
    if (printf("],\"codec_visible\":[") < 0) return -1;
    for (int i = 0; i < 3; ++i) {
        if (i && printf(",") < 0) return -1;
        if (emit_stats(&visible[i], (uint32_t)((size_t)frame->width - frame->crop_left - frame->crop_right) >> (i ? 1 : 0),
            (uint32_t)((size_t)frame->height - frame->crop_top - frame->crop_bottom) >> (i ? 1 : 0)) < 0) return -1;
    }
    return printf("]}\n") < 0 ? -1 : 0;
}
static int drain(AVCodecContext *codec, AVFrame *frame, int64_t *count) {
    for (;;) {
        int result = avcodec_receive_frame(codec, frame);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) return result;
        if (result < 0 || emit_frame(frame, count) < 0) return AVERROR_INVALIDDATA;
        av_frame_unref(frame);
    }
}
static int same_source(const struct stat *a, const struct stat *b) {
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino && a->st_size == b->st_size
        && a->st_uid == b->st_uid && a->st_mode == b->st_mode && a->st_nlink == b->st_nlink
        && a->st_mtimespec.tv_sec == b->st_mtimespec.tv_sec
        && a->st_mtimespec.tv_nsec == b->st_mtimespec.tv_nsec
        && a->st_ctimespec.tv_sec == b->st_ctimespec.tv_sec
        && a->st_ctimespec.tv_nsec == b->st_ctimespec.tv_nsec;
}
int main(int argc, char **argv) {
    int status = 1, selected = -1, threads = 4;
    int64_t packets = 0, frames = 0;
    struct stat before, after, path_after;
    Input input = { .fd = -1, .failed = 0 };
    AVFormatContext *format = NULL;
    AVIOContext *io = NULL;
    AVCodecContext *codec = NULL;
    AVPacket *packet = NULL;
    AVFrame *frame = NULL;
    av_log_set_level(AV_LOG_QUIET);
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) goto done;
    av_max_alloc(64 * 1024 * 1024); /* Per-allocation limit, not a total heap ceiling. */
    if (argc == 4 && strcmp(argv[2], "--threads") == 0
        && (strcmp(argv[3], "1") == 0 || strcmp(argv[3], "4") == 0)) threads = argv[3][0] - '0';
    else if (argc != 2) goto done;
    if ((input.fd = open(argv[1], O_RDONLY | O_NOFOLLOW | O_NONBLOCK)) < 0
        || fstat(input.fd, &before) < 0 || !S_ISREG(before.st_mode)
        || before.st_size <= 0 || before.st_size > (INT64_C(1) << 40)) goto done;
    uint8_t *buffer = av_malloc(32768);
    if (!buffer) goto done;
    io = avio_alloc_context(buffer, 32768, 0, &input, read_bytes, NULL, seek_bytes);
    if (!io) { av_free(buffer); goto done; }
    format = avformat_alloc_context();
    if (!format) goto done;
    format->pb = io;
    format->flags |= AVFMT_FLAG_CUSTOM_IO;
    format->max_streams = 256;
    format->probesize = 1024 * 1024;
    const AVInputFormat *demuxer = av_find_input_format("matroska");
    if (!demuxer || avformat_open_input(&format, NULL, demuxer, NULL) < 0) goto done;
    for (unsigned i = 0; i < format->nb_streams; ++i) {
        AVCodecParameters *par = format->streams[i]->codecpar;
        if (par->codec_type == AVMEDIA_TYPE_VIDEO) {
            if (selected >= 0 || par->codec_id != AV_CODEC_ID_HEVC) goto done;
            selected = (int)i;
        }
    }
    if (selected < 0) goto done;
    AVStream *stream = format->streams[selected];
    AVCodecParameters *par = stream->codecpar;
    if (par->extradata_size <= 0 || par->extradata_size > 1024 * 1024
        || stream->time_base.num <= 0 || stream->time_base.den <= 0) goto done;
    char hash[65];
    if (digest(par->extradata, (size_t)par->extradata_size, hash) < 0) goto done;
    const AVCodec *decoder = avcodec_find_decoder_by_name("hevc");
    if (!decoder || !(codec = avcodec_alloc_context3(decoder))
        || avcodec_parameters_to_context(codec, par) < 0) goto done;
    codec->flags |= AV_CODEC_FLAG_COPY_OPAQUE;
    codec->thread_count = threads;
    codec->apply_cropping = 0;
    codec->max_pixels = PIXEL_LIMIT;
    codec->err_recognition = AV_EF_EXPLODE | AV_EF_CAREFUL;
    codec->pkt_timebase = stream->time_base;
    if (avcodec_open2(codec, decoder, NULL) < 0) goto done;
    packet = av_packet_alloc(); frame = av_frame_alloc();
    if (!packet || !frame) goto done;
    if (printf("{\"kind\":\"sample-begin\",\"version\":1,\"input_bytes\":%"PRId64
        ",\"time_base\":[%d,%d],\"configuration_bytes\":%d,\"configuration_sha256\":\"%s\""
        ",\"decoder\":\"hevc\",\"codec_version\":%u,\"format_version\":%u,\"util_version\":%u"
        ",\"automatic_codec_crop\":false,\"threads\":%d}\n", (int64_t)before.st_size,
        stream->time_base.num, stream->time_base.den, par->extradata_size, hash,
        avcodec_version(), avformat_version(), avutil_version(), threads) < 0) goto done;
    for (;;) {
        int result = av_read_frame(format, packet);
        if (result == AVERROR_EOF) break;
        if (result < 0) goto done;
        if (packet->stream_index == selected) {
            if (packets >= COUNT_LIMIT || packet->size <= 0 || packet->size > PACKET_LIMIT
                || packet->pos < 0 || packet->pts == AV_NOPTS_VALUE
                || packet->flags & AV_PKT_FLAG_CORRUPT || digest(packet->data, (size_t)packet->size, hash) < 0) goto done;
            if (printf("{\"kind\":\"packet\",\"index\":%"PRId64",\"pts\":%"PRId64
                ",\"block_input_byte_offset\":%"PRId64",\"encoded_bytes\":%d,\"sha256\":\"%s\"}\n",
                packets, packet->pts, packet->pos, packet->size, hash) < 0) goto done;
            av_buffer_unref(&packet->opaque_ref);
            packet->opaque_ref = av_buffer_alloc(sizeof(Provenance));
            if (!packet->opaque_ref) goto done;
            Provenance p = { packets++, packet->pos, packet->size, packet->pts };
            memcpy(packet->opaque_ref->data, &p, sizeof(p));
            result = avcodec_send_packet(codec, packet);
            if (result == AVERROR(EAGAIN)) {
                if (drain(codec, frame, &frames) != AVERROR(EAGAIN)) goto done;
                result = avcodec_send_packet(codec, packet);
            }
            if (result < 0 || drain(codec, frame, &frames) != AVERROR(EAGAIN)) goto done;
        }
        av_packet_unref(packet);
    }
    if (input.failed || (format->pb && format->pb->error && format->pb->error != AVERROR_EOF)
        || !packets || avcodec_send_packet(codec, NULL) < 0
        || drain(codec, frame, &frames) != AVERROR_EOF || !frames) goto done;
    /* Release decoder/demuxer ownership while the custom source is still open. */
    av_frame_free(&frame); av_packet_free(&packet); avcodec_free_context(&codec);
    avformat_close_input(&format);
    if (io) { av_freep(&io->buffer); avio_context_free(&io); }
    if (fstat(input.fd, &after) < 0 || lstat(argv[1], &path_after) < 0
        || !same_source(&before, &after) || !same_source(&before, &path_after)) goto done;
    if (close(input.fd) != 0) { input.fd = -1; goto done; }
    input.fd = -1; /* Never retry a possibly reused descriptor number. */
    if (printf("{\"kind\":\"sample-complete\",\"version\":1,\"packets\":%"PRId64
        ",\"frames\":%"PRId64",\"decoder_drained\":true,\"descriptor_unchanged\":true}\n", packets, frames) < 0
        || fflush(stdout) != 0 || ferror(stdout)) goto done;
    status = 0;
done:
    av_frame_free(&frame); av_packet_free(&packet); avcodec_free_context(&codec);
    avformat_close_input(&format);
    if (io) { av_freep(&io->buffer); avio_context_free(&io); }
    if (input.fd >= 0) close(input.fd);
    if (status) fprintf(stderr, "Base sample probe did not complete.\n");
    return status;
}
