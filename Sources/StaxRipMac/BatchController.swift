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

    private var demoJournalRefused = false
    private(set) var isolatedDemoJournal = false
    func configureDemoJournal(refused: Bool) {
        demoJournalRefused = refused
        isolatedDemoJournal = !refused
        if refused { recoveryError = "Demonstration journal unavailable. Queue execution is disabled; the normal recovery journal was not selected." }
    }

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
        guard !demoJournalRefused else { return }
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
                        statuses[job.id] = BatchStatus(phase: "Failed", detail: "\(job.configuration.colorMode == DolbyConversionIntent.p81Copy ? "P8.1" : "HDR10") copy stopped without a verified published result. Source access and any staging resources are retained for ownership review. No automatic cleanup or retry.")
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
        if job.configuration.colorMode == DolbyConversionIntent.p81Copy {try await encodeDolbyCopy(job,tools:tools,p81:true);return}
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
    private var copyMuxSourceFD: Int32 = -1, copyMuxCandidateFD: Int32 = -1, copyMuxOutputFD: Int32 = -1
    private var copyToolOutputFD: Int32 = -1
    private struct CopyReviewFailure: CompanionUnsettledOwnership { let cause: Error }
    private struct CopyDirectoryCloseFailure: Error {
        let outcomes: [(role: String, status: Int32, code: Int32, reported: Bool)]
    }
    #if DEBUG
    private(set) var copyFailure: Error?
    var copyRetainedDescriptors: (Int32, Int32) { (copyParentFD, copyStageFD) }
    @TaskLocal static var copyHelper: URL?
    @TaskLocal static var copyDoviTool: URL?
    @TaskLocal static var copyMuxBoundary: (@Sendable (String) throws -> Void)?
    @TaskLocal static var copyMuxWriteLimit: Int?
    @TaskLocal static var reportCopyFileClose: (@Sendable (String, Bool) -> Bool)?
    var copyMuxRetainedDescriptors: [Int32] { [copyMuxSourceFD,copyMuxCandidateFD,copyMuxOutputFD,copyToolOutputFD] }
    @TaskLocal static var copyToolOutputBoundary: (@Sendable (URL) throws -> Void)?
    // Historical generated fixtures use the same ordinary route, without a bypass.
    func startGeneratedP81(_ jobs:[QueueJob]) {start(jobs)}
    var copyOwnedTask:Task<Void,Never>? {task}
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
    // The SAME controller owns every positive open before validation can fail.
    // The exact detached body is joined before successful close; failures retain
    // concrete FDs, scopes and stage through the existing heldCopies registry.
    private func copyMuxFiles(source:URL,candidate:URL?,output:URL,clock:HDRFraction,candidateClock:HDRFraction?) async throws {
        guard copyMuxSourceFD < 0,copyMuxCandidateFD < 0,copyMuxOutputFD < 0,
              output.deletingLastPathComponent().standardizedFileURL.path==copyStage?.standardizedFileURL.path else {throw DolbyCopyNative.failure()}
        func identity(_ fd:Int32,_ url:URL) throws -> stat {
            var value=stat(),path=stat()
            guard fd>=0,fstat(fd,&value)==0,lstat(url.path,&path)==0,value.st_mode&S_IFMT==S_IFREG,
                  value.st_size>0,value.st_size<=1<<40,ExportSourceFingerprint.CopyIdentity(value:value).matches(path) else {throw DolbyCopyNative.failure()}
            return value
        }
        copyMuxSourceFD=Darwin.open(source.path,O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_NOFOLLOW)
        let sourceIdentity=try identity(copyMuxSourceFD,source)
        var candidateIdentity:stat?
        if let candidate {
            copyMuxCandidateFD=Darwin.open(candidate.path,O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_NOFOLLOW)
            candidateIdentity=try identity(copyMuxCandidateFD,candidate)
        }
        guard let stage=copyStage else {throw DolbyCopyNative.failure()}
        try requireCopyDirectory(copyStageFD,at:stage)
        copyMuxOutputFD=Darwin.openat(copyStageFD,output.lastPathComponent,O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC|O_NOFOLLOW,0o600)
        guard copyMuxOutputFD>=0 else {throw DolbyCopyNative.failure()}
        var initialOutput=stat();guard fstat(copyMuxOutputFD,&initialOutput)==0,initialOutput.st_mode&S_IFMT==S_IFREG,initialOutput.st_size==0 else {throw DolbyCopyNative.failure()}
        let sourceFD=copyMuxSourceFD,candidateFD=copyMuxCandidateFD,outputFD=copyMuxOutputFD
        #if DEBUG
        let boundary=Self.copyMuxBoundary,writeLimit=Self.copyMuxWriteLimit
        #else
        let boundary:(@Sendable(String)throws->Void)?=nil,writeLimit:Int?=nil
        #endif
        let admittedCandidate=candidateIdentity
        let body=Task.detached(priority:Task.currentPriority) {
            func view(_ fd:Int32,_ bytes:Int64) -> CompanionDiskCheck.ReadView {
                .init(sourceBytes:bytes,source:{offset,count in
                    guard offset>=0,count>=0,offset<=bytes,Int64(count)<=bytes-offset else {throw DolbyCopyNative.failure()}
                    var data=Data(count:count),done=0
                    while done<count {
                        try Task.checkCancellation()
                        let n=data.withUnsafeMutableBytes {Darwin.pread(fd,$0.baseAddress!.advanced(by:done),count-done,offset+Int64(done))}
                        if n<0 && errno==EINTR {continue};guard n>0 else {throw DolbyCopyNative.failure()};done+=n
                    }
                    return data
                },component:{_ in throw DolbyCopyNative.failure()},checkpoint:{try Task.checkCancellation()})
            }
            var first=true
            let write:(Data)throws->Void={data in
                var offset=0
                while offset<data.count {
                    try Task.checkCancellation()
                    let length=min(data.count-offset,max(1,writeLimit ?? (1<<20)))
                    let n=data.withUnsafeBytes {Darwin.write(outputFD,$0.baseAddress!.advanced(by:offset),length)}
                    if n<0 && errno==EINTR {continue};guard n>0 else {throw DolbyCopyNative.failure()};offset+=n
                    if first {first=false;try boundary?("first write")}
                }
            }
            try boundary?("body entered");try Task.checkCancellation()
            let original=view(sourceFD,Int64(sourceIdentity.st_size))
            if let admittedCandidate,let candidateClock {
                try DolbyCopyNative.muxP81(original,candidate:view(candidateFD,Int64(admittedCandidate.st_size)),timeBase:clock,candidateTimeBase:candidateClock,write:write)
            } else {try DolbyCopyNative.extractP81Input(original,timeBase:clock,write:write)}
            try boundary?("body finished");try Task.checkCancellation()
        }
        try await withTaskCancellationHandler {try await body.value} onCancel:{body.cancel()}
        // No close is attempted while the actual body can still use the FDs.
        guard ExportSourceFingerprint.CopyIdentity(value:sourceIdentity).matches(try identity(copyMuxSourceFD,source)) else {throw DolbyCopyNative.failure()}
        if let candidate,let candidateIdentity {guard ExportSourceFingerprint.CopyIdentity(value:candidateIdentity).matches(try identity(copyMuxCandidateFD,candidate)) else {throw DolbyCopyNative.failure()}}
        let written=try identity(copyMuxOutputFD,output)
        guard written.st_dev==initialOutput.st_dev,written.st_ino==initialOutput.st_ino else {throw DolbyCopyNative.failure()}
        try requireCopyDirectory(copyStageFD,at:stage);try Task.checkCancellation()
        var outcomes:[(role:String,status:Int32,code:Int32,reported:Bool)]=[]
        for role in ["mux source","mux candidate","mux output"] {
            let fd:Int32
            switch role {case "mux source":fd=copyMuxSourceFD;copyMuxSourceFD = -1
            case "mux candidate":fd=copyMuxCandidateFD;copyMuxCandidateFD = -1
            default:fd=copyMuxOutputFD;copyMuxOutputFD = -1}
            guard fd>=0 else {continue}
            let status=Darwin.close(fd),code=status==0 ? 0 : errno
            #if DEBUG
            let reported=Self.reportCopyFileClose?(role,status==0) ?? false
            #else
            let reported=false
            #endif
            outcomes.append((role,status,code,reported))
        }
        if outcomes.contains(where:{$0.status != 0 || $0.reported}) {throw CopyReviewFailure(cause:CopyDirectoryCloseFailure(outcomes:outcomes))}
    }
    // Tool output is an inherited, already-exclusive descriptor. The child never
    // opens the stage pathname for writing. Any failure keeps the same FD here.
    private func copyToolOutput(executable:URL,arguments:[String],output:URL) async throws -> ToolResult {
        guard copyToolOutputFD < 0,let stage=copyStage,
              output.deletingLastPathComponent().standardizedFileURL.path==stage.standardizedFileURL.path else {throw DolbyCopyNative.failure()}
        try requireCopyDirectory(copyStageFD,at:stage);try Task.checkCancellation()
        copyToolOutputFD=Darwin.openat(copyStageFD,output.lastPathComponent,O_RDWR|O_CREAT|O_EXCL|O_CLOEXEC|O_NOFOLLOW,0o600)
        guard copyToolOutputFD>=0 else {throw DolbyCopyNative.failure()}
        var original=stat()
        guard fstat(copyToolOutputFD,&original)==0,original.st_mode&S_IFMT==S_IFREG,original.st_size==0 else {throw DolbyCopyNative.failure()}
        let borrowed=FileHandle(fileDescriptor:copyToolOutputFD,closeOnDealloc:false)
        #if DEBUG
        try Self.copyToolOutputBoundary?(output)
        #endif
        let result=try await ToolRunner(checkedReaders:true).run(executable:executable,arguments:arguments,borrowedInput:borrowed)
        guard result.status==0,!result.truncated else {throw DolbyCopyNative.failure()}
        var written=stat(),selected=stat()
        guard fstat(copyToolOutputFD,&written)==0,written.st_dev==original.st_dev,written.st_ino==original.st_ino,
              written.st_mode&S_IFMT==S_IFREG,written.st_size>0,written.st_size<=1<<40,
              lstat(output.path,&selected)==0,ExportSourceFingerprint.CopyIdentity(value:written).matches(selected) else {throw DolbyCopyNative.failure()}
        try requireCopyDirectory(copyStageFD,at:stage);try Task.checkCancellation()
        let fd=copyToolOutputFD;copyToolOutputFD = -1
        let status=Darwin.close(fd),code=status==0 ? 0 : errno
        #if DEBUG
        let reported=Self.reportCopyFileClose?("tool output",status==0) ?? false
        #else
        let reported=false
        #endif
        if status != 0 || reported {throw CopyReviewFailure(cause:CopyDirectoryCloseFailure(outcomes:[("tool output",status,code,reported)]))}
        return result
    }
    private func encodeDolbyCopy(_ job: QueueJob, tools: FFmpegTools, p81: Bool = false) async throws {
        try DolbyConversionIntent.validateCopySettings(job.configuration,p81:p81)
        let source = URL(fileURLWithPath: job.source).standardizedFileURL
        let output = URL(fileURLWithPath: job.destination).standardizedFileURL, parent = output.deletingLastPathComponent()
        var selectedHelper = DolbyInspection.bundledHelper()
        #if DEBUG
        selectedHelper = Self.copyHelper ?? selectedHelper
        #endif
        guard source == source.resolvingSymlinksInPath(), parent == parent.resolvingSymlinksInPath(),
              output.pathExtension.lowercased() == "mkv", let acknowledgement = (p81 ? job.configuration.p81EnhancementLossAcknowledgement : job.configuration.dolbyLossAcknowledgement),
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
            let p81Metadata = try await DolbyP81Metadata.read(source, report:report, helper:helper)
            if p81 {guard p81Metadata.supported else {throw DolbyCopyNative.failure()}}
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
            statuses[job.id] = BatchStatus(phase: "Encoding", detail: p81 ? "P8.1 base-layer copy · enhancement loss acknowledged · no video re-encoding" : "HDR10 base-layer copy · Dolby Vision loss acknowledged · no video re-encoding")
            try checkpoint()
            if p81 {
                #if DEBUG
                let tool=(Self.copyDoviTool ?? URL(fileURLWithPath:"/opt/homebrew/bin/dovi_tool")).resolvingSymlinksInPath()
                #else
                let tool=URL(fileURLWithPath:"/opt/homebrew/bin/dovi_tool").resolvingSymlinksInPath()
                #endif
                let toolHash=try await ExportSourceFingerprint.readCopyInput(tool)
                let version=try await ToolRunner(checkedReaders:true).run(executable:tool,arguments:["--version"])
                guard version.status==0,!version.truncated,String(decoding:version.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)=="dovi_tool 2.3.4" else {throw DolbyCopyNative.failure()}
                let raw=directory.appendingPathComponent("original.hevc"),converted=directory.appendingPathComponent("converted.hevc"),candidate=directory.appendingPathComponent("candidate.mkv")
                statuses[job.id]?.detail="Converting the reviewed P7 metadata to P8.1; enhancement-layer loss acknowledged"
                try await copyMuxFiles(source:source,candidate:nil,output:raw,clock:clock,candidateClock:nil)
                let rawHash=try await ExportSourceFingerprint.readCopyInput(raw)
                let conversion=try await copyToolOutput(executable:tool,arguments:["-m","2","convert","--discard",raw.path,"-o","/dev/fd/0"],output:converted)
                guard conversion.status==0,!conversion.truncated else {throw DolbyCopyNative.failure()}
                let convertedHash=try await ExportSourceFingerprint.readCopyInput(converted)
                let remux=try await copyToolOutput(executable:tools.ffmpeg,arguments:["-v","error","-nostdin","-n","-r","24000/1001","-i",converted.path,"-map","0:v:0","-c:v","copy","-an","-sn","-dn","-f","matroska","pipe:0"],output:candidate)
                guard remux.status==0,remux.stderr.isEmpty else {throw DolbyCopyNative.failure()}
                let candidateProbe=try await MediaProbe.read(candidate,tools:tools,checkedReaders:true)
                guard candidateProbe.streams.count==1,let candidateVideo=candidateProbe.video else {throw DolbyCopyNative.failure()}
                let candidateHash=try await ExportSourceFingerprint.readCopyInput(candidate)
                try await copyMuxFiles(source:source,candidate:candidate,output:staged,clock:clock,candidateClock:HDRFraction(candidateVideo.time_base))
                for (input,expected) in [(raw,rawHash),(converted,convertedHash),(candidate,candidateHash),(tool,toolHash)] {
                    guard try await ExportSourceFingerprint.readCopyInput(input)==expected else {throw DolbyCopyNative.failure()}
                }
            } else {
            let result = try await ToolRunner(checkedReaders: true).run(executable: tools.ffmpeg, arguments: [
                "-v","error","-nostdin","-n","-i",source.path,"-map","0:0","-c:v","copy",
                "-bsf:v","dovi_split=mode=bl,dovi_rpu=strip=1","-an","-sn","-dn",staged.path])
            guard result.status == 0, result.stderr.isEmpty else { throw DolbyCopyNative.failure() }
            }
            statuses[job.id] = BatchStatus(phase: "Verifying", detail: "Comparing every encoded packet, decoded frame and static HDR declaration")
            try checkpoint()
            let actual = try await MediaProbe.read(staged, tools: tools, checkedReaders: true)
            guard actual.streams.count == 1, let video = actual.video, video.index == 0 else { throw DolbyCopyNative.failure() }
            let outputClock = try HDRFraction(video.time_base)
            let outputRole:DolbyCopyNative.Role = p81 ? .p81Output : .output
            let (outputHash, nativeOutput) = try await ExportSourceFingerprint.readCopy(staged, role: outputRole, timeBase: outputClock)
            let timing = try await DolbyCopyTiming.read(staged, stream: video.index, timeBase: outputClock, tools: tools)
            if !p81 {try DolbyCopyNative.verify(source: nativeSource, output: nativeOutput, sourceTiming: sourceTiming, outputTiming: timing)}
            let frames = try await DolbyCopyFrames.read(staged, stream: video, source: p81, tools: tools)
            try frames.bind(nativeOutput); guard frames == sourceFrames else { throw DolbyCopyFrames.failure() }
            if p81 {
                let outputReport=try await DolbyInspection.read(source:staged,probe:actual,helper:helper,tools:tools,copyVerification:true,copyRole:.p81Output)
                let metadata=try await DolbyP81Metadata.read(staged,report:outputReport,helper:helper,sourceRole:false)
                try DolbyP81Verification.verify(source:nativeSource,output:nativeOutput,sourceFingerprint:sourceHash,outputFingerprint:outputHash,sourceTiming:sourceTiming,outputTiming:timing,sourceMetadata:p81Metadata,outputMetadata:metadata,sourceFrames:sourceFrames,outputFrames:frames)
            }
            let (finalSource, _) = try await ExportSourceFingerprint.readCopy(source, role: .source, timeBase: clock)
            let (finalOutput, _, verifiedIdentity) = try await ExportSourceFingerprint.readCopyIdentity(staged, role: outputRole, timeBase: outputClock)
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
            let (publishedHash, _, publishedIdentity) = try await ExportSourceFingerprint.readCopyIdentity(output, role: outputRole, timeBase: outputClock)
            guard publishedHash == outputHash, verifiedIdentity.matches(publishedIdentity.value, published: true) else { throw DolbyCopyNative.failure() }
            let summary = p81 ? "Verified P8.1 base-layer copy · \(frames.frames) frames · exact packet timing and complete reviewed Dolby metadata preserved. Enhancement data removed with source-specific acknowledgement. No video re-encoding. Independent Dolby playback and visual fidelity are not verified.\nVerified output SHA256: \(outputHash.sha256) · \(outputHash.byteCount) bytes · same artifact exclusively published. Temporary verification files are retained beside the output." : "Verified HDR10 base-layer copy · \(frames.frames) frames · PQ / BT.2020 / top-left chroma and static HDR unchanged. Dolby Vision and enhancement data removed with your acknowledgement. No video re-encoding or tone mapping.\nVerified output SHA256: \(outputHash.sha256) · \(outputHash.byteCount) bytes · same artifact exclusively published.\nThe temporary verification copy is retained beside the output; this route does not automatically delete it."
            let p81Detail = p81Metadata.supported
                ? "Source metadata fits the reviewed P8.1 subset; a separate P8.1 copy request still requires its own acknowledgement and complete output verification."
                : "Source metadata is outside the reviewed P8.1 subset; P8.1 conversion remains unavailable."
            statuses[job.id] = BatchStatus(phase: "Completed", progress: 1, detail: summary + (p81 ? "" : "\n" + p81Detail), destination: output)
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
                    detail: (completed ? statuses[job.id]!.detail : "An output was published, but final artifact verification did not complete. It is not a verified \(p81 ? "P8.1" : "HDR10") result.") + "\nCleanup warning: output remains published; copy ownership or identity needs review. Retained resources were not discarded.", destination: published)
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
