import Foundation
import Darwin

extension EncodeConfiguration {
    static let maximumExternalCaptions = 8
    var externalCaptions: [ExternalSubtitle] {
        get { (externalSubtitle.map { [$0] } ?? []) + (additionalExternalSubtitles ?? []) }
        set {
            externalSubtitle = newValue.first
            additionalExternalSubtitles = newValue.count > 1 ? Array(newValue.dropFirst()) : nil
        }
    }
    func validateExternalCaptions() throws {
        guard additionalExternalSubtitles == nil || (externalSubtitle != nil && !(additionalExternalSubtitles?.isEmpty ?? true)),
              externalCaptions.count <= Self.maximumExternalCaptions else {
            throw SubRipDocument.failure("Use at most eight ordered external tracks, with a first track before additional references.")
        }
        guard externalCaptions.filter({ $0.playback?.isDefault == true }).count <= 1 else {
            throw SubRipDocument.failure("Choose Default for only one added caption track. Change the other default to Automatic, Optional or Forced.")
        }
        guard container == "MKV" || externalCaptions.allSatisfy({ $0.playback == nil }) else {
            throw SubRipDocument.failure("Explicit caption playback choices require MKV. Choose MKV or set every added caption to Automatic for MP4.")
        }
        var paths = Set<String>()
        for (index, reference) in externalCaptions.enumerated() {
            do {
                try reference.validate()
                guard paths.insert(URL(fileURLWithPath: reference.path).standardizedFileURL.path).inserted else {
                    throw SubRipDocument.failure("The same caption path is selected more than once. Remove the duplicate reference.")
                }
            } catch { throw ExternalCaptionSnapshot.failure(error, reference: reference, index: index) }
        }
    }
    func captureExternalCaptions() async throws -> [ExternalCaptionSnapshot] {
        try validateExternalCaptions()
        var result: [ExternalCaptionSnapshot] = []
        for (index, reference) in externalCaptions.enumerated() {
            try Task.checkCancellation()
            do { result.append(ExternalCaptionSnapshot(reference: reference, document: try await reference.read())) }
            catch is CancellationError { throw CancellationError() }
            catch { throw ExternalCaptionSnapshot.failure(error, reference: reference, index: index) }
        }
        return result
    }
}

struct ExternalCaptionSnapshot: Sendable {
    let reference: ExternalSubtitle
    let document: SubRipDocument
    static func filename(_ index: Int) -> String { index == 0 ? "external.srt" : "external-\(index + 1).srt" }
    static func failure(_ error: Error, reference: ExternalSubtitle, index: Int) -> NativeExportError {
        .invalid("Caption track \(index + 1), \(URL(fileURLWithPath: reference.path).lastPathComponent): " + error.localizedDescription)
    }
}

// Captures intent before the native picker opens. A later callback cannot target
// a row that moved, changed metadata, disappeared or belongs to another source.
struct CaptionFileSelection {
    let references: [ExternalSubtitle]
    let source: String?
    let replacing: Int?

    func applying(_ url: URL, current: EncodeConfiguration, source currentSource: String?) throws -> [ExternalSubtitle] {
        guard url.isFileURL, source != nil, source == currentSource, current.externalCaptions == references else {
            throw SubRipDocument.failure("The source or caption list changed while choosing a file. Choose the intended track again.")
        }
        var result = references
        let previous: ExternalSubtitle?
        if let replacing {
            guard result.indices.contains(replacing) else { throw SubRipDocument.failure("The selected caption row no longer exists.") }
            previous = result[replacing]
        } else {
            guard result.count < EncodeConfiguration.maximumExternalCaptions else { throw SubRipDocument.failure("Eight external tracks are already selected.") }
            previous = nil
        }
        let reference = ExternalSubtitle(path: url.path, language: previous?.language ?? "und",
                                         title: previous?.title ?? "External captions", playback: previous?.playback, access: SubtitleFileAccess(url))
        if let replacing { result[replacing] = reference } else { result.append(reference) }
        var candidate = current; candidate.externalCaptions = result
        try candidate.validateExternalCaptions()
        return result
    }
}

// FFmpeg loads this literal option argument from a file, preserving Unicode bytes
// that Foundation.Process can normalize in arguments. No delimiter escaping.
struct ExternalCaptionTitles {
    static func filename(_ index: Int) -> String { "caption-title-\(index + 1).txt" }
    static func make(_ references: [ExternalSubtitle]) throws -> [Data] {
        guard references.count <= EncodeConfiguration.maximumExternalCaptions else {
            throw SubRipDocument.failure("Invalid caption title track count.")
        }
        return try references.map { reference in
            try reference.validate()
            return Data(("title=" + reference.title).utf8)
        }
    }
    static func write(_ titles: [Data], to directory: URL) async throws {
        guard titles.count <= EncodeConfiguration.maximumExternalCaptions,
              titles.allSatisfy({ $0.count <= 1030 && $0.starts(with: Data("title=".utf8)) }) else {
            throw SubRipDocument.failure("Invalid caption title argument files.")
        }
        for (index, data) in titles.enumerated() {
            try Task.checkCancellation()
            let priority = Task.currentPriority
            let qos: DispatchQoS.QoSClass = priority >= .high ? .userInitiated : priority >= .medium ? .default : priority >= .low ? .utility : .background
            let url = directory.appendingPathComponent(filename(index))
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue(label: "StaxRip.caption-titles", qos: DispatchQoS(qosClass: qos, relativePriority: 0)).async {
                    do {
                        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                        do { try handle.write(contentsOf: data); try handle.close() }
                        catch { try? handle.close(); throw error }
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
            try Task.checkCancellation()
        }
    }
}
