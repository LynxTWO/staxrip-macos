import Foundation
import AVFoundation

struct LoadedSource: Sendable {
    let nativePreview: Bool
    let info: String
}

/// Owns native property reads and propagates cancellation before trying fallback.
enum SourceLoader {
    typealias Reader = @Sendable (URL) async throws -> LoadedSource

    static func read(_ url: URL, tools: FFmpegTools? = FFmpegTools.discover(),
                     nativeReader: Reader = { try await native(AVURLAsset(url: $0)) }) async throws -> LoadedSource {
        try Task.checkCancellation()
        guard url.isFileURL else { throw NativeExportError.invalid("Choose a local source file.") }
        do {
            let result = try await nativeReader(url)
            try Task.checkCancellation()
            return result
        }
        catch {
            if error is CancellationError { throw error }
            try Task.checkCancellation()
            let nativeError = error.localizedDescription
            if let tools {
                do {
                    let probe = try await MediaProbe.read(url, tools: tools)
                    try Task.checkCancellation()
                    if let video = probe.video {
                        return LoadedSource(nativePreview: false,
                            info: "\(video.width ?? 0) × \(video.height ?? 0) · \(video.codec_name ?? "unknown") · native preview unavailable")
                    }
                } catch {
                    if error is CancellationError { throw error }
                    try Task.checkCancellation()
                }
            }
            throw NativeExportError.invalid("Neither native preview nor the available media tools could read a video track from this source.\n\n" + nativeError)
        }
    }

    static func native(_ asset: AVAsset) async throws -> LoadedSource {
        do { return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let tracks = try await asset.loadTracks(withMediaType: .video)
            try Task.checkCancellation()
            guard let track = tracks.first else { throw NativeExportError.invalid("No readable video track was found.") }
            let size = try await track.load(.naturalSize)
            try Task.checkCancellation()
            let transform = try await track.load(.preferredTransform)
            try Task.checkCancellation()
            let rate = try await track.load(.nominalFrameRate)
            try Task.checkCancellation()
            let duration = try await asset.load(.duration)
            try Task.checkCancellation()
            let bounds = CGRect(origin: .zero, size: size).applying(transform)
            return LoadedSource(nativePreview: true, info: summary(width: Double(bounds.width), height: Double(bounds.height),
                                                                   rate: Double(rate), seconds: duration.seconds))
        } onCancel: {
            // Task cancellation alone does not settle all native property requests.
            asset.cancelLoading()
        } } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    static func summary(width: Double, height: Double, rate: Double, seconds: Double) -> String {
        func dimension(_ value: Double) -> String {
            guard let integer = Int(exactly: abs(value).rounded(.towardZero)), integer > 0 else { return "?" }
            return String(integer)
        }
        let cadence = rate.isFinite && rate > 0 ? String(format: "%.2f", rate) + " fps" : "Unknown frame rate"
        let duration: String
        if seconds.isFinite, let count = Int(exactly: max(0, seconds).rounded(.down)) {
            let minutes = count / 60
            duration = (minutes < 10 ? "0" : "") + String(minutes) + ":" + String(format: "%02d", count % 60)
        } else { duration = "Unknown duration" }
        return "\(dimension(width)) × \(dimension(height))  ·  \(cadence)  ·  \(duration)"
    }
}
