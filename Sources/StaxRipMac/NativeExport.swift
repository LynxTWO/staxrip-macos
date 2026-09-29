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

struct NativeExportCleanupError: LocalizedError {
    let directory: URL
    let publishedOutput: URL?
    let operationError: Error?
    let cleanupError: Error

    var errorDescription: String? {
        let outcome = publishedOutput == nil ? "No output was published." : "The export was saved successfully."
        let operation = operationError.map { " Operation: \($0.localizedDescription)" } ?? ""
        let error = cleanupError as NSError
        return "\(outcome) Temporary export files could not be removed at \(directory.path). \(error.localizedDescription) [\(error.domain):\(error.code)]\(operation)"
    }
}

// Only call this for a directory created by the current export, after its writer
// completion callback. Retry transient removal errors without abandoning cleanup
// when the operation's Task has already been cancelled.
@MainActor
struct NativeExportStaging {
    static func remove(_ directory: URL,
                       removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
                       wait: (Double) async -> Void = { seconds in
                           await withCheckedContinuation { continuation in
                               DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
                           }
                       }) async throws {
        let delays = [0.05, 0.1, 0.2, 0.4, 0.8]
        for attempt in 0...delays.count {
            do { try removeItem(directory); return }
            catch {
                // Foundation can wrap the POSIX cause in an NSCocoaError.
                var cause = error as NSError
                for _ in 0..<8 {
                    guard let underlying = cause.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
                    cause = underlying
                }
                let missing = (cause.domain == NSPOSIXErrorDomain && cause.code == Int(ENOENT)) ||
                    (cause.domain == NSCocoaErrorDomain && cause.code == NSFileNoSuchFileError)
                if missing, !FileManager.default.fileExists(atPath: directory.path) { return }
                let transient = cause.domain == NSPOSIXErrorDomain && [Int(EBUSY), Int(ENOTEMPTY)].contains(cause.code)
                guard transient, attempt < delays.count else { throw error }
                await wait(delays[attempt])
            }
        }
    }
}

@MainActor
final class NativeExportService {
    private let removeStaging: (URL) async throws -> Void

    init(removeStaging: @escaping (URL) async throws -> Void = { try await NativeExportStaging.remove($0) }) {
        self.removeStaging = removeStaging
    }

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

        let staged = temporary.appendingPathComponent("video.mp4")
        export.shouldOptimizeForNetworkUse = true
        let poll = Task { @MainActor in
            while !Task.isCancelled {
                progress(Double(export.progress))
                do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
            }
        }
        defer { poll.cancel() }
        var operationError: Error?
        var publishedOutput: URL?
        do {
            // The async throwing API can resume cancellation while the writer still
            // owns staging files. The completion callback is our cleanup boundary.
            export.outputURL = staged
            export.outputFileType = .mp4
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    export.exportAsynchronously { continuation.resume() }
                }
            } onCancel: {
                export.cancelExport()
            }
            if export.status != .completed {
                throw export.error ?? NativeExportError.invalid("The export did not complete.")
            }
            try checkCancellation()
            // Validate the staged media before making it visible at the chosen name.
            let result = AVURLAsset(url: staged)
            guard !(try await result.loadTracks(withMediaType: .video)).isEmpty else {
                throw NativeExportError.invalid("The exported file contains no readable video.")
            }
            try checkCancellation()
            try ExportPublication.publish(staged: staged, destination: destination)
            publishedOutput = destination
        } catch {
            operationError = cancelled || Task.isCancelled ? CancellationError() : error
        }
        poll.cancel()
        do { try await removeStaging(temporary) }
        catch {
            throw NativeExportCleanupError(directory: temporary, publishedOutput: publishedOutput,
                                           operationError: operationError, cleanupError: error)
        }
        if let operationError { throw operationError }
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
            } catch let error as NativeExportCleanupError {
                result = error.publishedOutput
                failure = error.localizedDescription
                status = error.publishedOutput == nil ? "Export stopped · temporary files remain" : "Export saved · temporary files remain"
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
