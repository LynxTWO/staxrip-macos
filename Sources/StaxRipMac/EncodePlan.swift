import Foundation

struct EncodePlan: Sendable {
    let arguments: [String]
    let containerPreservation: ContainerPreservation
    let chapterPlan: ChapterPlan
    let outputGeometry: OutputGeometry
    let outputDisplayAspect: OutputDisplayAspect
    let externalSubtitles: [ExternalSubtitleExport]
    var externalSubtitle: ExternalSubtitleExport? { externalSubtitles.first }
    let captionTitles: [Data]
    let captionPlayback: CaptionPlaybackPlan?
    let videoCopy: VideoCopyContract?
    let expectedCodec: String
    let expectedAudio: String?
    let expectedWidth: Int?
    let expectedHeight: Int?
    let normalizedOrientation: Bool
    let audioCount: Int
    let subtitleCount: Int
    let duration: Double
    let summary: String

    static func make(job: QueueJob, probe: MediaProbe, encoders: Set<String>, staged: URL, hdr: HDR10Contract? = nil,
                     externalDocument: SubRipDocument? = nil, externalSnapshots: [ExternalCaptionSnapshot]? = nil) throws -> EncodePlan {
        try SessionDocument.validate(job.configuration)
        try DolbyConversionIntent.requireRunnable(job.configuration)
        guard !job.isDemo else { throw NativeExportError.invalid("Demo configurations cannot be encoded. Open a real source first.") }
        guard let video = probe.video else { throw NativeExportError.invalid("This queue currently requires a video source.") }
        let c = job.configuration
        let bufferLimits = try HEVCBufferPlanner.resolve(c, video: video)
        let copyingVideo = c.copiesVideo
        let videoCopy = copyingVideo ? try VideoCopyContract.make(probe: probe, configuration: c) : nil
        if !copyingVideo { try HDRInspection.requireQualifiedTranscode(video) }
        guard externalDocument == nil || externalSnapshots == nil else {
            throw SubRipDocument.failure("Conflicting caption snapshot inputs.")
        }
        let snapshots = externalSnapshots ?? externalDocument.map { document in
            c.externalSubtitle.map { [ExternalCaptionSnapshot(reference: $0, document: document)] } ?? []
        } ?? []
        guard snapshots.count == c.externalCaptions.count,
              snapshots.map(\.reference) == c.externalCaptions,
              externalDocument == nil || c.externalCaptions.count == 1 else {
            throw SubRipDocument.failure("A fresh matching snapshot is required for every ordered caption reference.")
        }
        for (index, snapshot) in snapshots.enumerated() {
            do { try snapshot.document.validateTimeline(probe: probe, configuration: c) }
            catch { throw ExternalCaptionSnapshot.failure(error, reference: snapshot.reference, index: index) }
        }
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
            throw NativeExportError.invalid("Precise trimming requires re-encoded audio (or no audio) and removed embedded subtitles. Embedded subtitle and copied-audio timing cannot yet be preserved by this trim workflow.")
        }
        let outputDuration = trimmed ? (picture.end > 0 ? picture.end : probe.seconds) - picture.start : probe.seconds
        let hardware = !copyingVideo && c.rate.backend == "Apple hardware"
        let encoder = copyingVideo ? "copy" : hardware ? (c.codec == "HEVC" ? "hevc_videotoolbox" : "h264_videotoolbox") : c.codec == "AV1" ? "libsvtav1" : c.codec == "HEVC" ? "libx265" : "libx264"
        guard copyingVideo || encoders.contains(encoder) else { throw NativeExportError.invalid("The installed FFmpeg does not provide \(encoder).") }
        // The copy contract above has already validated its own picture formats;
        // this restriction belongs to decoding and re-encoding the SDR picture.
        guard copyingVideo || preservingHDR || (!["smpte2084", "arib-std-b67"].contains(video.color_transfer ?? "") &&
              ["yuv420p", "nv12"].contains(video.pix_fmt ?? "")) else {
            throw NativeExportError.invalid("This first advanced pipeline supports 8-bit SDR 4:2:0 sources. HDR, high bit depth and other pixel formats need an explicit color workflow before encoding.")
        }
        let orientation = try SourceOrientation.read(video)
        try orientation.validateTranscode(video, configuration: c)
        let width = (orientation.swapsAxes ? video.height : video.width) ?? 0
        let height = (orientation.swapsAxes ? video.width : video.height) ?? 0
        guard width > picture.cropLeft + picture.cropRight, height > c.cropTop + c.cropBottom,
              (width - picture.cropLeft - picture.cropRight) % 2 == 0, (height - c.cropTop - c.cropBottom) % 2 == 0 else {
            throw NativeExportError.invalid("The crop leaves an invalid frame size for 4:2:0 encoding.")
        }
        let outputGeometry = try OutputGeometry(width: width - picture.cropLeft - picture.cropRight,
                                                height: height - c.cropTop - c.cropBottom, resolution: c.resolution)
        let outputDisplayAspect = try OutputDisplayAspect(width: outputGeometry.width, height: outputGeometry.height,
                                                         sampleAspectRatio: video.sample_aspect_ratio)
        let audio = try selectedStreams(probe, type: "audio", indices: c.audioTracks)
        let subtitles = try selectedStreams(probe, type: "subtitle", indices: c.subtitleTracks)
        let keepSubtitles = c.subtitleMode == "Keep embedded tracks"
        let external = try snapshots.enumerated().map { index, snapshot in
            do {
                return ExternalSubtitleExport(reference: snapshot.reference,
                    document: try snapshot.document.forExport(probe: probe, configuration: c),
                    ordinal: (keepSubtitles ? subtitles.count : 0) + index,
                    codec: c.container == "MP4" ? "mov_text" : "subrip")
            } catch { throw ExternalCaptionSnapshot.failure(error, reference: snapshot.reference, index: index) }
        }
        if c.container == "MP4" {
            if c.audio == "Opus" { throw NativeExportError.invalid("Choose MKV for Opus, or AAC for MP4.") }
            if c.audio == "Copy original", audio.contains(where: { !["aac", "mp3", "ac3", "eac3", "alac"].contains($0.codec_name ?? "") }) {
                throw NativeExportError.invalid("An audio codec cannot be copied into this MP4 workflow. Choose AAC or MKV.")
            }
            if c.subtitleMode == "Keep embedded tracks", subtitles.contains(where: { $0.codec_name != "mov_text" }) {
                throw NativeExportError.invalid("Use MKV to preserve these subtitle formats, or remove subtitles for MP4.")
            }
        }
        let captionPlayback = try CaptionPlaybackPlan.make(video: video, audio: c.audio == "No audio" ? [] : audio,
                                                           embedded: keepSubtitles ? subtitles : [], configuration: c)
        let captionTrim = trimmed && !external.isEmpty
        let chapterPlan = try ChapterPlan.make(probe: probe, configuration: c,
                                              metadataTimeline: captionTrim ? .output : .source)
        let containerPreservation = try ContainerPreservation.make(probe: probe, configuration: c, chapterPlan: chapterPlan)
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-progress", "pipe:1", "-stats_period", "0.25", "-protocol_whitelist", "file,pipe"] + orientation.inputArguments(stream: video.index) + ["-i", job.source]
        for index in external.indices {
            args += ["-f", "srt", "-protocol_whitelist", "file,pipe", "-i", staged.deletingLastPathComponent().appendingPathComponent(ExternalCaptionSnapshot.filename(index)).path]
        }
        if chapterPlan.metadata != nil {
            args += ["-f", "ffmetadata", "-protocol_whitelist", "file,pipe", "-i", staged.deletingLastPathComponent().appendingPathComponent("chapters.ffmetadata").path]
        }
        args += ["-map", "0:\(video.index)", "-c:v", encoder]
        let speed: String
        if copyingVideo { speed = "not applied" }
        else {
            args += ["-pix_fmt", preservingHDR ? "yuv420p10le" : "yuv420p", "-threads", "4"]
            if trimmed && !captionTrim {
                args += ["-ss", String(picture.start), "-t", String(outputDuration)]
            }
            if c.rate.mode == "Constant quality" { args += ["-crf", String(Int(c.quality))] }
            else { args += ["-b:v", "\(c.rate.bitrate)k"] }
            if hardware {
                speed = "hardware default"
                args += ["-allow_sw", "0"]
            } else if c.codec == "AV1" {
                speed = c.speed == "Thorough" ? "4" : c.speed == "Fast" ? "8" : "6"
                args += ["-svtav1-params", "lp=4"]
            } else { speed = c.speed == "Thorough" ? "slow" : c.speed == "Fast" ? "fast" : "medium" }
            if !hardware { args += ["-preset", speed] }
            if c.codec == "HEVC", !hardware {
                let parameters = (preservingHDR ? hdr!.x265Parameters : "pools=4:frame-threads=2") +
                    (bufferLimits.map { ":" + $0.parameters } ?? "")
                args += ["-x265-params", parameters]
            }
            if preservingHDR {
                args += ["-profile:v", "main10", "-fps_mode", "passthrough", "-color_range", "tv", "-color_primaries", "bt2020", "-color_trc", "smpte2084", "-colorspace", "bt2020nc", "-chroma_sample_location", "left"]
            }
            if !preservingHDR {
                // Nominal frame-rate time bases quantize genuine VFR intervals even
                // with passthrough. Preserve the filter timeline for video only.
                args += ["-fps_mode:v", "passthrough", "-enc_time_base:v", "filter"]
            }
        }
        let picturePlan = PicturePlan(c)
        var filters = orientation.filters + picturePlan.filters
        if captionTrim {
            let bounds = "start=\(picture.start)" + (picture.end > 0 ? ":end=\(picture.end)" : "")
            // Preserve source filter history, then subtract one common origin.
            // Global output seek would trim/offset the already-retimed captions again.
            filters += ["trim=\(bounds)", "setpts=PTS-\(picture.start)/TB"]
            if c.audio != "No audio", !audio.isEmpty {
                args += ["-af", "atrim=\(bounds),asetpts=PTS-\(picture.start)/TB"]
            }
        }
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
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
        if keepSubtitles, !subtitles.isEmpty {
            for stream in subtitles { args += ["-map", "0:\(stream.index)"] }
            args += ["-c:s", "copy"]
        }
        for (index, external) in external.enumerated() {
            args += ["-map", "\(index + 1):0", "-c:s:\(external.ordinal)", external.codec == "mov_text" ? "mov_text" : "copy",
                     "-metadata:s:s:\(external.ordinal)", "language=\(external.reference.language)",
                     "-/metadata:s:s:\(external.ordinal)", staged.deletingLastPathComponent().appendingPathComponent(ExternalCaptionTitles.filename(index)).path]
        }
        if external.isEmpty && (!keepSubtitles || subtitles.isEmpty) { args += ["-sn"] }
        if c.container == "MKV", keepSubtitles { args += ["-map", "0:t?", "-c:t", "copy"] }
        let chapterInput = chapterPlan.metadata != nil ? String(external.count + 1) : (chapterPlan.preservesSource ? "0" : "-1")
        args += ["-map_metadata", "0", "-map_chapters", chapterInput]
        if copyingVideo {
            for (flag, value) in [("-color_range:v", video.color_range), ("-color_primaries:v", video.color_primaries),
                                  ("-color_trc:v", video.color_transfer), ("-colorspace:v", video.color_space),
                                  ("-chroma_sample_location:v", video.chroma_location)] {
                if let value { args += [flag, value] }
            }
        }
        if c.container == "MP4" {
            let explicitColor = copyingVideo && [video.color_range, video.color_primaries, video.color_transfer, video.color_space].contains { $0 != nil }
            args += ["-movflags", explicitColor ? "+faststart+write_colr" : "+faststart"]
        }
        args += captionPlayback?.arguments ?? []
        args += [staged.path]
        let videoSummary = copyingVideo
            ? "Copy original \(video.codec_name ?? "") video · no video re-encoding · \(c.audio == "No audio" ? 0 : audio.count) audio tracks · packet verification required"
            : "\(encoder) · \(c.rateSummary) · preset \(speed) · \(orientation.summary) · first video · \(c.audio == "No audio" ? 0 : audio.count) audio tracks · \(preservingHDR ? "10-bit static HDR10; verification required" : "8-bit SDR")"
        let captionSummary: String = external.map { track in
            let trimDescription = captionTrim ? ", clipped to trim" : ""
            return " · additional SRT: \(track.document.cues.count) captured cues" + trimDescription + " (\(track.reference.language))" + (track.reference.playback.map { ", " + $0.label } ?? "")
        }.joined()
        let summary = videoSummary + (bufferLimits.map { " · " + $0.summary } ?? "") + TrackInspection.conversionSummary(audio, audio: c.audio) + captionSummary + " · " + outputDisplayAspect.summary + " · " + chapterPlan.summary
        let captionTitles = try ExternalCaptionTitles.make(external.map(\.reference))
        let expectedCodec = copyingVideo ? video.codec_name! : c.codec == "AV1" ? "av1" : c.codec == "HEVC" ? "hevc" : "h264"
        return EncodePlan(arguments: args, containerPreservation: containerPreservation, chapterPlan: chapterPlan, outputGeometry: outputGeometry, outputDisplayAspect: outputDisplayAspect, externalSubtitles: external, captionTitles: captionTitles, captionPlayback: captionPlayback, videoCopy: videoCopy, expectedCodec: expectedCodec, expectedAudio: expectedAudio,
                          expectedWidth: c.resolution == "Original" ? width - picture.cropLeft - picture.cropRight : nil,
                          expectedHeight: c.resolution == "Original" ? height - c.cropTop - c.cropBottom : nil,
                          normalizedOrientation: orientation.degrees != 0,
                          audioCount: c.audio == "No audio" ? 0 : audio.count, subtitleCount: (keepSubtitles ? subtitles.count : 0) + external.count,
                          duration: outputDuration, summary: summary)
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
