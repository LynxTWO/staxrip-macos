import Foundation
import Darwin
import CryptoKit

/// Fixed internal read-only native controller. Its stream is consumed independently
/// by the source-dependent package verifier; no release capability or archive action.
enum CompanionMetadataProcess {
    typealias Transaction = OriginalCompanionTransaction
    struct Tool: Sendable {
        fileprivate let url: URL
        fileprivate let sha256: String
        private init(url: URL, sha256: String) { self.url = url; self.sha256 = sha256 }
        #if DEBUG
        /// Explicit generated-test trust only, not application signature provenance.
        static func development(_ url: URL, expectedSHA256: String) throws -> Self {
            guard url.isFileURL, url.lastPathComponent == "staxrip-dolby-metadata-audit",
                  !url.path.utf8.contains(0), expectedSHA256.utf8.count == 64,
                  expectedSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw failure() }
            return .init(url: url, sha256: expectedSHA256)
        }
        #endif
    }
    struct OwnershipFailure: CompanionUnsettledOwnership, LocalizedError {
        let reason: String
        var operationError: (any Error)? = nil
        var pipeCloseRoles: [PipeRole] = []
        var errorDescription: String? { "Native metadata process ownership could not be fully settled. Retain the temporary stage for review." }
    }
    enum PipeRole: String, CaseIterable, Sendable { case stdoutRead, stdoutWrite, stderrRead, stderrWrite }
    struct PipeCloseFailure: CompanionUnsettledOwnership, LocalizedError {
        let operationError: (any Error)?
        let roles: [PipeRole]
        var errorDescription: String? { "Native metadata pipe ownership could not be settled. Retain needed source and stage access for review." }
    }
    struct NullCloseFailure: CompanionUnsettledOwnership, LocalizedError {
        let operationError: (any Error)?
        let closeStatus, closeErrno: Int32
        let reportedAfterActualClose: Bool
        var errorDescription: String? { "Native metadata input ownership could not be settled. Retain needed source and stage access for review." }
    }
    struct Boundary: Sendable {
        var launched: @Sendable (pid_t) -> Void = { _ in }
        var row: @Sendable (Data) -> Void = { _ in }
        var poll: @Sendable () -> Void = {}
        var settled: @Sendable (pid_t) -> Void = { _ in }
        var beforeReceipt: @Sendable () -> Void = {}
        var closed: @Sendable (PipeRole, Int32, Int32) -> Void = { _, _, _ in }
        var refuseClose: @Sendable (PipeRole) -> Bool = { _ in false }
        var nullClosed: @Sendable (Int32, Int32) -> Void = { _, _ in }
        var refuseNullClose: @Sendable () -> Bool = { false }
    }
    #if DEBUG
    @TaskLocal static var testBoundary = Boundary()
    #endif
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock(); private var requested = false
        func cancel() { lock.withLock { requested = true } }
        func check() throws { if lock.withLock({ requested }) { throw CancellationError() } }
    }
    private static func failure() -> NativeExportError { .invalid("Native metadata reader execution refused. No successful receipt.") }
    static func run(tool: Tool, source: URL, timeout: Double = 120,
                    observe: @escaping @Sendable (Data) throws -> Void = { _ in }) async throws -> CompanionMetadataStream.Receipt {
        guard timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        try Task.checkCancellation()
        let cancellation = Cancellation()
        #if DEBUG
        let boundary = testBoundary
        #endif
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // One dedicated worker owns all PID/group signals and reaping.
                DispatchQueue(label: "StaxRip.companion-metadata-owner", qos: .userInitiated).async {
                    let result = Result {
                        #if DEBUG
                        return try runOwned(tool: tool, source: source, observe: observe,
                                        timeout: timeout, checkCancellation: { try cancellation.check() }, boundary: boundary)
                        #else
                        return try runOwned(tool: tool, source: source, observe: observe,
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
    static func runOwned(tool: Tool, source: URL, observe: @escaping (Data) throws -> Void,
                             timeout: Double, checkCancellation: @escaping () throws -> Void, boundary: Boundary = .init()) throws -> CompanionMetadataStream.Receipt {
        guard timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        func check() throws { try checkCancellation(); guard DispatchTime.now().uptimeNanoseconds < deadline else { throw failure() } }
        try check()
        let input = try Pin(source), executable = try Pin(tool.url, executable: true)
        defer { withExtendedLifetime((input,executable)) {} }
        guard try executable.digest(check: check) == tool.sha256 else { throw failure() }
        try input.check(); try executable.check(); try check()
        let fingerprint = SourceFingerprint(sha256: try input.digest(check: check), byteCount: input.bytes)
        let parser = try CompanionMetadataStream(source: fingerprint) { row in
            #if DEBUG
            boundary.row(row)
            #endif
            try check(); try observe(row); try check()
        }
        let stdout = try PipeEnds(), stderr = try PipeEnds()
        var null = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        guard null >= 0 else { throw failure() }
        // Prelaunch/fallback/unresolved ownership remains a separate qualification.
        defer { if null >= 0 { Darwin.close(null) } }
        var nullTerminalEligible = false
        // Same worker scope: existing argv/attribute/action defers unwind BEFORE
        // the selected null close, preserving its prior worker-unwind position.
        let outcome = Result<CompanionMetadataStream.Receipt, Error> {
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
            let args = [tool.url.path, "mkv-summary", source.path]
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
            var uncertain: [PipeRole] = []
            func close(_ pipe: PipeEnds, read: Bool, role: PipeRole) {
                if !pipe.closeChecked(read: read, role: role, boundary: boundary) { uncertain.append(role) }
            }
            func settledError(_ original: any Error) -> any Error {
                guard !uncertain.isEmpty else { return original }
                if original is any CompanionUnsettledOwnership {
                    return OwnershipFailure(reason: "earlier-ownership", operationError: original, pipeCloseRoles: uncertain)
                }
                return PipeCloseFailure(operationError: original, roles: uncertain)
            }
            // Close refusal is deferred until the SAME required process/body settlement.
            close(stdout, read: false, role: .stdoutWrite); close(stderr, read: false, role: .stderrWrite)
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
                        if count == 0 { close(pipe, read: true, role: isOutput ? .stdoutRead : .stderrRead) }
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
                guard !reaped else { throw OwnershipFailure(reason:"unexpected-reap", operationError: original, pipeCloseRoles: uncertain) }
                let signal = Darwin.kill(-pid, SIGKILL), signalError = errno
                let groupStopped = signal == 0 || signalError == ESRCH
                if !groupStopped { _ = Darwin.kill(pid, SIGKILL) }
                close(stdout, read: true, role: .stdoutRead); close(stderr, read: true, role: .stderrRead)
                if !reaped {
                    var waited: pid_t
                    repeat { waited = waitpid(pid, &status, 0) } while waited < 0 && errno == EINTR
                    reaped = waited == pid
                }
                #if DEBUG
                boundary.settled(pid)
                #endif
                guard groupStopped, reaped else { throw OwnershipFailure(reason:"group-\(signalError)-joined-\(reaped)", operationError: original, pipeCloseRoles: uncertain) }
                nullTerminalEligible = !(original is any CompanionUnsettledOwnership)
                throw settledError(original)
            }
            close(stdout, read: true, role: .stdoutRead); close(stderr, read: true, role: .stderrRead)
            nullTerminalEligible = true // Actual normal EOF and owned waitpid above.
            let result: CompanionMetadataStream.Receipt
            do {
                #if DEBUG
                boundary.settled(pid); boundary.beforeReceipt()
                #endif
                try check(); try input.check(); try executable.check()
                guard status & 0x7f == 0 else { throw failure() }
                result = try parser.finish(status: (status >> 8) & 0xff)
                guard try input.digest(check: check) == fingerprint.sha256 else { throw failure() }
                try input.check(); try executable.check(); try check()
            } catch {
                // A supplied checkpoint may carry an earlier shared owner. Its
                // type is not this invocation's pipe-close provenance.
                if error is any CompanionUnsettledOwnership { nullTerminalEligible = false }
                throw settledError(error)
            }
            guard uncertain.isEmpty else { throw PipeCloseFailure(operationError: nil, roles: uncertain) }
            return result
        }
        guard nullTerminalEligible else { return try outcome.get() }
        // A prior shared marker is not additional release authority. Only the
        // selected settled pipe refusal may accompany this terminal transition.
        if case .failure(let error) = outcome, error is any CompanionUnsettledOwnership,
           !(error is PipeCloseFailure) { return try outcome.get() }
        let number = null; null = -1 // Consume before sole close; no retry/fallback.
        let closed = Darwin.close(number), code: Int32 = closed == 0 ? 0 : errno
        #if DEBUG
        boundary.nullClosed(closed, code)
        let reported = closed == 0 && boundary.refuseNullClose()
        #else
        let reported = false
        #endif
        if closed != 0 || reported {
            let cause: (any Error)?
            switch outcome { case .success: cause = nil; case .failure(let error): cause = error }
            throw NullCloseFailure(operationError: cause, closeStatus: closed, closeErrno: code,
                reportedAfterActualClose: reported)
        }
        return try outcome.get()
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
        // Only actual admitted postspawn roles use this checked path. Constructor,
        // prelaunch and fallback/deinit outcomes remain separate qualifications.
        func closeChecked(read reading: Bool, role: PipeRole, boundary: Boundary) -> Bool {
            let number = reading ? read : write
            guard number >= 0 else { return true }
            if reading { read = -1 } else { write = -1 }
            let status = Darwin.close(number), code: Int32 = status == 0 ? 0 : errno
            #if DEBUG
            boundary.closed(role, status, code)
            let reported = status == 0 && boundary.refuseClose(role)
            #else
            let reported = false
            #endif
            return status == 0 && !reported
        }
        func nonblock(_ fd: Int32) throws { let flags = fcntl(fd, F_GETFL); guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw failure() } }
    }
    private final class Pin {
        let url: URL, fd: Int32, initial: stat
        var id: Transaction.FileID { .init(initial) }
        var bytes: Int64 { initial.st_size }
        init(_ url: URL, executable: Bool = false) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            let opened = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
            guard opened >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(opened, &info) == 0, lstat(url.path, &path) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  (1...(executable ? Int64(32 << 20) : Int64(1 << 40))).contains(info.st_size),
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
