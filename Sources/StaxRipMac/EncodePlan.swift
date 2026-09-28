import Foundation

struct EncodePlan: Sendable {
    let arguments: [String]
    let expectedCodec: String
    let expectedAudio: String?
    let audioCount: Int
    let subtitleCount: Int
    let duration: Double
    let summary: String

    static func make(job: QueueJob, probe: MediaProbe, encoders: Set<String>, staged: URL) throws -> EncodePlan {
        try SessionDocument.validate(job.configuration)
        guard !job.isDemo else { throw NativeExportError.invalid("Demo configurations cannot be encoded. Open a real source first.") }
        guard let video = probe.video else { throw NativeExportError.invalid("This queue currently requires a video source.") }
        let c = job.configuration
        let encoder = c.codec == "AV1" ? "libsvtav1" : c.codec == "HEVC" ? "libx265" : "libx264"
        guard encoders.contains(encoder) else { throw NativeExportError.invalid("The installed FFmpeg does not provide \(encoder).") }
        guard !["smpte2084", "arib-std-b67"].contains(video.color_transfer ?? ""),
              ["yuv420p", "nv12"].contains(video.pix_fmt ?? "") else {
            throw NativeExportError.invalid("This first advanced pipeline supports 8-bit SDR 4:2:0 sources. HDR, high bit depth and other pixel formats need an explicit color workflow before encoding.")
        }
        let width = video.width ?? 0, height = video.height ?? 0
        guard width > 0, height > c.cropTop + c.cropBottom,
              width % 2 == 0, (height - c.cropTop - c.cropBottom) % 2 == 0 else {
            throw NativeExportError.invalid("The crop leaves an invalid frame size for 4:2:0 encoding.")
        }
        guard (video.tags?["rotate"] ?? "0") == "0", !(video.side_data_list ?? []).contains(where: { ($0.rotation ?? 0) != 0 }) else {
            throw NativeExportError.invalid("Rotated sources need an explicit orientation step. Use Quick Export for this source for now.")
        }
        let audio = probe.streams.filter { $0.codec_type == "audio" }
        let subtitles = probe.streams.filter { $0.codec_type == "subtitle" }
        if c.container == "MP4" {
            if c.audio == "Opus" { throw NativeExportError.invalid("Choose MKV for Opus, or AAC for MP4.") }
            if c.audio == "Copy original", audio.contains(where: { !["aac", "mp3", "ac3", "eac3", "alac"].contains($0.codec_name ?? "") }) {
                throw NativeExportError.invalid("An audio codec cannot be copied into this MP4 workflow. Choose AAC or MKV.")
            }
            if c.subtitleMode == "Keep embedded tracks", subtitles.contains(where: { $0.codec_name != "mov_text" }) {
                throw NativeExportError.invalid("Use MKV to preserve these subtitle formats, or remove subtitles for MP4.")
            }
        }
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-progress", "pipe:1", "-stats_period", "0.25", "-protocol_whitelist", "file,pipe", "-i", job.source,
                    "-map", "0:\(video.index)", "-c:v", encoder, "-crf", String(Int(c.quality)), "-pix_fmt", "yuv420p", "-threads", "4"]
        let speed: String
        if c.codec == "AV1" {
            speed = c.speed == "Thorough" ? "4" : c.speed == "Fast" ? "8" : "6"
            args += ["-svtav1-params", "lp=4"]
        } else { speed = c.speed == "Thorough" ? "slow" : c.speed == "Fast" ? "fast" : "medium" }
        args += ["-preset", speed]
        if c.codec == "HEVC" { args += ["-x265-params", "pools=4:frame-threads=2"] }
        var filters: [String] = []
        if c.cropTop + c.cropBottom > 0 { filters.append("crop=iw:ih-\(c.cropTop + c.cropBottom):0:\(c.cropTop)") }
        if c.resolution != "Original" {
            let size = c.resolution == "1920 × 1080" ? "1920:1080" : "1280:720"
            filters.append("scale=\(size):force_original_aspect_ratio=decrease:force_divisible_by=2")
        }
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
        var expectedAudio: String?
        if c.audio != "No audio", !audio.isEmpty {
            args += ["-map", "0:a"]
            if c.audio == "Copy original" { args += ["-c:a", "copy"] }
            else {
                let audioEncoder = c.audio == "Opus" ? "libopus" : "aac"
                guard encoders.contains(audioEncoder) else { throw NativeExportError.invalid("FFmpeg is missing \(audioEncoder).") }
                args += ["-c:a", audioEncoder, "-b:a", c.audioBitrate.replacingOccurrences(of: " kb/s", with: "k")]
                expectedAudio = c.audio == "Opus" ? "opus" : "aac"
            }
        } else { args += ["-an"] }
        let keepSubtitles = c.subtitleMode == "Keep embedded tracks"
        if keepSubtitles, !subtitles.isEmpty { args += ["-map", "0:s", "-c:s", "copy"] }
        else { args += ["-sn"] }
        if c.container == "MKV", keepSubtitles { args += ["-map", "0:t?", "-c:t", "copy"] }
        args += ["-map_metadata", "0", "-map_chapters", "0"]
        if c.container == "MP4" { args += ["-movflags", "+faststart"] }
        args += [staged.path]
        return EncodePlan(arguments: args, expectedCodec: c.codec == "AV1" ? "av1" : c.codec == "HEVC" ? "hevc" : "h264", expectedAudio: expectedAudio,
                          audioCount: c.audio == "No audio" ? 0 : audio.count, subtitleCount: keepSubtitles ? subtitles.count : 0,
                          duration: probe.seconds, summary: "\(encoder) · CRF \(Int(c.quality)) · preset \(speed) · first video · \(c.audio == "No audio" ? 0 : audio.count) audio tracks · 8-bit SDR")
    }
}
