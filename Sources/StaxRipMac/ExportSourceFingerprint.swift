import Foundation
import CryptoKit
import Darwin

/// Observes content at check boundaries; this is not an immutable input snapshot.
enum ExportSourceFingerprint {
    #if DEBUG
    // Opt-in timing observation for generated tests; no release-build logging.
    @TaskLocal static var observeBoundary: (@Sendable (String) -> Void)?
    #endif
    typealias Reader = @Sendable (URL, @escaping @Sendable (Int64, Int64) -> Void) async throws -> SourceFingerprint
    static func read(_ url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) async throws -> SourceFingerprint {
        #if DEBUG
        let observe = observeBoundary
        observe?("body entered")
        #endif
        let cancellation = Cancellation()
        // A continuation does not promote a utility worker to its awaiting task's
        // priority. Preserve the request at this boundary without moving I/O onto
        // the caller's actor or raising background requests to foreground work.
        let priority = Task.currentPriority
        let workerQoS: DispatchQoS.QoSClass = priority >= .high ? .userInitiated :
            priority >= .medium ? .default : priority >= .low ? .utility : .background
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                #if DEBUG
                observe?("submitting worker")
                #endif
                // Keep blocking file work out of the shared root queue's work
                // backlog. Each read owns its queue so one stalled filesystem
                // call cannot serialize independent source checks behind it.
                let queue = DispatchQueue(label: "StaxRip.source-fingerprint",
                    qos: DispatchQoS(qosClass: workerQoS, relativePriority: 0))
                queue.async {
                    #if DEBUG
                    observe?("worker entered")
                    #endif
                    // Resume only after the descriptor is closed, including cancellation.
                    continuation.resume(with: Result { try scan(url, cancellation: cancellation, progress: progress) })
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        func check() throws {
            lock.lock(); let value = cancelled; lock.unlock()
            if value { throw CancellationError() }
        }
    }

    private static func failure(_ reason: String) -> NativeExportError {
        .invalid("Source content check: \(reason) Nothing published.")
    }

    private static func scan(_ url: URL, cancellation: Cancellation,
                             progress: @Sendable (Int64, Int64) -> Void) throws -> SourceFingerprint {
        try cancellation.check()
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure("Invalid source path.") }
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
        guard fd >= 0 else { throw failure("Could not open the source (system error \(errno)).") }
        defer { Darwin.close(fd) }
        var initial = stat()
        guard fstat(fd, &initial) == 0, initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), initial.st_size > 0 else {
            throw failure("A nonempty regular file is required.")
        }
        let total = Int64(initial.st_size)
        var readCount: Int64 = 0
        var lastPercent = 0
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        progress(0, total)
        while readCount < total {
            try cancellation.check()
            let requested = Int(min(Int64(buffer.count), total - readCount))
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, requested) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw failure("Source changed or could not be read completely.") }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count])) }
            readCount += Int64(count)
            let percent = Int(Double(readCount) / Double(total) * 100)
            if percent > lastPercent {
                lastPercent = percent
                progress(readCount, total)
            }
        }
        try cancellation.check()
        var final = stat(), path = stat()
        guard fstat(fd, &final) == 0, fstatat(AT_FDCWD, url.path, &path, 0) == 0,
              final.st_size == initial.st_size,
              final.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
              final.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec,
              final.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec,
              path.st_dev == initial.st_dev, path.st_ino == initial.st_ino else {
            throw failure("Source changed during the content check.")
        }
        try cancellation.check()
        return SourceFingerprint(sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(), byteCount: readCount)
    }
}
