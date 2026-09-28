import SwiftUI
import AVKit
import UniformTypeIdentifiers

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
    private var videoRateOptions: VideoRateOptions?
    var rate: VideoRateOptions {
        get { videoRateOptions ?? VideoRateOptions() }
        set { videoRateOptions = newValue }
    }
    var rateSummary: String { rate.mode == "Constant quality" ? "CRF \(Int(quality))" : "\(rate.bitrate) kb/s" }
    var activeEncoder: String { rate.backend == "Software" ? encoder : "VideoToolbox" }
    var audioTracks: [Int]?
    var subtitleTracks: [Int]?
    private var pictureOptions: PictureOptions?
    var picture: PictureOptions {
        get { pictureOptions ?? PictureOptions() }
        set { pictureOptions = newValue }
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
    @Published var section = "Workspace"
    @Published var tab = "Video"
    @Published var config = EncodeConfiguration()
    @Published var sourceURL: URL?
    @Published var player: AVPlayer?
    @Published var sourceName = "Alpine escape.mov"
    @Published var sourceInfo = "3840 × 2160  ·  24 fps  ·  02:34"
    @Published var loading = false
    @Published var jobs: [QueueJob] = []
    @Published var outputFolder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
    @Published var outputStem = "Alpine escape_encoded"
    @Published var notice = ""
    @Published var error: String?
    @Published var sessionName = "Untitled session"
    @Published var sourceUnavailable = false
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
        loadID = UUID()
        loading = false
        player?.pause()
        player = nil
        sourceURL = nil
        sourceUnavailable = false
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

    func saveSession() {
        let panel = NSSavePanel()
        panel.title = "Save StaxRip Mac session"
        panel.nameFieldStringValue = "StaxRip session.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try sessionSnapshot.write(to: url)
            savedSnapshot = sessionSnapshot
            sessionName = url.deletingPathExtension().lastPathComponent
            notice = "Session saved"
        } catch { self.error = error.localizedDescription }
    }

    func openSession() {
        let panel = NSOpenPanel()
        panel.title = "Open StaxRip Mac session"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try SessionDocument.read(from: url)
            if savedSnapshot != sessionSnapshot {
                let alert = NSAlert()
                alert.messageText = "Replace the current workspace?"
                alert.informativeText = "Open this saved session in place of the current source, settings and queue. Cancel to save your current session first."
                alert.addButton(withTitle: "Open session")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            restoreSession(document)
            sessionName = url.deletingPathExtension().lastPathComponent
        } catch { self.error = error.localizedDescription }
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
            sourceInfo = "Saved source · preview not loaded"
            sourceUnavailable = true
            if FileManager.default.fileExists(atPath: path) { load(sourceURL!, keepOutputName: true) }
        }
        savedSnapshot = document
        notice = "Session restored"
    }

    func chooseSource() {
        let panel = NSOpenPanel()
        panel.title = "Open a source video"
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "mkv") ?? .movie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL, keepOutputName: Bool = false) {
        let id = UUID()
        loadID = id
        loading = true
        notice = ""
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { throw ImportError.noVideo }
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let rate = try await track.load(.nominalFrameRate)
                let duration = try await asset.load(.duration)
                let bounds = CGRect(origin: .zero, size: size).applying(transform)
                guard loadID == id else { return }
                player?.pause()
                player = AVPlayer(url: url)
                if !keepOutputName { config.audioTracks = nil; config.subtitleTracks = nil }
                sourceURL = url
                sourceName = url.lastPathComponent
                if !keepOutputName { outputStem = url.deletingPathExtension().lastPathComponent + "_encoded" }
                sourceUnavailable = false
                let seconds = duration.seconds.isFinite ? max(0, Int(duration.seconds)) : 0
                sourceInfo = "\(Int(abs(bounds.width))) × \(Int(abs(bounds.height)))  ·  \(String(format: "%.2f", rate)) fps  ·  \(String(format: "%02d:%02d", seconds / 60, seconds % 60))"
                loading = false
            } catch {
                guard loadID == id else { return }
                if let tools = FFmpegTools.discover(), let probe = try? await MediaProbe.read(url, tools: tools), let video = probe.video {
                    guard loadID == id else { return }
                    player?.pause(); player = nil
                    if !keepOutputName { config.audioTracks = nil; config.subtitleTracks = nil }
                    sourceURL = url; sourceName = url.lastPathComponent; sourceUnavailable = true
                    loading = false
                    sourceInfo = "\(video.width ?? 0) × \(video.height ?? 0) · \(video.codec_name ?? "unknown") · native preview unavailable"
                    if !keepOutputName { outputStem = url.deletingPathExtension().lastPathComponent + "_encoded" }
                    return
                }
                guard loadID == id else { return }
                loading = false
                self.error = "Neither native preview nor the available media tools could read a video track from this source.\n\n\(error.localizedDescription)"
            }
        }
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.title = "Choose an output folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = outputFolder
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url }
    }

    func applyPreset(_ name: String) {
        config.rate = VideoRateOptions()
        switch name {
        case "Everyday HEVC":
            config.codec = "HEVC"; config.encoder = "x265"; config.quality = 22; config.container = "MP4"
        case "Compact AV1":
            config.codec = "AV1"; config.encoder = "SVT-AV1"; config.quality = 28; config.container = "MKV"
        default:
            config.codec = "H.264"; config.encoder = "x264"; config.quality = 18; config.container = "MP4"
        }
        notice = "\(name) settings applied"
    }

    func addToQueue() {
        guard !loading else { return }
        if let issue = outputIssue { error = issue; return }
        jobs.append(QueueJob(id: UUID(), source: sourceURL?.path ?? sourceName, isDemo: isDemo,
                             destination: outputFolder.appendingPathComponent(outputName).path,
                             configuration: config, created: Date()))
        notice = "Configuration added to queue"
    }

    func exportQueue() {
        let panel = NSSavePanel()
        panel.title = "Export prototype queue"
        panel.nameFieldStringValue = "staxrip-prototype-queue.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(jobs).write(to: url, options: .atomic)
            notice = "Queue exported"
        } catch { self.error = error.localizedDescription }
    }

    enum ImportError: LocalizedError {
        case noVideo
        var errorDescription: String? { "No readable video track was found." }
    }
}
