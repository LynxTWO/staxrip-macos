import Foundation
import Darwin
import CryptoKit

/// Unused internal integrity settlement. Original track/RPU/index semantics remain
/// independent. No file writes, publication, import or native archive action.
enum CompanionDiskCheck {
    typealias Transaction = OriginalCompanionTransaction
    struct Receipt: Sendable {
        let contents: Transaction.Contents
        let fullContainerMatchesOriginalBytes: Bool
        let originalMetadataSemanticsVerified = false
    }
    struct Boundary: Sendable {
        var progress: @Sendable (String, Int64) -> Void = { _, _ in }
        var beforeFinal: @Sendable () -> Void = {}
    }
    #if DEBUG
    @TaskLocal static var testBoundary = Boundary()
    #endif
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock(); private var requested = false
        func cancel() { lock.withLock { requested = true } }
        func check() throws { if lock.withLock({ requested }) { throw CancellationError() } }
    }
    private static func failure() -> NativeExportError { .invalid("Companion disk verification refused. No successful integrity receipt.") }
    static func verify(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try Task.checkCancellation()
        let cancelled = Cancellation()
        #if DEBUG
        let boundary = testBoundary
        #else
        let boundary = Boundary()
        #endif
        let result: Receipt = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue(label: "StaxRip.companion-disk-check", qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try check(source: source, stage: stage, contents: contents, cancelled: cancelled, boundary: boundary)
                    })
                }
            }
        } onCancel: { cancelled.cancel() }
        try Task.checkCancellation(); return result
    }
    private static func check(source url: URL, stage urlStage: URL, contents: Transaction.Contents,
                              cancelled: Cancellation, boundary: Boundary) throws -> Receipt {
        try cancelled.check()
        let source = try File(url: url, maximum: 1 << 40), directory = try Directory(urlStage)
        let limits = contents.retention.limits, expected = Set(limits.keys)
        guard source.id == contents.sourceID, directory.id == contents.stageID,
              source.bytes == contents.sourceBytes, (1...2_000_000).contains(contents.packets),
              (1...2_000_000).contains(contents.records), (0...4_000_000_000_000).contains(contents.enhancementNALs),
              contents.members.count == expected.count, Set(contents.members.map(\.name)) == expected,
              try directory.names() == expected else { throw failure() }
        let sourceHash = try source.hash(cancelled: cancelled, original: nil, progress: { count in
            #if DEBUG
            boundary.progress("source", count)
            #endif
        })
        guard sourceHash == contents.sourceSHA256 else { throw failure() }
        var opened: [String: File] = [:]
        defer { withExtendedLifetime((source, directory, opened)) {} }
        for member in contents.members {
            try cancelled.check()
            guard let maximum = limits[member.name], (1...maximum).contains(member.byteCount) else { throw failure() }
            let file = try File(name: member.name, directory: directory.fd, maximum: maximum)
            opened[member.name] = file
            guard file.bytes == member.byteCount else { throw failure() }
            let original = member.name == "original-container.mkv" ? source : nil
            if original != nil { guard file.bytes == source.bytes else { throw failure() } }
            let digest = try file.hash(cancelled: cancelled, original: original, progress: { count in
                #if DEBUG
                boundary.progress(member.name, count)
                #endif
            })
            guard digest == member.sha256 else { throw failure() }
        }
        #if DEBUG
        boundary.beforeFinal()
        #endif
        try cancelled.check(); try source.check(url); try directory.check()
        guard try directory.names() == expected else { throw failure() }
        for (name, file) in opened { try cancelled.check(); try file.check(name: name, directory: directory.fd) }
        try cancelled.check()
        return .init(contents: contents, fullContainerMatchesOriginalBytes: contents.retention == .entireContainer)
    }
    private static func same(_ a: stat, _ b: stat) -> Bool {
        Transaction.FileID(a) == Transaction.FileID(b) && a.st_mode == b.st_mode && a.st_uid == b.st_uid &&
            a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
            a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
            a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private final class File {
        let fd: Int32, initial: stat
        var id: Transaction.FileID { .init(initial) }
        var bytes: Int64 { initial.st_size }
        init(url: URL, maximum: Int64) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(descriptor, &info) == 0, lstat(url.path, &path) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), (1...maximum).contains(info.st_size), same(info, path) else {
                Darwin.close(descriptor); throw failure()
            }
            fd = descriptor; initial = info
        }
        init(name: String, directory: Int32, maximum: Int64) throws {
            // Name comes only from the fixed exact membership/receipt schema above.
            let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(descriptor, &info) == 0, fstatat(directory, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == geteuid(),
                  info.st_mode & 0o7777 == 0o600, info.st_nlink == 1, (1...maximum).contains(info.st_size), same(info, path) else {
                Darwin.close(descriptor); throw failure()
            }
            fd = descriptor; initial = info
        }
        deinit { Darwin.close(fd) }
        func check(_ url: URL) throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, lstat(url.path, &path) == 0, same(initial, info), same(initial, path) else { throw failure() }
        }
        func check(name: String, directory: Int32) throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, fstatat(directory, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  same(initial, info), same(initial, path) else { throw failure() }
        }
        private func read(offset: Int64, count: Int, cancelled: Cancellation) throws -> Data {
            var data = Data(count: count), completed = 0
            while completed < count {
                try cancelled.check()
                let n = data.withUnsafeMutableBytes { p in pread(fd, p.baseAddress!.advanced(by: completed), count - completed, offset + Int64(completed)) }
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw failure() }; completed += n; try cancelled.check()
            }
            return data
        }
        func hash(cancelled: Cancellation, original: File?, progress: (Int64) -> Void) throws -> String {
            var hasher = SHA256(), offset: Int64 = 0
            while offset < bytes {
                try cancelled.check()
                let count = Int(min(1 << 20, bytes - offset)), data = try read(offset: offset, count: count, cancelled: cancelled)
                if let original { guard try original.read(offset: offset, count: count, cancelled: cancelled) == data else { throw failure() } }
                hasher.update(data: data); offset += Int64(count); progress(offset); try cancelled.check()
            }
            return DolbyInspection.hex(hasher.finalize())
        }
    }
    private final class Directory {
        let url: URL, fd: Int32, initial: stat
        var id: Transaction.FileID { .init(initial) }
        init(_ url: URL) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(descriptor, &info) == 0, lstat(url.path, &path) == 0, info.st_uid == geteuid(),
                  info.st_mode & 0o7777 == 0o700, same(info, path) else { Darwin.close(descriptor); throw failure() }
            self.url = url; fd = descriptor; initial = info
        }
        deinit { Darwin.close(fd) }
        func check() throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, lstat(url.path, &path) == 0, same(initial, info), same(initial, path) else { throw failure() }
        }
        func names() throws -> Set<String> {
            let copy = fcntl(fd, F_DUPFD_CLOEXEC, 0)
            guard copy >= 0 else { throw failure() }
            guard let entries = fdopendir(copy) else { Darwin.close(copy); throw failure() }
            defer { closedir(entries) }
            rewinddir(entries) // Duplicate descriptors share directory position.
            var result: Set<String> = []
            while true {
                errno = 0
                guard let entry = readdir(entries) else { guard errno == 0 else { throw failure() }; break }
                let count = Int(entry.pointee.d_namlen)
                guard (1...128).contains(count) else { throw failure() }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: count) { String(decoding: UnsafeBufferPointer(start: $0, count: count), as: UTF8.self) }
                }
                if name == "." || name == ".." { continue }
                guard result.count < 16, result.insert(name).inserted else { throw failure() }
            }
            return result
        }
    }
}
