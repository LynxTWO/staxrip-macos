import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionWriterProcessTests {
    typealias Writer = CompanionWriterProcess
    typealias Transaction = OriginalCompanionTransaction
    private final class State: @unchecked Sendable {
        private let lock = NSLock(); private var launchedPID: pid_t = 0, joinedPID: pid_t = 0
        private var task: Task<CompanionWriterProtocol.Receipt, Error>?, cancelled = false
        func launch(_ pid: pid_t) { lock.withLock { launchedPID = pid } }
        func settle(_ pid: pid_t) { lock.withLock { joinedPID = pid } }
        func set(_ task: Task<CompanionWriterProtocol.Receipt, Error>) { lock.withLock { self.task = task } }
        func cancel() { lock.withLock { if let task { task.cancel(); cancelled = true } } }
        var didCancel: Bool { lock.withLock { cancelled } }
        var pid: pid_t { lock.withLock { launchedPID } }
        func assertJoined() {
            let (pid, joined) = lock.withLock { (launchedPID, joinedPID) }
            #expect(pid > 0 && joined == pid)
            var status: Int32 = 0
            #expect(waitpid(pid, &status, WNOHANG) == -1)
            #expect(errno == ECHILD)
        }
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>
        private let event: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value: 0)
        init() { var c: AsyncStream<Void>.Continuation!; entered = AsyncStream { c = $0 }; event = c }
        func hold() { event.yield(()); if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated process gate expired") } }
    }
    private struct Fixture {
        let root, source, stage, executable: URL
        var tool: Writer.Tool { get throws { try .development(executable, expectedSHA256: DolbyInspection.hex(SHA256.hash(data: Data(contentsOf: executable)))) } }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
    private static var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-companion-process-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let generated = root.appendingPathComponent("generated")
            try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: false)
            let cargo = repo.appendingPathComponent("Tools/DolbyMetadataAudit/Cargo.toml")
            // This suite owns its writer artifacts; unrelated default-feature builds
            // must not replace/remove a binary between successful build and copy.
            let target = repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/owned-native-writer-fixtures")
            let f = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "STAXRIP_GENERATED_STAGED_COMPANION_DIRECTORY=" + generated.path, "cargo", "test", "--locked",
                "--target-dir", target.path, "--manifest-path", cargo.path, "owned_stage_packages_preserve_originals_and_match_disk_receipts"])
            try #require(f.status == 0)
            let b = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "cargo", "build", "--release", "--locked", "--features", "development-companion-writer", "--bin",
                "staxrip-dolby-companion-writer", "--target-dir", target.path, "--manifest-path", cargo.path])
            try #require(b.status == 0)
            let executable = root.appendingPathComponent("staxrip-dolby-companion-writer")
            try FileManager.default.copyItem(at: target.appendingPathComponent("release/staxrip-dolby-companion-writer"), to: executable)
            let stage = root.appendingPathComponent("stage")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return .init(root: root, source: generated.appendingPathComponent("generated-source.mkv"), stage: stage, executable: executable)
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }
    @Test(.timeLimit(.minutes(2))) func actualWriterBothModesHasJoinedNativeHandshakeAndDiskAgreement() async throws {
        for mode in [Transaction.Retention.metadataOnly, .entireContainer] {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let original = try Data(contentsOf: f.source), state = State(), tool = try f.tool
            let result = try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) })) {
                try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: mode)
            }
            state.assertJoined()
            #expect(result.contents.retention == mode && result.contents.packets == 1 && result.contents.records == 2)
            #expect(result.contents.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data: original)))
            #expect(result.contents.members.count == mode.limits.count)
            for m in result.contents.members {
                let bytes = try Data(contentsOf: f.stage.appendingPathComponent(m.name))
                #expect(Int64(bytes.count) == m.byteCount && DolbyInspection.hex(SHA256.hash(data: bytes)) == m.sha256)
            }
            #expect(try Data(contentsOf: f.source) == original)
            if mode == .entireContainer { #expect(try Data(contentsOf: f.stage.appendingPathComponent("original-container.mkv")) == original) }
        }
    }
    @Test func cancelledAtActualReadyJoinsBeforeReturningAndWritesNoComponents() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }
        let state = State(), gate = Gate(), original = try Data(contentsOf: f.source), tool = try f.tool
        let task = Task {
            try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, ready: { gate.hold() }, settled: { state.settle($0) })) {
                try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly)
            }
        }
        for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        state.assertJoined()
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
        #expect(try Data(contentsOf: f.source) == original)
    }
    @Test func cancellationDuringActualGeneratedWholeContainerCopyRefusesPartialReceipt() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }
        // Matroska permits a trailing global Void. Make a sparse 128 MiB payload;
        // the actual producer streams it into the original-container component.
        let handle = try FileHandle(forWritingTo: f.source)
        let end = try handle.seekToEnd(); let padding: UInt64 = 128 << 20
        var encoded = (padding | (1 << 56)).bigEndian
        var header = Data([0xec]); withUnsafeBytes(of: &encoded) { header.append(contentsOf: $0) }
        try handle.write(contentsOf: header); try handle.truncate(atOffset: end + UInt64(header.count) + padding); try handle.close()
        let sourceLength = end + UInt64(header.count) + padding
        let before = try await ExportSourceFingerprint.read(f.source), state = State(), tool = try f.tool
        let output = f.stage.appendingPathComponent("original-container.mkv")
        let task = Task {
            try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, poll: {
                if let info = try? FileManager.default.attributesOfItem(atPath: output.path),
                   let size = info[.size] as? NSNumber, size.int64Value > 0, size.int64Value < Int64(sourceLength) { state.cancel() }
            }, settled: { state.settle($0) })) {
                try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .entireContainer)
            }
        }
        state.set(task)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(state.didCancel); state.assertJoined()
        let partial = try #require(try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)
        #expect(partial.int64Value > 0 && partial.uint64Value < sourceLength)
        #expect(try await ExportSourceFingerprint.read(f.source) == before)
        #expect(!FileManager.default.fileExists(atPath: f.stage.appendingPathComponent("manifest.json").path))
    }
    @Test func cancellationAfterActualZeroExitRefusesLateReceipt() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }
        let state = State(), tool = try f.tool
        let task = Task {
            try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) }, beforeReceipt: { state.cancel() })) {
                try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly)
            }
        }
        state.set(task)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(state.didCancel); state.assertJoined()
        #expect(FileManager.default.fileExists(atPath: f.stage.appendingPathComponent("manifest.json").path))
    }
    @Test func unsafeInputsWrongDigestAndPrecancelNeverLaunch() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }
        let state = State(), tool = try f.tool
        await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) })) {
            let wrong = try! Writer.Tool.development(f.executable, expectedSHA256: String(repeating: "0", count: 64))
            await #expect(throws: (any Error).self) { try await Writer.run(tool: wrong, source: f.source, stage: f.stage, retention: .metadataOnly) }
            try? Data("keep".utf8).write(to: f.stage.appendingPathComponent("keep"))
            await #expect(throws: (any Error).self) { try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly) }
            try? FileManager.default.removeItem(at: f.stage.appendingPathComponent("keep"))
            let (stream, end) = AsyncStream<Void>.makeStream()
            let cancelled = Task { for await _ in stream { break }; return try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly) }
            cancelled.cancel(); end.finish(); await #expect(throws: CancellationError.self) { try await cancelled.value }
        }
        #expect(state.pid == 0)
    }
    @Test func sourceAndStageReplacementAtReadyRefuseBeforeWrites() async throws {
        for change in ["source", "stage", "executable"] {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let state = State(), tool = try f.tool, original = try Data(contentsOf: f.source)
            await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, ready: {
                let target = change == "source" ? f.source : (change == "stage" ? f.stage : f.executable)
                let moved = f.root.appendingPathComponent("moved-" + change)
                do {
                    try FileManager.default.moveItem(at: target, to: moved)
                    if change == "stage" { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                    else { try FileManager.default.copyItem(at: moved, to: target) }
                } catch { Issue.record("Generated replacement failed") }
            }, settled: { state.settle($0) })) {
                await #expect(throws: (any Error).self) { try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly) }
            }
            state.assertJoined()
            #expect(try Data(contentsOf: f.source) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
        }
    }
    @Test func actualNativeSurrogatesRefuseAndSettleDeadlineEarlyEOFMalformedAndPipeHolder() async throws {
        for behavior in ["sleep", "earlyEOF", "nonzero", "malformed", "stderr", "brokenInput", "holder"] {
            let f = try await Self.fixture(); defer { f.cleanup() }
            try FileManager.default.removeItem(at: f.executable)
            let c = f.root.appendingPathComponent("fixture.c")
            let body: String
            switch behavior {
            case "sleep": body = "sleep(60);"
            case "earlyEOF": body = "close(1); close(2); sleep(60);"
            case "nonzero": body = "return 7;"
            case "malformed": body = "puts(\"{\\\"kind\\\":\\\"wrong\\\"}\"); fflush(stdout); sleep(60);"
            case "brokenInput": body = "printf(\"{\\\"kind\\\":\\\"ready\\\",\\\"protocol\\\":1,\\\"operation\\\":\\\"%s\\\"}\\n\",argv[4]);fflush(stdout);close(0);sleep(60);"
            case "stderr": body = "for(int i=0;i<70000;i++) fputc('x',stderr); fflush(stderr); sleep(60);"
            default: body = "pid_t p=fork(); if(p==0){sleep(60);_exit(0);} char path[4096];snprintf(path,sizeof(path),\"%s/holder-pid\",argv[3]);FILE*f=fopen(path,\"w\");fprintf(f,\"%d\",p);fclose(f);return 0;"
            }
            try ("#include <stdio.h>\n#include <unistd.h>\nint main(int argc,char**argv){" + body + "return 0;}\n").write(to: c, atomically: false, encoding: .utf8)
            let compiled = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["clang", c.path, "-o", f.executable.path])
            try #require(compiled.status == 0)
            let state = State(), tool = try f.tool
            await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) })) {
                await #expect(throws: (any Error).self) { try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly, timeout: 0.25) }
            }
            state.assertJoined()
            if behavior == "holder" {
                let number = try String(contentsOf: f.stage.appendingPathComponent("holder-pid"), encoding: .utf8)
                let pid = try #require(Int32(number))
                // Orphans are reaped by the OS. A zombie has stopped execution;
                // do not claim that this caller can join a non-child.
                let ps = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
                #expect(ps.status != 0 || String(decoding: ps.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
            }
        }
    }
}
