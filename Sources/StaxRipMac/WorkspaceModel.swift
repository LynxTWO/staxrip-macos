import SwiftUI
import AVKit

struct EncodeConfiguration: Codable, Equatable {
    var codec = "AV1"
    var encoder = "SVT-AV1"
    var quality = 28.0
    var speed = "Balanced"
    var container = "MKV"
    var resolution = "Original"
    var cropTop = 0
    var cropBottom = 0
    var audio = "AAC"
    var audioBitrate = "192 kb/s"
    var subtitleMode = "Keep embedded tracks"
    private var colorIntent: String?
    var colorMode: String {
        get { colorIntent ?? "SDR" }
        set { colorIntent = newValue }
    }
    private var videoRateOptions: VideoRateOptions?
    var rate: VideoRateOptions {
        get { videoRateOptions ?? VideoRateOptions() }
        set { videoRateOptions = newValue }
    }
    var rateSummary: String { rate.mode == "Constant quality" ? "CRF \(Int(quality))" : "\(rate.bitrate) kb/s" }
    var activeEncoder: String { rate.backend == "Software" ? encoder : "VideoToolbox" }
    var audioTracks: [Int]?
    var subtitleTracks: [Int]?
    var externalSubtitle: ExternalSubtitle?
    var chapterEdits: ChapterEdits?
    private var pictureOptions: PictureOptions?
    var picture: PictureOptions {
        get { pictureOptions ?? PictureOptions() }
        set { pictureOptions = newValue }
    }
}

extension EncodeConfiguration {
    mutating func selectCodec(_ value: String) {
        codec = value
        encoder = value == "AV1" ? "SVT-AV1" : value == "HEVC" ? "x265" : "x264"
        if value == "AV1", rate.backend != "Software" { rate.backend = "Software" }
    }
    mutating func selectBackend(_ value: String) {
        rate.backend = value
        if value == "Apple hardware" { rate.mode = "Target bitrate" }
    }
}

struct QueueJob: Identifiable, Codable, Equatable {
    let id: UUID
    let source: String
    let isDemo: Bool
    var destination: String
    var configuration: EncodeConfiguration
    let created: Date
}

@MainActor
final class WorkspaceModel: ObservableObject {
    private let filePanels: any WorkspacePanelPresenting
    @Published private var fileRequestID: UUID?
    private var fileSelectionPending = false
    var filePanelActive: Bool { fileRequestID != nil }
    private let readSource: SourceLoader.Reader
    init(filePanels: (any WorkspacePanelPresenting)? = nil,
         readSource: @escaping SourceLoader.Reader = { try await SourceLoader.read($0) }) {
        self.readSource = readSource
        self.filePanels = filePanels ?? WorkspaceFilePanels()
    }

    @Published var section = "Workspace"
    @Published var tab = "Video"
    @Published var config = EncodeConfiguration() {
        didSet {
            guard !restoringSettings, oldValue != config else { return }
            // Coupled controls can briefly pass through an invalid configuration.
            // Keep only restorable snapshots, not those intermediate states.
            if (try? SessionDocument.validate(oldValue)) != nil, undoSettingsStack.last != oldValue {
                undoSettingsStack.append(oldValue)
            }
            if undoSettingsStack.count > 100 { undoSettingsStack.removeFirst(undoSettingsStack.count - 100) }
            redoSettingsStack = []
        }
    }
    @Published private var undoSettingsStack: [EncodeConfiguration] = []
    @Published private var redoSettingsStack: [EncodeConfiguration] = []
    private var restoringSettings = false
    var canUndoSettings: Bool { !undoSettingsStack.isEmpty }
    var canRedoSettings: Bool { !redoSettingsStack.isEmpty }
    func clearSettingsHistory() { undoSettingsStack = []; redoSettingsStack = [] }
    func undoSettings() {
        guard let previous = undoSettingsStack.popLast() else { return }
        if (try? SessionDocument.validate(config)) != nil { redoSettingsStack.append(config) }; restoringSettings = true
        config = previous; restoringSettings = false; notice = "Workspace settings undone"
    }
    func redoSettings() {
        guard let next = redoSettingsStack.popLast() else { return }
        undoSettingsStack.append(config); restoringSettings = true
        config = next; restoringSettings = false; notice = "Workspace settings redone"
    }
    func applyCustomPreset(_ preset: CustomPreset) throws {
        config = try preset.applying(to: config)
        notice = "\(preset.name) applied. Source-specific crop, trim, tracks and external captions retained."
    }
    @Published var sourceURL: URL? {
        didSet { if oldValue != sourceURL { clearSettingsHistory() } }
    }
    @Published var player: AVPlayer?
    @Published var sourceName = "Alpine escape.mov"
    @Published var sourceInfo = "3840 × 2160  ·  24 fps  ·  02:34"
    @Published private(set) var loading = false
    @Published private(set) var sourceLoadingStatus = ""
    @Published private(set) var sourceLoadStopping = false
    private var sourceTask: Task<Void, Never>?
    private struct SourceRequest { let id: UUID; let url: URL; let keepOutputName: Bool }
    private var pendingSource: SourceRequest?
    @Published var jobs: [QueueJob] = []
    @Published var outputFolder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
    @Published var outputStem = "Alpine escape_encoded"
    @Published var notice = ""
    @Published var error: String?
    @Published var sessionName = "Untitled session"
    @Published var sourceUnavailable = false
    @Published private(set) var sourceNeedsReview = false
    private var savedSnapshot: SessionDocument?
    private var loadID = UUID()
    var isDemo: Bool { sourceURL == nil }
    var outputName: String {
        return outputStem.trimmingCharacters(in: .whitespacesAndNewlines) + "." + config.container.lowercased()
    }

