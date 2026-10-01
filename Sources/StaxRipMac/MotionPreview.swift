import Foundation
import AVFoundation
import Darwin

// Constructed only by create(), never from a session or caller-supplied path.
struct MotionWorkspace: Sendable {
    let directory: URL
    var movie: URL { directory.appendingPathComponent("comparison.mp4") }
    private init(directory: URL) { self.directory = directory }
    static func create() throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("staxrip-motion-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return Self(directory: root)
    }
    func remove() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "StaxRip.motion-cleanup", qos: .utility).async {
                do { try FileManager.default.removeItem(at: directory); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct MotionComparison: Sendable {
    let requested, end: Double
    let frames: [MotionFrame]
    let sourceIdentity: SourceFingerprint
    let operations: String
    let bytes: Int
}

final class MotionFileSink: @unchecked Sendable {
    // Mutated only by the stdout callback; examined after ToolRunner joins it.
    private let handle: FileHandle
    private let limit: Int
    private(set) var count = 0
    private(set) var failure: Error?
    init(url: URL, limit: Int = 64 * 1024 * 1024) throws {
        self.limit = max(0, min(limit, 64 * 1024 * 1024))
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    func accept(_ data: Data, runner: ToolRunner) {
        guard failure == nil else { return } // ToolRunner still drains/discards.
        do {
            guard data.count <= limit - count else { throw PicturePreview.failure("Motion preview exceeded the 64 MiB storage bound.") }
            try handle.write(contentsOf: data); count += data.count
        } catch { failure = error; runner.cancel() }
    }
    func close() throws { try handle.close() }
}

private final class MotionTrace: @unchecked Sendable {
    var metadata = MotionMetadata()
    var failure: Error?
    private var started = false
    let progress: @Sendable (String) -> Void
    init(progress: @escaping @Sendable (String) -> Void) { self.progress = progress }
    func accept(_ data: Data, runner: ToolRunner) {
        guard failure == nil else { return }
        do {
            try metadata.accept(data)
            if !started, !(metadata.frames["original"] ?? []).isEmpty {
                started = true; progress("Rendering motion frames…")
            }
        } catch { failure = error; runner.cancel() }
    }
}

enum MotionPreview {
    static func render(source: URL, configuration: EncodeConfiguration, time: Double, tools: FFmpegTools,
                       workspace: MotionWorkspace, timeout: Double = 120,
                       progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> MotionComparison {
        try await withThrowingTaskGroup(of: MotionComparison.self) { group in
            group.addTask {
                progress("Checking source identity…")
                let identity = try await ExportSourceFingerprint.read(source)
                let probe = try await MediaProbe.read(source, tools: tools)
                let video = try PicturePreview.validate(configuration, probe: probe, time: time)
                let end = min(time + 3, configuration.picture.end > 0 ? configuration.picture.end : probe.seconds)
                let orientation = try SourceOrientation.read(video), plan = PicturePlan(configuration)
                let runner = ToolRunner(), sink = try MotionFileSink(url: workspace.movie), trace = MotionTrace(progress: progress)
                let result: ToolResult
                progress("Rendering silent motion from the beginning of the source…")
                do {
                    result = try await runner.runWithStreams(executable: tools.ffmpeg, arguments: arguments(source: source, stream: video,
                        orientation: orientation, plan: plan, time: time, end: end), stdoutLimit: 0,
                        onErrorOutput: { trace.accept($0, runner: runner) }, onOutput: { sink.accept($0, runner: runner) })
                    try sink.close()
                } catch {
                    try? sink.close()
                    if let failure = sink.failure ?? trace.failure { throw failure }
                    throw error
                }
                if let failure = sink.failure ?? trace.failure { throw failure }
                guard result.status == 0 else { throw PicturePreview.failure("Motion rendering failed. Check the source and installed FFmpeg; no preview was accepted.") }
                try trace.metadata.finish()
                let frames = try trace.metadata.verify(time: time, end: end, range: video.color_range!)
                progress("Verifying the silent movie and decoded timestamps…")
                try await verifyOutput(workspace.movie, frames: frames, tools: tools)
                guard try await AVURLAsset(url: workspace.movie).load(.isPlayable) else { throw PicturePreview.failure("The native player cannot play this motion proxy.") }
                progress("Rechecking source identity…")
                guard try await ExportSourceFingerprint.read(source) == identity else { throw PicturePreview.failure("The source changed during motion rendering. Render again after it is stable.") }
                try Task.checkCancellation()
                return MotionComparison(requested: time, end: end, frames: frames, sourceIdentity: identity,
                    operations: (orientation.degrees == 0 ? "" : orientation.summary + " · ") + plan.summary, bytes: sink.count)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(max(0.001, min(120, timeout))))
                throw PicturePreview.failure("Motion rendering reached its time limit. Choose an earlier time after cancellation finishes.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func arguments(source: URL, stream: MediaProbe.Stream, orientation: SourceOrientation, plan: PicturePlan, time: Double, end: Double) -> [String] {
        let fit = "scale=w='max(2,trunc(min(640,360*dar)/2)*2)':h='max(2,trunc(min(360,640/dar)/2)*2)',setsar=1"
        func branch(_ name: String, filters: [String]) -> String {
            (filters + ["trim=start=\(time):end=\(end)", "showinfo@\(name)=checksum=0",
                        "colorspace=all=bt709:range=tv:format=yuv420p", fit, "showinfo@\(name)fit=checksum=0",
                        "pad=640:360:(ow-iw)/2:(oh-ih)/2", "setpts=PTS-STARTPTS"]).joined(separator: ",")
        }
        let graph = "[0:\(stream.index)]split[o][f];[o]" + branch("original", filters: orientation.filters) + "[op];[f]" +
            branch("filtered", filters: orientation.filters + plan.filters) + "[fp];[op][fp]hstack=inputs=2:shortest=1[out]"
        return ["-hide_banner", "-nostdin", "-nostats", "-xerror", "-loglevel", "info", "-threads", "2", "-protocol_whitelist", "file,pipe"] +
            orientation.inputArguments(stream: stream.index) + ["-i", source.path, "-filter_complex_threads", "1", "-filter_complex", graph,
            "-map", "[out]", "-an", "-sn", "-dn", "-map_metadata", "-1", "-map_chapters", "-1", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "16", "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709:fullrange=off", "-bf", "0", "-threads", "2", "-fps_mode:v", "passthrough", "-enc_time_base:v", "filter",
            "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv",
            "-movflags", "frag_keyframe+empty_moov+default_base_moof", "-f", "mp4", "pipe:1"]
    }

    struct OutputFrames: Decodable {
        struct Frame: Decodable { let pts: Int64? }
        let frames: [Frame]
    }
    static func verifyOutput(_ movie: URL, frames: [MotionFrame], tools: FFmpegTools) async throws {
        let probe = try await MediaProbe.read(movie, tools: tools)
        guard probe.seconds.isFinite, probe.seconds > 0, probe.seconds <= 3.25 else {
            throw PicturePreview.failure("Motion playback duration exceeds the three-second interval and 250 ms final-frame allowance.")
        }
        guard probe.streams.count == 1, let video = probe.video, video.codec_name == "h264", video.width == 1280, video.height == 360,
              video.sample_aspect_ratio == "1:1", video.pix_fmt == "yuv420p", video.color_range == "tv",
              video.color_primaries == "bt709", video.color_transfer == "bt709", video.color_space == "bt709" else {
            throw PicturePreview.failure("The rendered proxy has unsupported streams, shape or color.")
        }
        guard try SourceOrientation.read(video).degrees == 0 else { throw PicturePreview.failure("The motion proxy retained an unexpected display transform.") }
        let result = try await ToolRunner().run(executable: tools.ffprobe, arguments: ["-v", "error", "-threads", "2", "-protocol_whitelist", "file,pipe",
            "-select_streams", "v:0", "-show_frames", "-show_entries", "frame=pts:frame_side_data=", "-of", "json", movie.path])
        guard result.status == 0, !result.truncated else { throw PicturePreview.failure("Motion output timestamp verification failed or exceeded its bounds.") }
        let decoded = try JSONDecoder().decode(OutputFrames.self, from: result.stdout)
        try verifyTimes(decoded.frames.map(\.pts), base: HDRFraction(video.time_base), expected: frames)
    }
    static func verifyTimes(_ values: [Int64?], base: HDRFraction, expected: [MotionFrame]) throws {
        guard !expected.isEmpty, values.count == expected.count, values.count <= 600, base.numerator > 0 else { throw PicturePreview.failure("Motion output frame count differs from the source comparison.") }
        for (value, frame) in zip(values, expected) {
            guard let pts = value, (0...1_000_000_000_000).contains(pts),
                  Decimal(pts) * Decimal(base.numerator) * Decimal(frame.stamp.base.denominator) ==
                    Decimal(frame.stamp.pts - expected[0].stamp.pts) * Decimal(frame.stamp.base.numerator) * Decimal(base.denominator) else {
                throw PicturePreview.failure("Motion output timestamps differ from the compared source frames.")
            }
        }
    }
}
