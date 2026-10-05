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
        let operationError: (any Error)?
        let pipeCloseRoles: [PipeRole]
        let pinCloseRoles: [PinRole]
        init(operationError: (any Error)? = nil, pipeCloseRoles: [PipeRole] = [], pinCloseRoles: [PinRole] = []) {
            self.operationError = operationError; self.pipeCloseRoles = pipeCloseRoles; self.pinCloseRoles = pinCloseRoles
        }
        var errorDescription: String? { "Companion process ownership could not be fully settled. Retain the temporary stage for review." }
    }
    enum PipeRole: String, CaseIterable, Sendable {
        case stdinRead, stdinWrite, stdoutRead, stdoutWrite, stderrRead, stderrWrite
    }
    struct PipeCloseFailure: CompanionUnsettledOwnership, LocalizedError {
        let operationError: (any Error)?
        let roles: [PipeRole]
        var errorDescription: String? { "Companion writer pipe ownership could not be fully settled. Retain needed source and stage access for review." }
    }
    enum PinRole: String, CaseIterable, Sendable { case source, stage, executable }
    struct PinCloseFailure: CompanionUnsettledOwnership, LocalizedError {
        let operationError: (any Error)?
        let roles: [PinRole]
        var errorDescription: String? { "Companion writer pin ownership could not be settled. Retain source and stage access for review." }
    }
    // Concrete writer pins, retained independently of thrown errors or completed Tasks.
    // No production release/recovery interface exists.
    final class AdmittedPins: @unchecked Sendable {
        fileprivate let source, stage, executable: Pin
        fileprivate var launched = false, terminalEligible = false
        fileprivate init(source: Pin, stage: Pin, executable: Pin) {
            self.source = source; self.stage = stage; self.executable = executable
        }
        fileprivate func closeChecked(_ boundary: Boundary) -> [PinRole] {
            var uncertain: [PinRole] = []
            for (role, pin) in [(PinRole.source, source), (.stage, stage), (.executable, executable)] {
                if !pin.closeChecked(role, boundary: boundary) { uncertain.append(role) }
            }
            return uncertain
        }
        fileprivate func conflicts(source: URL, stage: URL, executable: URL) -> Bool {
            self.source.url == source || self.stage.url == stage || self.executable.url == executable
        }
        #if DEBUG
        var descriptorsForTesting: [Int32] { [source.fd, stage.fd, executable.fd] }
        #endif
    }
    private final class PinRetention: @unchecked Sendable {
        private let lock = NSLock(); private var values: [AdmittedPins] = []
        func check(source: URL, stage: URL, executable: URL) throws {
            guard !lock.withLock({ values.contains { $0.conflicts(source: source, stage: stage, executable: executable) } }) else { throw failure() }
        }
        func retain(_ pins: AdmittedPins) { lock.withLock { values.append(pins) } }
        func owner(source: URL) -> AdmittedPins? { lock.withLock { values.first { $0.source.url == source } } }
        #if DEBUG
        // Generated isolation only after separately proving owned child settlement.
        // No production recovery, group proof or checked fallback-close claim follows.
        func isolate(_ pins: AdmittedPins) { lock.withLock { values.removeAll { $0 === pins } } }
        #endif
    }
    private static let pinRetention = PinRetention()
    static func retainedPins(source: URL) -> AdmittedPins? { pinRetention.owner(source: source) }
    #if DEBUG
    static func isolateGeneratedPinsForTesting(_ pins: AdmittedPins) { pinRetention.isolate(pins) }
    #endif
    struct Boundary: Sendable {
        var launched: @Sendable (pid_t) -> Void = { _ in }
        var ready: @Sendable () -> Void = {}
        var started: @Sendable () -> Void = {}
        var poll: @Sendable () -> Void = {}
        var settled: @Sendable (pid_t) -> Void = { _ in }
        var beforeReceipt: @Sendable () -> Void = {}
        // DEBUG reports follow each actual close; refusal never masks OS failure.
        var closed: @Sendable (PipeRole, Int32, Int32) -> Void = { _,_,_ in }
        var refuseClose: @Sendable (PipeRole, Int32, Int32) -> Bool = { _,_,_ in false }
        var pinClosed: @Sendable (PinRole, Int32, Int32) -> Void = { _,_,_ in }
        var refusePinClose: @Sendable (PinRole, Int32, Int32) -> Bool = { _,_,_ in false }
        // Controlled report after actual eligible body settlement; not OS process denial.
        var reportPinSettlementUncertainty: @Sendable () -> Bool = { false }
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
        try pinRetention.check(source: source, stage: stage, executable: tool.url)
        var uncertain: [PipeRole] = [], pins: AdmittedPins?
        let result = Result {
            try workBody(tool: tool, source: source, stage: stage, retention: retention,
                timeout: timeout, cancellation: cancellation, boundary: boundary,
                recordClose: { uncertain.append($0) }, admitted: { pins = $0 })
        }
        let original: (any Error)?
        switch result { case .success: original = nil; case .failure(let error): original = error }
        var operationError = original
        if !uncertain.isEmpty {
            if let original = original as? OwnershipFailure {
                operationError = OwnershipFailure(operationError: original, pipeCloseRoles: uncertain)
            } else { operationError = PipeCloseFailure(operationError: original, roles: uncertain) }
        }
        if let pins, pins.launched {
            #if DEBUG
            if pins.terminalEligible && boundary.reportPinSettlementUncertainty() {
                pins.terminalEligible = false
                operationError = OwnershipFailure(operationError: operationError)
            }
            #endif
            if !pins.terminalEligible {
                // No pin close while process ownership remains uncertain. Retention
                // survives even a standalone caller dropping its error and Task.
                pinRetention.retain(pins)
                throw operationError ?? OwnershipFailure()
            }
            let pinRoles = pins.closeChecked(boundary)
            if !pinRoles.isEmpty {
                pinRetention.retain(pins)
                if operationError is OwnershipFailure {
                    throw OwnershipFailure(operationError: operationError, pinCloseRoles: pinRoles)
                }
                throw PinCloseFailure(operationError: operationError, roles: pinRoles)
            }
        }
        // Partial admission/pre-spawn rollback remains a separate qualification.
        if let operationError { throw operationError }
        return try result.get()
    }
    private static func workBody(tool: Tool, source: URL, stage: URL, retention: Transaction.Retention,
        timeout: Double, cancellation: Cancellation, boundary: Boundary,
        recordClose: (PipeRole) -> Void, admitted: (AdmittedPins) -> Void) throws -> CompanionWriterProtocol.Receipt {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        func check() throws { try cancellation.check(); guard DispatchTime.now().uptimeNanoseconds < deadline else { throw failure() } }
        try check()
        let input = try Pin(source), directory = try Pin(stage, directory: true), executable = try Pin(tool.url, executable: true)
        let pins = AdmittedPins(source: input, stage: directory, executable: executable)
        admitted(pins)
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
        pins.launched = true
        func close(_ pipe: PipeEnds, read: Bool, role: PipeRole) {
            if !pipe.closeChecked(read: read, role: role, boundary: boundary) { recordClose(role) }
        }
        close(stdin, read: true, role: .stdinRead)
        close(stdout, read: false, role: .stdoutWrite)
        close(stderr, read: false, role: .stderrWrite)
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
                        close(stdin, read: false, role: .stdinWrite)
                        #if DEBUG
                        boundary.started()
                        #endif
                    }
                }
                for (pipe, isOutput) in [(stdout, true), (stderr, false)] where pipe.read >= 0 {
                    var buffer = [UInt8](repeating: 0, count: 16_384)
                    let count = Darwin.read(pipe.read, &buffer, buffer.count)
                    if count == 0 { close(pipe, read: true, role: isOutput ? .stdoutRead : .stderrRead) }
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
            guard !reaped else {
                close(stdin, read: false, role: .stdinWrite)
                close(stdout, read: true, role: .stdoutRead)
                close(stderr, read: true, role: .stderrRead)
                throw OwnershipFailure(operationError: original)
            }
            let groupStopped = Darwin.kill(-pid, SIGKILL) == 0 || errno == ESRCH
            if !groupStopped { _ = Darwin.kill(pid, SIGKILL) }
            close(stdin, read: false, role: .stdinWrite)
            close(stdout, read: true, role: .stdoutRead)
            close(stderr, read: true, role: .stderrRead)
            if !reaped {
                var waited: pid_t
                repeat { waited = waitpid(pid, &status, 0) } while waited < 0 && errno == EINTR
                reaped = waited == pid
            }
            #if DEBUG
            boundary.settled(pid)
            #endif
            guard groupStopped, reaped else { throw OwnershipFailure(operationError: original) }
            pins.terminalEligible = true
            throw original
        }
        close(stdin, read: false, role: .stdinWrite)
        close(stdout, read: true, role: .stdoutRead)
        close(stderr, read: true, role: .stderrRead)
        pins.terminalEligible = true
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
        /// Finite post-spawn role only. Consume before close, check once, never retry.
        /// Admission rollback/deinit and Pin retirement remain separate qualifications.
        func closeChecked(read reading: Bool, role: PipeRole, boundary: Boundary) -> Bool {
            let fd = reading ? read : write
            guard fd >= 0 else { return true }
            if reading { read = -1 } else { write = -1 }
            let status = Darwin.close(fd)
            var settled = status == 0
            #if DEBUG
            boundary.closed(role, fd, status)
            if boundary.refuseClose(role, fd, status) { settled = false }
            #endif
            return settled
        }
        func nonblock(_ fd: Int32) throws { let flags = fcntl(fd, F_GETFL); guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw failure() } }
    }
    fileprivate final class Pin {
        let url: URL, initial: stat, isDirectory: Bool
        private(set) var fd: Int32
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
        deinit { if fd >= 0 { Darwin.close(fd) } }
        func closeChecked(_ role: PinRole, boundary: Boundary) -> Bool {
            guard fd >= 0 else { return true }
            let consumed = fd; fd = -1
            let status = Darwin.close(consumed)
            #if DEBUG
            boundary.pinClosed(role, consumed, status)
            let reported = boundary.refusePinClose(role, consumed, status)
            #else
            let reported = false
            #endif
            return status == 0 && !reported
        }
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
