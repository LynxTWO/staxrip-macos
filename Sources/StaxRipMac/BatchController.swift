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
    #if DEBUG
    @TaskLocal static var observeStage: (@Sendable (String) -> Void)?
    #endif
    @Published var running = false
    @Published private(set) var publicationJobID: UUID?
    @Published var toolDescription = "Checking FFmpeg…"
    @Published var statuses: [UUID: BatchStatus] = [:]
    @Published var encoders: Set<String> = [] {
        didSet { if oldValue != encoders { invalidateReview() } }
    }
    @Published var tools: FFmpegTools? {
        didSet {
            if oldValue?.ffmpeg != tools?.ffmpeg || oldValue?.ffprobe != tools?.ffprobe { invalidateReview() }
        }
    }
    @Published var inspecting = false
    @Published var inspection: MediaProbe?
    @Published var inspectionError: String?
    private var inspectionGeneration = UUID()
    @Published var recovery: BatchJournal?
    @Published var recoveryError: String?
    @Published private(set) var reviewing = false
    @Published private(set) var queueChecks: [UUID: QueueCheck] = [:]
    @Published private(set) var reviewStatus = ""
    @Published private(set) var reviewDate: Date?
    private var reviewJobs: [QueueJob]?
    private var reviewToolPaths: [URL] = []
    private var reviewEncoders: Set<String> = []
    private var reviewGeneration = UUID()
    private var reviewTask: Task<Void, Never>?

    func reviewMatches(_ jobs: [QueueJob]) -> Bool {
        guard let tools else { return false }
        return reviewJobs == jobs && reviewToolPaths == [tools.ffmpeg, tools.ffprobe] && reviewEncoders == encoders
    }
    func invalidateReview() {
        reviewGeneration = UUID(); reviewTask?.cancel()
        queueChecks = [:]; reviewJobs = nil; reviewDate = nil
        reviewStatus = reviewing ? "Queue changed. Stopping the old check…" : ""
    }
    func cancelReview() { reviewTask?.cancel() }
    func review(_ jobs: [QueueJob]) {
        guard !running, !reviewing, !jobs.isEmpty, let tools else { return }
        let id = UUID(); reviewGeneration = id
        reviewJobs = jobs; reviewToolPaths = [tools.ffmpeg, tools.ffprobe]; reviewEncoders = encoders
        queueChecks = [:]; reviewDate = nil; reviewing = true
        reviewStatus = "Checking queue…"
        let completed = Set(statuses.filter { $0.value.phase == "Completed" }.map(\.key))
        let knownEncoders = encoders
        reviewTask = Task { [self] in
            defer {
                reviewing = false; reviewTask = nil
                if reviewGeneration != id { reviewStatus = "Queue changed. Check again." }
            }
            do {
                let results = try await QueuePreflight.review(jobs, completed: completed, tools: tools, encoders: knownEncoders) { [weak self] item in
                    Task { @MainActor in
                        guard let self, self.reviewGeneration == id, self.reviewing else { return }
                        self.queueChecks[item.id] = item
                        self.reviewStatus = "Checked \(self.queueChecks.count) of \(jobs.count) queue items…"
                    }
                }
                try Task.checkCancellation()
                guard reviewGeneration == id else { return }
                queueChecks = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
                reviewDate = Date()
                reviewStatus = "Preliminary check: \(results.filter { $0.kind == .checked }.count) passed, \(results.filter { $0.kind == .issue }.count) need correction, \(results.filter { $0.kind == .deferred }.count) need further checks, \(results.filter { $0.kind == .completed }.count) already completed."
            } catch {
                guard reviewGeneration == id else { return }
                queueChecks = [:]; reviewJobs = nil; reviewDate = nil
                reviewStatus = error is CancellationError ? "Check cancelled. No files were encoded or written." : String(error.localizedDescription.prefix(2000))
            }
        }
    }

    private let readSource: ExportSourceFingerprint.Reader
    private let publishOutput: (URL, URL) async throws -> Void
    private let removeStaging: (URL) async throws -> Void
    private let journalURL: URL?
    private var journalLease: BatchJournalLease?
    private var journalJobs: [QueueJob] = []
    private var task: Task<Void, Never>?
    private var sourceCheck: (id: UUID, jobID: UUID, acceptsProgress: Bool)?

    init(journalURL: URL? = nil,
         readSource: @escaping ExportSourceFingerprint.Reader = { try await ExportSourceFingerprint.read($0, progress: $1) },
         publishOutput: @escaping (URL, URL) async throws -> Void = { try await ExportPublication.publishAsync(staged: $0, destination: $1) },
         removeStaging: @escaping (URL) async throws -> Void = { try await ExportStaging.remove($0) }) {
        self.readSource = readSource
        self.publishOutput = publishOutput
        self.removeStaging = removeStaging
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
        let id = UUID(); inspectionGeneration = id
        inspection = nil; inspectionError = nil; inspecting = false
        guard let tools else { inspectionError = "FFmpeg tools are unavailable."; return }
        inspecting = true
        defer { if inspectionGeneration == id { inspecting = false } }
        do {
            let result = try await MediaProbe.read(source, tools: tools)
            try Task.checkCancellation()
            guard inspectionGeneration == id else { return }
            inspection = result
        } catch {
            guard inspectionGeneration == id else { return }
            inspectionError = error is CancellationError ? "Inspection cancelled." : error.localizedDescription
        }
    }

    func pendingJobs(in jobs: [QueueJob]) -> [QueueJob] {
        jobs.filter { statuses[$0.id]?.phase != "Completed" }
    }

    func start(_ jobs: [QueueJob]) {
        guard !running, !reviewing, let tools else { return }
        let selected = pendingJobs(in: jobs)
        guard !selected.isEmpty else { return }
        invalidateReview()
        journalJobs = jobs
        for job in selected { statuses[job.id] = BatchStatus() }
        do {
            if let journalURL { journalLease = try BatchJournalLease(journalURL: journalURL) }
            #if DEBUG
            Self.observeStage?("checkpoint begin")
            #endif
            try checkpoint()
            #if DEBUG
            Self.observeStage?("checkpoint returned")
            #endif
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
                    #if DEBUG
                    Self.observeStage?("checkpoint begin")
                    #endif
                    try checkpoint()
                    #if DEBUG
                    Self.observeStage?("checkpoint returned")
                    #endif
                    try await encode(job, tools: tools)
                } catch let error as ExportCleanupError {
                    if let output = error.publishedOutput {
                        let summary = statuses[job.id]?.detail ?? ""
                        statuses[job.id] = BatchStatus(phase: "Completed", progress: 1,
                            detail: summary + "\nCleanup warning: " + error.localizedDescription, destination: output)
                    } else {
                        let phase = error.operationError is CancellationError ? "Cancelled" : "Failed"
                        statuses[job.id] = BatchStatus(phase: phase, detail: "Cleanup warning: " + error.localizedDescription)
                    }
                    checkpointAfterOutcome()
                    // Keep the publication outcome, but do not accumulate more leftovers.
                    break
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

    func cancel() {
        if let id = publicationJobID {
            statuses[id]?.detail = "Stop requested. Waiting for the current output to finish publishing; later jobs will not start."
        }
        if let check = sourceCheck {
            sourceCheck?.acceptsProgress = false
            statuses[check.jobID]?.detail = "Stop requested. Waiting for the source content check to finish."
        }
        task?.cancel()
    }

    private func fingerprint(_ source: URL, jobID: UUID, label: String) async throws -> SourceFingerprint {
        let id = UUID()
        sourceCheck = (id, jobID, true)
        defer { if sourceCheck?.id == id { sourceCheck = nil } }
        statuses[jobID]?.progress = 0
        statuses[jobID]?.detail = label
        return try await readSource(source) { [weak self] bytes, total in
            Task { @MainActor in
                self?.sourceCheckProgress(id: id, jobID: jobID, label: label, bytes: bytes, total: total)
            }
        }
    }

    private func sourceCheckProgress(id: UUID, jobID: UUID, label: String, bytes: Int64, total: Int64) {
        guard sourceCheck?.id == id, sourceCheck?.jobID == jobID, sourceCheck?.acceptsProgress == true else { return }
        statuses[jobID]?.progress = Double(bytes) / Double(total)
        statuses[jobID]?.detail = "\(label) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }

    private func publish(_ staged: URL, to output: URL, jobID: UUID) async throws {
        publicationJobID = jobID
        defer { publicationJobID = nil }
        statuses[jobID]?.detail = "Finishing output. Waiting for the destination filesystem to publish the verified file."
        #if DEBUG
        Self.observeStage?("checkpoint begin")
        #endif
        try checkpoint()
        #if DEBUG
        Self.observeStage?("checkpoint returned")
        #endif
        try await publishOutput(staged, output)
    }
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
        if job.configuration.externalSubtitle != nil { try ExternalSubtitle.validateWorkflow(job.configuration) }
        if preservingHDR { try EncodePlan.validateHDRSettings(job.configuration) }
        #if DEBUG
        Self.observeStage?("source fingerprint begin")
        #endif
        let fingerprint = try await fingerprint(source, jobID: job.id, label: "Checking source content before inspection")
        #if DEBUG
        Self.observeStage?("source fingerprint returned")
        #endif
        try Task.checkCancellation()
        statuses[job.id]?.progress = 0
        statuses[job.id]?.detail = "Inspecting source metadata"
        var hdr: HDR10Contract?
        if preservingHDR {
            statuses[job.id] = BatchStatus(phase: "Inspecting", detail: "HDR10: checking tool coverage and source identity before full-frame audit")
            #if DEBUG
            Self.observeStage?("checkpoint begin")
            #endif
            try checkpoint()
            #if DEBUG
            Self.observeStage?("checkpoint returned")
            #endif
            try await HDR10Audit.checkTools(tools)
        }
        #if DEBUG
        Self.observeStage?("source probe begin")
        #endif
        let probe = try await MediaProbe.read(source, tools: tools)
        #if DEBUG
        Self.observeStage?("source probe returned")
        #endif
        if !job.configuration.externalCaptions.isEmpty { statuses[job.id]?.detail = "Reading and validating external caption files" }
        #if DEBUG
        Self.observeStage?("caption capture begin")
        #endif
        let externalSnapshots = try await job.configuration.captureExternalCaptions()
        #if DEBUG
        Self.observeStage?("caption capture returned")
        #endif
        if preservingHDR {
            statuses[job.id]?.detail = "HDR10: decoding every source frame; checking static metadata and fixed cadence"
            hdr = try await HDR10Audit.read(source, tools: tools, probe: probe) { [weak self] frames, fraction in
                Task { @MainActor in
                    guard self?.statuses[job.id]?.phase == "Inspecting", self?.sourceCheck == nil else { return }
                    self?.statuses[job.id]?.progress = fraction
                    self?.statuses[job.id]?.detail = "HDR10: source audit · \(frames) decoded frames · static metadata and cadence"
                }
            }
            guard try await self.fingerprint(source, jobID: job.id, label: "Rechecking source content after HDR10 preflight") == fingerprint else { throw HDR10Audit.failure("Source changed during preflight. Nothing published.") }
        }
        try Task.checkCancellation()
        let directory = output.deletingLastPathComponent().appendingPathComponent(".staxrip-batch-" + UUID().uuidString)
        let staged = directory.appendingPathComponent("encoded." + job.configuration.container.lowercased())
        #if DEBUG
        Self.observeStage?("plan begin")
        #endif
        let plan = try EncodePlan.make(job: job, probe: probe, encoders: encoders, staged: staged, hdr: hdr, externalSnapshots: externalSnapshots)
        #if DEBUG
        Self.observeStage?("plan returned")
        #endif
        #if DEBUG
        Self.observeStage?("staging directory begin")
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        #if DEBUG
        Self.observeStage?("staging directory returned")
        #endif
        var operationError: Error?
        var publishedOutput: URL?
        do {
            for (index, external) in plan.externalSubtitles.enumerated() {
                #if DEBUG
                Self.observeStage?("snapshot begin")
                #endif
                try await external.document.writeSnapshot(to: directory.appendingPathComponent(ExternalCaptionSnapshot.filename(index)))
                #if DEBUG
                Self.observeStage?("snapshot returned")
                #endif
            }
            #if DEBUG
            Self.observeStage?("titles begin")
            #endif
            try await ExternalCaptionTitles.write(plan.captionTitles, to: directory)
            #if DEBUG
            Self.observeStage?("titles returned")
            #endif
            #if DEBUG
            Self.observeStage?("chapter metadata begin")
            #endif
            try await plan.chapterPlan.writeMetadata(to: directory)
            #if DEBUG
            Self.observeStage?("chapter metadata returned")
            #endif
            let copiedVideo: VideoCopyManifest?
            if let contract = plan.videoCopy {
                statuses[job.id]?.detail = "Capturing original encoded video packets for verification"
                #if DEBUG
                Self.observeStage?("checkpoint begin")
                #endif
                try checkpoint()
                #if DEBUG
                Self.observeStage?("checkpoint returned")
                #endif
                copiedVideo = try await VideoCopyManifest.capture(source, contract: contract, directory: directory, tools: tools)
                guard try await self.fingerprint(source, jobID: job.id, label: "Rechecking source after video packet capture") == fingerprint else {
                    throw VideoCopyContract.failure("Source changed during packet capture. Nothing published.")
                }
            } else { copiedVideo = nil }
            statuses[job.id] = BatchStatus(phase: "Encoding", detail: plan.summary)
            #if DEBUG
            Self.observeStage?("checkpoint begin")
            #endif
            try checkpoint()
            #if DEBUG
            Self.observeStage?("checkpoint returned")
            #endif
            let parser = ProgressParser(duration: plan.duration) { [weak self] fraction in
                Task { @MainActor in
                    guard self?.statuses[job.id]?.phase == "Encoding" else { return }
                    self?.statuses[job.id]?.progress = fraction
                }
            }
            #if DEBUG
            Self.observeStage?("encode begin")
            #endif
            let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: plan.arguments) { data in parser.accept(data) }
            #if DEBUG
            Self.observeStage?("encode returned")
            #endif
            try Task.checkCancellation()
            guard result.status == 0 else {
                throw NativeExportError.invalid("FFmpeg exited \(result.status).\n" + String(decoding: result.stderr, as: UTF8.self))
            }
            statuses[job.id]?.phase = "Verifying"
            statuses[job.id]?.progress = 0
            #if DEBUG
            Self.observeStage?("checkpoint begin")
            #endif
            try checkpoint()
            #if DEBUG
            Self.observeStage?("checkpoint returned")
            #endif
            #if DEBUG
            Self.observeStage?("output probe begin")
            #endif
            let actual = try await MediaProbe.read(staged, tools: tools)
            #if DEBUG
            Self.observeStage?("output probe returned")
            #endif
            guard actual.video?.codec_name == plan.expectedCodec,
                  actual.streams.filter({ $0.codec_type == "audio" }).count == plan.audioCount,
                  actual.streams.filter({ $0.codec_type == "subtitle" }).count == plan.subtitleCount,
                  plan.expectedWidth == nil || actual.video?.width == plan.expectedWidth,
                  plan.expectedHeight == nil || actual.video?.height == plan.expectedHeight else {
                throw NativeExportError.invalid("The output did not match the expected codec, dimensions or tracks.")
            }
            let durationSummary = try OutputDurationCheck.verify(expected: plan.duration, actual: actual.seconds)
            if plan.normalizedOrientation {
                guard let video = actual.video, try SourceOrientation.read(video) == .identity,
                      video.sample_aspect_ratio == "1:1" else {
                    throw SourceOrientation.failure("The encoded output retained an unexpected display transform or pixel aspect ratio. Nothing was published.")
                }
            }
            if let expected = plan.expectedAudio, actual.streams.filter({ $0.codec_type == "audio" }).contains(where: { $0.codec_name != expected }) {
                throw NativeExportError.invalid("Output audio did not match the planned codec.")
            }
            var verifiedSummary = plan.summary
            if let hdr {
                statuses[job.id]?.detail = "HDR10: decoding every staged output frame before publication"
                let verified = try await HDR10Audit.read(staged, tools: tools, probe: actual, expectedRate: hdr.rate) { [weak self] frames, fraction in
                    Task { @MainActor in
                        guard self?.statuses[job.id]?.phase == "Verifying", self?.publicationJobID != job.id, self?.sourceCheck == nil else { return }
                        self?.statuses[job.id]?.progress = fraction
                        self?.statuses[job.id]?.detail = "HDR10: output audit · \(frames) decoded frames · checking against source"
                    }
                }
                try hdr.verify(verified)
                verifiedSummary = hdr.summary + " · source/output timestamp bound ≤ \(hdr.timeBase.value + verified.timeBase.value) s"
            }
            try Task.checkCancellation()
            verifiedSummary += " · " + durationSummary
            verifiedSummary += " · " + (try plan.outputGeometry.verify(width: actual.video?.width, height: actual.video?.height))
            verifiedSummary += " · " + (try plan.outputDisplayAspect.verify(width: actual.video?.width, height: actual.video?.height,
                                                                           sampleAspectRatio: actual.video?.sample_aspect_ratio))
            verifiedSummary += " · " + (try plan.containerPreservation.verify(actual))
            for (index, external) in plan.externalSubtitles.enumerated() {
                statuses[job.id]?.detail = "Verifying caption track \(index + 1), \(URL(fileURLWithPath: external.reference.path).lastPathComponent)"
                do { verifiedSummary += " · Track \(index + 1) (\(external.reference.language)): " + (try await external.verify(staged, probe: actual, tools: tools)) }
                catch is CancellationError { throw CancellationError() }
                catch { throw ExternalCaptionSnapshot.failure(error, reference: external.reference, index: index) }
            }
            if let copiedVideo {
                statuses[job.id]?.detail = "Verifying original video packets and presentation timing before publication"
                verifiedSummary += " · " + (try await copiedVideo.verify(staged, probe: actual, tools: tools))
            }
            try Task.checkCancellation()
            guard try await self.fingerprint(source, jobID: job.id, label: "Rechecking source content before publication") == fingerprint else {
                throw NativeExportError.invalid("Source changed during export: content fingerprint differs. Nothing published.")
            }
            try Task.checkCancellation()
            verifiedSummary += " · Source content fingerprint unchanged"
            try await publish(staged, to: output, jobID: job.id)
            if Task.isCancelled { verifiedSummary += " · Batch stopped after this output." }
            publishedOutput = output
            statuses[job.id] = BatchStatus(phase: "Completed", progress: 1, detail: verifiedSummary, destination: output)
            // Publication already succeeded. A journal failure must not mislabel the media as failed.
            checkpointAfterOutcome()
        } catch { operationError = error }
        // ToolRunner has settled the process and drained both pipes before this
        // boundary, even on cancellation. Never remove a directory owned by another job.
        do { try await removeStaging(directory) }
        catch {
            throw ExportCleanupError(directory: directory, publishedOutput: publishedOutput,
                                     operationError: operationError, cleanupError: error)
        }
        if let operationError { throw operationError }
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
