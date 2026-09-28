import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Darwin

enum NativePreset: String, CaseIterable, Identifiable {
    case h264HD = "H.264 · 1080p"
    case h264Small = "H.264 · 720p"
    case hevcHD = "HEVC · 1080p"
    var id: String { rawValue }
    var avPreset: String {
        switch self {
        case .h264HD: return AVAssetExportPreset1920x1080
        case .h264Small: return AVAssetExportPreset1280x720
        case .hevcHD: return AVAssetExportPresetHEVC1920x1080
        }
    }
    var detail: String {
        switch self {
        case .h264HD: return "A broadly compatible MP4 using Apple's 1080p H.264/AAC preset."
        case .h264Small: return "A smaller frame for sharing, using Apple's 720p H.264/AAC preset."
        case .hevcHD: return "Efficient compression using Apple's 1080p HEVC/AAC preset."
        }
    }
}

enum NativeExportError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

// Publication uses a same-volume hard link: the completed result becomes visible
// atomically, and an existing destination (including a symlink) is never replaced.
struct ExportPublication {
    static func publish(staged: URL, destination: URL) throws {
        let result = staged.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in Darwin.link(from!, to!) }
        }
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw NativeExportError.invalid("An output already exists at that name. Choose a new name; nothing was overwritten.") }
            throw NativeExportError.invalid("Could not publish the output: \(String(cString: strerror(code))). Choose a local destination that supports hard links.")
        }
    }
}

@MainActor
final class NativeExportService {
    private var session: AVAssetExportSession?
    private var cancelled = false
    private(set) var active = false

    func cancel() {
        cancelled = true
        session?.cancelExport()
    }

    func export(source: URL, destination: URL, preset: NativePreset, progress: @escaping (Double) -> Void = { _ in }) async throws {
        guard !active else { throw NativeExportError.invalid("An export is already running.") }
        active = true
        cancelled = false
        defer { active = false; session = nil }
        guard source.isFileURL, destination.isFileURL, destination.pathExtension.lowercased() == "mp4" else {
            throw NativeExportError.invalid("Choose a local video and an MP4 destination.")
        }
        guard source.resolvingSymlinksInPath().standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else {
            throw NativeExportError.invalid("The output cannot be the source video.")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw NativeExportError.invalid("That output already exists. Choose a new file name.")
        }
        let asset = AVURLAsset(url: source)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw NativeExportError.invalid("The source contains no readable video track.")
        }
        try checkCancellation()
        guard let export = AVAssetExportSession(asset: asset, presetName: preset.avPreset), export.supportedFileTypes.contains(.mp4) else {
            throw NativeExportError.invalid("This video is not compatible with the selected native preset.")
        }
        session = export
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".staxrip-export-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let staged = temporary.appendingPathComponent("video.mp4")
        export.shouldOptimizeForNetworkUse = true
        let poll = Task { @MainActor in
            while !Task.isCancelled {
                progress(Double(export.progress))
                do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
            }
        }
        defer { poll.cancel() }
        do {
            if #available(macOS 15.0, *) {
                try await export.export(to: staged, as: .mp4)
            } else {
                export.outputURL = staged
                export.outputFileType = .mp4
                await withCheckedContinuation { continuation in
                    export.exportAsynchronously { continuation.resume() }
                }
                if export.status != .completed {
                    throw export.error ?? NativeExportError.invalid("The export did not complete.")
                }
            }
        } catch {
            if cancelled || Task.isCancelled { throw CancellationError() }
            throw error
        }
        try checkCancellation()
        // Validate the staged media before making it visible at the chosen name.
        let result = AVURLAsset(url: staged)
        guard !(try await result.loadTracks(withMediaType: .video)).isEmpty else {
            throw NativeExportError.invalid("The exported file contains no readable video.")
        }
        try checkCancellation()
        try ExportPublication.publish(staged: staged, destination: destination)
        progress(1)
    }

    private func checkCancellation() throws {
        if cancelled || Task.isCancelled { throw CancellationError() }
    }
}

@MainActor
final class ExportController: ObservableObject {
    @Published var preset: NativePreset = .h264HD
    @Published var running = false
    @Published var progress = 0.0
    @Published var status = "Ready for your first export"
    @Published var failure: String?
    @Published var result: URL?
    @Published var sourceName = ""
    private let service = NativeExportService()
    private var task: Task<Void, Never>?

    func chooseDestination(source: URL) {
        guard !running else { return }
        let panel = NSSavePanel()
        panel.title = "Export MP4 with Apple media tools"
        panel.prompt = "Export"
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "_native.mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.message = "Choose a new output name. Existing files will not be replaced."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        start(source: source, destination: destination)
    }

    func start(source: URL, destination: URL) {
        guard !running else { return }
        running = true
        progress = 0
        failure = nil
        result = nil
        sourceName = source.lastPathComponent
        status = "Preparing export…"
        let chosenPreset = preset
        task = Task { [self] in
            defer { running = false; task = nil }
            do {
                try await service.export(source: source, destination: destination, preset: chosenPreset) { [weak self] value in
                    self?.progress = value
                    if value > 0 { self?.status = "Exporting \(Int(value * 100))%" }
                }
                result = destination
                status = "Export complete"
            } catch is CancellationError {
                status = "Export cancelled · no output published"
            } catch {
                failure = error.localizedDescription
                status = "Export failed"
            }
        }
    }

    func cancel() {
        guard running else { return }
        status = "Cancelling…"
        service.cancel()
        task?.cancel()
    }
}
