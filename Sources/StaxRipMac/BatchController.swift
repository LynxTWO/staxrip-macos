import SwiftUI
import AppKit

struct BatchStatus {
    var phase = "Pending"
    var progress = 0.0
    var detail = ""
    var destination: URL?
}

@MainActor
final class BatchController: ObservableObject {
    @Published var running = false
    @Published var toolDescription = "Checking FFmpeg…"
    @Published var statuses: [UUID: BatchStatus] = [:]
    @Published var encoders: Set<String> = []
    @Published var tools: FFmpegTools?
    @Published var inspecting = false
    @Published var inspection: MediaProbe?
    @Published var inspectionError: String?
    private var task: Task<Void, Never>?

    func discover() async {
        guard let found = FFmpegTools.discover() else { toolDescription = "FFmpeg not found · install with Homebrew"; return }
        do {
            let result = try await ToolRunner().run(executable: found.ffmpeg, arguments: ["-hide_banner", "-encoders"])
            guard result.status == 0, !result.truncated else { throw NativeExportError.invalid("Encoder discovery failed") }
            let text = String(decoding: result.stdout, as: UTF8.self)
            encoders = Set(text.split(separator: "\n").compactMap { line in
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count > 1, parts[0].count == 6, ["V", "A", "S"].contains(String(parts[0].prefix(1))) else { return nil }
                return String(parts[1])
            })
            let version = try await ToolRunner().run(executable: found.ffmpeg, arguments: ["-version"])
            toolDescription = String(decoding: version.stdout, as: UTF8.self).components(separatedBy: "\n").first ?? "FFmpeg ready"
            tools = found
        } catch { toolDescription = error.localizedDescription }
    }

    func inspect(_ source: URL) async {
        guard let tools else { inspectionError = "FFmpeg tools are unavailable."; return }
        inspecting = true; inspection = nil; inspectionError = nil
        defer { inspecting = false }
        do { inspection = try await MediaProbe.read(source, tools: tools) }
        catch { inspectionError = error.localizedDescription }
    }

    func start(_ jobs: [QueueJob]) {
        guard !running, let tools else { return }
        let selected = jobs.filter { statuses[$0.id]?.phase != "Completed" }
        guard !selected.isEmpty else { return }
        running = true
        for job in selected { statuses[job.id] = BatchStatus() }
        task = Task {
            defer { running = false; task = nil }
            for job in selected {
                if Task.isCancelled { break }
                statuses[job.id] = BatchStatus(phase: "Inspecting")
                do {
                    try await encode(job, tools: tools)
                } catch is CancellationError {
                    statuses[job.id] = BatchStatus(phase: "Cancelled", detail: "No output published")
                    break
                } catch {
                    statuses[job.id] = BatchStatus(phase: "Failed", detail: error.localizedDescription)
                    // Stop on the first failed job; unstarted jobs remain pending.
                    break
                }
            }
        }
    }

    func cancel() { task?.cancel() }
    func reset(_ id: UUID) { guard !running else { return }; statuses[id] = nil }

    private func encode(_ job: QueueJob, tools: FFmpegTools) async throws {
        guard !job.isDemo else { throw NativeExportError.invalid("Demo source: open a real video and add its configuration.") }
        let source = URL(fileURLWithPath: job.source), output = URL(fileURLWithPath: job.destination)
        guard source.path.hasPrefix("/"), output.path.hasPrefix("/"),
              source.resolvingSymlinksInPath() != output.resolvingSymlinksInPath(),
              !FileManager.default.fileExists(atPath: output.path) else {
            throw NativeExportError.invalid("The output exists or points to the source. Choose a new output name.")
        }
        let probe = try await MediaProbe.read(source, tools: tools)
        try Task.checkCancellation()
        let directory = output.deletingLastPathComponent().appendingPathComponent(".staxrip-batch-" + UUID().uuidString)
        let staged = directory.appendingPathComponent("encoded." + job.configuration.container.lowercased())
        let plan = try EncodePlan.make(job: job, probe: probe, encoders: encoders, staged: staged)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        statuses[job.id] = BatchStatus(phase: "Encoding", detail: plan.summary)
        let parser = ProgressParser(duration: plan.duration) { [weak self] fraction in
            Task { @MainActor in
                guard self?.statuses[job.id]?.phase == "Encoding" else { return }
                self?.statuses[job.id]?.progress = fraction
            }
        }
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: plan.arguments) { data in parser.accept(data) }
        try Task.checkCancellation()
        guard result.status == 0 else {
            throw NativeExportError.invalid("FFmpeg exited \(result.status).\n" + String(decoding: result.stderr, as: UTF8.self))
        }
        statuses[job.id]?.phase = "Verifying"
        let actual = try await MediaProbe.read(staged, tools: tools)
        guard actual.video?.codec_name == plan.expectedCodec,
              actual.streams.filter({ $0.codec_type == "audio" }).count == plan.audioCount,
              actual.streams.filter({ $0.codec_type == "subtitle" }).count == plan.subtitleCount,
              actual.seconds > 0,
              plan.duration <= 0 || abs(actual.seconds - plan.duration) < max(1, plan.duration * 0.01) else {
            throw NativeExportError.invalid("The output did not match the expected codec, tracks or duration.")
        }
        if let expected = plan.expectedAudio, actual.streams.filter({ $0.codec_type == "audio" }).contains(where: { $0.codec_name != expected }) {
            throw NativeExportError.invalid("Output audio did not match the planned codec.")
        }
        try Task.checkCancellation()
        try ExportPublication.publish(staged: staged, destination: output)
        statuses[job.id] = BatchStatus(phase: "Completed", progress: 1, detail: plan.summary, destination: output)
    }
}

private final class ProgressParser: @unchecked Sendable {
    private var buffer = Data()
    private let duration: Double
    private let update: @Sendable (Double) -> Void
    init(duration: Double, update: @escaping @Sendable (Double) -> Void) { self.duration = duration; self.update = update }
    func accept(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<end], as: UTF8.self)
            buffer.removeSubrange(...end)
            if line.hasPrefix("out_time_us="), let time = Double(line.dropFirst(12)), duration > 0 {
                update(min(0.99, max(0, time / 1_000_000 / duration)))
            }
        }
        if buffer.count > 8192 { buffer.removeAll() }
    }
}
