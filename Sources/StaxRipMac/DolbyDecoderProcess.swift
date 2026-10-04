import Foundation
import Darwin
import CryptoKit

/// Unused development-only decoder owner. Fixed caller-captured executable/library
/// identities are not release authentication, hardened loading or frame association.
enum DolbyDecoderProcess {
    typealias Transaction = OriginalCompanionTransaction
    struct Tool: Sendable {
        fileprivate let url: URL
        fileprivate let sha256: String
        fileprivate let librarySHA256: [String:String]
        fileprivate let versions: [UInt64]
        private init(url: URL, sha256: String, libraries: [String:String], versions: [UInt64]) { self.url=url; self.sha256=sha256; self.librarySHA256=libraries; self.versions=versions }
        #if DEBUG
        /// Explicit generated-test trust only, not application signature provenance.
        static func development(_ url: URL, expectedSHA256: String, libraries: [String:String], versions: [UInt64]) throws -> Self {
            guard url.isFileURL, url.lastPathComponent == "reference", url.deletingLastPathComponent().lastPathComponent == "Helpers",
                  !url.path.utf8.contains(0), Set(libraries.keys) == ["libavcodec.63.dylib","libavformat.63.dylib","libavutil.61.dylib"],
                  versions.count == 3, versions.allSatisfy({ (1...UInt64(UInt32.max)).contains($0) }) else { throw failure() }
            for digest in [expectedSHA256] + Array(libraries.values) { _ = try DolbyInspection.hash(digest) }
            return .init(url:url,sha256:expectedSHA256,libraries:libraries,versions:versions)
        }
        #endif
    }
    struct OwnershipFailure: CompanionUnsettledOwnership, LocalizedError {
        let reason: String
        var errorDescription: String? { "Development decoder process ownership could not be fully settled. Retain needed source and temporary access for review." }
    }
    struct Boundary: Sendable {
        var launched: @Sendable (pid_t) -> Void = { _ in }
        var row: @Sendable (Data) -> Void = { _ in }
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
    private static func failure() -> NativeExportError { .invalid("Development decoder reader execution refused. No settled frame result.") }
    static func run(tool: Tool, source: URL, threads: Int = 4, timeout: Double = 120,
                    observe: @escaping @Sendable (Data) throws -> Void = { _ in }) async throws -> DolbyDecoderStream.Receipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        try Task.checkCancellation()
        let cancellation = Cancellation()
        #if DEBUG
        let boundary = testBoundary
        #endif
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // One dedicated worker owns all PID/group signals and reaping.
                DispatchQueue(label: "StaxRip.development-decoder-owner", qos: .userInitiated).async {
                    let result = Result {
                        #if DEBUG
                        return try runOwned(tool: tool, source: source, threads: threads, observe: observe,
                                        timeout: timeout, checkCancellation: { try cancellation.check() }, boundary: boundary)
                        #else
                        return try runOwned(tool: tool, source: source, threads: threads, observe: observe,
                                        timeout: timeout, checkCancellation: { try cancellation.check() })
                        #endif
                    }
                    continuation.resume(with: result)
                }
            }
        } onCancel: { cancellation.cancel() }
        try Task.checkCancellation()
        return result
    }
    /// Called synchronously only on an already owned worker; never starts another worker.
    private static func runOwned(tool: Tool, source: URL, threads: Int, observe: @escaping (Data) throws -> Void,
                             timeout: Double, checkCancellation: @escaping () throws -> Void, boundary: Boundary = .init()) throws -> DolbyDecoderStream.Receipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        func check() throws { try checkCancellation(); guard DispatchTime.now().uptimeNanoseconds < deadline else { throw failure() } }
        try check()
        let input = try Pin(source), executable = try Pin(tool.url, executable: true)
        defer { withExtendedLifetime((input,executable)) {} }
        guard try executable.digest(check: check) == tool.sha256 else { throw failure() }
        try input.check(); try executable.check(); try check()
        let directory = tool.url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks",isDirectory:true)
        var libraries = [(Pin,String)]()
        for name in tool.librarySHA256.keys.sorted() {
            let pin = try Pin(directory.appendingPathComponent(name), library:true)
            let digest = tool.librarySHA256[name]!
            guard try pin.digest(check:check) == digest else { throw failure() }
            libraries.append((pin,digest))
        }
        defer { withExtendedLifetime(libraries) {} }
        let fingerprint = SourceFingerprint(sha256: try input.digest(check: check), byteCount: input.bytes)
        let parser = try DolbyDecoderStream(source: fingerprint, threads:threads, versions:tool.versions) { row in
            #if DEBUG
            boundary.row(row)
            #endif
            try check(); try observe(row); try check()
        }
        let stdout = try PipeEnds(), stderr = try PipeEnds()
        let null = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        guard null >= 0 else { throw failure() }; defer { Darwin.close(null) }
        try stdout.nonblock(stdout.read); try stderr.nonblock(stderr.read)
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw failure() }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw failure() }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, null, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdout.write, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stderr.write, STDERR_FILENO) == 0 else { throw failure() }
        for (pin,_) in libraries { try pin.check() }
        let args = [tool.url.path, source.path, "--threads", String(threads)]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString { strdup($0) } } + [nil]
        let environment: [String] = ["PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C"]
        var env: [UnsafeMutablePointer<CChar>?] = environment.map { $0.withCString { strdup($0) } } + [nil]
        defer { for p in argv + env { free(p) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), env.dropLast().allSatisfy({ $0 != nil }) else { throw failure() }
        try check(); try input.check(); try executable.check()
        var pid: pid_t = 0
        let launched = argv.withUnsafeMutableBufferPointer { a in env.withUnsafeMutableBufferPointer { e in
            posix_spawn(&pid, tool.url.path, &actions, &attributes, a.baseAddress!, e.baseAddress!)
        } }
        guard launched == 0, pid > 0 else { throw failure() }
        stdout.closeWrite(); stderr.closeWrite()
        #if DEBUG
        boundary.launched(pid)
        #endif
        var reaped = false, status: Int32 = 0
        do {
            var stderrBytes = 0
            while true {
                try check()
                #if DEBUG
                boundary.poll()
                #endif
                try check()
                for (pipe, isOutput) in [(stdout, true), (stderr, false)] where pipe.read >= 0 {
                    var buffer = [UInt8](repeating: 0, count: 16_384)
                    let count = Darwin.read(pipe.read, &buffer, buffer.count)
                    if count == 0 { pipe.closeRead() }
                    else if count > 0 {
                        if isOutput {
                            try parser.accept(Data(buffer.prefix(count)))
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
                    if waited < 0 && errno != EINTR { if errno == ECHILD { reaped = true }; throw OwnershipFailure(reason:"unexpected-reap") }
                }
                var descriptors = [pollfd]()
                if stdout.read >= 0 { descriptors.append(pollfd(fd: stdout.read, events: Int16(POLLIN), revents: 0)) }
                if stderr.read >= 0 { descriptors.append(pollfd(fd: stderr.read, events: Int16(POLLIN), revents: 0)) }
                let polled = descriptors.withUnsafeMutableBufferPointer { Darwin.poll($0.baseAddress, nfds_t($0.count), 10) }
                if polled < 0 && errno != EINTR { throw failure() }
            }
        } catch {
            let original = error
            // An unexpected external reap removes PID ownership; never signal it.
            guard !reaped else { throw OwnershipFailure(reason:"unexpected-reap") }
            let signal = Darwin.kill(-pid, SIGKILL), signalError = errno
            let groupStopped = signal == 0 || signalError == ESRCH
            if !groupStopped { _ = Darwin.kill(pid, SIGKILL) }
            stdout.closeRead(); stderr.closeRead()
            if !reaped {
                var waited: pid_t
                repeat { waited = waitpid(pid, &status, 0) } while waited < 0 && errno == EINTR
                reaped = waited == pid
            }
            #if DEBUG
            boundary.settled(pid)
            #endif
            guard groupStopped, reaped else { throw OwnershipFailure(reason:"group-\(signalError)-joined-\(reaped)") }
            throw original
        }
        stdout.closeRead(); stderr.closeRead()
        #if DEBUG
        boundary.settled(pid); boundary.beforeReceipt()
        #endif
        try check(); try input.check(); try executable.check()
        guard status & 0x7f == 0 else { throw failure() }
        let result = try parser.finish(status: (status >> 8) & 0xff)
        guard try input.digest(check: check) == fingerprint.sha256 else { throw failure() }
        guard try executable.digest(check:check) == tool.sha256 else { throw failure() }
        for (pin,digest) in libraries { guard try pin.digest(check:check) == digest else { throw failure() }; try pin.check() }
        try input.check(); try executable.check(); try check(); return result
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
        let url: URL, fd: Int32, initial: stat
        var id: Transaction.FileID { .init(initial) }
        var bytes: Int64 { initial.st_size }
        init(_ url: URL, executable: Bool = false, library: Bool = false) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            let opened = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
            guard opened >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(opened, &info) == 0, lstat(url.path, &path) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  (1...((executable || library) ? Int64(32 << 20) : Int64(1 << 40))).contains(info.st_size),
                  !executable || info.st_mode & 0o111 != 0, Self.same(info, path) else {
                Darwin.close(opened); throw failure()
            }
            self.url = url; fd = opened; initial = info
        }
        deinit { Darwin.close(fd) }
        private static func same(_ a: stat, _ b: stat) -> Bool {
            Transaction.FileID(a) == Transaction.FileID(b) && a.st_mode == b.st_mode && a.st_uid == b.st_uid &&
                (a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
                    a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
                    a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec)
        }
        func check() throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, lstat(url.path, &path) == 0,
                  Self.same(initial, info), Self.same(initial, path) else { throw failure() }
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
