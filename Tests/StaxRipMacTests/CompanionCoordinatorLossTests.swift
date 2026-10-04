import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

/// A generated test runner, never a runtime archive/recovery bridge. Immediate POSIX exit is
/// self-directed only after the parent grants an acknowledged, joined boundary.
@Suite(.serialized)
struct CompanionCoordinatorLossTests {
    typealias T = OriginalCompanionTransaction
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var writer: pid_t = 0, writerJoined: pid_t = 0, reader: pid_t = 0, readerJoined: pid_t = 0
        private var value: T.Contents?, directory: URL?
        func launched(_ p: pid_t, reader r: Bool) { lock.withLock { if r { reader = p } else { writer = p } } }
        func joined(_ p: pid_t, reader r: Bool) { lock.withLock { if r { readerJoined = p } else { writerJoined = p } } }
        func set(_ c: T.Contents, _ d: URL) { lock.withLock { value = c; directory = d } }
        func snapshot() throws -> (T.Contents, URL, [pid_t]) {
            try lock.withLock {
                guard writer > 0, reader > 0, writer == writerJoined, reader == readerJoined,
                      let value, let directory else { throw NativeExportError.invalid("Generated helper settlement missing") }
                for p in [writer, reader] {
                    var status: Int32 = 0
                    guard waitpid(p, &status, WNOHANG) == -1, errno == ECHILD else {
                        throw NativeExportError.invalid("Generated helper not joined")
                    }
                }
                return (value, directory, [writer, reader])
            }
        }
    }
    /// One caller owns waitpid. No Foundation reaper or monitor competes with it.
    private final class Coordinator {
        let pid: pid_t
        private let input: FileHandle
        private let output: FileHandle
        private(set) var status: Int32?
        init(executable: URL, arguments: [String], environment: [String: String], log: URL) throws {
            let gate = Pipe(); output = try FileHandle(forWritingTo: log); input = gate.fileHandleForWriting
            var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
            try #require(posix_spawn_file_actions_init(&actions) == 0)
            defer { posix_spawn_file_actions_destroy(&actions) }
            try #require(posix_spawnattr_init(&attributes) == 0)
            defer { posix_spawnattr_destroy(&attributes) }
            try #require(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0)
            try #require(posix_spawn_file_actions_adddup2(&actions, gate.fileHandleForReading.fileDescriptor, STDIN_FILENO) == 0)
            try #require(posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDOUT_FILENO) == 0)
            try #require(posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDERR_FILENO) == 0)
            let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
            let envp = environment.sorted { $0.key < $1.key }.map { strdup($0.key + "=" + $0.value) } + [nil]
            defer { for v in argv + envp { if let v { free(v) } } }
            var child: pid_t = 0
            let code = argv.withUnsafeBufferPointer { a in envp.withUnsafeBufferPointer { e in
                posix_spawn(&child, executable.path, &actions, &attributes, a.baseAddress!, e.baseAddress!)
            } }
            try #require(code == 0 && child > 0); pid = child
            try gate.fileHandleForReading.close()
        }
        deinit { try? input.close(); try? output.close() }
        func reapIfExited() throws -> Bool {
            if status != nil { return true }
            var observed: Int32 = 0
            let result = waitpid(pid, &observed, WNOHANG)
            if result < 0 && errno == EINTR { return false }
            try #require(result == 0 || result == pid)
            if result == pid { status = observed; return true }
            return false
        }
        func grant() throws { try input.write(contentsOf: Data([0x4b])); try input.close() }
        func closeInput() { try? input.close() }
        func assertExitedAndJoined() throws {
            let value = try #require(status)
            try #require(value & 0x7f == 0 && (value >> 8) & 0xff == 86)
            var again: Int32 = 0
            try #require(waitpid(pid, &again, WNOHANG) == -1 && errno == ECHILD)
            try output.close()
        }
    }
    private func fingerprint(_ url: URL) throws -> String {
        DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: url)))
    }
    private func contents(_ c: T.Contents) -> [String: Any] {
        ["sourceDevice": c.sourceID.device, "sourceInode": c.sourceID.inode,
         "stageDevice": c.stageID.device, "stageInode": c.stageID.inode,
         "sourceBytes": c.sourceBytes, "sourceSHA256": c.sourceSHA256,
         "packets": c.packets, "records": c.records, "enhancementNALs": c.enhancementNALs,
         "members": c.members.map { ["name": $0.name, "byteCount": $0.byteCount, "sha256": $0.sha256] as [String: Any] }]
    }
    private func readContents(_ v: [String: Any], _ mode: T.Retention) throws -> T.Contents {
        func n(_ key: String) throws -> NSNumber { try #require(v[key] as? NSNumber) }
        let members = try #require(v["members"] as? [[String: Any]]).map { m in
            ResultSetStaging.Member(name: try #require(m["name"] as? String),
                byteCount: try #require(m["byteCount"] as? NSNumber).int64Value,
                sha256: try #require(m["sha256"] as? String))
        }
        return .init(retention: mode, sourceID: .init(device: try n("sourceDevice").uint64Value, inode: try n("sourceInode").uint64Value),
            stageID: .init(device: try n("stageDevice").uint64Value, inode: try n("stageInode").uint64Value),
            sourceBytes: try n("sourceBytes").int64Value, sourceSHA256: try #require(v["sourceSHA256"] as? String),
            packets: try n("packets").int64Value, records: try n("records").int64Value,
            enhancementNALs: try n("enhancementNALs").int64Value, members: members)
    }
    private func child(_ root: URL, mode: T.Retention, phase: String, writerHash: String, readerHash: String) async throws {
        let source = root.appendingPathComponent("source.mkv"), parent = root.appendingPathComponent("destination")
        let writer = try CompanionWriterProcess.Tool.development(root.appendingPathComponent("staxrip-dolby-companion-writer"), expectedSHA256: writerHash)
        let reader = try CompanionMetadataProcess.Tool.development(root.appendingPathComponent("staxrip-dolby-metadata-audit"), expectedSHA256: readerHash)
        let state = State()
        @Sendable func stop(_ point: String) throws {
            guard point == phase else { return }
            let (c, stage, joined) = try state.snapshot()
            let location = point == "before" ? stage : parent.appendingPathComponent("result")
            var s = stat(); try #require(lstat(location.path, &s) == 0 && T.FileID(s) == c.stageID)
            let frame: [String: Any] = ["phase": point, "pid": getpid(), "stageName": stage.lastPathComponent,
                "helperPIDsJoined": joined, "contents": contents(c)]
            let data = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys])
            try #require(data.count <= 16384)
            let fd = Darwin.open(root.appendingPathComponent("ready.json").path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0o600)
            try #require(fd >= 0); let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try file.write(contentsOf: data); try file.close()
            // Announce only a closed complete frame, never a visible partial write.
            let announced = Darwin.open(root.appendingPathComponent("ready").path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0o600)
            try #require(announced >= 0); Darwin.close(announced)
            // Test-only finite permission frame. EOF/wrong grant refuses abrupt exit.
            try #require(try FileHandle.standardInput.read(upToCount: 1) == Data([0x4b]))
            // Immediate process exit bypasses Swift unwinding, defer/atexit and
            // D105 discard. This is process loss, not signal/power-loss proof.
            Darwin._exit(86)
        }
        let boundary = ResultSetStaging.TestBoundary(beforeCommit: { try stop("before") }, afterCommit: {
            do { try stop("after") } catch { Issue.record("Generated post-commit acknowledgment refused: \(error)") }
        })
        _ = try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { state.launched($0, reader: false) }, settled: { state.joined($0, reader: false) })) {
            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { state.launched($0, reader: true) }, settled: { state.joined($0, reader: true) })) {
                try await ResultSetStaging.$testBoundary.withValue(boundary) {
                    try await T.execute(source: source, in: parent, destinationName: "result", retention: mode, produce: { stage in
                        let c = try await CompanionWriterProcess.run(tool: writer, source: source, stage: stage, retention: mode).contents
                        state.set(c, stage); return c
                    }, verify: { stage, c in
                        let r = try await CompanionDiskCheck.verifyOriginalMetadata(source: source, stage: stage, contents: c, tool: reader)
                        let m = try #require(r.originalMetadata)
                        return .init(contents: r.contents, originalComponentsMatchSource: r.originalMetadataSemanticsVerified && m.originalComponentsMatchSource,
                            sourceIdentityChecked: true, decodedFrameAssociation: m.decodedFrameAssociation, immutableSnapshot: m.immutableSnapshot, stableImporter: m.stableImporter)
                    })
                }
            }
        }
        Issue.record("Generated coordinator returned instead of abrupt loss")
    }

    @Test func actualCoordinatorLossBeforeAndAfterCommitKeepsSourcePriorAndSurvivingNativeSemantics() async throws {
        let env = ProcessInfo.processInfo.environment
        if let path = env["STAXRIP_TEST_COORDINATOR_ROOT"] {
            try #require(env["STAXRIP_TEST_COORDINATOR_PHASE"] == "before" || env["STAXRIP_TEST_COORDINATOR_PHASE"] == "after")
            try #require(env["STAXRIP_TEST_COORDINATOR_MODE"] == "metadata" || env["STAXRIP_TEST_COORDINATOR_MODE"] == "entire")
            try await child(URL(fileURLWithPath: path), mode: env["STAXRIP_TEST_COORDINATOR_MODE"] == "metadata" ? .metadataOnly : .entireContainer,
                phase: try #require(env["STAXRIP_TEST_COORDINATOR_PHASE"]), writerHash: try #require(env["STAXRIP_TEST_COORDINATOR_WRITER_SHA"]), readerHash: try #require(env["STAXRIP_TEST_COORDINATOR_READER_SHA"]))
            return
        }
        // Own isolated Rust artifacts; child never invokes Cargo or an app action.
        let f = try await CompanionOriginalMetadataCheckTests.fixture(targetName: "native-companion-loss-fixtures")
        var allSettled = false
        defer { if allSettled { f.cleanup() } else { print("GENERATED_COORDINATOR_REVIEW " + f.root.path) } }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        try #require(executable.lastPathComponent == "swiftpm-testing-helper")
        let index = try #require(CommandLine.arguments.firstIndex(of: "--test-bundle-path"))
        try #require(index + 1 < CommandLine.arguments.count)
        let bundle = CommandLine.arguments[index + 1]
        let original = try Data(contentsOf: f.source), prior = Data("generated prior output\n".utf8)
        for mode in [T.Retention.metadataOnly, .entireContainer] {
            for phase in ["before", "after"] {
                let root = f.root.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let source = root.appendingPathComponent("source.mkv"), parent = root.appendingPathComponent("destination")
                try FileManager.default.copyItem(at: f.source, to: source)
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try prior.write(to: parent.appendingPathComponent("prior"), options: .withoutOverwriting)
                for tool in [f.executable, f.reader] { try FileManager.default.copyItem(at: tool, to: root.appendingPathComponent(tool.lastPathComponent)) }
                let writerHash = try fingerprint(f.executable), readerHash = try fingerprint(f.reader)
                let log = root.appendingPathComponent("child.log")
                try #require(FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]))
                let arguments = ["--test-bundle-path", bundle, "--filter", "CompanionCoordinatorLossTests/actualCoordinatorLossBeforeAndAfterCommitKeepsSourcePriorAndSurvivingNativeSemantics", "--testing-library", "swift-testing"]
                var environment = env
                environment["STAXRIP_TEST_COORDINATOR_ROOT"] = root.path
                environment["STAXRIP_TEST_COORDINATOR_PHASE"] = phase
                environment["STAXRIP_TEST_COORDINATOR_MODE"] = mode == .metadataOnly ? "metadata" : "entire"
                environment["STAXRIP_TEST_COORDINATOR_WRITER_SHA"] = writerHash
                environment["STAXRIP_TEST_COORDINATOR_READER_SHA"] = readerHash

                var rootID = stat(), parentID = stat()
                try #require(lstat(root.path, &rootID) == 0 && lstat(parent.path, &parentID) == 0)
                let process = try Coordinator(executable: executable, arguments: arguments, environment: environment, log: log)
                let deadline = ContinuousClock.now.advanced(by: .seconds(20)), ready = root.appendingPathComponent("ready")
                while !FileManager.default.fileExists(atPath: ready.path), try !process.reapIfExited(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
                // If readiness fails, close input and retain fixture. Never kill an
                // unknown helper group or discard its potentially active stage.
                guard FileManager.default.fileExists(atPath: ready.path), try !process.reapIfExited() else {
                    process.closeInput()
                    throw NativeExportError.invalid("Generated coordinator boundary missing; retain fixture for review")
                }
                let frameData = try Data(contentsOf: root.appendingPathComponent("ready.json")); try #require(frameData.count <= 16384)
                let frame = try #require(JSONSerialization.jsonObject(with: frameData) as? [String: Any])
                try #require(frame["phase"] as? String == phase && (frame["pid"] as? NSNumber)?.int32Value == process.pid)
                let helperPIDs = try #require(frame["helperPIDsJoined"] as? [NSNumber]); try #require(helperPIDs.count == 2 && helperPIDs.allSatisfy { $0.int32Value > 0 })
                let stageName = try #require(frame["stageName"] as? String)
                try #require(stageName.hasPrefix(".staxrip-result-") && UUID(uuidString: String(stageName.dropFirst(".staxrip-result-".count))) != nil)
                let c = try readContents(try #require(frame["contents"] as? [String: Any]), mode)
                let location = parent.appendingPathComponent(phase == "before" ? stageName : "result")
                let pin = Darwin.open(location.path, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                try #require(pin >= 0); defer { Darwin.close(pin) }
                var pinned = stat(); try #require(fstat(pin, &pinned) == 0 && T.FileID(pinned) == c.stageID)
                try process.grant()
                while try !process.reapIfExited(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
                try #require(try process.reapIfExited(), "Coordinator did not settle; retain fixture")
                try process.assertExitedAndJoined()
                var current = stat(), descriptor = stat(), finalRoot = stat(), finalParent = stat()
                try #require(lstat(root.path, &finalRoot) == 0 && lstat(parent.path, &finalParent) == 0 && T.FileID(finalRoot) == T.FileID(rootID) && T.FileID(finalParent) == T.FileID(parentID))
                try #require((try FileManager.default.attributesOfItem(atPath: log.path)[.size] as? NSNumber)?.int64Value ?? Int64.max <= 1 << 20)
                try #require(lstat(location.path, &current) == 0 && fstat(pin, &descriptor) == 0 && T.FileID(current) == c.stageID && T.FileID(descriptor) == c.stageID)
                try #require(Set(FileManager.default.contentsOfDirectory(atPath: parent.path)) == ["prior", phase == "before" ? stageName : "result"])
                try #require(try Data(contentsOf: source) == original && Data(contentsOf: parent.appendingPathComponent("prior")) == prior)
                let reader = try CompanionMetadataProcess.Tool.development(f.reader, expectedSHA256: readerHash)
                // The lost coordinator frame is no longer available to review.
                try FileManager.default.removeItem(at: root.appendingPathComponent("ready.json"))
                try FileManager.default.removeItem(at: ready)
                let verified = try await CompanionDiskCheck.reviewOriginalCandidate(source: source, candidate: location, retention: mode, tool: reader)
                try #require(verified.contents.sourceID == c.sourceID && verified.contents.stageID == c.stageID)
                try #require(verified.originalMetadataSemanticsVerified && verified.originalMetadata?.originalComponentsMatchSource == true)
                if mode == .entireContainer { try #require(try Data(contentsOf: location.appendingPathComponent("original-container.mkv")) == original) }
                print("GENERATED_COORDINATOR_LOSS mode=" + (mode == .metadataOnly ? "metadata" : "entire") + " phase=" + phase + " helper_joins=2 immediate_exit=86 native_semantics=true retained_identity=true")
            }
        }
        try #require(try Data(contentsOf: f.source) == original)
        allSettled = true
    }
}
