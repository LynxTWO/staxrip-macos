import Foundation
import CryptoKit
import Darwin

/// Observes content at check boundaries; this is not an immutable input snapshot.
enum ExportSourceFingerprint {
    #if DEBUG
    // Opt-in timing observation for generated tests; no release-build logging.
    @TaskLocal static var observeBoundary: (@Sendable (String) -> Void)?
    #endif
    struct CopyCloseFailure: CompanionUnsettledOwnership {
        let status: Int32, code: Int32, cause: Error?
    }
    struct CopyIdentity {
        let value: stat
        func matches(_ other: stat, published: Bool = false) -> Bool {
            value.st_dev == other.st_dev && value.st_ino == other.st_ino && value.st_size == other.st_size &&
            value.st_mode == other.st_mode && value.st_mtimespec.tv_sec == other.st_mtimespec.tv_sec &&
            value.st_mtimespec.tv_nsec == other.st_mtimespec.tv_nsec &&
            (published || (value.st_ctimespec.tv_sec == other.st_ctimespec.tv_sec && value.st_ctimespec.tv_nsec == other.st_ctimespec.tv_nsec))
        }
    }
    private final class CopyInspection: @unchecked Sendable {
        let role: DolbyCopyNative.Role?, timeBase: HDRFraction?, reportClose: Bool
        var receipt: DolbyCopyNative.Receipt?
        var identity: CopyIdentity?
        init(role: DolbyCopyNative.Role?, timeBase: HDRFraction?, reportClose: Bool) {
            self.role = role; self.timeBase = timeBase; self.reportClose = reportClose
        }
    }
    @TaskLocal private static var copyInspection: CopyInspection?
    #if DEBUG
    @TaskLocal static var reportCopyClose = false
    #endif
    // Intermediate conversion files/tool identity: checked close, no native container claim.
    static func readCopyInput(_ url:URL) async throws -> SourceFingerprint {
        #if DEBUG
        let report=reportCopyClose
        #else
        let report=false
        #endif
        let inspection=CopyInspection(role:nil,timeBase:nil,reportClose:report)
        return try await $copyInspection.withValue(inspection) {try await read(url)}
    }
    static func readCopy(_ url: URL, role: DolbyCopyNative.Role, timeBase: HDRFraction) async throws -> (SourceFingerprint, DolbyCopyNative.Receipt) {
        let result = try await readCopyIdentity(url, role: role, timeBase: timeBase)
        return (result.0, result.1)
    }
    static func readCopyIdentity(_ url: URL, role: DolbyCopyNative.Role, timeBase: HDRFraction) async throws -> (SourceFingerprint, DolbyCopyNative.Receipt, CopyIdentity) {
        #if DEBUG
        let report = reportCopyClose
        #else
        let report = false
        #endif
        let inspection = CopyInspection(role: role, timeBase: timeBase, reportClose: report)
        let fingerprint = try await $copyInspection.withValue(inspection) { try await read(url) }
        guard let receipt = inspection.receipt, let identity = inspection.identity else { throw DolbyCopyNative.failure() }
        return (fingerprint, receipt, identity)
    }
    typealias Reader = @Sendable (URL, @escaping @Sendable (Int64, Int64) -> Void) async throws -> SourceFingerprint
    static func read(_ url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) async throws -> SourceFingerprint {
        #if DEBUG
        let observe = observeBoundary
        observe?("body entered")
        #endif
        let cancellation = Cancellation()
        let copy = copyInspection
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
                    continuation.resume(with: Result { try scan(url, cancellation: cancellation, progress: progress, copy: copy) })
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
                             progress: @Sendable (Int64, Int64) -> Void, copy: CopyInspection?) throws -> SourceFingerprint {
        func refusal(_ reason: String) -> NativeExportError {
            copy == nil ? failure(reason) : .invalid("Copy content check: " + reason)
        }
        try cancellation.check()
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw refusal("Invalid source path.") }
        var fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOCTTY | (copy == nil ? 0 : O_NOFOLLOW))
        guard fd >= 0 else { throw refusal("Could not open the source (system error \(errno)).") }
        defer { if copy == nil { Darwin.close(fd) } }
        let result = Result<SourceFingerprint, Error> {
        var initial = stat()
        guard fstat(fd, &initial) == 0, initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), initial.st_size > 0 else {
            throw refusal("A nonempty regular file is required.")
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
            guard count > 0 else { throw refusal("Source changed or could not be read completely.") }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count])) }
            readCount += Int64(count)
            let percent = Int(Double(readCount) / Double(total) * 100)
            if percent > lastPercent {
                lastPercent = percent
                progress(readCount, total)
            }
        }
        try cancellation.check()
        if let copy,let role=copy.role,let timeBase=copy.timeBase {
            let view = CompanionDiskCheck.ReadView(sourceBytes: total, source: { offset, count in
                guard offset >= 0, count >= 0, offset <= total, Int64(count) <= total - offset else { throw DolbyCopyNative.failure() }
                var bytes = Data(count: count), done = 0
                while done < count {
                    try cancellation.check()
                    let n = bytes.withUnsafeMutableBytes { Darwin.pread(fd, $0.baseAddress!.advanced(by: done), count - done, offset + Int64(done)) }
                    if n < 0, errno == EINTR { continue }
                    guard n > 0 else { throw DolbyCopyNative.failure() }; done += n
                }
                return bytes
            }, component: { _ in throw DolbyCopyNative.failure() }, checkpoint: { try cancellation.check() })
            copy.receipt = try DolbyCopyNative.read(view, role: role, timeBase: timeBase)
        }
        var final = stat(), path = stat()
        guard fstat(fd, &final) == 0, fstatat(AT_FDCWD, url.path, &path, 0) == 0,
              final.st_size == initial.st_size,
              final.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
              final.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec,
              final.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec,
              path.st_dev == initial.st_dev, path.st_ino == initial.st_ino else {
            throw refusal("Source changed during the content check.")
        }
        try cancellation.check()
        copy?.identity = CopyIdentity(value: final)
        return SourceFingerprint(sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(), byteCount: readCount)
        }
        if let copy {
            // This worker has finished every local read; no helper is active at
            // this boundary. Consume before one close, including body refusal.
            let consumed = fd; fd = -1
            let status = Darwin.close(consumed), code = status == 0 ? 0 : errno
            if status != 0 || copy.reportClose {
                let cause: Error?; if case .failure(let error) = result { cause = error } else { cause = nil }
                throw CopyCloseFailure(status: status, code: code, cause: cause)
            }
        }
        return try result.get()
    }
}
