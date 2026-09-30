import Foundation

struct EncodePlan: Sendable {
    let arguments: [String]
    let expectedCodec: String
    let expectedAudio: String?
    let expectedWidth: Int?
    let expectedHeight: Int?
    let audioCount: Int
    let subtitleCount: Int
    let duration: Double
    let summary: String

    static func make(job: QueueJob, probe: MediaProbe, encoders: Set<String>, staged: URL, hdr: HDR10Contract? = nil) throws -> EncodePlan {
        try SessionDocument.validate(job.configuration)
        guard !job.isDemo else { throw NativeExportError.invalid("Demo configurations cannot be encoded. Open a real source first.") }
        guard let video = probe.video else { throw NativeExportError.invalid("This queue currently requires a video source.") }
        let c = job.configuration
        let picture = c.picture
        let preservingHDR = c.colorMode == "Preserve static HDR10"
        if preservingHDR {
            try validateHDRSettings(c)
            guard let hdr, hdr.width == video.width, hdr.height == video.height else {
                throw HDR10Audit.failure("A complete source audit is required before planning this export.")
            }
            try HDR10Audit.validate(video)
        }
        let trimmed = picture.start > 0 || picture.end > 0
        guard !trimmed || (probe.seconds.isFinite && probe.seconds > picture.start && (picture.end == 0 || picture.end <= probe.seconds)) else {
            throw NativeExportError.invalid("The trim range must lie within the source duration.")
        }
        guard !trimmed || (c.audio != "Copy original" && c.subtitleMode == "Remove all subtitles") else {
            throw NativeExportError.invalid("Precise trimming requires re-encoded audio (or no audio) and removed subtitles. Embedded subtitle and copied-audio timing cannot yet be preserved by this trim workflow.")
        }
        let outputDuration = trimmed ? (picture.end > 0 ? picture.end : probe.seconds) - picture.start : probe.seconds
        let hardware = c.rate.backend == "Apple hardware"
        let encoder = hardware ? (c.codec == "HEVC" ? "hevc_videotoolbox" : "h264_videotoolbox") : c.codec == "AV1" ? "libsvtav1" : c.codec == "HEVC" ? "libx265" : "libx264"
        guard encoders.contains(encoder) else { throw NativeExportError.invalid("The installed FFmpeg does not provide \(encoder).") }
        guard preservingHDR || (!["smpte2084", "arib-std-b67"].contains(video.color_transfer ?? "") &&
              ["yuv420p", "nv12"].contains(video.pix_fmt ?? "")) else {
            throw NativeExportError.invalid("This first advanced pipeline supports 8-bit SDR 4:2:0 sources. HDR, high bit depth and other pixel formats need an explicit color workflow before encoding.")
        }
        let width = video.width ?? 0, height = video.height ?? 0
        guard width > picture.cropLeft + picture.cropRight, height > c.cropTop + c.cropBottom,
              (width - picture.cropLeft - picture.cropRight) % 2 == 0, (height - c.cropTop - c.cropBottom) % 2 == 0 else {
            throw NativeExportError.invalid("The crop leaves an invalid frame size for 4:2:0 encoding.")
        }
        guard (video.tags?["rotate"] ?? "0") == "0", !(video.side_data_list ?? []).contains(where: { ($0.rotation ?? 0) != 0 }) else {
            throw NativeExportError.invalid("Rotated sources need an explicit orientation step. Use Quick Export for this source for now.")
        }
        let audio = try selectedStreams(probe, type: "audio", indices: c.audioTracks)
        let subtitles = try selectedStreams(probe, type: "subtitle", indices: c.subtitleTracks)
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
                    "-map", "0:\(video.index)", "-c:v", encoder, "-pix_fmt", preservingHDR ? "yuv420p10le" : "yuv420p", "-threads", "4"]
        if trimmed {
            args += ["-ss", String(picture.start), "-t", String(outputDuration)]
        }
        if c.rate.mode == "Constant quality" { args += ["-crf", String(Int(c.quality))] }
        else { args += ["-b:v", "\(c.rate.bitrate)k"] }
        let speed: String
        if hardware {
            speed = "hardware default"
            args += ["-allow_sw", "0"]
        } else if c.codec == "AV1" {
            speed = c.speed == "Thorough" ? "4" : c.speed == "Fast" ? "8" : "6"
            args += ["-svtav1-params", "lp=4"]
        } else { speed = c.speed == "Thorough" ? "slow" : c.speed == "Fast" ? "fast" : "medium" }
        if !hardware { args += ["-preset", speed] }
        if c.codec == "HEVC", !hardware { args += ["-x265-params", preservingHDR ? hdr!.x265Parameters : "pools=4:frame-threads=2"] }
        if preservingHDR {
            args += ["-profile:v", "main10", "-fps_mode", "passthrough", "-color_range", "tv", "-color_primaries", "bt2020", "-color_trc", "smpte2084", "-colorspace", "bt2020nc", "-chroma_sample_location", "left"]
        }
        let picturePlan = PicturePlan(c)
        if !picturePlan.filters.isEmpty { args += ["-vf", picturePlan.expression] }
        var expectedAudio: String?
        if c.audio != "No audio", !audio.isEmpty {
            for stream in audio { args += ["-map", "0:\(stream.index)"] }
            if c.audio == "Copy original" { args += ["-c:a", "copy"] }
            else {
                let audioEncoder = c.audio == "Opus" ? "libopus" : "aac"
                guard encoders.contains(audioEncoder) else { throw NativeExportError.invalid("FFmpeg is missing \(audioEncoder).") }
                args += ["-c:a", audioEncoder, "-b:a", c.audioBitrate.replacingOccurrences(of: " kb/s", with: "k")]
                expectedAudio = c.audio == "Opus" ? "opus" : "aac"
            }
        } else { args += ["-an"] }
        let keepSubtitles = c.subtitleMode == "Keep embedded tracks"
        if keepSubtitles, !subtitles.isEmpty {
            for stream in subtitles { args += ["-map", "0:\(stream.index)"] }
            args += ["-c:s", "copy"]
        }
        else { args += ["-sn"] }
        if c.container == "MKV", keepSubtitles { args += ["-map", "0:t?", "-c:t", "copy"] }
        args += ["-map_metadata", "0", "-map_chapters", trimmed ? "-1" : "0"]
        if c.container == "MP4" { args += ["-movflags", "+faststart"] }
        args += [staged.path]
        return EncodePlan(arguments: args, expectedCodec: c.codec == "AV1" ? "av1" : c.codec == "HEVC" ? "hevc" : "h264", expectedAudio: expectedAudio,
                          expectedWidth: c.resolution == "Original" ? width - picture.cropLeft - picture.cropRight : nil,
                          expectedHeight: c.resolution == "Original" ? height - c.cropTop - c.cropBottom : nil,
                          audioCount: c.audio == "No audio" ? 0 : audio.count, subtitleCount: keepSubtitles ? subtitles.count : 0,
                          duration: outputDuration, summary: "\(encoder) · \(c.rateSummary) · preset \(speed) · first video · \(c.audio == "No audio" ? 0 : audio.count) audio tracks · \(preservingHDR ? "10-bit static HDR10; verification required" : "8-bit SDR")")
    }

    static func validateHDRSettings(_ c: EncodeConfiguration) throws {
        let p = c.picture
        guard c.codec == "HEVC", c.encoder == "x265", c.rate.backend == "Software", c.container == "MKV",
              c.resolution == "Original", c.cropTop == 0, c.cropBottom == 0, p.cropLeft == 0, p.cropRight == 0,
              p.start == 0, p.end == 0, p.deinterlace == "Off" else {
            throw HDR10Audit.failure("Choose software HEVC (x265), MKV, original dimensions, zero crop, no trim and deinterlacing Off. Settings are never changed automatically.")
        }
    }

    static func selectedStreams(_ probe: MediaProbe, type: String, indices: [Int]?) throws -> [MediaProbe.Stream] {
        let streams = probe.streams.filter { $0.codec_type == type }
        guard let indices else { return streams }
        return try indices.map { index in
            guard let stream = streams.first(where: { $0.index == index }) else {
                throw NativeExportError.invalid("Selected \(type) track #\(index) is missing or has changed type. Review the source tracks.")
            }
            return stream
        }
    }
}
