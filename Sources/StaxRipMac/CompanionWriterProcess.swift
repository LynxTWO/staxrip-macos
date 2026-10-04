import Foundation
import Darwin
import CryptoKit

/// Unused internal controller. No release executable capability, archive action,
/// independent semantic validator or writer packaging is installed.
enum CompanionWriterProcess {
    typealias Transaction = OriginalCompanionTransaction
    struct Tool: Sendable {
        fileprivate let url: URL
        fileprivate let sha256: String
        private init(url: URL, sha256: String) { self.url = url; self.sha256 = sha256 }
        #if DEBUG
        /// Explicit generated-test trust only, not application signature provenance.
        static func development(_ url: URL, expectedSHA256: String) throws -> Self {
            guard url.isFileURL, url.lastPathComponent == "staxrip-dolby-companion-writer",
                  !url.path.utf8.contains(0), expectedSHA256.utf8.count == 64,
                  expectedSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw failure() }
            return .init(url: url, sha256: expectedSHA256)
        }
        #endif
    }
    /// Nonzero fixed development writer status from actual component ENOSPC.
    /// No receipt, cleanup authorization or release authentication is inferred.
    struct StorageFullFailure: Error, LocalizedError {
        var errorDescription: String? { "Companion storage is full. Free destination space and retry. No result was published." }
    }
    struct OwnershipFailure: CompanionUnsettledOwnership, LocalizedError {
        var errorDescription: String? { "Companion process ownership could not be fully settled. Retain the temporary stage for review." }
    }
    struct Boundary: Sendable {
        var launched: @Sendable (pid_t) -> Void = { _ in }
        var ready: @Sendable () -> Void = {}
        var started: @Sendable () -> Void = {}
        var poll: @Sendable () -> Void = {}
        var settled: @Sendable (pid_t) -> Void = { _ in }
        var beforeReceipt: @Sendable () -> Void = {}
    }
    #if DEBUG
    @TaskLocal static var testBoundary = Boundary()
    #endif
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock(); private var requested = false
        func cancel() { lock.withLock { requested = true } }
        func check() throws { if lock.withLock({ requested }) { throw CancellationError() } }
    }
    private static func failure() -> NativeExportError { .invalid("Companion writer execution refused. No successful receipt.") }
    static func run(tool: Tool, source: URL, stage: URL, retention: Transaction.Retention,
                    timeout: Double = 120) async throws -> CompanionWriterProtocol.Receipt {
        guard timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        try Task.checkCancellation()
        let cancellation = Cancellation()
        #if DEBUG
        let boundary = testBoundary
        #endif
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // One dedicated worker owns all PID/group signals and reaping.
                DispatchQueue(label: "StaxRip.companion-writer-owner", qos: .userInitiated).async {
                    let result = Result {
                        #if DEBUG
                        return try work(tool: tool, source: source, stage: stage, retention: retention,
                                        timeout: timeout, cancellation: cancellation, boundary: boundary)
                        #else
                        return try work(tool: tool, source: source, stage: stage, retention: retention,
                                        timeout: timeout, cancellation: cancellation)
                        #endif
                    }
                    continuation.resume(with: result)
                }
            }
        } onCancel: { cancellation.cancel() }
        try Task.checkCancellation()
        return result
    }
    private static func work(tool: Tool, source: URL, stage: URL, retention: Transaction.Retention,
                             timeout: Double, cancellation: Cancellation, boundary: Boundary = .init()) throws -> CompanionWriterProtocol.Receipt {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        func check() throws { try cancellation.check(); guard DispatchTime.now().uptimeNanoseconds < deadline else { throw failure() } }
        try check()
        let input = try Pin(source), directory = try Pin(stage, directory: true), executable = try Pin(tool.url, executable: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: stage.path), names.isEmpty else { throw failure() }
        guard try executable.digest(check: check) == tool.sha256 else { throw failure() }
        try input.check(); try directory.check(); try executable.check(); try check()
        let operation = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let parser = try CompanionWriterProtocol(operation: operation, retention: retention, sourceID: input.id,
                                                stageID: directory.id, sourceBytes: input.bytes)
        let stdin = try PipeEnds(), stdout = try PipeEnds(), stderr = try PipeEnds()
        try stdin.nonblock(stdin.write); try stdout.nonblock(stdout.read); try stderr.nonblock(stderr.read)
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw failure() }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw failure() }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdin.read, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdout.write, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stderr.write, STDERR_FILENO) == 0 else { throw failure() }
        let mode = retention == .metadataOnly ? "metadata" : "full"
        let args = [tool.url.path, mode, source.path, stage.path, operation, String(input.id.device),
                    String(input.id.inode), String(directory.id.device), String(directory.id.inode)]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString { strdup($0) } } + [nil]
        let environment: [String] = ["PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C"]
        var env: [UnsafeMutablePointer<CChar>?] = environment.map { $0.withCString { strdup($0) } } + [nil]
        defer { for p in argv + env { free(p) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), env.dropLast().allSatisfy({ $0 != nil }) else { throw failure() }
        try check(); try executable.check()
        var pid: pid_t = 0
        let launched = argv.withUnsafeMutableBufferPointer { a in env.withUnsafeMutableBufferPointer { e in
            posix_spawn(&pid, tool.url.path, &actions, &attributes, a.baseAddress!, e.baseAddress!)
        } }
        guard launched == 0, pid > 0 else { throw failure() }
        stdin.closeRead(); stdout.closeWrite(); stderr.closeWrite()
        #if DEBUG
        boundary.launched(pid)
        #endif
        var reaped = false, status: Int32 = 0
        do {
            var control = Data(), sent = 0, stderrBytes = 0
            while true {
                try check()
                #if DEBUG
                boundary.poll()
                #endif
                try check()
                if stdin.write >= 0 && sent < control.count {
                    let count = control.withUnsafeBytes { p in Darwin.write(stdin.write, p.baseAddress!.advanced(by: sent), control.count - sent) }
                    if count > 0 { sent += count }
                    else if count < 0 && errno != EAGAIN && errno != EINTR { throw failure() }
                    if sent == control.count {
                        stdin.closeWrite()
                        #if DEBUG
                        boundary.started()
                        #endif
                    }
                }
                for (pipe, isOutput) in [(stdout, true), (stderr, false)] where pipe.read >= 0 {
                    var buffer = [UInt8](repeating: 0, count: 16_384)
                    let count = Darwin.read(pipe.read, &buffer, buffer.count)
                    if count == 0 { pipe.closeRead() }
                    else if count > 0 {
                        if isOutput {
                            for event in try parser.accept(Data(buffer.prefix(count))) {
                                switch event {
                                case .ready:
                                    #if DEBUG
                                    boundary.ready()
                                    #endif
                                    try check(); try input.check(); try directory.check(); try executable.check()
                                    control = try parser.authorizeStart()
                                case .staged: guard stdin.write < 0 else { throw failure() }
                                }
                            }
                        } else {
                            stderrBytes += count; guard stderrBytes <= 65_536 else { throw failure() }
                        }
                    } else if errno != EAGAIN && errno != EINTR { throw failure() }
                }
                // Do not reap before both EOFs: a pipe-holding descendant must not
                // outlive ownership by allowing reuse of the group leader's PID.
                if stdout.read < 0 && stderr.read < 0 {
                    let waited = waitpid(pid, &status, WNOHANG)
                    if waited == pid { reaped = true; break }
                    if waited < 0 && errno != EINTR { if errno == ECHILD { reaped = true }; throw OwnershipFailure() }
                }
                var descriptors = [pollfd]()
                if stdout.read >= 0 { descriptors.append(pollfd(fd: stdout.read, events: Int16(POLLIN), revents: 0)) }
                if stderr.read >= 0 { descriptors.append(pollfd(fd: stderr.read, events: Int16(POLLIN), revents: 0)) }
                if stdin.write >= 0 && !control.isEmpty { descriptors.append(pollfd(fd: stdin.write, events: Int16(POLLOUT), revents: 0)) }
                let polled = descriptors.withUnsafeMutableBufferPointer { Darwin.poll($0.baseAddress, nfds_t($0.count), 10) }
                if polled < 0 && errno != EINTR { throw failure() }
            }
        } catch {
            let original = error
            // An unexpected external reap removes PID ownership; never signal it.
            guard !reaped else { throw OwnershipFailure() }
            let groupStopped = Darwin.kill(-pid, SIGKILL) == 0 || errno == ESRCH
            if !groupStopped { _ = Darwin.kill(pid, SIGKILL) }
            stdin.closeWrite(); stdout.closeRead(); stderr.closeRead()
            if !reaped {
                var waited: pid_t
                repeat { waited = waitpid(pid, &status, 0) } while waited < 0 && errno == EINTR
                reaped = waited == pid
            }
            #if DEBUG
            boundary.settled(pid)
            #endif
            guard groupStopped, reaped else { throw OwnershipFailure() }
            throw original
        }
        stdin.closeWrite(); stdout.closeRead(); stderr.closeRead()
        #if DEBUG
        boundary.settled(pid); boundary.beforeReceipt()
        #endif
        try check(); try input.check(); try directory.check(); try executable.check()
        guard status & 0x7f == 0 else { throw failure() }
        let exitStatus = (status >> 8) & 0xff
        if exitStatus == 28 { throw StorageFullFailure() }
        let result = try parser.finish(status: exitStatus)
        try check(); return result
    }
    private final class PipeEnds {
        var read: Int32, write: Int32
        init() throws {
            var fds: [Int32] = [-1, -1]
            guard Darwin.pipe(&fds) == 0 else { throw failure() }
            read = fds[0]; write = fds[1]
            guard fcntl(read, F_SETFD, FD_CLOEXEC) == 0, fcntl(write, F_SETFD, FD_CLOEXEC) == 0,
                  fcntl(write, F_SETNOSIGPIPE, 1) == 0 else {
                Darwin.close(read); Darwin.close(write); read = -1; write = -1; throw failure()
            }
        }
        deinit { closeRead(); closeWrite() }
        func closeRead() { if read >= 0 { Darwin.close(read); read = -1 } }
        func closeWrite() { if write >= 0 { Darwin.close(write); write = -1 } }
        func nonblock(_ fd: Int32) throws { let flags = fcntl(fd, F_GETFL); guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw failure() } }
    }
    private final class Pin {
        let url: URL, fd: Int32, initial: stat, isDirectory: Bool
        var id: Transaction.FileID { .init(initial) }
        var bytes: Int64 { initial.st_size }
        init(_ url: URL, directory: Bool = false, executable: Bool = false) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            let opened = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW | (directory ? O_DIRECTORY : 0))
            guard opened >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(opened, &info) == 0, lstat(url.path, &path) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(directory ? S_IFDIR : S_IFREG),
                  directory ? info.st_uid == geteuid() && info.st_mode & 0o7777 == 0o700 : (1...(executable ? Int64(32 << 20) : Int64(1 << 40))).contains(info.st_size),
                  !executable || info.st_mode & 0o111 != 0, Self.same(info, path, directory: directory) else {
                Darwin.close(opened); throw failure()
            }
            self.url = url; fd = opened; initial = info; isDirectory = directory
        }
        deinit { Darwin.close(fd) }
        private static func same(_ a: stat, _ b: stat, directory: Bool) -> Bool {
            Transaction.FileID(a) == Transaction.FileID(b) && a.st_mode == b.st_mode && a.st_uid == b.st_uid &&
                (directory || (a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
                    a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
                    a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec))
        }
        func check() throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, lstat(url.path, &path) == 0,
                  Self.same(initial, info, directory: isDirectory), Self.same(initial, path, directory: isDirectory) else { throw failure() }
        }
        func digest(check: () throws -> Void) throws -> String {
            var hasher = SHA256(), offset: Int64 = 0, buffer = [UInt8](repeating: 0, count: 1 << 20)
            while offset < bytes {
                try check(); let count = pread(fd, &buffer, min(buffer.count, Int(bytes - offset)), offset)
                guard count > 0 else { throw failure() }; hasher.update(data: Data(buffer.prefix(count))); offset += Int64(count)
            }
            try check(); try self.check(); return DolbyInspection.hex(hasher.finalize())
        }
    }
}
