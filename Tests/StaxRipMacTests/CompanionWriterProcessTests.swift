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
            let helpers = try await RustFixtureBuild.generate(.staged, at: generated, copiesIn: root)
            let executable = helpers.writer
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
    private final class PipeEvents: @unchecked Sendable {
        private let lock = NSLock(); private var events: [(Writer.PipeRole,Int32,Int32)] = []
        func record(_ role: Writer.PipeRole, _ fd: Int32, _ status: Int32) { lock.withLock { events.append((role,fd,status)) } }
        func assertOnce() {
            let all = lock.withLock { events }
            #expect(all.count == 6 && Set(all.map { $0.0 }) == Set(Writer.PipeRole.allCases))
            #expect(all.allSatisfy { $0.1 >= 0 && $0.2 == 0 })
            for role in Writer.PipeRole.allCases { #expect(all.filter { $0.0 == role }.count == 1) }
        }
        var count: Int { lock.withLock { events.count } }
    }
    @Test func actualBothModePipeRolesCloseOnceAndReportsPreventReceiptWithoutRetry() async throws {
        for mode in [Transaction.Retention.metadataOnly,.entireContainer] {
            for fault in ["normal"] + Writer.PipeRole.allCases.map(\.rawValue) + ["all"] {
                let f = try await Self.fixture(); var keep = fault != "normal"
                defer { if keep { print("GENERATED_WRITER_PIPE_REVIEW " + f.root.path) } else { f.cleanup() } }
                let state = State(), events = PipeEvents(), original = try Data(contentsOf: f.source), tool = try f.tool
                do {
                    let result = try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) },
                        settled: { state.settle($0) }, closed: { events.record($0,$1,$2) },
                        refuseClose: { role,_,status in status == 0 && (fault == "all" || fault == role.rawValue) })) {
                        try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: mode)
                    }
                    #expect(fault == "normal" && result.contents.retention == mode)
                    keep = false
                } catch let error as Writer.PipeCloseFailure {
                    #expect(fault != "normal" && error.operationError == nil)
                    #expect(Set(error.roles) == (fault == "all" ? Set(Writer.PipeRole.allCases) : Set([try #require(Writer.PipeRole(rawValue: fault))])))
                }
                state.assertJoined(); events.assertOnce()
                let manifest = try Data(contentsOf: f.stage.appendingPathComponent("manifest.json"))
                #expect(!manifest.isEmpty)
                #expect(try Data(contentsOf: f.source) == original)
                if mode == .entireContainer { #expect(try Data(contentsOf: f.stage.appendingPathComponent("original-container.mkv")) == original) }
            }
        }
    }
    @Test func reportedPipeCloseKeepsActiveLateAndFirstCloseCancellationCauseAfterJoin() async throws {
        for phase in ["first-close","ready","late"] {
            let f = try await Self.fixture(); defer { print("GENERATED_WRITER_PIPE_CANCEL_REVIEW " + f.root.path) }
            let state = State(), events = PipeEvents(), gate = Gate(), tool = try f.tool, original = try Data(contentsOf: f.source)
            let task = Task {
                try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) },
                    ready: { if phase == "ready" { gate.hold() } }, settled: { state.settle($0) },
                    beforeReceipt: { if phase == "late" { gate.hold() } },
                    closed: { role,fd,status in events.record(role,fd,status); if phase == "first-close" && role == .stdinRead { gate.hold() } },
                    refuseClose: { _,_,status in status == 0 })) {
                    try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly)
                }
            }
            for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
            do { _ = try await task.value; Issue.record("Reported pipe close admitted cancelled writer") }
            catch let e as Writer.PipeCloseFailure { #expect(e.operationError is CancellationError && Set(e.roles) == Set(Writer.PipeRole.allCases)) }
            catch let e as Writer.OwnershipFailure {
                #expect(e.operationError is Writer.OwnershipFailure && Set(e.pipeCloseRoles) == Set(Writer.PipeRole.allCases))
                let originalError = try #require(e.operationError as? Writer.OwnershipFailure)
                #expect(originalError.operationError is CancellationError)
            }
            state.assertJoined(); events.assertOnce(); #expect(try Data(contentsOf: f.source) == original)
        }
    }
    @Test func reportedPipeClosePreservesFinalIdentityAndNonzeroRefusalsWithoutPrelaunchClaims() async throws {
        for fault in ["source","stage","executable","malformed-source"] {
            let f = try await Self.fixture(); defer { print("GENERATED_WRITER_PIPE_CAUSE_REVIEW " + f.root.path) }
            if fault == "malformed-source" { try Data("Generated malformed container".utf8).write(to: f.source) }
            let state = State(), events = PipeEvents(), tool = try f.tool, original = try Data(contentsOf: f.source)
            do {
                _ = try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) },
                    beforeReceipt: {
                        guard fault != "malformed-source" else { return }
                        let target = fault == "source" ? f.source : fault == "stage" ? f.stage : f.executable
                        let moved = f.root.appendingPathComponent("moved-" + fault)
                        do { try FileManager.default.moveItem(at: target, to: moved); try FileManager.default.copyItem(at: moved, to: target) }
                        catch { Issue.record("Generated same-byte final identity substitution failed") }
                    }, closed: { events.record($0,$1,$2) }, refuseClose: { role,_,status in status == 0 && role == .stderrRead })) {
                    try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly)
                }
                Issue.record("Reported close/ordinary cause returned receipt")
            } catch let e as Writer.PipeCloseFailure { #expect(e.roles == [.stderrRead] && e.operationError is NativeExportError) }
            state.assertJoined(); events.assertOnce(); #expect(try Data(contentsOf: f.source) == original)
        }
        let f = try await Self.fixture(); defer { f.cleanup() }; let state = State(), events = PipeEvents()
        let wrong = try Writer.Tool.development(f.executable, expectedSHA256: String(repeating:"0",count:64))
        await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, closed: { events.record($0,$1,$2) })) {
            await #expect(throws: NativeExportError.self) { try await Writer.run(tool: wrong, source: f.source, stage: f.stage, retention: .metadataOnly) }
        }
        #expect(state.pid == 0 && events.count == 0) // No post-spawn role qualification on this path.
    }

    private final class PinEvents: @unchecked Sendable {
        private let lock = NSLock(); private var values: [(Writer.PinRole,Int32,Int32)] = []
        func record(_ role: Writer.PinRole, _ fd: Int32, _ status: Int32) { lock.withLock { values.append((role,fd,status)) } }
        var count: Int { lock.withLock { values.count } }
        func assertOnce() {
            lock.withLock {
                #expect(values.count == 3 && values.allSatisfy { $0.1 >= 0 && $0.2 == 0 })
                for role in Writer.PinRole.allCases { #expect(values.filter { $0.0 == role }.count == 1) }
            }
        }
    }
    @Test func admittedWriterPinsCloseOnceAfterBothModeBodiesAndAllReportCombinations() async throws {
        let faults: [[Writer.PinRole]] = [[], [.source], [.stage], [.executable], [.source,.stage], [.source,.executable], [.stage,.executable], Writer.PinRole.allCases]
        for mode in [Transaction.Retention.metadataOnly, .entireContainer] {
            for faults in faults {
                let f = try await Self.fixture(), state = State(), pipes = PipeEvents(), pins = PinEvents(), tool = try f.tool
                let original = try Data(contentsOf: f.source)
                defer { if faults.isEmpty { f.cleanup() } else { print("GENERATED_WRITER_PIN_REVIEW " + f.root.path) } }
                do {
                    let result = try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) },
                        closed: { pipes.record($0,$1,$2) }, pinClosed: { role,fd,status in state.assertJoined(); pipes.assertOnce(); pins.record(role,fd,status) },
                        refusePinClose: { role,_,status in status == 0 && faults.contains(role) })) {
                        try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: mode)
                    }
                    #expect(faults.isEmpty && result.contents.retention == mode)
                } catch let e as Writer.PinCloseFailure {
                    #expect(Set(e.roles) == Set(faults) && e.operationError == nil)
                }
                state.assertJoined(); pins.assertOnce(); pipes.assertOnce()
                #expect(try Data(contentsOf: f.source) == original)
                if mode == .entireContainer { #expect(try Data(contentsOf: f.stage.appendingPathComponent("original-container.mkv")) == original) }
                if !faults.isEmpty {
                    let owner = try #require(Writer.retainedPins(source: f.source))
                    #expect(owner.descriptorsForTesting == [-1,-1,-1]) // Owned fields consumed, NOT an OS-number absence probe.
                    await #expect(throws: NativeExportError.self) { try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: mode) }
                    Writer.isolateGeneratedPinsForTesting(owner)
                }
            }
        }
    }
    @Test func admittedPinRefusalKeepsFirstActiveLateCancellationAndPipeCause() async throws {
        for phase in ["first", "active", "late"] {
            let f = try await Self.fixture(), state = State(), pins = PinEvents(), pipes = PipeEvents(), gate = Gate(), tool = try f.tool
            defer { print("GENERATED_WRITER_PIN_CANCEL_REVIEW " + f.root.path) }
            let task = Task {
                try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, ready: { if phase == "active" { gate.hold() } },
                    settled: { state.settle($0) }, beforeReceipt: { if phase == "late" { gate.hold() } },
                    closed: { role,fd,status in pipes.record(role,fd,status); if phase == "first" && role == .stdinRead { gate.hold() } },
                    refuseClose: { role,_,status in status == 0 && role == .stdinRead },
                    pinClosed: { pins.record($0,$1,$2) }, refusePinClose: { _,_,status in status == 0 })) {
                    try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly)
                }
            }
            for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
            do { _ = try await task.value; Issue.record("Pin refusal returned cancelled receipt") }
            catch let e as Writer.PinCloseFailure {
                #expect(Set(e.roles) == Set(Writer.PinRole.allCases))
                let pipe = try #require(e.operationError as? Writer.PipeCloseFailure)
                #expect(pipe.roles == [.stdinRead] && pipe.operationError is CancellationError)
            } catch let e as Writer.OwnershipFailure { #expect(!e.pipeCloseRoles.isEmpty || e.operationError != nil) }
            state.assertJoined(); pipes.assertOnce()
            let owner = try #require(Writer.retainedPins(source: f.source))
            if owner.descriptorsForTesting == [-1,-1,-1] {
                pins.assertOnce(); Writer.isolateGeneratedPinsForTesting(owner)
            } else { #expect(pins.count == 0) } // Actual uncertainty remains retained, no isolation/cleanup authority.
        }
    }
    @Test func admittedPinRefusalPreservesFinalIdentityAndNonzeroBodyCauses() async throws {
        for fault in ["source", "stage", "executable", "malformed"] {
            let f = try await Self.fixture(), state = State(), pins = PinEvents(), tool = try f.tool
            defer { print("GENERATED_WRITER_PIN_CAUSE_REVIEW " + f.root.path) }
            if fault == "malformed" { try Data("Generated malformed container".utf8).write(to: f.source) }
            let original = try Data(contentsOf: f.source)
            do {
                _ = try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) }, beforeReceipt: {
                    guard fault != "malformed" else { return }
                    let target = fault == "source" ? f.source : fault == "stage" ? f.stage : f.executable
                    let moved = f.root.appendingPathComponent("moved-" + fault)
                    do { try FileManager.default.moveItem(at: target, to: moved); try FileManager.default.copyItem(at: moved, to: target) }
                    catch { Issue.record("Generated writer final pin substitution failed") }
                }, pinClosed: { pins.record($0,$1,$2) }, refusePinClose: { role,_,status in status == 0 && role == .stage })) {
                    try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly)
                }
                Issue.record("Pin refusal admitted final body refusal")
            } catch let e as Writer.PinCloseFailure { #expect(e.roles == [.stage] && e.operationError is NativeExportError) }
            state.assertJoined(); pins.assertOnce(); #expect(try Data(contentsOf: f.source) == original)
            Writer.isolateGeneratedPinsForTesting(try #require(Writer.retainedPins(source: f.source)))
        }
    }
    // Hosted Swift6.1.2 rejects weak let locals; keep witness storage mutable.
    // Compatibility awaits changed-head CI. ARC alone changes the weak value.
    private final class WeakWriterPins {
        weak var value: Writer.AdmittedPins?
        init(_ value: Writer.AdmittedPins?) { self.value = value }
    }
    @Test func reportedSettlementKeepsSameOpenedPinsAfterTaskErrorDropAndExcludesDirectConflict() async throws {
        let f = try await Self.fixture(), state = State(), pins = PinEvents(), tool = try f.tool
        defer { print("GENERATED_WRITER_OPEN_PIN_REVIEW " + f.root.path) }
        var task: Task<CompanionWriterProtocol.Receipt,Error>? = Task {
            try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) },
                pinClosed: { pins.record($0,$1,$2) }, reportPinSettlementUncertainty: { true })) {
                try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly)
            }
        }
        do { _ = try await task!.value; Issue.record("Reported settlement returned receipt") }
        catch let e as Writer.OwnershipFailure { #expect(e.operationError == nil) }
        task = nil; state.assertJoined(); #expect(pins.count == 0)
        let witness = WeakWriterPins(Writer.retainedPins(source: f.source))
        let numbers = try #require(witness.value?.descriptorsForTesting)
        for fd in numbers { var info = stat(); #expect(fd >= 0 && fstat(fd,&info) == 0) }
        await #expect(throws: NativeExportError.self) { try await Writer.run(tool: tool, source: f.source, stage: f.stage, retention: .metadataOnly) }
        #expect(witness.value != nil && witness.value?.descriptorsForTesting == numbers)
        Writer.isolateGeneratedPinsForTesting(try #require(witness.value)); #expect(witness.value == nil)
    }

    private final class AdmissionCloses: @unchecked Sendable {
        private let lock = NSLock(); private var values: [(Writer.PinRole,Int32,Int32)] = []
        func add(_ role: Writer.PinRole, _ fd: Int32, _ status: Int32) { lock.withLock { values.append((role,fd,status)) } }
        func expect(_ roles: [Writer.PinRole]) {
            lock.withLock {
                #expect(values.map { $0.0 } == roles && values.allSatisfy { $0.1 >= 0 && $0.2 == 0 })
                #expect(Set(values.map { $0.1 }).count == values.count)
            }
        }
    }
    @Test func actualWriterPinAdmissionRefusalsCloseEveryPositiveOpenBeforeReturn() async throws {
        for variant in ["source-empty","source-directory","source-link","source-missing","source-denied","stage-mode","stage-missing","executable-mode","executable-empty","executable-missing","digest","spawn","stage-not-empty"] {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let tool = try f.tool, state = State(), closes = AdmissionCloses()
            switch variant {
            case "source-empty": try Data().write(to: f.source)
            case "source-directory": try FileManager.default.removeItem(at: f.source); try FileManager.default.createDirectory(at: f.source, withIntermediateDirectories: false)
            case "source-link": let moved = f.root.appendingPathComponent("original"); try FileManager.default.moveItem(at: f.source, to: moved); try FileManager.default.createSymbolicLink(at: f.source, withDestinationURL: moved)
            case "source-missing": try FileManager.default.removeItem(at: f.source)
            case "source-denied": try #require(chmod(f.source.path,0) == 0)
            case "stage-mode": try #require(chmod(f.stage.path,0o755) == 0)
            case "stage-missing": try FileManager.default.removeItem(at: f.stage)
            case "executable-mode": try #require(chmod(f.executable.path,0o600) == 0)
            case "executable-empty": try Data().write(to: f.executable)
            case "executable-missing": try FileManager.default.removeItem(at: f.executable)
            case "stage-not-empty": try Data([1]).write(to: f.stage.appendingPathComponent("existing"))
            default: break
            }
            let selectedTool: Writer.Tool
            if variant == "digest" { selectedTool = try .development(f.executable, expectedSHA256: String(repeating:"0",count:64)) }
            else if variant == "spawn" { try Data("Generated invalid executable".utf8).write(to:f.executable); selectedTool = try f.tool }
            else { selectedTool = tool }
            await #expect(throws: NativeExportError.self) {
                try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, pinClosed: { closes.add($0,$1,$2) })) {
                    try await Writer.run(tool:selectedTool,source:f.source,stage:f.stage,retention:.metadataOnly)
                }
            }
            let roles: [Writer.PinRole]
            if ["source-link","source-missing","source-denied"].contains(variant) { roles = [] }
            else if ["source-empty","source-directory","stage-missing"].contains(variant) { roles = [.source] }
            else if ["stage-mode","executable-missing"].contains(variant) { roles = [.source,.stage] }
            else { roles = Writer.PinRole.allCases }
            closes.expect(roles); #expect(state.pid == 0 && Writer.retainedPins(source:f.source) == nil)
        }
    }
    @Test func writerPartialAdmissionReportsRetainSameOwnerAndOriginalCauseAfterDrop() async throws {
        for phase in Writer.PinRole.allCases {
            let f = try await Self.fixture(), closes = AdmissionCloses(), tool = try f.tool
            defer { print("GENERATED_WRITER_PARTIAL_PIN_REVIEW " + f.root.path) }
            let expected: [Writer.PinRole] = phase == .source ? [.source] : phase == .stage ? [.source,.stage] : Writer.PinRole.allCases
            var task: Task<CompanionWriterProtocol.Receipt,Error>? = Task {
                try await Writer.$testBoundary.withValue(.init(launched: { _ in Issue.record("Admission report launched writer") },
                    pinOpened: { role in if role == phase { throw NativeExportError.invalid("Generated writer admission refusal") } },
                    pinClosed: { closes.add($0,$1,$2) }, refusePinClose: { _,_,status in status == 0 })) {
                    try await Writer.run(tool:tool,source:f.source,stage:f.stage,retention:.metadataOnly)
                }
            }
            do { _ = try await task!.value; Issue.record("Partial pin report returned receipt") }
            catch let e as Writer.PinCloseFailure { #expect(e.roles == expected && e.operationError is NativeExportError) }
            task = nil; closes.expect(expected)
            let witness = WeakWriterPins(Writer.retainedPins(source:f.source))
            #expect(witness.value != nil && witness.value?.descriptorsForTesting == [-1,-1,-1])
            await #expect(throws: NativeExportError.self) { try await Writer.run(tool:tool,source:f.source,stage:f.stage,retention:.metadataOnly) }
            #expect(witness.value != nil)
            Writer.isolateGeneratedPinsForTesting(try #require(witness.value)); #expect(witness.value == nil)
        }
    }
    @Test func actualTaskCancellationDuringWriterPinAdmissionOrPrelaunchClosesBeforeThrow() async throws {
        for phase in ["source","stage","executable","prelaunch"] {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let tool = try f.tool, gate = Gate(), closes = AdmissionCloses(), state = State()
            let task = Task {
                try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) },
                    pinOpened: { role in if role.rawValue == phase { gate.hold() } }, beforeSpawn: { if phase == "prelaunch" { gate.hold() } },
                    pinClosed: { closes.add($0,$1,$2) })) {
                    try await Writer.run(tool:tool,source:f.source,stage:f.stage,retention:.metadataOnly)
                }
            }
            for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
            await #expect(throws: CancellationError.self) { try await task.value }
            closes.expect(phase == "source" ? [.source] : phase == "stage" ? [.source,.stage] : Writer.PinRole.allCases)
            #expect(state.pid == 0 && Writer.retainedPins(source:f.source) == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath:f.stage.path).isEmpty)
        }
    }
    @Test func writerObservedAdmissionSubstitutionRefusesAfterOwningActualOpenedRole() async throws {
        for phase in Writer.PinRole.allCases {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let closes = AdmissionCloses(), tool = try f.tool
            let expected: [Writer.PinRole] = phase == .source ? [.source] : phase == .stage ? [.source,.stage] : Writer.PinRole.allCases
            await #expect(throws: NativeExportError.self) {
                try await Writer.$testBoundary.withValue(.init(launched: { _ in Issue.record("Substituted admission launched writer") }, pinOpened: { role in
                    guard role == phase else { return }
                    let target = role == .source ? f.source : role == .stage ? f.stage : f.executable
                    let moved = f.root.appendingPathComponent("substituted-" + role.rawValue)
                    try FileManager.default.moveItem(at:target,to:moved); try FileManager.default.copyItem(at:moved,to:target)
                }, pinClosed: { closes.add($0,$1,$2) })) {
                    try await Writer.run(tool:tool,source:f.source,stage:f.stage,retention:.metadataOnly)
                }
            }
            closes.expect(expected); #expect(Writer.retainedPins(source:f.source) == nil)
        }
    }

    private final class PrelaunchPipeCloses: @unchecked Sendable {
        private let lock = NSLock(); private var values: [(Writer.PipeRole,Int32,Int32)] = []
        func add(_ role: Writer.PipeRole, _ fd: Int32, _ status: Int32) { lock.withLock { values.append((role,fd,status)) } }
        func expect(_ roles: [Writer.PipeRole]) { lock.withLock {
            #expect(values.map { $0.0 } == roles && values.allSatisfy { $0.1 >= 0 && $0.2 == 0 })
            #expect(Set(values.map { $0.1 }).count == values.count)
        } }
    }
    private func prelaunchRoles(_ phase: String) -> [Writer.PipeRole] {
        phase.hasPrefix("stdin") && !phase.hasSuffix("Nonblocking") ? [.stdinRead,.stdinWrite] :
        phase.hasPrefix("stdout") && !phase.hasSuffix("Nonblocking") ? [.stdinRead,.stdinWrite,.stdoutRead,.stdoutWrite] : Writer.PipeRole.allCases
    }
    private final class PrelaunchGate: @unchecked Sendable {
        let entered: AsyncStream<Void>, signal: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value:0)
        init() { let pair = AsyncStream<Void>.makeStream(); entered=pair.stream; signal=pair.continuation }
        func hold() { signal.yield(()); if release.wait(timeout:.now()+30) != .success { Issue.record("Generated prelaunch gate expired") } }
    }
    @Test func writerPipeOpenedConfiguredNonblockingAndSpawnRefusalsCloseAllOwnedPairs() async throws {
        for phase in Writer.PipeAdmissionStep.allCases.map(\.rawValue) + ["prelaunch","spawn"] {
            let f = try await Self.fixture(); defer { f.cleanup() }
            if phase == "spawn" { try Data("Generated invalid executable".utf8).write(to:f.executable) }
            let tool = try f.tool, pipes = PrelaunchPipeCloses(), pins = AdmissionCloses(), state = State(), original = try Data(contentsOf:f.source)
            let roles = prelaunchRoles(phase)
            await #expect(throws: NativeExportError.self) {
                try await Writer.$testBoundary.withValue(.init(launched: { state.launch($0) }, closed: { pipes.add($0,$1,$2) },
                    pipeAdmission: { step in if step.rawValue == phase { throw NativeExportError.invalid("Generated pipe admission refusal") } },
                    beforeSpawn: { if phase == "prelaunch" { throw NativeExportError.invalid("Generated prelaunch refusal") } },
                    pinClosed: { role,fd,status in pipes.expect(roles); pins.add(role,fd,status) })) {
                    try await Writer.run(tool:tool,source:f.source,stage:f.stage,retention:.metadataOnly)
                }
            }
            pipes.expect(roles); pins.expect(Writer.PinRole.allCases); #expect(state.pid == 0 && Writer.retainedPins(source:f.source) == nil)
            #expect(try Data(contentsOf:f.source) == original && FileManager.default.contentsOfDirectory(atPath:f.stage.path).isEmpty)
        }
    }
    @Test func writerPartialPipeReportsKeepSameOwnerCauseAfterTaskDropAndConflict() async throws {
        for phase in ["stdinOpened","stdoutOpened","stderrOpened","prelaunch","spawn"] {
            for firstOnly in [true,false] {
                let f = try await Self.fixture(); defer { print("GENERATED_WRITER_PRELAUNCH_PIPE_REVIEW " + f.root.path) }
                if phase == "spawn" { try Data("Generated invalid executable".utf8).write(to:f.executable) }
                let tool = try f.tool, pipes = PrelaunchPipeCloses(), pins = AdmissionCloses(), roles = prelaunchRoles(phase)
                var task: Task<CompanionWriterProtocol.Receipt,Error>? = Task {
                    try await Writer.$testBoundary.withValue(.init(launched: { _ in Issue.record("Refused prelaunch pipe launched writer") },
                        closed: { pipes.add($0,$1,$2) }, refuseClose: { role,_,status in status == 0 && (!firstOnly || role == .stdinRead) },
                        pipeAdmission: { step in if step.rawValue == phase { throw CancellationError() } },
                        beforeSpawn: { if phase == "prelaunch" { throw CancellationError() } }, pinClosed: { pins.add($0,$1,$2) })) {
                        try await Writer.run(tool:tool,source:f.source,stage:f.stage,retention:.metadataOnly)
                    }
                }
                do { _ = try await task!.value; Issue.record("Partial pipe report returned receipt") }
                catch let e as Writer.PipeCloseFailure { #expect(e.roles == (firstOnly ? [.stdinRead] : roles)); #expect(phase == "spawn" ? e.operationError is NativeExportError : e.operationError is CancellationError) }
                task=nil; pipes.expect(roles); pins.expect(Writer.PinRole.allCases)
                let witness = WeakWriterPins(Writer.retainedPins(source:f.source))
                #expect(witness.value != nil && witness.value?.descriptorsForTesting == [-1,-1,-1] && witness.value?.pipeDescriptorsForTesting == Array(repeating:-1,count:6))
                await #expect(throws: NativeExportError.self) { try await Writer.run(tool:tool,source:f.source,stage:f.stage,retention:.metadataOnly) }
                Writer.isolateGeneratedPinsForTesting(try #require(witness.value)); #expect(witness.value == nil)
            }
        }
    }
    @Test func actualTaskCancellationAtPipeAdmissionAndPrelaunchClosesPairsBeforePins() async throws {
        for phase in Writer.PipeAdmissionStep.allCases.map(\.rawValue) + ["prelaunch"] {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let tool = try f.tool, gate = PrelaunchGate(), pipes = PrelaunchPipeCloses(), pins = AdmissionCloses(), roles = prelaunchRoles(phase)
            let task = Task {
                defer { gate.signal.finish() }
                return try await Writer.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled prelaunch pipe launched writer") },
                    closed: { pipes.add($0,$1,$2) }, pipeAdmission: { step in if step.rawValue == phase { gate.hold() } },
                    beforeSpawn: { if phase == "prelaunch" { gate.hold() } }, pinClosed: { role,fd,status in pipes.expect(roles); pins.add(role,fd,status) })) {
                    try await Writer.run(tool:tool,source:f.source,stage:f.stage,retention:.metadataOnly)
                }
            }
            for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
            await #expect(throws: CancellationError.self) { try await task.value }
            pipes.expect(roles); pins.expect(Writer.PinRole.allCases); #expect(Writer.retainedPins(source:f.source) == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath:f.stage.path).isEmpty)
        }
    }

}
