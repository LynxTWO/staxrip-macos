import Foundation
import Darwin

struct ToolResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
    let truncated: Bool
}

// Owns one process. Pipes are drained concurrently and retained output is bounded.
final class ToolRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        let current = process
        lock.unlock()
        guard let current, current.isRunning else { return }
        current.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if current.isRunning { current.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            if current.isRunning { Darwin.kill(current.processIdentifier, SIGKILL) }
        }
    }

    func run(executable: URL, arguments: [String], stdoutLimit: Int = 4 * 1024 * 1024, onOutput: (@Sendable (Data) -> Void)? = nil) async throws -> ToolResult {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let task = Process()
                    task.executableURL = executable
                    task.arguments = arguments
                    task.standardInput = FileHandle.nullDevice
                    let output = Pipe(), errors = Pipe()
                    task.standardOutput = output; task.standardError = errors
                    lock.lock()
                    if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                    process = task
                    do { try task.run() } catch {
                        process = nil; lock.unlock(); continuation.resume(throwing: error); return
                    }
                    lock.unlock()
                    let stdout = BoundedBytes(limit: max(0, min(stdoutLimit, 4 * 1024 * 1024)))
                    let stderr = BoundedBytes(limit: 64 * 1024)
                    let group = DispatchGroup()
                    for (handle, buffer, callback) in [(output.fileHandleForReading, stdout, onOutput), (errors.fileHandleForReading, stderr, nil)] {
                        group.enter()
                        DispatchQueue.global().async {
                            defer { try? handle.close(); group.leave() }
                            while true {
                                // FileHandle creates autoreleased Foundation buffers. Drain per
                                // chunk so long PCM streams do not retain an entire movie.
                                let hadData = autoreleasepool {
                                    let data = handle.availableData
                                    guard !data.isEmpty else { return false }
                                    buffer.append(data)
                                    callback?(data)
                                    return true
                                }
                                if !hadData { break }
                            }
                        }
                    }
                    task.waitUntilExit()
                    group.wait()
                    lock.lock(); process = nil; let wasCancelled = cancelled; lock.unlock()
                    if wasCancelled { continuation.resume(throwing: CancellationError()); return }
                    continuation.resume(returning: ToolResult(status: task.terminationStatus, stdout: stdout.data, stderr: stderr.data, truncated: stdout.truncated))
                }
            }
        } onCancel: { self.cancel() }
    }
}

private final class BoundedBytes: @unchecked Sendable {
    let limit: Int
    var data = Data()
    var truncated = false
    init(limit: Int) { self.limit = limit }
    func append(_ chunk: Data) {
        guard limit > 0 else { truncated = truncated || !chunk.isEmpty; return }
        data.append(chunk)
        if data.count > limit { data.removeFirst(data.count - limit); truncated = true }
    }
}

struct FFmpegTools: Sendable {
    let ffmpeg: URL
    let ffprobe: URL
    static func discover() -> FFmpegTools? {
        for folder in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let root = URL(fileURLWithPath: folder)
            let encoder = root.appendingPathComponent("ffmpeg"), probe = root.appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: encoder.path), FileManager.default.isExecutableFile(atPath: probe.path) {
                return FFmpegTools(ffmpeg: encoder, ffprobe: probe)
            }
        }
        return nil
    }
}

struct MediaProbe: Decodable, Sendable {
    struct Stream: Decodable, Identifiable, Sendable {
        let index: Int
        let codec_type: String?
        let codec_name: String?
        let width: Int?
        let height: Int?
        let pix_fmt: String?
        let sample_rate: String?
        let bits_per_raw_sample: String?
        let channels: Int?
        let channel_layout: String?
        let color_transfer: String?
        let profile: String?
        let color_primaries: String?
        let color_space: String?
        let color_range: String?
        let avg_frame_rate: String?
        let r_frame_rate: String?
        let sample_aspect_ratio: String?
        let display_aspect_ratio: String?
        let field_order: String?
        let time_base: String?
        let start_pts: Int64?
        let chroma_location: String?
        let nb_frames: String?
        let tags: [String: String]?
        let disposition: [String: Int]?
        struct SideData: Codable, Sendable {
            let rotation: Int?
            let side_data_type: String?
            let red_x, red_y, green_x, green_y, blue_x, blue_y, white_point_x, white_point_y: String?
            let min_luminance, max_luminance: String?
            let max_content, max_average: Int64?
            func fields() throws -> [String: Any] {
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as! [String: Any]
            }
        }
        let side_data_list: [SideData]?
        var id: Int { index }
    }
    struct Format: Decodable, Sendable {
        let duration: String?
        let format_name: String?
        let size: String?
    }
    let streams: [Stream]
    let format: Format?
    var seconds: Double { Double(format?.duration ?? "") ?? 0 }
    var video: Stream? { streams.first { $0.codec_type == "video" && $0.disposition?["attached_pic"] != 1 } }

    static func read(_ source: URL, tools: FFmpegTools) async throws -> MediaProbe {
        let result = try await ToolRunner().run(executable: tools.ffprobe, arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format", "-of", "json", source.path])
        guard result.status == 0, !result.truncated else {
            throw NativeExportError.invalid("Media inspection failed. " + String(decoding: result.stderr, as: UTF8.self))
        }
        return try JSONDecoder().decode(MediaProbe.self, from: result.stdout)
    }
}
