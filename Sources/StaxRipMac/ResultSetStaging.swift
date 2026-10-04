import Foundation
import CryptoKit
import Darwin

/// Internal publication boundary, not an archive format or a semantic HDR verifier.
/// The caller owns and must settle every writer before supplying component receipts.
final class ResultSetStaging: @unchecked Sendable {
    struct Member: Sendable {
        let name: String
        let byteCount: Int64
        let sha256: String
    }
    struct Published: Sendable {
        let directory: URL
        let verifiedBytes: Int64
        let memberCount: Int
    }
    private enum State { case available, publishing, published, discarded }
    private let lock = NSLock()
    private var state: State = .available
    private let parent: URL
    private let parentFD: Int32
    private let directoryFD: Int32
    private let name: String
    private let identity: stat

    #if DEBUG
    // Generated filesystem mutations only; absent from optimized product code.
    struct TestBoundary: Sendable {
        var progress: @Sendable (Int64) throws -> Void = { _ in }
        var beforeCommit: @Sendable () throws -> Void = {}
        var afterCommit: @Sendable () -> Void = {}
    }
    @TaskLocal static var testBoundary = TestBoundary()
    #endif

    private static func failure(_ message: String) -> NativeExportError {
        .invalid("Result set: \(message)")
    }
    private static func safeName(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...120).contains(bytes.count) && bytes.first != 46 && bytes.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
        }
    }

    static func create(in parent: URL) throws -> ResultSetStaging {
        guard parent.isFileURL, !parent.path.utf8.contains(0) else { throw failure("Invalid parent directory.") }
        let p = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard p >= 0 else { throw failure("Cannot open destination parent (system error \(errno)).") }
        let name = ".staxrip-result-" + UUID().uuidString
        guard mkdirat(p, name, 0o700) == 0 else {
            let code = errno; Darwin.close(p)
            throw failure("Cannot create owned stage (system error \(code)).")
        }
        let d = openat(p, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        var value = stat()
        guard d >= 0, fstat(d, &value) == 0, value.st_uid == geteuid(), value.st_mode & 0o777 == 0o700 else {
            if d >= 0 { Darwin.close(d) }
            // Never remove a directory whose identity we did not establish.
            Darwin.close(p)
            throw failure("Owned stage could not be established; its temporary directory may remain.")
        }
        return ResultSetStaging(parent: parent, parentFD: p, directoryFD: d, name: name, identity: value)
    }

    private init(parent: URL, parentFD: Int32, directoryFD: Int32, name: String, identity: stat) {
        self.parent = parent; self.parentFD = parentFD; self.directoryFD = directoryFD
        self.name = name; self.identity = identity
    }
    // Cleanup is explicit so a failed removal cannot be silently described as success.
    deinit { Darwin.close(directoryFD); Darwin.close(parentFD) }

    func fileURL(_ filename: String) throws -> URL {
        try lock.withLock {
            guard state == .available, Self.safeName(filename) else { throw Self.failure("Stage or filename is unavailable.") }
            try checkIdentity()
            return parent.appendingPathComponent(name).appendingPathComponent(filename)
        }
    }

    private static func sameObject(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode && a.st_uid == b.st_uid
    }
    private static func unchanged(_ a: stat, _ b: stat) -> Bool {
        sameObject(a, b) && a.st_size == b.st_size && a.st_nlink == b.st_nlink &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private func checkIdentity() throws {
        var path = stat(), descriptor = stat(), p = stat(), currentParent = stat()
        guard fstatat(parentFD, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(directoryFD, &descriptor) == 0, Self.sameObject(identity, path), Self.sameObject(identity, descriptor),
              fstat(parentFD, &p) == 0, lstat(parent.path, &currentParent) == 0,
              Self.sameObject(p, currentParent) else {
            throw Self.failure("Stage or parent identity changed. Nothing published or removed.")
        }
    }

    private func names(limit: Int) throws -> Set<String> {
        // A fresh open description prevents repeated enumeration sharing an offset.
        let fd = openat(directoryFD, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw Self.failure("Cannot enumerate stage.") }
        guard let directory = fdopendir(fd) else { Darwin.close(fd); throw Self.failure("Cannot enumerate stage.") }
        defer { closedir(directory) }
        var result = Set<String>()
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw Self.failure("Stage enumeration failed.") }
                return result
            }
            let value = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if value == "." || value == ".." { continue }
            guard result.count < limit, result.insert(value).inserted else { throw Self.failure("Stage membership exceeds its bound.") }
        }
    }

    /// Removes only this stage's immediate entries, never following links or recursing.
    /// A published directory or active worker is never removed by this operation.
    func discard() throws {
        try lock.withLock {
            guard state == .available else { throw Self.failure("Cannot discard a settled or active stage.") }
            try checkIdentity()
            let entries = try names(limit: 64)
            for entry in entries {
                guard unlinkat(directoryFD, entry, 0) == 0 else {
                    throw Self.failure("Owned temporary cleanup failed (system error \(errno)); temporary entries remain.")
                }
            }
            try checkIdentity()
            guard unlinkat(parentFD, name, AT_REMOVEDIR) == 0 else {
                throw Self.failure("Owned temporary directory cleanup failed (system error \(errno)).")
            }
            state = .discarded
        }
    }

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private enum State { case active, cancelled, committing, committed }
        private var state: State = .active
        func cancel() { lock.withLock { if state == .active { state = .cancelled } } }
        func check() throws { try lock.withLock { if state == .cancelled { throw CancellationError() } } }
        func commit(_ operation: () throws -> Void) throws {
            try lock.withLock {
                if state == .cancelled { throw CancellationError() }
                state = .committing
            }
            // Commit admission is the cancellation boundary. Do not hold this lock
            // across a filesystem call: cancellation must not block the caller's actor.
            // Once admitted, await the syscall and report its real success or failure.
            try operation()
            lock.withLock { state = .committed }
        }
    }

    func publish(as destinationName: String, members: [Member]) async throws -> Published {
        guard Self.safeName(destinationName), (3...16).contains(members.count),
              members.contains(where: { $0.name == "manifest.json" && $0.byteCount <= 1_048_576 }),
              Set(members.map(\.name)).count == members.count,
              members.allSatisfy({ Self.safeName($0.name) && (1...Int64(1 << 40)).contains($0.byteCount) &&
                  $0.sha256.utf8.count == 64 && $0.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) }) else {
            throw Self.failure("Invalid requested component receipts.")
        }
        let cancellation = Cancellation()
        #if DEBUG
        let boundary = Self.testBoundary
        #endif
        let priority = Task.currentPriority
        let qos: DispatchQoS.QoSClass = priority >= .high ? .userInitiated : priority >= .medium ? .default : priority >= .low ? .utility : .background
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try lock.withLock {
                guard state == .available else { throw Self.failure("Stage already has an operation or is settled.") }
                state = .publishing
            }
            return try await withCheckedThrowingContinuation { continuation in
                let worker = DispatchQueue(label: "StaxRip.result-set", qos: DispatchQoS(qosClass: qos, relativePriority: 0))
                worker.async {
                    let result = Result {
                        try self.verifyAndCommit(destinationName: destinationName, members: members, cancellation: cancellation,
                            progress: { count in
                                #if DEBUG
                                try boundary.progress(count)
                                #endif
                            }, beforeCommit: {
                                #if DEBUG
                                try boundary.beforeCommit()
                                #endif
                            }, afterCommit: {
                                #if DEBUG
                                boundary.afterCommit()
                                #endif
                            })
                    }
                    self.lock.withLock {
                        switch result {
                        case .success: self.state = .published
                        case .failure: self.state = .available
                        }
                    }
                    // All verification descriptors have closed before the waiter can clean up.
                    continuation.resume(with: result)
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    private func verifyAndCommit(destinationName: String, members: [Member], cancellation: Cancellation,
                                 progress: (Int64) throws -> Void, beforeCommit: () throws -> Void,
                                 afterCommit: () -> Void) throws -> Published {
        try cancellation.check(); try checkIdentity()
        let expected = Set(members.map(\.name))
        guard try names(limit: 16) == expected else { throw Self.failure("Requested components are missing or unexpected entries exist. Nothing published.") }
        var initialDirectory = stat()
        guard fstat(directoryFD, &initialDirectory) == 0 else { throw Self.failure("Cannot inspect stage.") }
        var files: [(Member, Int32, stat)] = []
        defer { for (_, fd, _) in files { Darwin.close(fd) } }
        var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        try progress(0)
        for member in members {
            try cancellation.check()
            let fd = openat(directoryFD, member.name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
            guard fd >= 0 else { throw Self.failure("Cannot open a requested component. Nothing published.") }
            var value = stat()
            guard fstat(fd, &value) == 0, value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  value.st_uid == geteuid(), value.st_nlink == 1, value.st_size == member.byteCount else {
                Darwin.close(fd); throw Self.failure("A component is linked, special, missing or has changed length. Nothing published.")
            }
            files.append((member, fd, value))
            var hasher = SHA256(), count: Int64 = 0
            while count < member.byteCount {
                try cancellation.check()
                let requested = Int(min(Int64(buffer.count), member.byteCount - count))
                let bytes = buffer.withUnsafeMutableBytes {
                    Darwin.read(fd, $0.baseAddress!, requested)
                }
                if bytes < 0 && errno == EINTR { continue }
                guard bytes > 0 else { throw Self.failure("A component could not be read completely. Nothing published.") }
                buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<bytes])) }
                count += Int64(bytes); total += Int64(bytes)
                try progress(total)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == member.sha256 else { throw Self.failure("Component integrity mismatch. Nothing published.") }
        }
        try beforeCommit()
        try cancellation.check(); try checkIdentity()
        guard try names(limit: 16) == expected else { throw Self.failure("Stage membership changed. Nothing published.") }
        var finalDirectory = stat()
        guard fstat(directoryFD, &finalDirectory) == 0, Self.unchanged(initialDirectory, finalDirectory) else {
            throw Self.failure("Stage changed during verification. Nothing published.")
        }
        for (member, fd, initial) in files {
            var descriptor = stat(), path = stat()
            guard fstat(fd, &descriptor) == 0, fstatat(directoryFD, member.name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  Self.unchanged(initial, descriptor), Self.unchanged(initial, path) else {
                throw Self.failure("Component changed during verification. Nothing published.")
            }
        }
        try cancellation.commit {
            guard renameatx_np(parentFD, name, parentFD, destinationName, UInt32(RENAME_EXCL)) == 0 else {
                let code = errno
                if code == EEXIST { throw Self.failure("A result already exists at that name. Nothing overwritten or published.") }
                throw Self.failure("Exclusive result publication failed (system error \(code)). Nothing published; no fallback attempted.")
            }
        }
        afterCommit()
        return Published(directory: parent.appendingPathComponent(destinationName), verifiedBytes: total, memberCount: members.count)
    }
}
