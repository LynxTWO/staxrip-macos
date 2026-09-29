import SwiftUI
import AppKit

struct BatchStatus: Codable {
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
    @Published var recovery: BatchJournal?
    @Published var recoveryError: String?
    private let journalURL: URL?
    private var journalLease: BatchJournalLease?
    private var journalJobs: [QueueJob] = []
    private var task: Task<Void, Never>?

    init(journalURL: URL? = nil) {
        self.journalURL = journalURL
        if let journalURL, FileManager.default.fileExists(atPath: journalURL.path) {
            do { recovery = try BatchJournal.read(from: journalURL) }
            catch { recoveryError = "Could not read queue recovery: " + error.localizedDescription }
        }
    }

    func restoreQueue() -> [QueueJob]? {
        guard !running, let recovery else { return nil }
        journalJobs = recovery.jobs
        statuses = recovery.restoredStatuses()
        self.recovery = nil
        return journalJobs
    }

    private func checkpoint() throws {
        guard let journalURL else { return }
        let ids = Set(journalJobs.map(\.id))
        try BatchJournal(jobs: journalJobs, statuses: statuses.filter { ids.contains($0.key) }).write(to: journalURL)
    }

    private func checkpointAfterOutcome() {
        do { try checkpoint() }
        catch { recoveryError = "Queue state could not be saved: " + error.localizedDescription }
    }

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
        journalJobs = jobs
        for job in selected { statuses[job.id] = BatchStatus() }
        do {
            if let journalURL { journalLease = try BatchJournalLease(journalURL: journalURL) }
            try checkpoint()
        }
        catch { journalLease = nil; recoveryError = "Batch did not start because recovery state could not be saved: " + error.localizedDescription; return }
        recovery = nil; recoveryError = nil
        running = true
        task = Task {
            defer { running = false; task = nil; journalLease = nil }
            for job in selected {
                if Task.isCancelled { break }
                statuses[job.id] = BatchStatus(phase: "Inspecting")
                do {
                    try checkpoint()
                    try await encode(job, tools: tools)
                } catch is CancellationError {
                    statuses[job.id] = BatchStatus(phase: "Cancelled", detail: "No output published")
                    checkpointAfterOutcome()
                    break
                } catch {
                    statuses[job.id] = BatchStatus(phase: "Failed", detail: error.localizedDescription)
                    checkpointAfterOutcome()
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
        let preservingHDR = job.configuration.colorMode == "Preserve static HDR10"
        try SessionDocument.validate(job.configuration)
        if preservingHDR { try EncodePlan.validateHDRSettings(job.configuration) }
        var fingerprint: SourceFingerprint?
        var hdr: HDR10Contract?
        if preservingHDR {
            statuses[job.id] = BatchStatus(phase: "Inspecting", detail: "HDR10: checking tool coverage and source identity before full-frame audit")
            try checkpoint()
            try await HDR10Audit.checkTools(tools)
            fingerprint = try await SourceFingerprint.read(source)
        }
        let probe = try await MediaProbe.read(source, tools: tools)
        if preservingHDR {
            statuses[job.id]?.detail = "HDR10: decoding every source frame; checking static metadata and fixed cadence"
            hdr = try await HDR10Audit.read(source, tools: tools, probe: probe) { [weak self] frames, fraction in
                Task { @MainActor in
                    guard self?.statuses[job.id]?.phase == "Inspecting" else { return }
                    self?.statuses[job.id]?.progress = fraction
                    self?.statuses[job.id]?.detail = "HDR10: source audit · \(frames) decoded frames · static metadata and cadence"
                }
            }
            guard try await SourceFingerprint.read(source) == fingerprint else { throw HDR10Audit.failure("Source changed during preflight. Nothing published.") }
        }
        try Task.checkCancellation()
        let directory = output.deletingLastPathComponent().appendingPathComponent(".staxrip-batch-" + UUID().uuidString)
        let staged = directory.appendingPathComponent("encoded." + job.configuration.container.lowercased())
        let plan = try EncodePlan.make(job: job, probe: probe, encoders: encoders, staged: staged, hdr: hdr)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        statuses[job.id] = BatchStatus(phase: "Encoding", detail: plan.summary)
        try checkpoint()
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
        statuses[job.id]?.progress = 0
        try checkpoint()
        let actual = try await MediaProbe.read(staged, tools: tools)
        guard actual.video?.codec_name == plan.expectedCodec,
              actual.streams.filter({ $0.codec_type == "audio" }).count == plan.audioCount,
              actual.streams.filter({ $0.codec_type == "subtitle" }).count == plan.subtitleCount,
              plan.expectedWidth == nil || actual.video?.width == plan.expectedWidth,
              plan.expectedHeight == nil || actual.video?.height == plan.expectedHeight,
              actual.seconds > 0,
              plan.duration <= 0 || abs(actual.seconds - plan.duration) < max(0.25, plan.duration * 0.01) else {
            throw NativeExportError.invalid("The output did not match the expected codec, dimensions, tracks or duration.")
        }
        if let expected = plan.expectedAudio, actual.streams.filter({ $0.codec_type == "audio" }).contains(where: { $0.codec_name != expected }) {
            throw NativeExportError.invalid("Output audio did not match the planned codec.")
        }
        var verifiedSummary = plan.summary
        if let hdr {
            statuses[job.id]?.detail = "HDR10: decoding every staged output frame before publication"
            let verified = try await HDR10Audit.read(staged, tools: tools, probe: actual, expectedRate: hdr.rate) { [weak self] frames, fraction in
                Task { @MainActor in
                    guard self?.statuses[job.id]?.phase == "Verifying" else { return }
                    self?.statuses[job.id]?.progress = fraction
                    self?.statuses[job.id]?.detail = "HDR10: output audit · \(frames) decoded frames · checking against source"
                }
            }
            try hdr.verify(verified)
            statuses[job.id]?.detail = "HDR10: rechecking source identity before publication"
            guard try await SourceFingerprint.read(source) == fingerprint else { throw HDR10Audit.failure("Source changed during export. Nothing published.") }
            verifiedSummary = hdr.summary + " · source/output timestamp bound ≤ \(hdr.timeBase.value + verified.timeBase.value) s"
        }
        try Task.checkCancellation()
        try ExportPublication.publish(staged: staged, destination: output)
        statuses[job.id] = BatchStatus(phase: "Completed", progress: 1, detail: verifiedSummary, destination: output)
        // Publication already succeeded. A journal failure must not mislabel the media as failed.
        checkpointAfterOutcome()
    }
}

final class ProgressParser: @unchecked Sendable {
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