    var outputIssue: String? {
        Self.filenameIssue(outputStem) ?? destinationIssue(outputFolder.appendingPathComponent(outputName).path, source: sourceURL?.path)
    }

    nonisolated static func filenameIssue(_ stem: String) -> String? {
        let value = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "Enter an output file name." }
        if value == "." || value == ".." || value.contains("/") || value.contains(":") || value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "Use a file name without slashes, colons, or control characters."
        }
        return nil
    }

    func destinationIssue(_ destination: String, source: String?, excluding: UUID? = nil) -> String? {
        let target = URL(fileURLWithPath: destination).standardizedFileURL.path
        if let source, target == URL(fileURLWithPath: source).standardizedFileURL.path {
            return "Choose an output name different from the source."
        }
        if jobs.contains(where: { $0.id != excluding && URL(fileURLWithPath: $0.destination).standardizedFileURL.path == target }) {
            return "Another queue item uses this output name. Choose a different name."
        }
        return nil
    }

    func showDemo() {
        cancelSourceLoad()
        resetSourceSelections()
        loadID = UUID()
        loading = sourceTask != nil
        player?.pause()
        player = nil
        sourceURL = nil
        sourceUnavailable = false
        sourceNeedsReview = false
        sourceName = "Alpine escape.mov"
        sourceInfo = "3840 × 2160  ·  24 fps  ·  02:34"
        outputStem = "Alpine escape_encoded"
        notice = "Demo preview restored"
    }

    func moveJob(_ id: UUID, by offset: Int) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs.indices.contains(index + offset) else { return }
        jobs.swapAt(index, index + offset)
        notice = "Queue order updated"
    }

    func duplicateJob(_ job: QueueJob) {
        let url = URL(fileURLWithPath: job.destination)
        var number = 2
        var target: URL
        repeat {
            target = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-\(number)." + url.pathExtension)
            number += 1
        } while jobs.contains(where: { $0.destination == target.path })
        let copy = QueueJob(id: UUID(), source: job.source, isDemo: job.isDemo, destination: target.path, configuration: job.configuration, created: Date())
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs.insert(copy, at: index + 1)
        notice = "Configuration duplicated with a new output name"
    }

    func updateJob(_ job: QueueJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
        notice = "Queue configuration updated"
    }

    var sessionSnapshot: SessionDocument {
        SessionDocument(sourcePath: sourceURL?.path, configuration: config, outputFolder: outputFolder.path, outputStem: outputStem, jobs: jobs)
    }

    private struct FileIntent {
        let id = UUID()
        let snapshot: SessionDocument
        let loadID: UUID
    }
    private func beginFileRequest() -> FileIntent? {
        guard fileRequestID == nil else { return nil }
        let intent = FileIntent(snapshot: sessionSnapshot, loadID: loadID)
        fileRequestID = intent.id; fileSelectionPending = true
        return intent
    }
    private func consumeSelection(_ intent: FileIntent) -> Bool {
        guard fileRequestID == intent.id, fileSelectionPending else { return false }
        fileSelectionPending = false
        return true
    }
    @discardableResult
    private func finishFileRequest(_ intent: FileIntent) -> Bool {
        guard fileRequestID == intent.id else { return false }
        fileRequestID = nil; fileSelectionPending = false
        return true
    }
    private func intentIsCurrent(_ intent: FileIntent) -> Bool {
        guard fileRequestID == intent.id else { return false }
        guard sessionSnapshot == intent.snapshot, loadID == intent.loadID else {
            finishFileRequest(intent)
            notice = "The workspace changed while the dialog was open. Choose again to use the current settings."
            return false
        }
        return true
    }
    private func selectFile(_ request: WorkspaceFileRequest, intent: FileIntent,
                            completion: @escaping @MainActor (URL?) -> Void) {
        if !filePanels.select(request, completion: completion), finishFileRequest(intent) {
            notice = "Bring the workspace forward and close its current dialog, then try again."
        }
    }

    private struct QueueStartIntent {
        let snapshot: SessionDocument
        let pendingIDs: [UUID]
        let folders: [URL]
    }

    func chooseQueueStart(using batch: BatchController,
                          canStart: @escaping @MainActor () -> Bool = { true }) {
        guard !filePanelActive, !batch.running, !batch.reviewing, batch.tools != nil, canStart() else { return }
        let pending = batch.pendingJobs(in: jobs)
        guard !pending.isEmpty else { notice = "No pending jobs to start."; return }
        var seen = Set<String>()
        let folders = pending.compactMap { job -> URL? in
            let folder = URL(fileURLWithPath: job.destination).deletingLastPathComponent().standardizedFileURL
            return seen.insert(folder.path).inserted ? folder : nil
        }
        let request = QueueStartIntent(snapshot: sessionSnapshot, pendingIDs: pending.map(\.id), folders: folders)
        reviewQueueDestination(request, index: 0, using: batch, canStart: canStart)
    }

    private func reviewQueueDestination(_ request: QueueStartIntent, index: Int, using batch: BatchController,
                                        canStart: @escaping @MainActor () -> Bool) {
        guard !batch.running, !batch.reviewing, batch.tools != nil, canStart() else {
            notice = "Available operations changed. Choose Start queue again when ready."
            return
        }
        guard sessionSnapshot == request.snapshot, batch.pendingJobs(in: jobs).map(\.id) == request.pendingIDs else {
            notice = "The queue or workspace changed. Choose Start queue again to review current destinations."
            return
        }
        guard index < request.folders.count else {
            batch.start(request.snapshot.jobs)
            if batch.running { notice = "Queue started after destination review. Each job still performs independent file checks." }
            return
        }
        guard let intent = beginFileRequest() else { return }
        let expected = request.folders[index]
        selectFile(.reviewQueueDestination(expected, position: index + 1, total: request.folders.count), intent: intent) { [weak self] selected in
            guard let self, self.consumeSelection(intent) else { return }
            guard let selected else {
                self.finishFileRequest(intent)
                self.notice = "Destination review cancelled. No batch started; the recovery record is unchanged."
                return
            }
            guard self.intentIsCurrent(intent), self.finishFileRequest(intent) else { return }
            guard selected.isFileURL, selected.standardizedFileURL.path == expected.path else {
                self.notice = "A different folder was selected. No batch started; queue paths are unchanged. Choose Start queue again and select the configured folder."
                return
            }
            // The next sheet gets a fresh identity. An old completion cannot
            // consume its selection or advance the sequence more than once.
            self.reviewQueueDestination(request, index: index + 1, using: batch, canStart: canStart)
        }
    }

    func chooseNativeExport(using exporter: ExportController,
                            canStart: @escaping @MainActor () -> Bool = { true }) {
        guard !loading, !sourceUnavailable, !sourceNeedsReview, !exporter.running,
              canStart(), let source = sourceURL, let intent = beginFileRequest() else { return }
        let preset = exporter.preset
        selectFile(.nativeExport(source), intent: intent) { [weak self] destination in
            guard let self, self.consumeSelection(intent) else { return }
            guard let destination else { self.finishFileRequest(intent); return }
            guard self.intentIsCurrent(intent), self.finishFileRequest(intent) else { return }
            guard !self.loading, !self.sourceUnavailable, !self.sourceNeedsReview,
                  !exporter.running, exporter.preset == preset, canStart() else {
                self.notice = "The source, native preset or available operation changed. Choose Export MP4 again when ready."
                return
            }
            exporter.start(source: source, destination: destination)
        }
    }

    func saveSession() {
        guard let intent = beginFileRequest() else { return }
        selectFile(.saveSession, intent: intent) { [weak self] url in
            guard let self, self.consumeSelection(intent), self.finishFileRequest(intent), let url else { return }
            do {
                try intent.snapshot.write(to: url)
                self.savedSnapshot = intent.snapshot
                self.sessionName = url.deletingPathExtension().lastPathComponent
                self.notice = self.sessionSnapshot == intent.snapshot ? "Session saved" : "Session snapshot saved. Current workspace has unsaved changes."
            } catch { self.error = error.localizedDescription }
        }
    }

    func openSession() {
        guard let intent = beginFileRequest() else { return }
        selectFile(.openSession, intent: intent) { [weak self] url in
            guard let self, self.consumeSelection(intent) else { return }
            guard let url else { self.finishFileRequest(intent); return }
            guard self.intentIsCurrent(intent) else { return }
            do {
                let document = try SessionDocument.read(from: url)
                let restore: @MainActor (Bool) -> Void = { [weak self] confirmed in
                    guard let self, self.fileRequestID == intent.id else { return }
                    guard confirmed else { self.finishFileRequest(intent); return }
                    guard self.intentIsCurrent(intent), self.finishFileRequest(intent) else { return }
                    self.restoreSession(document)
                    self.sessionName = url.deletingPathExtension().lastPathComponent
                }
                if self.savedSnapshot != self.sessionSnapshot {
                    if !self.filePanels.confirmReplacement(completion: restore), self.finishFileRequest(intent) {
                        self.notice = "Bring the workspace forward and close its current dialog before opening the session."
                    }
                } else { restore(true) }
            } catch { self.finishFileRequest(intent); self.error = error.localizedDescription }
        }
    }

    func restoreSession(_ document: SessionDocument) {
        showDemo()
        config = document.configuration
        outputFolder = URL(fileURLWithPath: document.outputFolder)
        outputStem = document.outputStem
        jobs = document.jobs
        if let path = document.sourcePath {
            sourceURL = URL(fileURLWithPath: path)
            sourceName = sourceURL!.lastPathComponent
            sourceInfo = "Saved source · review access to load preview"
            sourceUnavailable = true
            sourceNeedsReview = true
        }
        clearSettingsHistory()
        savedSnapshot = document
        notice = sourceNeedsReview ? "Session restored. Review the saved source when you are ready to load its preview." : "Session restored"
    }

    func reviewSavedSource() {
        guard sourceNeedsReview, !loading, let expected = sourceURL,
              let intent = beginFileRequest() else { return }
        selectFile(.reviewSource(expected), intent: intent) { [weak self] url in
            guard let self, self.consumeSelection(intent) else { return }
            guard let url else { self.finishFileRequest(intent); return }
            guard self.intentIsCurrent(intent), self.finishFileRequest(intent) else { return }
            guard url.isFileURL, url.standardizedFileURL == expected.standardizedFileURL else {
                self.error = "Choose the saved source, \(expected.lastPathComponent), at its saved location. To use a different video, choose Open source; that resets source-specific track choices and output naming. Your saved session settings have been retained."
                return
            }
            self.load(url, keepOutputName: true)
        }
    }

    func chooseSource() {
        guard let intent = beginFileRequest() else { return }
        selectFile(.source, intent: intent) { [weak self] url in
            guard let self, self.consumeSelection(intent) else { return }
            guard let url else { self.finishFileRequest(intent); return }
            guard self.intentIsCurrent(intent), self.finishFileRequest(intent) else { return }
            self.load(url)
        }
    }

    func load(_ url: URL, keepOutputName: Bool = false) {
        let id = UUID(); loadID = id
        pendingSource = SourceRequest(id: id, url: url, keepOutputName: keepOutputName)
        loading = true; sourceLoadStopping = false
        notice = ""; error = nil
        if let sourceTask {
            sourceLoadingStatus = "Stopping the previous source load before opening the selected source…"
            sourceTask.cancel()
        } else { beginPendingSource() }
    }

    func cancelSourceLoad() {
        guard loading else { return }
        loadID = UUID(); pendingSource = nil
        sourceLoadStopping = sourceTask != nil
        sourceLoadingStatus = sourceTask == nil ? "" : "Stopping source loading. Waiting for the current reader to finish…"
        notice = "Source loading cancelled. The previous workspace is retained."
        sourceTask?.cancel()
        loading = sourceTask != nil
    }

    private func beginPendingSource() {
        guard sourceTask == nil, let request = pendingSource else { return }
        pendingSource = nil
        loading = true; sourceLoadStopping = false
        sourceLoadingStatus = "Reading selected source…"
        sourceTask = Task { [self] in
            defer {
                sourceTask = nil
                if pendingSource != nil { beginPendingSource() }
                else { loading = false; sourceLoadStopping = false; sourceLoadingStatus = "" }
            }
            do {
                try Task.checkCancellation()
                let result = try await readSource(request.url)
                try Task.checkCancellation()
                guard loadID == request.id else { return }
                player?.pause()
                player = result.nativePreview ? AVPlayer(url: request.url) : nil
                if !request.keepOutputName { resetSourceSelections() }
                sourceURL = request.url
                sourceName = request.url.lastPathComponent
                if !request.keepOutputName { outputStem = request.url.deletingPathExtension().lastPathComponent + "_encoded" }
                sourceUnavailable = !result.nativePreview
                sourceNeedsReview = false
                sourceInfo = result.info
                clearSettingsHistory()
                notice = result.nativePreview ? "Source loaded" : "Source inspected. Native preview is unavailable; the advanced engine may support it."
            } catch {
                guard loadID == request.id, !Task.isCancelled, !(error is CancellationError) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    func chooseOutput() {
        guard let intent = beginFileRequest() else { return }
        selectFile(.destination(outputFolder), intent: intent) { [weak self] url in
            guard let self, self.consumeSelection(intent) else { return }
            guard let url else { self.finishFileRequest(intent); return }
            guard self.intentIsCurrent(intent), self.finishFileRequest(intent) else { return }
            self.outputFolder = url
        }
    }

    func applyPreset(_ name: String) {
        var next = config
        next.rate = VideoRateOptions()
        switch name {
        case "Everyday HEVC":
            next.codec = "HEVC"; next.encoder = "x265"; next.quality = 22; next.container = "MP4"
        case "Compact AV1":
            next.codec = "AV1"; next.encoder = "SVT-AV1"; next.quality = 28; next.container = "MKV"
        default:
            next.codec = "H.264"; next.encoder = "x264"; next.quality = 18; next.container = "MP4"
        }
        config = next
        notice = "\(name) settings applied"
    }

    func addToQueue() {
        guard !loading else { return }
        if let issue = outputIssue { error = issue; return }
        do { try SessionDocument.validate(config) }
        catch { self.error = error.localizedDescription; return }
        jobs.append(QueueJob(id: UUID(), source: sourceURL?.path ?? sourceName, isDemo: isDemo,
                             destination: outputFolder.appendingPathComponent(outputName).path,
                             configuration: config, created: Date()))
        notice = "Configuration added to queue"
    }

    private func resetSourceSelections() {
        var next = config
        next.audioTracks = nil; next.subtitleTracks = nil; next.externalSubtitle = nil; next.chapterEdits = nil
        config = next
        // Reselecting the same source also clears old source-specific intent;
        // settings undo must not resurrect its discarded caption reference.
        clearSettingsHistory()
    }

    func exportQueue() {
        guard let intent = beginFileRequest() else { return }
        selectFile(.exportQueue, intent: intent) { [weak self] url in
            guard let self, self.consumeSelection(intent), self.finishFileRequest(intent), let url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(intent.snapshot.jobs).write(to: url, options: .atomic)
                self.notice = self.jobs == intent.snapshot.jobs ? "Queue exported" : "Queue snapshot exported. The current queue has changed."
            } catch { self.error = error.localizedDescription }
        }
    }

}
