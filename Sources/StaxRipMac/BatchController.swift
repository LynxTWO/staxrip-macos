import SwiftUI
import AppKit
import Darwin

struct BatchStatus: Codable {
    var phase = "Pending"
    var progress = 0.0
    var detail = ""
    var destination: URL?
}

@MainActor
final class BatchController: ObservableObject {
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

    private let readInspection: (URL, FFmpegTools) async throws -> MediaProbe
    private let readSource: ExportSourceFingerprint.Reader
    private let publishOutput: (URL, URL) async throws -> Void
    private let removeStaging: (URL) async throws -> Void
    private let beginActivity: ExportActivity.Factory
    private let journalURL: URL?
    private var journalLease: BatchJournalLease?
    private var journalJobs: [QueueJob] = []
    private var task: Task<Void, Never>?
    private var sourceCheck: (id: UUID, jobID: UUID, acceptsProgress: Bool)?

    #if DEBUG
    private var demoJournalRefused = false
    private(set) var isolatedDemoJournal = false
    func configureDemoJournal(refused: Bool) {
        demoJournalRefused = refused
        isolatedDemoJournal = !refused
        if refused { recoveryError = "Demonstration journal unavailable. Queue execution is disabled; the normal recovery journal was not selected." }
    }
    #endif

    init(journalURL: URL? = nil,
         readInspection: @escaping (URL, FFmpegTools) async throws -> MediaProbe = { try await MediaProbe.read($0, tools: $1) },
         readSource: @escaping ExportSourceFingerprint.Reader = { try await ExportSourceFingerprint.read($0, progress: $1) },
         publishOutput: @escaping (URL, URL) async throws -> Void = { try await ExportPublication.publishAsync(staged: $0, destination: $1) },
         removeStaging: @escaping (URL) async throws -> Void = { try await ExportStaging.remove($0) },
         beginActivity: @escaping ExportActivity.Factory = ExportActivity.begin) {
        self.readInspection = readInspection
        self.readSource = readSource
        self.publishOutput = publishOutput
        self.removeStaging = removeStaging
        self.beginActivity = beginActivity
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
            let result = try await readInspection(source, tools)
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
        #if DEBUG
        guard !demoJournalRefused else { return }
        #endif
        guard !running, !reviewing, !copyHeld, let tools else { return }
        let selected = pendingJobs(in: jobs)
        guard !selected.isEmpty else { return }
        invalidateReview()
        journalJobs = jobs
        for job in selected { statuses[job.id] = BatchStatus() }
        do {
            if let journalURL { journalLease = try BatchJournalLease(journalURL: journalURL) }
            try checkpoint()
        }
        catch { journalLease = nil; recoveryError = "Batch did not start because recovery state could not be saved: " + error.localizedDescription; return }
        recovery = nil; recoveryError = nil
        running = true
        let endActivity = beginActivity("StaxRip advanced video queue")
        task = Task {
            defer { endActivity(); running = false; task = nil; journalLease = nil }
            for job in selected {
                if Task.isCancelled { break }
                statuses[job.id] = BatchStatus(phase: "Inspecting")
                do {
                    try checkpoint()
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
                } catch let error as CopyReviewFailure {
                    if statuses[job.id]?.destination == nil {
                        statuses[job.id] = BatchStatus(phase: "Failed", detail: "HDR10 copy stopped without a verified published result. Source access and any staging resources are retained for ownership review. No automatic cleanup or retry.")
                    }
                    _ = error; checkpointAfterOutcome(); break
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
        try checkpoint()
        try await publishOutput(staged, output)
    }
    func reset(_ id: UUID) { guard !running, !copyHeld else { return }; statuses[id] = nil }

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
        if job.configuration.colorMode == DolbyConversionIntent.hdr10Copy {
            try await encodeDolbyCopy(job, tools: tools); return
        }
        try DolbyConversionIntent.requireRunnable(job.configuration)
        if job.configuration.externalSubtitle != nil { try ExternalSubtitle.validateWorkflow(job.configuration) }
        if preservingHDR { try EncodePlan.validateHDRSettings(job.configuration) }
        let fingerprint = try await fingerprint(source, jobID: job.id, label: "Checking source content before inspection")
        try Task.checkCancellation()
        statuses[job.id]?.progress = 0
        statuses[job.id]?.detail = "Inspecting source metadata"
        var hdr: HDR10Contract?
        if preservingHDR {
            statuses[job.id] = BatchStatus(phase: "Inspecting", detail: "HDR10: checking tool coverage and source identity before full-frame audit")
            try checkpoint()
            try await HDR10Audit.checkTools(tools)
        }
        let probe = try await MediaProbe.read(source, tools: tools)
        if !job.configuration.externalCaptions.isEmpty { statuses[job.id]?.detail = "Reading and validating external caption files" }
        let externalSnapshots = try await job.configuration.captureExternalCaptions()
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
        let plan = try EncodePlan.make(job: job, probe: probe, encoders: encoders, staged: staged, hdr: hdr, externalSnapshots: externalSnapshots)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var operationError: Error?
        var publishedOutput: URL?
        do {
            for (index, external) in plan.externalSubtitles.enumerated() {
                try await external.document.writeSnapshot(to: directory.appendingPathComponent(ExternalCaptionSnapshot.filename(index)))
            }
            try await ExternalCaptionTitles.write(plan.captionTitles, to: directory)
            try await plan.chapterPlan.writeMetadata(to: directory)
            let copiedVideo: VideoCopyManifest?
            if let contract = plan.videoCopy {
                statuses[job.id]?.detail = "Capturing original encoded video packets for verification"
                try checkpoint()
                copiedVideo = try await VideoCopyManifest.capture(source, contract: contract, directory: directory, tools: tools)
                guard try await self.fingerprint(source, jobID: job.id, label: "Rechecking source after video packet capture") == fingerprint else {
                    throw VideoCopyContract.failure("Source changed during packet capture. Nothing published.")
                }
            } else { copiedVideo = nil }
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
            if let playback = plan.captionPlayback { verifiedSummary += " · " + (try playback.verify(actual)) }
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
    // The existing controller is the concrete conversion owner. A review-held
    // controller remains alive with its actual scopes, descriptors and stage.
    private static var heldCopies: [BatchController] = []
    @Published private(set) var copyHeld = false
    private var copySource: URL?, copyParent: URL?, copyStage: URL?
    private var copySourceScoped = false, copyParentScoped = false
    private var copyParentFD: Int32 = -1, copyStageFD: Int32 = -1
    private struct CopyReviewFailure: CompanionUnsettledOwnership { let cause: Error }
    private struct CopyDirectoryCloseFailure: Error {
        let outcomes: [(role: String, status: Int32, code: Int32, reported: Bool)]
    }
    #if DEBUG
    private(set) var copyFailure: Error?
    var copyRetainedDescriptors: (Int32, Int32) { (copyParentFD, copyStageFD) }
    @TaskLocal static var copyHelper: URL?
    @TaskLocal static var copyBeforePublication: (@Sendable (URL) throws -> Void)?
    @TaskLocal static var reportCopyDirectoryClose: (@Sendable (String, Bool) -> Bool)?
    #endif
    private func releaseCopyScopes() {
        if copyParentScoped { copyParent?.stopAccessingSecurityScopedResource() }
        if copySourceScoped { copySource?.stopAccessingSecurityScopedResource() }
        copyParentScoped = false; copySourceScoped = false
        copyParent = nil; copySource = nil; copyStage = nil
    }
    private func closeCopyDirectories() throws {
        var outcomes: [(role: String, status: Int32, code: Int32, reported: Bool)] = []
        for role in ["stage", "parent"] {
            let fd = role == "stage" ? copyStageFD : copyParentFD
            guard fd >= 0 else { continue }
            if role == "stage" { copyStageFD = -1 } else { copyParentFD = -1 }
            let status = Darwin.close(fd), code = status == 0 ? 0 : errno
            var reported = false
            #if DEBUG
            reported = Self.reportCopyDirectoryClose?(role, status == 0) == true
            #endif
            outcomes.append((role,status,code,reported))
        }
        if outcomes.contains(where: { $0.status != 0 || $0.reported }) {
            throw CopyReviewFailure(cause: CopyDirectoryCloseFailure(outcomes: outcomes))
        }
    }
    private func requireCopyDirectory(_ fd: Int32, at url: URL) throws {
        var opened = stat(), selected = stat()
        guard fd >= 0, fstat(fd, &opened) == 0, lstat(url.path, &selected) == 0,
              opened.st_mode & S_IFMT == S_IFDIR, selected.st_mode & S_IFMT == S_IFDIR,
              opened.st_dev == selected.st_dev, opened.st_ino == selected.st_ino else { throw DolbyCopyNative.failure() }
    }
    private func encodeDolbyCopy(_ job: QueueJob, tools: FFmpegTools) async throws {
        try DolbyConversionIntent.validateCopySettings(job.configuration)
        let source = URL(fileURLWithPath: job.source).standardizedFileURL
        let output = URL(fileURLWithPath: job.destination).standardizedFileURL, parent = output.deletingLastPathComponent()
        var selectedHelper = DolbyInspection.bundledHelper()
        #if DEBUG
        selectedHelper = Self.copyHelper ?? selectedHelper
        #endif
        guard source == source.resolvingSymlinksInPath(), parent == parent.resolvingSymlinksInPath(),
              output.pathExtension.lowercased() == "mkv", let acknowledgement = job.configuration.dolbyLossAcknowledgement,
              !Self.heldCopies.contains(where: { $0.copySource == source || $0.copyParent == parent }),
              let helper = selectedHelper else { throw DolbyCopyNative.failure() }
        copySource = source; copyParent = parent
        copySourceScoped = source.startAccessingSecurityScopedResource(); copyParentScoped = parent.startAccessingSecurityScopedResource()
        var published: URL?
        do {
            copyParentFD = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            try requireCopyDirectory(copyParentFD, at: parent)
            for executable in [tools.ffmpeg,tools.ffprobe] {
                let result = try await ToolRunner(checkedReaders: true).run(executable: executable, arguments: ["-version"])
                let words = String(decoding: result.stdout, as: UTF8.self).split(whereSeparator: \.isWhitespace)
                guard result.status == 0, !result.truncated, words.count > 2,
                      words[2] == "9.0" || words[2].hasPrefix("9.0.") else { throw DolbyCopyNative.failure() }
            }
            let probe = try await MediaProbe.read(source, tools: tools, checkedReaders: true)
            guard probe.streams.count == 1, (probe.chapters ?? []).isEmpty, let stream = probe.video, stream.index == 0 else { throw DolbyCopyNative.failure() }
            let clock = try HDRFraction(stream.time_base)
            let (sourceHash, nativeSource) = try await ExportSourceFingerprint.readCopy(source, role: .source, timeBase: clock)
            guard acknowledgement.matches(source: source, fingerprint: sourceHash) else { throw DolbyCopyNative.failure() }
            statuses[job.id]?.detail = "Inspecting complete Dolby metadata and decoded base-layer frames"
            let report = try await DolbyInspection.read(source: source, probe: probe, helper: helper, tools: tools, copyVerification: true)
            guard report.source == sourceHash, report.packets == nativeSource.packets, report.records == report.packets,
                  report.packetsWithoutRPU == 0, report.packetsWithMultipleRPUs == 0,
                  report.mappings == ["7:MEL": report.records], report.cmv29Records == report.records, report.cmv40Records == 0,
                  report.header.declaredPixelWidth == 3840, report.header.declaredPixelHeight == 2160,
                  report.header.declaredCropLeftRightTopBottom == [0,0,0,0] else { throw DolbyCopyNative.failure() }
            let sourceTiming = try await DolbyCopyTiming.read(source, stream: stream.index, timeBase: clock, tools: tools)
            let sourceFrames = try await DolbyCopyFrames.read(source, stream: stream, source: true, tools: tools)
            try sourceFrames.bind(nativeSource)
            try requireCopyDirectory(copyParentFD, at: parent); try Task.checkCancellation()
            let directory = parent.appendingPathComponent(".staxrip-batch-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            copyStage = directory
            copyStageFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            try requireCopyDirectory(copyStageFD, at: directory)
            let staged = directory.appendingPathComponent("encoded.mkv")
            statuses[job.id] = BatchStatus(phase: "Encoding", detail: "HDR10 base-layer copy · Dolby Vision loss acknowledged · no video re-encoding")
            try checkpoint()
            let result = try await ToolRunner(checkedReaders: true).run(executable: tools.ffmpeg, arguments: [
                "-v","error","-nostdin","-n","-i",source.path,"-map","0:0","-c:v","copy",
                "-bsf:v","dovi_split=mode=bl,dovi_rpu=strip=1","-an","-sn","-dn",staged.path])
            guard result.status == 0, result.stderr.isEmpty else { throw DolbyCopyNative.failure() }
            statuses[job.id] = BatchStatus(phase: "Verifying", detail: "Comparing every encoded packet, decoded frame and static HDR declaration")
            try checkpoint()
            let actual = try await MediaProbe.read(staged, tools: tools, checkedReaders: true)
            guard actual.streams.count == 1, let video = actual.video, video.index == 0 else { throw DolbyCopyNative.failure() }
            let outputClock = try HDRFraction(video.time_base)
            let (outputHash, nativeOutput) = try await ExportSourceFingerprint.readCopy(staged, role: .output, timeBase: outputClock)
            let timing = try await DolbyCopyTiming.read(staged, stream: video.index, timeBase: outputClock, tools: tools)
            try DolbyCopyNative.verify(source: nativeSource, output: nativeOutput, sourceTiming: sourceTiming, outputTiming: timing)
            let frames = try await DolbyCopyFrames.read(staged, stream: video, source: false, tools: tools)
            try frames.bind(nativeOutput); guard frames == sourceFrames else { throw DolbyCopyFrames.failure() }
            let (finalSource, _) = try await ExportSourceFingerprint.readCopy(source, role: .source, timeBase: clock)
            let (finalOutput, _, verifiedIdentity) = try await ExportSourceFingerprint.readCopyIdentity(staged, role: .output, timeBase: outputClock)
            guard finalSource == sourceHash, finalOutput == outputHash else { throw DolbyCopyNative.failure() }
            try requireCopyDirectory(copyParentFD, at: parent); try requireCopyDirectory(copyStageFD, at: directory)
            #if DEBUG
            try Self.copyBeforePublication?(staged)
            #endif
            var before = stat(); guard lstat(staged.path, &before) == 0, before.st_mode & S_IFMT == S_IFREG, verifiedIdentity.matches(before) else { throw DolbyCopyNative.failure() }
            try Task.checkCancellation(); try await publish(staged, to: output, jobID: job.id); published = output
            // The existing exclusive hard-link publication must expose this same
            // verified artifact. Later errors never turn Published into Unpublished.
            var after = stat(); guard lstat(output.path, &after) == 0, verifiedIdentity.matches(after, published: true) else { throw DolbyCopyNative.failure() }
            let (publishedHash, _, publishedIdentity) = try await ExportSourceFingerprint.readCopyIdentity(output, role: .output, timeBase: outputClock)
            guard publishedHash == outputHash, verifiedIdentity.matches(publishedIdentity.value, published: true) else { throw DolbyCopyNative.failure() }
            let summary = "Verified HDR10 base-layer copy · \(frames.frames) frames · PQ / BT.2020 / top-left chroma and static HDR unchanged. Dolby Vision and enhancement data removed with your acknowledgement. No video re-encoding or tone mapping.\nVerified output SHA256: \(outputHash.sha256) · \(outputHash.byteCount) bytes · same artifact exclusively published.\nThe temporary verification copy is retained beside the output; this route does not automatically delete it."
            statuses[job.id] = BatchStatus(phase: "Completed", progress: 1, detail: summary, destination: output)
            checkpointAfterOutcome()
            try requireCopyDirectory(copyParentFD, at: parent); try requireCopyDirectory(copyStageFD, at: directory)
            try closeCopyDirectories()
            // Retain the verification files. Path-only recursive deletion cannot
            // prove it still names this owned directory after publication.
            releaseCopyScopes()
        } catch {
            // Conservative first route: preserve the concrete owner and all
            // remaining access/FDs/files on ANY failed qualification. No retry,
            // discard or review-release interface is implied by task completion.
            #if DEBUG
            copyFailure = error
            #endif
            copyHeld = true; Self.heldCopies.append(self)
            if let published {
                let completed = statuses[job.id]?.phase == "Completed"
                statuses[job.id] = BatchStatus(phase: completed ? "Completed" : "Failed", progress: completed ? 1 : 0,
                    detail: (completed ? statuses[job.id]!.detail : "An output was published, but final artifact verification did not complete. It is not a verified HDR10 result.") + "\nCleanup warning: output remains published; copy ownership or identity needs review. Retained resources were not discarded.", destination: published)
                checkpointAfterOutcome()
            }
            throw CopyReviewFailure(cause: error)
        }
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
