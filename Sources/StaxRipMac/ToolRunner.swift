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
    #if DEBUG
    @TaskLocal static var observeBoundary: (@Sendable (String) -> Void)?
    #endif
    // Control never waits for a child or a pipe callback. Its own queue keeps
    // launch, escalation and completion out of unrelated shared-work backlogs.
    private let controlQueue = DispatchQueue(label: "StaxRip.tool-control", qos: .userInitiated)
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
        controlQueue.asyncAfter(deadline: .now() + 2) {
            if current.isRunning { current.terminate() }
        }
        controlQueue.asyncAfter(deadline: .now() + 4) {
            if current.isRunning { Darwin.kill(current.processIdentifier, SIGKILL) }
        }
    }

    func run(executable: URL, arguments: [String], stdoutLimit: Int = 4 * 1024 * 1024, onOutput: (@Sendable (Data) -> Void)? = nil) async throws -> ToolResult {
        try await runWithStreams(executable: executable, arguments: arguments, stdoutLimit: stdoutLimit, onOutput: onOutput)
    }

    // A distinct entry point preserves existing trailing-closure stdout binding.
    func runWithStreams(executable: URL, arguments: [String], stdoutLimit: Int = 4 * 1024 * 1024, onErrorOutput: (@Sendable (Data) -> Void)? = nil, onOutput: (@Sendable (Data) -> Void)? = nil) async throws -> ToolResult {
        #if DEBUG
        let observe = Self.observeBoundary
        observe?("body entered")
        #endif
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                #if DEBUG
                observe?("submitting worker")
                #endif
                controlQueue.async { [self] in
                    #if DEBUG
                    observe?("worker entered")
                    #endif
                    let task = Process()
                    task.executableURL = executable
                    task.arguments = arguments
                    task.standardInput = FileHandle.nullDevice
                    let output = Pipe(), errors = Pipe()
                    task.standardOutput = output; task.standardError = errors
                    do {
                        for pipe in [output, errors] {
                            let fd = pipe.fileHandleForReading.fileDescriptor
                            let flags = fcntl(fd, F_GETFL)
                            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
                                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                            }
                        }
                    } catch { continuation.resume(throwing: error); return }
                    lock.lock()
                    if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                    guard process == nil else {
                        lock.unlock()
                        continuation.resume(throwing: NativeExportError.invalid("This tool runner already owns an active process.")); return
                    }
                    let group = DispatchGroup()
                    // Completion joins process exit and both fully drained, closed readers.
                    // No shared worker waits for a child or another dispatch block.
                    for _ in 0..<3 { group.enter() }
                    task.terminationHandler = { _ in group.leave() }
                    process = task
                    do { try task.run() } catch {
                        process = nil; lock.unlock(); task.terminationHandler = nil
                        for _ in 0..<3 { group.leave() }
                        continuation.resume(throwing: error); return
                    }
                    lock.unlock()
                    let stdout = BoundedBytes(limit: max(0, min(stdoutLimit, 4 * 1024 * 1024)))
                    let stderr = BoundedBytes(limit: 64 * 1024)
                    let readFailure = ToolReadFailure()
                    for (handle, buffer, callback) in [(output.fileHandleForReading, stdout, onOutput), (errors.fileHandleForReading, stderr, onErrorOutput)] {
                        let queue = DispatchQueue(label: "StaxRip.tool-pipe", qos: .userInitiated)
                        let source = DispatchSource.makeReadSource(fileDescriptor: handle.fileDescriptor, queue: queue)
                        source.setEventHandler { [self] in
                            autoreleasepool {
                                var bytes = [UInt8](repeating: 0, count: 64 * 1024)
                                let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                                if count > 0 {
                                    let data = Data(bytes.prefix(count))
                                    buffer.append(data)
                                    callback?(data)
                                } else if count == 0 {
                                    source.cancel()
                                } else if errno != EAGAIN && errno != EINTR {
                                    readFailure.record(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
                                    source.cancel(); cancel()
                                }
                            }
                        }
                        source.setCancelHandler {
                            try? handle.close()
                            source.setEventHandler(handler: nil)
                            source.setCancelHandler(handler: nil)
                            group.leave()
                        }
                        source.resume()
                    }
                    group.notify(queue: controlQueue) { [self] in
                        task.terminationHandler = nil
                        lock.lock(); process = nil; let wasCancelled = cancelled; lock.unlock()
                        if let error = readFailure.error { continuation.resume(throwing: error); return }
                        if wasCancelled { continuation.resume(throwing: CancellationError()); return }
                        continuation.resume(returning: ToolResult(status: task.terminationStatus, stdout: stdout.data, stderr: stderr.data, truncated: stdout.truncated))
                    }
                }
            }
        } onCancel: { self.cancel() }
    }
}

private final class ToolReadFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?
    var error: Error? { lock.withLock { stored } }
    func record(_ error: Error) { lock.withLock { if stored == nil { stored = error } } }
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
        let extradata_size: Int?
        let extradata_hash: String?
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
            let displaymatrix: String?
            let side_data_type: String?
            let red_x, red_y, green_x, green_y, blue_x, blue_y, white_point_x, white_point_y: String?
            let min_luminance, max_luminance: String?
            let max_content, max_average: Int64?
            let dv_version_major, dv_version_minor, dv_profile, dv_level: Int?
            let rpu_present_flag, el_present_flag, bl_present_flag, dv_bl_signal_compatibility_id: Int?
            let dv_md_compression: String?
            func fields() throws -> [String: Any] {
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as! [String: Any]
            }
        }
        let side_data_list: [SideData]?
        var id: Int { index }
    }
    struct Format: Decodable, Sendable {
        let duration: String?
        let start_time: String?
        let format_name: String?
        let size: String?
    }
    struct Chapter: Decodable, Sendable {
        let id: Int64?
        let time_base: String?
        let start: Int64?
        let start_time: String?
        let end: Int64?
        let end_time: String?
        let tags: [String: String]?
    }
    let streams: [Stream]
    let format: Format?
    let chapters: [Chapter]?
    init(streams: [Stream], format: Format?, chapters: [Chapter]? = nil) {
        self.streams = streams; self.format = format; self.chapters = chapters
    }
    var seconds: Double { Double(format?.duration ?? "") ?? 0 }
    var video: Stream? { streams.first { $0.codec_type == "video" && $0.disposition?["attached_pic"] != 1 } }

    static func read(_ source: URL, tools: FFmpegTools) async throws -> MediaProbe {
        let result = try await ToolRunner().run(executable: tools.ffprobe, arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format", "-show_chapters", "-show_data_hash", "sha256", "-of", "json", source.path])
        guard result.status == 0, !result.truncated else {
            throw NativeExportError.invalid("Media inspection failed. " + String(decoding: result.stderr, as: UTF8.self))
        }
        return try JSONDecoder().decode(MediaProbe.self, from: result.stdout)
    }
}
