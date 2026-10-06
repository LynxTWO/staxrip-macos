import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
@MainActor
struct CompanionArchiveOperationTests {
    typealias Operation = CompanionArchiveOperation
    typealias Fixture = CompanionOriginalMetadataCheckTests.Fixture
    private final class Ledger: @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0, scopes = 0, ended = 0, stopped = 0
        private var launched: [pid_t] = [], joined: [pid_t] = []
        private var pins: [(Int32, OriginalCompanionTransaction.FileID)] = []
        func pinned(_ descriptors: [Int32]) {
            lock.withLock {
                #expect(descriptors.count == 2)
                pins = descriptors.enumerated().map { i, fd in
                    var s = stat(); #expect(fstat(fd, &s) == 0)
                    #expect(s.st_mode & mode_t(S_IFMT) == mode_t(i == 0 ? S_IFREG : S_IFDIR))
                    return (fd, .init(s))
                }
            }
        }
        private func checkPins() {
            for (fd, id) in pins { var s = stat(); #expect(fstat(fd, &s) == 0 && OriginalCompanionTransaction.FileID(s) == id) }
        }
        func beginActivity() { lock.withLock { active += 1 } }
        func endActivity() { lock.withLock { #expect(active == 1); active -= 1; ended += 1 } }
        func beginScope() { lock.withLock { scopes += 1 } }
        func endScope() { lock.withLock { #expect(scopes > 0); scopes -= 1; stopped += 1 } }
        func expectActive(scoped: Bool = false) { lock.withLock { #expect(active == 1); checkPins(); if scoped { #expect(scopes == 2) } } }
        func expectEnded(scoped: Bool = false) { lock.withLock { #expect(active == 0 && ended == 1); if scoped { #expect(scopes == 0 && stopped == 2) } } }
        func expectRetainedGrants() { lock.withLock { #expect(scopes == 2 && stopped == 0) } }
        func expectRetained() { lock.withLock { #expect(scopes == 2 && stopped == 0); checkPins() } }
        private var closedCount = 0
        func closed(_ count: Int) { lock.withLock { #expect(closedCount == 0 && count == 2); closedCount = count } }
        func expectClosed() { lock.withLock { #expect(closedCount == 2) } }
        var latestPID: pid_t? { lock.withLock { launched.last } }
        func launch(_ p: pid_t) { expectActive(); lock.withLock { launched.append(p) } }
        func join(_ p: pid_t) { expectActive(); lock.withLock { joined.append(p) } }
        func expectJoined(count: Int) {
            let pair = lock.withLock { (launched, joined) }
            #expect(pair.0.count == count && pair.0 == pair.1)
            for p in pair.0 { var status: Int32 = 0; #expect(waitpid(p, &status, WNOHANG) == -1 && errno == ECHILD) }
        }
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>, signal: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value: 0)
        private let lock = NSLock(); private var held = false
        func holdFirst() { if lock.withLock({ if held { return false }; held = true; return true }) { hold() } }
        init() { let p = AsyncStream<Void>.makeStream(); entered = p.stream; signal = p.continuation }
        func hold() { signal.yield(()); signal.finish(); if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated access gate expired") } }
    }
    private func fixture() async throws -> Fixture {
        try await CompanionOriginalMetadataCheckTests.fixture()
    }
    private func environment(_ ledger: Ledger, fakeScopes: Bool) -> Operation.Environment {
        .init(access: { url in
            if fakeScopes { ledger.beginScope(); return { ledger.endScope() } }
            // Actual ordinary URLs often have no sandbox extension. False is not
            // denied access; the operation must still qualify concrete descriptors.
            guard url.startAccessingSecurityScopedResource() else { return nil }
            ledger.beginScope(); return { url.stopAccessingSecurityScopedResource(); ledger.endScope() }
        }, activity: { reason in
            ledger.beginActivity(); let end = ExportActivity.begin(reason: reason)
            return { end(); ledger.endActivity() }
        }, retainedActivitySeconds: 0.05)
    }
    private func execute(_ f: Fixture, mode: OriginalCompanionTransaction.Retention = .metadataOnly) async throws -> ResultSetStaging.Published {
        try await Operation.execute(source: f.source, reviewedSource: f.reviewedSource, in: f.root, destinationName: "published", retention: mode, writer: f.tool, reader: f.readerTool)
    }
    private func assertions() throws -> String {
        let p = Process(), pipe = Pipe(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]; p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        try #require(p.terminationStatus == 0 && data.count < 1 << 20)
        return String(decoding: data, as: UTF8.self)
    }
    private func ownAssertion(_ text: String, reason: String = "StaxRip original companion preservation") -> Bool {
        text.split(separator: "\n").contains { $0.contains("pid \(getpid())(") && $0.contains("PreventUserIdleSystemSleep") && $0.contains(reason) }
    }
    @Test func actualNativeBothModesHoldAccessActivityThroughJoinedPhasesAndExclusiveCommit() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let f = try await fixture(); defer { f.cleanup() }
            let ledger = Ledger(), original = try Data(contentsOf: f.source)
            let result = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: false)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in ledger.expectActive() }, pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit: { ledger.expectActive() }, afterCommit: { ledger.expectActive() })) {
                                try await execute(f, mode: mode)
                            }
                        }
                    }
                }
            }
            ledger.expectJoined(count: 2); ledger.expectEnded(); ledger.expectClosed()
            #expect(!ownAssertion(try assertions()))
            #expect(try Data(contentsOf: f.source) == original)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: result.directory.path)) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf: result.directory.appendingPathComponent("original-container.mkv")) == original) }
            let prior = try Data(contentsOf: result.directory.appendingPathComponent("manifest.json"))
            await #expect(throws: (any Error).self) { try await execute(f, mode: mode) }
            #expect(try Data(contentsOf: result.directory.appendingPathComponent("manifest.json")) == prior)
        }
    }
    @Test func reviewedContentMismatchRefusesBothRetentionModesAfterIndependentVerification() async throws {
        let f = try await fixture()
        let original = try Data(contentsOf: f.source), reviewed = f.reviewedSource
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            for wrongBytes in [false, true] {
                let ledger = Ledger()
                let stale = SourceFingerprint(sha256: wrongBytes ? reviewed.sha256 : String(repeating: "0", count: 64),
                                              byteCount: reviewed.byteCount + (wrongBytes ? 1 : 0))
                do {
                    _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                        try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) })) {
                            try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                                try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                                    try await Operation.execute(source: f.source, reviewedSource: stale, in: f.root,
                                        destinationName: "stale-review", retention: mode, writer: f.tool, reader: f.readerTool)
                                }
                            }
                        }
                    }
                    Issue.record("Stale reviewed content published")
                } catch NativeExportError.invalid(let message) {
                    #expect(message == "The original source no longer matches the reviewed content. Review it again before preservation.")
                }
                ledger.expectJoined(count: 2); ledger.expectEnded(scoped: true); ledger.expectClosed()
                #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("stale-review").path))
                #expect(try Data(contentsOf: f.source) == original)
            }
        }
        // Retain the generated fixture; this does not qualify native UI consent.
        print("GENERATED_REVIEWED_CONTENT_RETAINED " + f.root.path)
    }
    private final class WriterPipeCloses: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(CompanionWriterProcess.PipeRole, Int32, Int32)] = []
        func add(_ role: CompanionWriterProcess.PipeRole, _ fd: Int32, _ status: Int32) {
            lock.withLock { values.append((role, fd, status)) }
        }
        func expectOnce() {
            lock.withLock {
                #expect(values.count == 6 && values.allSatisfy { $0.1 >= 0 && $0.2 == 0 })
                for role in CompanionWriterProcess.PipeRole.allCases { #expect(values.filter { $0.0 == role }.count == 1) }
            }
        }
    }
    private final class WriterPinCloses: @unchecked Sendable {
        private let lock = NSLock(); private var values: [(CompanionWriterProcess.PinRole,Int32,Int32)] = []
        func add(_ role: CompanionWriterProcess.PinRole, _ fd: Int32, _ status: Int32) { lock.withLock { values.append((role,fd,status)) } }
        func expectOnce() {
            lock.withLock {
                #expect(values.count == 3 && values.allSatisfy { $0.1 >= 0 && $0.2 == 0 })
                for role in CompanionWriterProcess.PinRole.allCases { #expect(values.filter { $0.0 == role }.count == 1) }
            }
        }
    }
    @Test func checkedWriterPipesPrecedeBothModeSemanticVerificationAndExclusivePublication() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let f = try await fixture(); defer { f.cleanup() }
            let ledger = Ledger(), closes = WriterPipeCloses(), pinCloses = WriterPinCloses(), original = try Data(contentsOf: f.source)
            let result = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) }, closed: { closes.add($0, $1, $2) }, pinClosed: { pinCloses.add($0,$1,$2) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { closes.expectOnce(); pinCloses.expectOnce(); ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await execute(f, mode: mode)
                        }
                    }
                }
            }
            closes.expectOnce(); ledger.expectJoined(count: 2); ledger.expectEnded(scoped: true); ledger.expectClosed()
            #expect(!ownAssertion(try assertions()))
            #expect(try Data(contentsOf: f.source) == original)
            let names = try FileManager.default.contentsOfDirectory(atPath: result.directory.path)
            #expect(Set(names) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf: result.directory.appendingPathComponent("original-container.mkv")) == original) }
            let published = try snapshot(result.directory)
            await #expect(throws: (any Error).self) { try await execute(f, mode: mode) }
            let after = try snapshot(result.directory); #expect(after == published)
        }
    }
    @Test func checkedWriterPipeUncertaintyRetainsConcreteStageAccessAfterDropExpiryAndSourcePriority() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for fault in ["one", "all", "cancel", "source-priority"] {
            let f = try await fixture(), ledger = Ledger(), closes = WriterPipeCloses(), gate = Gate()
            defer { print("GENERATED_WRITER_PIPE_ACCESS_REVIEW " + f.root.path) }
            let original = try Data(contentsOf: f.source), prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior output".utf8)
            try priorBytes.write(to: prior)
            var task: Task<ResultSetStaging.Published, any Error>? = Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { _ in Issue.record("Uncertain writer released outer pins") })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, ready: { if fault == "cancel" { gate.hold() } }, settled: { ledger.join($0) }, closed: { closes.add($0, $1, $2) }, refuseClose: { role,_,_ in fault == "all" || role == .stdinRead })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Uncertain writer launched verifier") })) {
                                try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose: { fault == "source-priority" })) { try await execute(f, mode: mode) }
                            }
                        }
                    }
                }
            }
            if fault == "cancel" {
                for await _ in gate.entered { break }
                ledger.expectActive(scoped: true)
                #expect(ownAssertion(try assertions()))
                let pid = try #require(ledger.latestPID)
                let state = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
                #expect(state.status == 0 && !String(decoding: state.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
                task?.cancel(); gate.release.signal()
            }
            var reviewID: UUID?
            weak var retained: ResultSetStaging?
            do { _ = try await task!.value; Issue.record("Writer pipe uncertainty returned publication") }
            catch let e as Operation.ReviewFailure {
                reviewID = e.reviewID; retained = Operation.retainedStageForTesting(e.reviewID)
                #expect(e.published == nil && e.removed == nil)
                var underlying: (any Error)?
                if fault == "source-priority" {
                    let source = try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)
                    underlying = source.operationError
                } else {
                    let phase = try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)
                    underlying = phase.operationError
                }
                let pipe = try #require(underlying as? CompanionWriterProcess.PipeCloseFailure)
                #expect(Set(pipe.roles) == Set(fault == "all" ? CompanionWriterProcess.PipeRole.allCases : [.stdinRead]))
                if fault == "cancel" { #expect(pipe.operationError is CancellationError) }
                else { #expect(pipe.operationError == nil) }
            }
            task = nil // Drop the completed Task's retained error as well.
            // The returned error and worker locals are dropped. Existing registry owns
            // the same concrete stage and access, not only a namespace locator.
            let id = try #require(reviewID), stage = try #require(retained?.originalDirectoryURL)
            ledger.expectJoined(count: 1); closes.expectOnce(); ledger.expectRetained()
            let pins = try #require(retained?.retainedPinIdentitiesForTesting()), files = try snapshot(stage)
            #expect(pins.count == 2 && retained != nil)
            #expect(throws: NativeExportError.self) { try retained?.fileURL("manifest.json") }
            #expect(throws: NativeExportError.self) { try retained?.discard() }
            await #expect(throws: NativeExportError.self) { try await execute(f) }
            await #expect(throws: NativeExportError.self) { try await review(f) }
            try await Task.sleep(for: .milliseconds(100))
            ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id) && retained != nil)
            let laterPins = try #require(retained?.retainedPinIdentitiesForTesting()), laterFiles = try snapshot(stage)
            #expect(zip(pins, laterPins).allSatisfy { $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 } && files == laterFiles)
            #expect(try Data(contentsOf: f.source) == original && Data(contentsOf: prior) == priorBytes)
            #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("published").path))
            // Only controlled DEBUG isolation after all generated workers/children join;
            // no production recovery/cleanup authority or stage fallback-close proof.
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
            #expect(retained == nil)
          }
        }
    }

    @Test func positiveInjectedScopesBalanceAndSecondAcquisitionFailureRollsBackWithoutActivity() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger()
        _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
            try await Operation.$testBoundary.withValue(.init(phase: { _ in ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) })) { try await execute(f) }
        }
        ledger.expectEnded(scoped: true)
        var stopped = 0, attempts = 0, activities = 0
        let failed = Operation.Environment(access: { _ in
            attempts += 1
            if attempts == 2 { throw NativeExportError.invalid("Generated acquisition refusal") }
            return { stopped += 1 }
        }, activity: { _ in activities += 1; return {} })
        await Operation.$testEnvironment.withValue(failed) { await #expect(throws: NativeExportError.self) { try await execute(f) } }
        #expect(attempts == 2 && stopped == 1 && activities == 0)
    }
    @Test func realSourceParentDescriptorRefusalsAndPrecancelAcquireNoActivity() async throws {
        let f = try await fixture(); defer { f.cleanup() }; var activities = 0
        let env = Operation.Environment(activity: { _ in activities += 1; return {} })
        let writer = try f.tool, reader = try f.readerTool
        for (source, parent) in [(f.root.appendingPathComponent("missing"), f.root), (f.source, f.source)] {
            await Operation.$testEnvironment.withValue(env) {
                await #expect(throws: NativeExportError.self) { try await Operation.execute(source: source, reviewedSource: f.reviewedSource, in: parent, destinationName: "refused", retention: .metadataOnly, writer: writer, reader: reader) }
            }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Operation.$testEnvironment.withValue(env) { try await execute(f) }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(activities == 0)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("refused").path))
    }
    @Test func actualMalformedSourceWriterRefusalJoinsAndCleansBeforeBalancedRelease() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger()
        let invalid = Data("Generated invalid container".utf8); try invalid.write(to: f.source)
        let baseline = Set(try FileManager.default.contentsOfDirectory(atPath: f.root.path))
        await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
            await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                await #expect(throws: NativeExportError.self) { try await execute(f) }
            }
        }
        ledger.expectJoined(count: 1); ledger.expectEnded(scoped: true)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: f.root.path)) == baseline)
        #expect(try Data(contentsOf: f.source) == invalid)
    }
    @Test(.enabled(if: geteuid() != 0))
    func actualPOSIXReadAndDestinationWriteDenialsDoNotLaunchWriter() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        let writer = try f.tool, reader = try f.readerTool, original = try Data(contentsOf: f.source)
        var sourceInfo = stat(); try #require(lstat(f.source.path, &sourceInfo) == 0)
        let sourceMode = sourceInfo.st_mode & 0o7777
        var starts = 0, ends = 0
        let env = Operation.Environment(activity: { _ in starts += 1; return { ends += 1 } })
        let denied = f.root.appendingPathComponent("denied-parent")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o555])
        defer { _ = chmod(denied.path, 0o700); _ = chmod(f.source.path, sourceMode) }
        try #require(chmod(f.source.path, 0) == 0)
        await Operation.$testEnvironment.withValue(env) {
            await #expect(throws: NativeExportError.self) {
                try await Operation.execute(source: f.source, reviewedSource: f.reviewedSource, in: f.root, destinationName: "refused", retention: .metadataOnly, writer: writer, reader: reader)
            }
        }
        #expect(starts == 0 && ends == 0)
        try #require(chmod(f.source.path, sourceMode) == 0)
        await Operation.$testEnvironment.withValue(env) {
            await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Permission denial launched writer") })) {
                await #expect(throws: NativeExportError.self) {
                    try await Operation.execute(source: f.source, reviewedSource: f.reviewedSource, in: denied, destinationName: "refused", retention: .metadataOnly, writer: writer, reader: reader)
                }
            }
        }
        #expect(starts == 1 && ends == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: denied.path).isEmpty)
        #expect(try Data(contentsOf: f.source) == original)
    }
    @Test func actualReaderCancellationJoinsBeforeAccessReleaseOrTypedReviewRetention() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), gate = Gate()
        let original = try Data(contentsOf: f.source)
        let task = Task {
            try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                    try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); gate.hold() }, settled: { ledger.join($0) })) {
                        try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) { try await execute(f) }
                    }
                }
            }
        }
        for await _ in gate.entered { break }
        ledger.expectActive(scoped: true); #expect(ownAssertion(try assertions()))
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        task.cancel(); ledger.expectActive(scoped: true); gate.release.signal()
        do { _ = try await task.value; Issue.record("Cancelled access operation published") }
        catch is CancellationError { ledger.expectEnded(scoped: true) }
        catch let e as Operation.ReviewFailure {
            let phase = try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)
            #expect((phase.operationError as? CompanionMetadataProcess.OwnershipFailure)?.reason == "group-1-joined-true")
            ledger.expectRetained(); #expect(Operation.retainedForTesting(e.reviewID))
            // Actual fixed generated helper has returned/joined; no production
            // settlement authority or OS signal-denial repair is inferred.
            ledger.expectJoined(count: 2); Operation.releaseGeneratedReviewForTesting(e.reviewID)
            ledger.expectEnded(scoped: true)
        }
        ledger.expectJoined(count: 2)
        #expect(!ownAssertion(try assertions()))
        #expect(try Data(contentsOf: f.source) == original)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("published").path))
    }
    @Test func controlledUnsettledPhaseRetainsAccessAfterEnergyExpiryAndDroppedError() async throws {
        struct ControlledUnsettled: CompanionUnsettledOwnership {}
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                    try await Operation.$testBoundary.withValue(.init(phase: { phase in if phase == "verifier" { throw ControlledUnsettled() } }, pinned: { ledger.pinned($0) })) { try await execute(f) }
                }
            }
            Issue.record("Injected unsettled phase published")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(FileManager.default.fileExists(atPath: e.intendedStage.path)) }
        let id = try #require(reviewID); ledger.expectJoined(count: 1); ledger.expectActive(scoped: true)
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        try await Task.sleep(for: .milliseconds(100))
        ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        Operation.releaseGeneratedReviewForTesting(id); #expect(!Operation.retainedForTesting(id)); ledger.expectEnded(scoped: true)
    }
    @Test func actualStageSubstitutionAfterJoinedWriterRetainsAccessForCleanupReview() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger()
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) }, beforeReceipt: {
                    do {
                        let name = try #require(FileManager.default.contentsOfDirectory(atPath: f.root.path).first { $0.hasPrefix(".staxrip-result-") })
                        let stage = f.root.appendingPathComponent(name)
                        try FileManager.default.moveItem(at: stage, to: f.root.appendingPathComponent("retained-original-stage"))
                        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
                    } catch { Issue.record("Generated stage substitution failed") }
                })) { try await execute(f) }
            }
            Issue.record("Substituted stage published")
        } catch let e as Operation.ReviewFailure {
            #expect(e.operationError is OriginalCompanionTransaction.CleanupFailure)
            ledger.expectJoined(count: 1); ledger.expectRetained()
            #expect(FileManager.default.fileExists(atPath: e.intendedStage.path))
            #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("retained-original-stage/manifest.json").path))
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
        }
    }

    private func candidate(_ mode: OriginalCompanionTransaction.Retention = .metadataOnly) async throws -> Fixture {
        let f = try await fixture()
        do { _ = try await CompanionWriterProcess.run(tool: f.tool, source: f.source, stage: f.stage, retention: mode); return f }
        catch { f.cleanup(); throw error }
    }
    private func review(_ f: Fixture, mode: OriginalCompanionTransaction.Retention = .metadataOnly) async throws -> CompanionDiskCheck.Receipt {
        try await Operation.reviewCandidate(source: f.source, candidate: f.stage, retention: mode, reader: f.readerTool)
    }
    private func snapshot(_ url: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: url.path).map {
            ($0, try Data(contentsOf: url.appendingPathComponent($0)))
        })
    }
    @Test func actualReadOnlyBothModesOwnOnlyExplicitSourceCandidateAndJoinBeforeRelease() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let f = try await candidate(mode); defer { f.cleanup() }
            let ledger = Ledger(), original = try Data(contentsOf: f.source), before = try snapshot(f.stage)
            let prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior output".utf8)
            try priorBytes.write(to: prior)
            var requested: [URL] = [], stopped: [URL] = []
            var env = environment(ledger, fakeScopes: true)
            env.access = { url in
                requested.append(url); ledger.beginScope()
                return { stopped.append(url); ledger.endScope() }
            }
            let result = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(phase: { phase in #expect(phase == "reviewer"); ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) })) {
                    try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await review(f, mode: mode)
                    }
                }
            }
            #expect(requested == [f.source, f.stage] && stopped == [f.stage, f.source])
            #expect(result.originalMetadataSemanticsVerified && result.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
            ledger.expectJoined(count: 1); ledger.expectEnded(scoped: true); ledger.expectClosed()
            #expect(!ownAssertion(try assertions(), reason: "StaxRip original companion review"))
            #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original && Data(contentsOf: prior) == priorBytes)
        }
    }
    @Test func readOnlyAcquisitionRollbackPrecancelAndActualPOSIXDenialAcquireNoActivity() async throws {
        let f = try await candidate(); defer { f.cleanup() }
        let original = try Data(contentsOf: f.source), before = try snapshot(f.stage)
        var attempts = 0, stopped = 0, activities = 0
        let failed = Operation.Environment(access: { _ in
            attempts += 1
            if attempts == 2 { throw NativeExportError.invalid("Generated candidate grant refusal") }
            return { stopped += 1 }
        }, activity: { _ in activities += 1; return {} })
        await Operation.$testEnvironment.withValue(failed) { await #expect(throws: NativeExportError.self) { try await review(f) } }
        #expect(attempts == 2 && stopped == 1 && activities == 0)
        let env = Operation.Environment(activity: { _ in activities += 1; return {} })
        let reader = try f.readerTool
        for (source, folder) in [(f.root.appendingPathComponent("missing"), f.stage), (f.source, f.source)] {
            await Operation.$testEnvironment.withValue(env) {
                await #expect(throws: NativeExportError.self) { try await Operation.reviewCandidate(source: source, candidate: folder, retention: .metadataOnly, reader: reader) }
            }
        }
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await Operation.$testEnvironment.withValue(env) { try await review(f) } }
        await #expect(throws: CancellationError.self) { try await task.value }
        if geteuid() != 0 {
            var info = stat(); try #require(lstat(f.source.path, &info) == 0)
            let mode = info.st_mode & 0o7777
            defer { _ = chmod(f.source.path, mode); _ = chmod(f.stage.path, 0o700) }
            for url in [f.source, f.stage] {
                try #require(chmod(url.path, 0) == 0)
                await Operation.$testEnvironment.withValue(env) {
                    await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied review launched reader") })) {
                        await #expect(throws: NativeExportError.self) { try await review(f) }
                    }
                }
                try #require(chmod(url.path, url == f.source ? mode : 0o700) == 0)
            }
        }
        #expect(activities == 0)
        #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
    }
    @Test func readOnlySemanticRefusalBalancesAccessAfterActualReaderJoin() async throws {
        let f = try await candidate(); defer { f.cleanup() }; let ledger = Ledger()
        // Reuse the independently qualified semantic-forgery fixture machinery.
        let audit = f.stage.appendingPathComponent("source-audit.jsonl")
        var rows = try Data(contentsOf: audit).split(separator: 10).map { try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
        let index = try #require(rows.firstIndex { $0["kind"] as? String == "rpu-summary" })
        var summary = try #require(rows[index]["summary"] as? [String: Any])
        summary["cmv29_present"] = !(try #require(summary["cmv29_present"] as? Bool)); rows[index]["summary"] = summary
        var bytes = Data()
        for row in rows { bytes.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])); bytes.append(10) }
        try bytes.write(to: audit)
        let manifest = f.stage.appendingPathComponent("manifest.json")
        var m = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        var components = try #require(m["components"] as? [[String: Any]])
        let member = try #require(components.firstIndex { $0["name"] as? String == "source-audit.jsonl" })
        components[member]["bytes"] = bytes.count; components[member]["sha256"] = DolbyInspection.hex(SHA256.hash(data: bytes))
        m["components"] = components; try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]).write(to: manifest)
        let original = try Data(contentsOf: f.source), before = try snapshot(f.stage)
        await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
            await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) })) {
                await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                    await #expect(throws: NativeExportError.self) { try await review(f) }
                }
            }
        }
        ledger.expectJoined(count: 1); ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
    }
    @Test func liveReadOnlyCancellationHoldsOSActivityAndExcludesWriterUntilSettlement() async throws {
        let f = try await candidate(); var retainedFixture = false
        defer { if retainedFixture { print("GENERATED_ACCESS_CANDIDATE_REVIEW " + f.root.path) } else { f.cleanup() } }
        let ledger = Ledger(), gate = Gate(), original = try Data(contentsOf: f.source), before = try snapshot(f.stage)
        let task = Task {
            try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                    try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); gate.hold() }, settled: { ledger.join($0) })) {
                        try await review(f)
                    }
                }
            }
        }
        for await _ in gate.entered { break }
        ledger.expectActive(scoped: true)
        #expect(ownAssertion(try assertions(), reason: "StaxRip original companion review"))
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        task.cancel(); gate.release.signal()
        do { _ = try await task.value; Issue.record("Cancelled read-only review succeeded") }
        catch is CancellationError { ledger.expectEnded(scoped: true) }
        catch let e as Operation.ReviewFailure {
            retainedFixture = true
            #expect((e.operationError as? CompanionMetadataProcess.OwnershipFailure)?.reason == "group-1-joined-true")
            ledger.expectJoined(count: 1); ledger.expectRetained()
            #expect(Operation.retainedForTesting(e.reviewID))
            // Isolate only the generated registry after the fixed child's observed
            // join; retain files. No production group settlement or cleanup follows.
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
        }
        ledger.expectJoined(count: 1)
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original companion review"))
        #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
    }
    @Test func controlledUnsettledReadOnlyReviewRetainsDroppedErrorAndScopesAfterEnergyExpiry() async throws {
        struct ControlledUnsettled: CompanionUnsettledOwnership {}
        let f = try await candidate(); defer { f.cleanup() }; let ledger = Ledger()
        let original = try Data(contentsOf: f.source), before = try snapshot(f.stage)
        var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in throw ControlledUnsettled() }, pinned: { ledger.pinned($0) })) { try await review(f) }
            }
            Issue.record("Unsettled read-only review succeeded")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.intendedStage == f.stage) }
        let id = try #require(reviewID); ledger.expectRetained(); ledger.expectActive(scoped: true)
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        try await Task.sleep(for: .milliseconds(100))
        ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
    }
    @Test func finalReadOnlyCandidateSubstitutionRetainsPinnedOriginalAfterReaderJoin() async throws {
        let f = try await candidate(); defer { f.cleanup() }; let ledger = Ledger()
        let original = try Data(contentsOf: f.source), before = try snapshot(f.stage), moved = f.root.appendingPathComponent("retained-candidate")
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                    try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
                            do {
                                try FileManager.default.moveItem(at: f.stage, to: moved)
                                try FileManager.default.createDirectory(at: f.stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                            } catch { Issue.record("Generated candidate substitution failed") }
                        })) { try await review(f) }
                    }
                }
            }
            Issue.record("Changed candidate reviewed successfully")
        } catch let e as Operation.ReviewFailure {
            #expect(e.intendedStage == f.stage); ledger.expectJoined(count: 1); ledger.expectRetained()
            #expect(try snapshot(moved) == before && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
        }
        #expect(try Data(contentsOf: f.source) == original)
    }

    @Test func relocatedSealedRustReaderHostRunsBothNativeModesAndReadOnlyReviewWithJoinedAccess() async throws {
        let b = try await HardenedReaderBundleFixture.make(); defer { b.cleanup() }
        let original = try Data(contentsOf: b.original.source), (writer, reader) = try b.admit()
        let prior = b.original.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior output".utf8)
        try priorBytes.write(to: prior)
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let ledger = Ledger()
            let result = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: false)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await Operation.execute(source: b.original.source, reviewedSource: b.original.reviewedSource, in: b.original.root,
                                destinationName: mode == .metadataOnly ? "metadata-result" : "container-result", retention: mode, writer: writer, reader: reader)
                        }
                    }
                }
            }
            ledger.expectJoined(count: 2); ledger.expectEnded()
            let before = try snapshot(result.directory), reviewLedger = Ledger()
            let reviewed = try await Operation.$testEnvironment.withValue(environment(reviewLedger, fakeScopes: false)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { reviewLedger.pinned($0) })) {
                    try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { reviewLedger.launch($0) }, settled: { reviewLedger.join($0) })) {
                        try await Operation.reviewCandidate(source: b.original.source, candidate: result.directory, retention: mode, reader: reader)
                    }
                }
            }
            #expect(reviewed.originalMetadataSemanticsVerified && reviewed.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
            reviewLedger.expectJoined(count: 1); reviewLedger.expectEnded()
            #expect(try snapshot(result.directory) == before)
            #expect(try Data(contentsOf: b.original.source) == original && Data(contentsOf: prior) == priorBytes)
        }
        _ = try b.admit()
        let osState = try assertions()
        #expect(!ownAssertion(osState) && !ownAssertion(osState, reason: "StaxRip original companion review"))
    }
    @Test func relocatedHardenedReaderHostCancellationKeepsAccessUntilJoinOrTypedReview() async throws {
        let b = try await HardenedReaderBundleFixture.make(); var keep = false
        defer { if keep { print("GENERATED_HARDENED_BUNDLE_REVIEW " + b.original.root.path) } else { b.cleanup() } }
        let (writer, reader) = try b.admit()
        _ = try await CompanionWriterProcess.run(tool: writer, source: b.original.source, stage: b.original.stage, retention: .metadataOnly)
        let ledger = Ledger(), gate = Gate(), original = try Data(contentsOf: b.original.source), before = try snapshot(b.original.stage)
        let task = Task {
            try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: false)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                    try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); gate.hold() }, settled: { ledger.join($0) })) {
                        try await Operation.reviewCandidate(source: b.original.source, candidate: b.original.stage, retention: .metadataOnly, reader: reader)
                    }
                }
            }
        }
        for await _ in gate.entered { break }; ledger.expectActive()
        task.cancel(); gate.release.signal()
        do { _ = try await task.value; Issue.record("Cancelled hardened reader-host review succeeded") }
        catch is CancellationError { ledger.expectEnded() }
        catch let e as Operation.ReviewFailure {
            keep = true
            #expect((e.operationError as? CompanionMetadataProcess.OwnershipFailure)?.reason == "group-1-joined-true")
            ledger.expectJoined(count: 1); #expect(Operation.retainedForTesting(e.reviewID))
            // Controlled registry isolation only; uncertain generated files survive.
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded()
        }
        ledger.expectJoined(count: 1); _ = try b.admit()
        #expect(try Data(contentsOf: b.original.source) == original && snapshot(b.original.stage) == before)
    }
    private nonisolated static var frozenDecoderDirectory: String? {
        ProcessInfo.processInfo.environment["STAXRIP_TEST_FROZEN_DECODER_DIRECTORY"]
    }
    private func associationTool(in root: URL) throws -> DolbyDecoderProcess.Tool {
        let hash = String(repeating: "a", count: 64)
        return try .development(root.appendingPathComponent("Helpers/reference"), expectedSHA256: hash,
            libraries: Dictionary(uniqueKeysWithValues: ["libavcodec.63.dylib", "libavformat.63.dylib", "libavutil.61.dylib"].map { ($0, hash) }), versions: [1, 1, 1])
    }
    private func associate(_ f: Fixture, tool: DolbyDecoderProcess.Tool) async throws -> CompanionDiskCheck.SourceFrameReceipt {
        try await Operation.associateOriginalFrames(source: f.source, spoolDirectory: f.stage, tool: tool)
    }
    @Test func associationAcquisitionRollbackPrecancelAndActualReadWriteDenials() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        let tool = try associationTool(in: f.root), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], starts = 0, ends = 0
        let failed = Operation.Environment(access: { url in
            requested.append(url)
            if url == f.stage { throw NativeExportError.invalid("Generated spool grant refusal") }
            return { stopped.append(url) }
        }, activity: { _ in starts += 1; return { ends += 1 } })
        await Operation.$testEnvironment.withValue(failed) {
            await #expect(throws: NativeExportError.self) { try await associate(f, tool: tool) }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.source] && starts == 0)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await Operation.$testEnvironment.withValue(failed) { try await associate(f, tool: tool) } }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(requested == [f.source, f.stage])
        let env = Operation.Environment(activity: { _ in starts += 1; return { ends += 1 } })
        if geteuid() != 0 {
            var info = stat(); try #require(lstat(f.source.path, &info) == 0)
            let mode = info.st_mode & 0o7777
            defer { _ = chmod(f.source.path, mode); _ = chmod(f.stage.path, 0o700) }
            for (url, deniedMode) in [(f.source, mode_t(0)), (f.stage, mode_t(0))] {
                try #require(chmod(url.path, deniedMode) == 0)
                await Operation.$testEnvironment.withValue(env) {
                    await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied source/spool launched decoder") })) {
                        await #expect(throws: NativeExportError.self) { try await associate(f, tool: tool) }
                    }
                }
                try #require(chmod(url.path, url == f.source ? mode : 0o700) == 0)
            }
            #expect(starts == 0 && ends == 0)
            // Keep strict private POSIX mode while actual generated ACL denies
            // creation of the fixed member. Remove only this fixture's new ACL.
            let acl = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["+a", "everyone deny add_file", f.stage.path])
            try #require(acl.status == 0)
            defer { let result = chmod(f.stage.path, 0o700); #expect(result == 0) }
            await Operation.$testEnvironment.withValue(env) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied spool write launched decoder") })) {
                    await #expect(throws: DolbyAssociationSpool.Failure.self) { try await associate(f, tool: tool) }
                }
            }
            let removed = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["-N", f.stage.path])
            try #require(removed.status == 0)
            #expect(starts == 1 && ends == 1)
        }
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func associationSourceRefusalClosesPinsAndBalancesOnlyExplicitGrants() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger()
        let tool = try associationTool(in: f.root), invalid = Data("Generated invalid source".utf8)
        try invalid.write(to: f.source)
        var requested: [URL] = [], stopped: [URL] = []
        var env = environment(ledger, fakeScopes: true)
        env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } }
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(phase: { phase in #expect(phase == "association"); ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Invalid source launched decoder") })) {
                    await #expect(throws: NativeExportError.self) { try await associate(f, tool: tool) }
                }
            }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.stage, f.source])
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source frame association"))
        #expect(try Data(contentsOf: f.source) == invalid)
        // A partial disposable SQLite file is still owned by this explicit caller.
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test func controlledUnsettledAssociationRetainsAccessAndExcludesAllOperationKindsAfterExpiry() async throws {
        struct ControlledUnsettled: CompanionUnsettledOwnership {}
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), tool = try associationTool(in: f.root)
        let original = try Data(contentsOf: f.source); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in throw ControlledUnsettled() }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) { try await associate(f, tool: tool) }
            }
            Issue.record("Controlled uncertain association returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.intendedStage == f.stage) }
        let id = try #require(reviewID); ledger.expectRetained(); ledger.expectActive(scoped: true)
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: tool) }
        try await Task.sleep(for: .milliseconds(100))
        ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }

    @Test func activeSourcePassCancellationSettlesBeforeGrantAndPinRelease() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), gate = Gate(), tool = try associationTool(in: f.root)
        let original = try Data(contentsOf: f.source)
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled source pass launched decoder") })) {
                        try await CompanionDiskCheck.$testBoundary.withValue(.init(progress: { phase, _ in if phase == "source" { gate.holdFirst() } })) { try await associate(f, tool: tool) }
                    }
                }
            }
        }
        for await _ in gate.entered { break }; ledger.expectActive(scoped: true)
        task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func controlledActualOuterCloseRefusalRetainsGrantsWithoutRetryingDescriptor() async throws {
        final class CloseFault: @unchecked Sendable {
            private let lock = NSLock(); private var descriptors: [Int32] = []
            func pins(_ fds: [Int32]) { lock.withLock { descriptors = fds } }
            func removeOne() throws {
                let fd = try lock.withLock { try #require(descriptors.first) }
                try #require(Darwin.close(fd) == 0)
            }
        }
        let f = try await fixture(); defer { f.cleanup() }; let fault = CloseFault(), tool = try associationTool(in: f.root)
        try Data("Generated invalid source".utf8).write(to: f.source)
        var scopes = 0, stops = 0, energy = 0
        let env = Operation.Environment(access: { _ in scopes += 1; return { stops += 1 } }, activity: { _ in energy += 1; return { energy -= 1 } }, retainedActivitySeconds: 0.05)
        var id: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(pinned: { fault.pins($0) }, beforeAssociationRelease: { try fault.removeOne() })) { try await associate(f, tool: tool) }
            }
            Issue.record("Controlled close refusal released access")
        } catch let e as Operation.ReviewFailure { id = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let review = try #require(id)
        #expect(scopes == 2 && stops == 0 && energy == 1 && Operation.retainedForTesting(review))
        // The controller consumed both descriptor numbers. Controlled registry
        // isolation must not retry close and affect a later independently owned FD.
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(energy == 0 && stops == 0)
        Operation.releaseGeneratedReviewForTesting(review)
        var info = stat(); #expect(fstat(later, &info) == 0 && stops == 2 && energy == 0)
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    private nonisolated static var sampleDecoderDirectory: String? {
        ProcessInfo.processInfo.environment["STAXRIP_TEST_SAMPLE_DECODER_DIRECTORY"]
    }
    private func sampleAccessTool(in root: URL) throws -> DolbyDecoderProcess.Tool {
        let hash = String(repeating: "a", count: 64)
        return try .developmentSamples(root.appendingPathComponent("Helpers/sample-probe"), expectedSHA256: hash,
            libraries: Dictionary(uniqueKeysWithValues: ["libavcodec.63.dylib", "libavformat.63.dylib", "libavutil.61.dylib"].map { ($0, hash) }), versions: [1,1,1])
    }
    private func associateSamples(_ f: Fixture, tool: DolbyDecoderProcess.Tool) async throws -> CompanionDiskCheck.SourceSampleReceipt {
        try await Operation.associateOriginalSamples(source: f.source, spoolDirectory: f.stage, tool: tool)
    }
    @Test func sampleAssociationAcquisitionRollbackPrecancelAndActualReadWriteDenials() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        let tool = try sampleAccessTool(in: f.root), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], starts = 0, ends = 0
        let failed = Operation.Environment(access: { url in
            requested.append(url)
            if url == f.stage { throw NativeExportError.invalid("Generated spool grant refusal") }
            return { stopped.append(url) }
        }, activity: { _ in starts += 1; return { ends += 1 } })
        await Operation.$testEnvironment.withValue(failed) {
            await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: tool) }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.source] && starts == 0)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await Operation.$testEnvironment.withValue(failed) { try await associateSamples(f, tool: tool) } }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(requested == [f.source, f.stage])
        let env = Operation.Environment(activity: { _ in starts += 1; return { ends += 1 } })
        if geteuid() != 0 {
            var info = stat(); try #require(lstat(f.source.path, &info) == 0)
            let mode = info.st_mode & 0o7777
            defer { _ = chmod(f.source.path, mode); _ = chmod(f.stage.path, 0o700) }
            for (url, deniedMode) in [(f.source, mode_t(0)), (f.stage, mode_t(0))] {
                try #require(chmod(url.path, deniedMode) == 0)
                await Operation.$testEnvironment.withValue(env) {
                    await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied source/spool launched decoder") })) {
                        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: tool) }
                    }
                }
                try #require(chmod(url.path, url == f.source ? mode : 0o700) == 0)
            }
            #expect(starts == 0 && ends == 0)
            // Keep strict private POSIX mode while actual generated ACL denies
            // creation of the fixed member. Remove only this fixture's new ACL.
            let acl = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["+a", "everyone deny add_file", f.stage.path])
            try #require(acl.status == 0)
            defer { let result = chmod(f.stage.path, 0o700); #expect(result == 0) }
            await Operation.$testEnvironment.withValue(env) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied spool write launched decoder") })) {
                    await #expect(throws: DolbyAssociationSpool.Failure.self) { try await associateSamples(f, tool: tool) }
                }
            }
            let removed = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["-N", f.stage.path])
            try #require(removed.status == 0)
            #expect(starts == 1 && ends == 1)
        }
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func sampleAssociationSourceRefusalClosesPinsAndBalancesOnlyExplicitGrants() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger()
        let tool = try sampleAccessTool(in: f.root), invalid = Data("Generated invalid source".utf8)
        try invalid.write(to: f.source)
        var requested: [URL] = [], stopped: [URL] = []
        var env = environment(ledger, fakeScopes: true)
        env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } }
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(phase: { phase in #expect(phase == "sample-association"); ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Invalid source launched decoder") })) {
                    await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: tool) }
                }
            }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.stage, f.source])
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source sample association"))
        #expect(try Data(contentsOf: f.source) == invalid)
        // A partial disposable SQLite file is still owned by this explicit caller.
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test func sampleControlledUnsettledAssociationRetainsAccessAndExcludesAllOperationKindsAfterExpiry() async throws {
        struct ControlledUnsettled: CompanionUnsettledOwnership {}
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), tool = try sampleAccessTool(in: f.root)
        let original = try Data(contentsOf: f.source); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in throw ControlledUnsettled() }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) { try await associateSamples(f, tool: tool) }
            }
            Issue.record("Controlled uncertain association returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.intendedStage == f.stage) }
        let id = try #require(reviewID); ledger.expectRetained(); ledger.expectActive(scoped: true)
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
        try await Task.sleep(for: .milliseconds(100))
        ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }

    @Test func sampleActiveSourcePassCancellationSettlesBeforeGrantAndPinRelease() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), gate = Gate(), tool = try sampleAccessTool(in: f.root)
        let original = try Data(contentsOf: f.source)
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled source pass launched decoder") })) {
                        try await CompanionDiskCheck.$testBoundary.withValue(.init(progress: { phase, _ in if phase == "source" { gate.holdFirst() } })) { try await associateSamples(f, tool: tool) }
                    }
                }
            }
        }
        for await _ in gate.entered { break }; ledger.expectActive(scoped: true)
        task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func sampleReportedOuterCloseRefusalRetainsGrantsAfterActualCloses() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let tool = try sampleAccessTool(in: f.root)
        try Data("Generated invalid source".utf8).write(to: f.source)
        final class Reports: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let reports = Reports()
        var scopes = 0, stops = 0, energy = 0, reviewID: UUID?
        let env = Operation.Environment(access: { _ in scopes += 1; return { stops += 1 } }, activity: { _ in energy += 1; return { energy -= 1 } }, retainedActivitySeconds: 0.05)
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(associationClosed: { _ in Issue.record("Reported close refusal released access") }, refuseAssociationClose: { reports.report() })) {
                    try await associateSamples(f, tool: tool)
                }
            }
            Issue.record("Reported outer close uncertainty returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID)
        #expect(scopes == 2 && stops == 0 && energy == 1 && reports.value == 1 && Operation.retainedForTesting(id))
        // Actual closes have consumed numbers; no FD-number absence probe. A
        // subsequent independent FD must not be closed by controlled isolation.
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(energy == 0 && stops == 0)
        Operation.releaseGeneratedReviewForTesting(id)
        var info = stat(); #expect(fstat(later, &info) == 0 && stops == 2 && reports.value == 1)
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test(.enabled(if: frozenDecoderDirectory != nil), .timeLimit(.minutes(2)))
    func actualFrozenAssociationOwnsActivityBothThreadsCancellationAndFinalSelection() async throws {
        let runtime = URL(fileURLWithPath: try #require(Self.frozenDecoderDirectory), isDirectory: true)
        func digest(_ url: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: url))) }
        let exe = runtime.appendingPathComponent("Helpers/reference"), originalExe = try digest(exe)
        var hashes: [String: String] = [:]
        for name in ["libavcodec.63.dylib", "libavformat.63.dylib", "libavutil.61.dylib"] { hashes[name] = try digest(runtime.appendingPathComponent("Frameworks/" + name)) }
        let tool = try DolbyDecoderProcess.Tool.development(exe, expectedSHA256: originalExe, libraries: hashes, versions: [4129126,4129126,3998054])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-association-access-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var keep = true
        defer { if keep { print("GENERATED_ASSOCIATION_ACCESS_REVIEW " + root.path) } else { try? FileManager.default.removeItem(at: root) } }
        _ = try await RustFixtureBuild.generate(.reference, at: root, copiesIn: root)
        let original = root.appendingPathComponent("single.mkv"), originalBytes = try Data(contentsOf: original)
        let prior = root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8); try priorBytes.write(to: prior)
        func folder() throws -> URL {
            let url = root.appendingPathComponent("spool-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); return url
        }
        for threads in [1, 4] {
            let spool = try folder(), ledger = Ledger(); var requested: [URL] = [], stopped: [URL] = []
            var env = environment(ledger, fakeScopes: threads == 1)
            if threads == 1 { env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } } }
            let result = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await Operation.associateOriginalFrames(source: original, spoolDirectory: spool, tool: tool, threads: threads)
                    }
                }
            }
            #expect(result.independentSourceFrameAssociationVerified && !result.editedPictureSemanticsVerified && result.decoder.frames == 4)
            if threads == 1 { #expect(requested == [original, spool] && stopped == [spool, original]) }
            ledger.expectJoined(count: 1); ledger.expectEnded(scoped: threads == 1); ledger.expectClosed()
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: spool.path)) == ["association.sqlite"])
        }
        // All these final selected-path refusals occur after the real decoder join.
        for changeSource in [false, true] {
            let source = root.appendingPathComponent("final-source-" + UUID().uuidString); try originalBytes.write(to: source)
            let spool = try folder(), ledger = Ledger(), moved = root.appendingPathComponent("retained-selection-" + UUID().uuidString)
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
                                do {
                                    let selected = changeSource ? source : spool
                                    try FileManager.default.moveItem(at: selected, to: moved)
                                    if changeSource { try originalBytes.write(to: selected) }
                                    else { try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                                } catch { Issue.record("Generated association selection substitution failed") }
                            })) { try await Operation.associateOriginalFrames(source: source, spoolDirectory: spool, tool: tool) }
                        }
                    }
                }
                Issue.record("Changed outer association selection returned success")
            } catch let e as Operation.ReviewFailure {
                #expect(e.intendedStage == spool); ledger.expectJoined(count: 1); ledger.expectRetained()
                #expect(Operation.retainedForTesting(e.reviewID))
                Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
            }
            #expect(try Data(contentsOf: source) == originalBytes)
            if changeSource { #expect(try Data(contentsOf: moved) == originalBytes) }
            else { #expect(Set(try FileManager.default.contentsOfDirectory(atPath: moved.path)) == ["association.sqlite"]) }
        }
        // Cancellation after direct-child join is a refusal with balanced release.
        let lateSpool = try folder(), lateLedger = Ledger(), lateGate = Gate()
        let late = Task {
            defer { lateGate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(lateLedger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { lateLedger.pinned($0) }, associationClosed: { lateLedger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { lateLedger.launch($0) }, settled: { lateLedger.join($0) }, beforeReceipt: { lateGate.hold() })) {
                        try await Operation.associateOriginalFrames(source: original, spoolDirectory: lateSpool, tool: tool)
                    }
                }
            }
        }
        for await _ in lateGate.entered { break }; lateLedger.expectJoined(count: 1); lateLedger.expectActive(scoped: true)
        late.cancel(); lateGate.release.signal()
        await #expect(throws: CancellationError.self) { try await late.value }
        lateLedger.expectEnded(scoped: true); lateLedger.expectClosed()
        // A long generated source keeps the actual decoder live at a frame gate.
        let view = CompanionDiskCheck.ReadView(sourceBytes: Int64(originalBytes.count), source: { o, n in originalBytes.subdata(in: Int(o)..<(Int(o) + n)) }, component: { _ in throw NativeExportError.invalid("Generated source-only fixture") }, checkpoint: {})
        let walker = CompanionOriginalTrackCheck.Walker(view), header = try walker.element(0, end: view.sourceBytes)
        let segment = try walker.element(header.end, end: view.sourceBytes)
        var prefix = Data(), clusters = Data(), offset = segment.payload
        while offset < segment.end {
            let element = try walker.element(offset, end: segment.end)
            let bytes = originalBytes.subdata(in: Int(offset)..<Int(element.end))
            if element.id == 0x1f43b675 { clusters.append(bytes) } else { prefix.append(bytes) }
            offset = element.end
        }
        var longBytes = originalBytes.prefix(Int(header.end)) + Data([0x18,0x53,0x80,0x67,0xff]) + prefix
        for _ in 0..<2000 { longBytes.append(clusters) }
        let source = root.appendingPathComponent("live-source.mkv"); try longBytes.write(to: source)
        let spool = try folder(), ledger = Ledger(), gate = Gate()
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, row: { d in if String(decoding: d, as: UTF8.self).contains("\"kind\":\"frame\"") { gate.holdFirst() } }, settled: { ledger.join($0) })) {
                        try await Operation.associateOriginalFrames(source: source, spoolDirectory: spool, tool: tool)
                    }
                }
            }
        }
        for await _ in gate.entered { break }
        ledger.expectActive(scoped: true)
        #expect(ownAssertion(try assertions(), reason: "StaxRip original source frame association"))
        let pid = try #require(ledger.latestPID)
        let state = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
        #expect(state.status == 0 && !String(decoding: state.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
        await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalFrames(source: original, spoolDirectory: spool, tool: tool) }
        task.cancel(); ledger.expectActive(scoped: true); gate.release.signal()
        var uncertain = false
        do { _ = try await task.value; Issue.record("Cancelled live association returned success") }
        catch is CancellationError { ledger.expectEnded(scoped: true); ledger.expectClosed() }
        catch let e as Operation.ReviewFailure {
            uncertain = true
            #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "group-1-joined-true")
            ledger.expectJoined(count: 1); ledger.expectRetained(); #expect(Operation.retainedForTesting(e.reviewID))
            // Controlled registry isolation after fixed-child join; retain files.
            // This is not process-group settlement or production cleanup authority.
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
        }
        ledger.expectJoined(count: 1)
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source frame association"))
        #expect(try Data(contentsOf: original) == originalBytes && Data(contentsOf: source) == longBytes && Data(contentsOf: prior) == priorBytes)
        #expect(try digest(exe) == originalExe)
        for (name, hash) in hashes { #expect(try digest(runtime.appendingPathComponent("Frameworks/" + name)) == hash) }
        keep = uncertain
        print("Generated concrete association: both threads, six joined decoders, final/late/live refusal; uncertain group=\(uncertain)")
    }
    @Test(.enabled(if: sampleDecoderDirectory != nil), .timeLimit(.minutes(2)))
    func actualSampleAssociationOwnsActivityClosesBothThreadsCancellationAndFinalSelection() async throws {
        let runtime = URL(fileURLWithPath: try #require(Self.sampleDecoderDirectory), isDirectory: true)
        func digest(_ url: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: url))) }
        let exe = runtime.appendingPathComponent("Helpers/sample-probe"), originalExe = try digest(exe)
        var hashes: [String: String] = [:]
        for name in ["libavcodec.63.dylib", "libavformat.63.dylib", "libavutil.61.dylib"] { hashes[name] = try digest(runtime.appendingPathComponent("Frameworks/" + name)) }
        let tool = try DolbyDecoderProcess.Tool.developmentSamples(exe, expectedSHA256: originalExe, libraries: hashes, versions: [4129126,4129126,3998054])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-sample-access-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var keep = true
        defer { if keep { print("GENERATED_SAMPLE_ACCESS_REVIEW " + root.path) } else { try? FileManager.default.removeItem(at: root) } }
        _ = try await RustFixtureBuild.generate(.reference, at: root, copiesIn: root)
        let original = root.appendingPathComponent("single.mkv"), originalBytes = try Data(contentsOf: original)
        let prior = root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8); try priorBytes.write(to: prior)
        func folder() throws -> URL {
            let url = root.appendingPathComponent("spool-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); return url
        }
        for name in ["single", "conformance", "whole-gop"] {
          let selected = root.appendingPathComponent(name + ".mkv"), selectedBytes = try Data(contentsOf: selected)
          for threads in [1, 4] {
            let spool = try folder(), ledger = Ledger(), closes = DecoderCloseObservations(); var requested: [URL] = [], stopped: [URL] = []
            var env = environment(ledger, fakeScopes: threads == 1)
            if threads == 1 { env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } } }
            let result = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); closes.launch($0) }, settled: { ledger.join($0); closes.settle($0) }, closed: { closes.close($0,$1,$2) })) {
                        try await Operation.associateOriginalSamples(source: selected, spoolDirectory: spool, tool: tool, threads: threads)
                    }
                }
            }
            #expect(result.independentSourceFrameAssociationVerified && result.independentSampleSourceAssociationVerified && !result.independentSampleValuesVerified && !result.editedPictureSemanticsVerified && result.decoder.frames == (name == "whole-gop" ? 24 : 4))
            if threads == 1 { #expect(requested == [selected, spool] && stopped == [spool, selected]) }
            closes.expect(Set(DolbyDecoderProcess.DescriptorRole.allCases), launched: true)
            ledger.expectJoined(count: 1); ledger.expectEnded(scoped: threads == 1); ledger.expectClosed()
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: spool.path)) == ["association.sqlite"])
            #expect(result.decoder.sampleFrameSummaryCount == result.decoder.frames)
            #expect(try Data(contentsOf: selected) == selectedBytes)
            if name == "conformance" { #expect(result.decoder.geometry.crop == [0,14,0,14]) }
          }
        }
        for role in [DolbyDecoderProcess.DescriptorRole.stdoutWrite, .nullInput] {
            let spool = try folder(), ledger = Ledger(), closes = DecoderCloseObservations(refused: role)
            var reviewID: UUID?
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { _ in Issue.record("Uncertain helper released access") })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); closes.launch($0) }, settled: { ledger.join($0); closes.settle($0) }, closed: { closes.close($0,$1,$2) }, refuseClose: { r,_,_ in closes.inject(r) })) {
                            try await Operation.associateOriginalSamples(source: original, spoolDirectory: spool, tool: tool)
                        }
                    }
                }
                Issue.record("Reported helper close uncertainty released sample access")
            } catch let e as Operation.ReviewFailure {
                reviewID = e.reviewID
                #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "descriptor-close")
            }
            let id = try #require(reviewID)
            closes.expect(Set(DolbyDecoderProcess.DescriptorRole.allCases), launched: true)
            ledger.expectJoined(count: 1); ledger.expectRetained(); ledger.expectActive(scoped: true)
            await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalSamples(source: original, spoolDirectory: spool, tool: tool) }
            try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
            // Controlled reported refusal after real closes and fixed-child join;
            // test registry isolation is not production recovery/cleanup authority.
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        }
        // All these final selected-path refusals occur after the real decoder join.
        for changeSource in [false, true] {
            let source = root.appendingPathComponent("final-source-" + UUID().uuidString); try originalBytes.write(to: source)
            let spool = try folder(), ledger = Ledger(), moved = root.appendingPathComponent("retained-selection-" + UUID().uuidString)
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
                                do {
                                    let selected = changeSource ? source : spool
                                    try FileManager.default.moveItem(at: selected, to: moved)
                                    if changeSource { try originalBytes.write(to: selected) }
                                    else { try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                                } catch { Issue.record("Generated association selection substitution failed") }
                            })) { try await Operation.associateOriginalSamples(source: source, spoolDirectory: spool, tool: tool) }
                        }
                    }
                }
                Issue.record("Changed outer association selection returned success")
            } catch let e as Operation.ReviewFailure {
                #expect(e.intendedStage == spool); ledger.expectJoined(count: 1); ledger.expectRetained()
                #expect(Operation.retainedForTesting(e.reviewID))
                Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
            }
            #expect(try Data(contentsOf: source) == originalBytes)
            if changeSource { #expect(try Data(contentsOf: moved) == originalBytes) }
            else { #expect(Set(try FileManager.default.contentsOfDirectory(atPath: moved.path)) == ["association.sqlite"]) }
        }
        // Cancellation after direct-child join is a refusal with balanced release.
        let lateSpool = try folder(), lateLedger = Ledger(), lateGate = Gate()
        let late = Task {
            defer { lateGate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(lateLedger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { lateLedger.pinned($0) }, associationClosed: { lateLedger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { lateLedger.launch($0) }, settled: { lateLedger.join($0) }, beforeReceipt: { lateGate.hold() })) {
                        try await Operation.associateOriginalSamples(source: original, spoolDirectory: lateSpool, tool: tool)
                    }
                }
            }
        }
        for await _ in lateGate.entered { break }; lateLedger.expectJoined(count: 1); lateLedger.expectActive(scoped: true)
        late.cancel(); lateGate.release.signal()
        await #expect(throws: CancellationError.self) { try await late.value }
        lateLedger.expectEnded(scoped: true); lateLedger.expectClosed()
        // A long generated source keeps the actual decoder live at a frame gate.
        let view = CompanionDiskCheck.ReadView(sourceBytes: Int64(originalBytes.count), source: { o, n in originalBytes.subdata(in: Int(o)..<(Int(o) + n)) }, component: { _ in throw NativeExportError.invalid("Generated source-only fixture") }, checkpoint: {})
        let walker = CompanionOriginalTrackCheck.Walker(view), header = try walker.element(0, end: view.sourceBytes)
        let segment = try walker.element(header.end, end: view.sourceBytes)
        var prefix = Data(), clusters = Data(), offset = segment.payload
        while offset < segment.end {
            let element = try walker.element(offset, end: segment.end)
            let bytes = originalBytes.subdata(in: Int(offset)..<Int(element.end))
            if element.id == 0x1f43b675 { clusters.append(bytes) } else { prefix.append(bytes) }
            offset = element.end
        }
        var longBytes = originalBytes.prefix(Int(header.end)) + Data([0x18,0x53,0x80,0x67,0xff]) + prefix
        for _ in 0..<2000 { longBytes.append(clusters) }
        let source = root.appendingPathComponent("live-source.mkv"); try longBytes.write(to: source)
        let spool = try folder(), ledger = Ledger(), gate = Gate()
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, row: { d in if String(decoding: d, as: UTF8.self).contains("\"kind\":\"sample-frame\"") { gate.holdFirst() } }, settled: { ledger.join($0) })) {
                        try await Operation.associateOriginalSamples(source: source, spoolDirectory: spool, tool: tool)
                    }
                }
            }
        }
        for await _ in gate.entered { break }
        ledger.expectActive(scoped: true)
        #expect(ownAssertion(try assertions(), reason: "StaxRip original source sample association"))
        let pid = try #require(ledger.latestPID)
        let state = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
        #expect(state.status == 0 && !String(decoding: state.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
        await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalSamples(source: original, spoolDirectory: spool, tool: tool) }
        task.cancel(); ledger.expectActive(scoped: true); gate.release.signal()
        var uncertain = false
        do { _ = try await task.value; Issue.record("Cancelled live association returned success") }
        catch is CancellationError { ledger.expectEnded(scoped: true); ledger.expectClosed() }
        catch let e as Operation.ReviewFailure {
            uncertain = true
            #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "group-1-joined-true")
            ledger.expectJoined(count: 1); ledger.expectRetained(); #expect(Operation.retainedForTesting(e.reviewID))
            // Controlled registry isolation after fixed-child join; retain files.
            // This is not process-group settlement or production cleanup authority.
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
        }
        ledger.expectJoined(count: 1)
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source sample association"))
        #expect(try Data(contentsOf: original) == originalBytes && Data(contentsOf: source) == longBytes && Data(contentsOf: prior) == priorBytes)
        #expect(try digest(exe) == originalExe)
        for (name, hash) in hashes { #expect(try digest(runtime.appendingPathComponent("Frameworks/" + name)) == hash) }
        keep = true
        print("Generated concrete sample access: six accepted trials/both threads, twelve joined decoders, final/late/live refusal; uncertain group=\(uncertain)")
    }

    @Test func samplePartialAcquisitionCheckedRollbackRetainsGrantsOnReportedUncertainty() async throws {
        final class Reports: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let f = try await fixture(); defer { f.cleanup() }; let tool = try sampleAccessTool(in: f.root)
        let missing = f.root.appendingPathComponent("missing-spool"), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], activities = 0
        let env = Operation.Environment(access: { url in requested.append(url); return { stopped.append(url) } }, activity: { _ in activities += 1; return {} }, retainedActivitySeconds: 0.05)
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(acquisitionClosed: { #expect($0 == 1) })) {
                await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalSamples(source: f.source, spoolDirectory: missing, tool: tool) }
            }
        }
        #expect(requested == [f.source, missing] && stopped == [missing, f.source] && activities == 0)
        requested.removeAll(); stopped.removeAll()
        let reports = Reports(); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(refuseAssociationClose: { reports.report() }, acquisitionClosed: { _ in Issue.record("Uncertain rollback released grants") })) {
                    try await Operation.associateOriginalSamples(source: f.source, spoolDirectory: missing, tool: tool)
                }
            }
            Issue.record("Partial acquisition uncertainty returned ordinary refusal/success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID)
        #expect(requested == [f.source, missing] && stopped.isEmpty && activities == 0 && reports.value == 1)
        #expect(Operation.retainedForTesting(id))
        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(stopped.isEmpty && activities == 0)
        Operation.releaseGeneratedReviewForTesting(id)
        var info = stat(); #expect(fstat(later, &info) == 0 && stopped == [missing, f.source] && reports.value == 1)
        #expect(try Data(contentsOf: f.source) == original && !FileManager.default.fileExists(atPath: missing.path))
    }
    @Test func candidateSemanticRefusalReportedCloseSupersedesOrdinaryError() async throws {
        let f = try await candidate(); defer { f.cleanup() }; let ledger = Ledger()
        // Reuse the independently qualified semantic-forgery fixture machinery.
        let audit = f.stage.appendingPathComponent("source-audit.jsonl")
        var rows = try Data(contentsOf: audit).split(separator: 10).map { try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
        let index = try #require(rows.firstIndex { $0["kind"] as? String == "rpu-summary" })
        var summary = try #require(rows[index]["summary"] as? [String: Any])
        summary["cmv29_present"] = !(try #require(summary["cmv29_present"] as? Bool)); rows[index]["summary"] = summary
        var bytes = Data()
        for row in rows { bytes.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])); bytes.append(10) }
        try bytes.write(to: audit)
        let manifest = f.stage.appendingPathComponent("manifest.json")
        var m = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        var components = try #require(m["components"] as? [[String: Any]])
        let member = try #require(components.firstIndex { $0["name"] as? String == "source-audit.jsonl" })
        components[member]["bytes"] = bytes.count; components[member]["sha256"] = DolbyInspection.hex(SHA256.hash(data: bytes))
        m["components"] = components; try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]).write(to: manifest)
        let original = try Data(contentsOf: f.source), before = try snapshot(f.stage)
        final class Report: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func refuse() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let report = Report(); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { _ in Issue.record("Reported close released semantic refusal access") }, refuseArchiveClose: { report.refuse() })) {
                    try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) { try await review(f) }
                }
            }
            Issue.record("Semantic/close refusal returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.published == nil && e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID); ledger.expectJoined(count: 1); ledger.expectRetainedGrants()
        #expect(report.value == 1 && Operation.retainedForTesting(id))
        try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetainedGrants()
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
    }

    @Test func exclusiveCommitLateCancellationAndReportedOuterCloseKeepActualPublishedState() async throws {
        final class Report: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func refuse() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for refuse in [false, true] {
            let f = try await fixture(); var keep = true
            defer { if keep { print("GENERATED_COMMITTED_CLOSE_REVIEW " + f.root.path) } else { f.cleanup() } }
            let ledger = Ledger(), gate = Gate(), report = Report(), original = try Data(contentsOf: f.source)
            let prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8); try priorBytes.write(to: prior)
            let task = Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) }, refuseArchiveClose: { refuse ? report.refuse() : false })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                                try await ResultSetStaging.$testBoundary.withValue(.init(afterCommit: { gate.hold() })) { try await execute(f, mode: mode) }
                            }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }
            ledger.expectJoined(count: 2); ledger.expectActive(scoped: true)
            let directory = f.root.appendingPathComponent("published"), before = try snapshot(directory)
            task.cancel(); gate.release.signal()
            if refuse {
                var reviewID: UUID?
                do { _ = try await task.value; Issue.record("Committed close refusal returned ordinary success") }
                catch let e as Operation.ReviewFailure {
                    reviewID = e.reviewID
                    let actual = try #require(e.published)
                    #expect(actual.directory == directory && actual.memberCount == mode.limits.count && actual.verifiedBytes > 0)
                    #expect(e.intendedStage == directory && e.operationError is any CompanionUnsettledOwnership)
                    #expect(e.errorDescription?.contains("was published") == true)
                }
                let id = try #require(reviewID); ledger.expectRetainedGrants(); #expect(report.value == 1)
                await #expect(throws: NativeExportError.self) { try await execute(f) }
                await #expect(throws: NativeExportError.self) { try await review(f) }
                await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
                await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
                try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetainedGrants(); #expect(Operation.retainedForTesting(id))
                let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
                try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
                Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
                var info = stat(); #expect(fstat(later, &info) == 0 && report.value == 1)
            } else {
                let actual = try await task.value
                #expect(actual.directory == directory && actual.memberCount == mode.limits.count)
                ledger.expectEnded(scoped: true); ledger.expectClosed(); keep = false
            }
            ledger.expectJoined(count: 2)
            #expect(try snapshot(directory) == before && Data(contentsOf: f.source) == original && Data(contentsOf: prior) == priorBytes)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf: directory.appendingPathComponent("original-container.mkv")) == original) }
          }
        }
    }
    @Test func exclusiveCommitInternalSourceCloseRetainsActualPublishedState() async throws {
        final class Report: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0, closes = 0
            func refuse() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
            func closed() { lock.withLock { closes += 1 } }
            var closeCount: Int { lock.withLock { closes } }
        }
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for refuse in [false, true] {
            let f = try await fixture(); var keep = true
            defer { if keep { print("GENERATED_INTERNAL_SOURCE_COMMITTED_REVIEW " + f.root.path) } else { f.cleanup() } }
            let ledger = Ledger(), gate = Gate(), report = Report(), original = try Data(contentsOf: f.source)
            let prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8); try priorBytes.write(to: prior)
            let task = Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) }, refuseArchiveClose: { false })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                                try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(closed: { #expect($0 == 1); report.closed() }, refuseClose: { refuse ? report.refuse() : false })) {
                                    try await ResultSetStaging.$testBoundary.withValue(.init(afterCommit: { gate.hold() })) { try await execute(f, mode: mode) }
                                }
                            }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }
            ledger.expectJoined(count: 2); ledger.expectActive(scoped: true)
            let directory = f.root.appendingPathComponent("published"), before = try snapshot(directory)
            task.cancel(); gate.release.signal()
            if refuse {
                var reviewID: UUID?
                do { _ = try await task.value; Issue.record("Committed close refusal returned ordinary success") }
                catch let e as Operation.ReviewFailure {
                    reviewID = e.reviewID
                    let actual = try #require(e.published)
                    #expect(actual.directory == directory && actual.memberCount == mode.limits.count && actual.verifiedBytes > 0)
                    let inner = try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)
                    #expect(inner.published?.directory == directory)
                    #expect((inner.closeError as? OriginalCompanionTransaction.SourceCloseFailure)?.reportedAfterActualClose == true)
                    #expect(e.intendedStage == directory)
                    #expect(e.errorDescription?.contains("was published") == true)
                }
                let id = try #require(reviewID); ledger.expectRetainedGrants(); #expect(report.value == 1)
                await #expect(throws: NativeExportError.self) { try await execute(f) }
                await #expect(throws: NativeExportError.self) { try await review(f) }
                await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
                await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
                try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetainedGrants(); #expect(Operation.retainedForTesting(id))
                let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
                try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
                Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
                var info = stat(); #expect(fstat(later, &info) == 0 && report.value == 1)
            } else {
                let actual = try await task.value
                #expect(actual.directory == directory && actual.memberCount == mode.limits.count)
                ledger.expectEnded(scoped: true); ledger.expectClosed(); keep = false
            }
            ledger.expectJoined(count: 2); #expect(report.closeCount == 1)
            #expect(try snapshot(directory) == before && Data(contentsOf: f.source) == original && Data(contentsOf: prior) == priorBytes)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf: directory.appendingPathComponent("original-container.mkv")) == original) }
          }
        }
    }
    @Test func candidateSuccessfulFullReviewReportedCloseRetainsWithoutMutatingCandidate() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let f = try await candidate(mode); defer { print("GENERATED_CANDIDATE_CLOSE_REVIEW " + f.root.path) }
            let ledger = Ledger(), original = try Data(contentsOf: f.source), before = try snapshot(f.stage)
            var reviewID: UUID?
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, refuseArchiveClose: { true })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) { try await review(f, mode: mode) }
                    }
                }
                Issue.record("Read-only close uncertainty returned ordinary result")
            } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.published == nil && e.intendedStage == f.stage && e.operationError is any CompanionUnsettledOwnership) }
            let id = try #require(reviewID); ledger.expectJoined(count: 1); ledger.expectRetainedGrants()
            try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetainedGrants()
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
            #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
        }
    }

    @Test func actualJoinedWriterRefusalInternalSourceCloseRetainsOwnedStageAndGrants() async throws {
        let f = try await fixture(); defer { print("GENERATED_INTERNAL_SOURCE_STAGE_REVIEW " + f.root.path) }
        let ledger = Ledger(), original = try Data(contentsOf: f.source), priorBytes = Data("Generated prior".utf8)
        let prior = f.root.appendingPathComponent("prior-output"); try priorBytes.write(to: prior)
        var reviewID: UUID?, stage: URL?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { phase in
                    if phase == "verifier" { throw NativeExportError.invalid("Generated settled verifier admission refusal") }
                }, pinned: { ledger.pinned($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(closed: { #expect($0 == 1) }, refuseClose: { true })) { try await execute(f) }
                    }
                }
            }
            Issue.record("Internal source close uncertainty returned ordinary refusal")
        } catch let e as Operation.ReviewFailure {
            reviewID = e.reviewID; stage = e.intendedStage
            let inner = try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)
            #expect(e.published == nil && inner.published == nil && inner.operationError is NativeExportError)
            #expect((inner.closeError as? OriginalCompanionTransaction.SourceCloseFailure)?.reportedAfterActualClose == true)
        }
        let id = try #require(reviewID), directory = try #require(stage), before = try snapshot(directory)
        ledger.expectJoined(count: 1); ledger.expectRetained()
        #expect(before["manifest.json"] != nil && !FileManager.default.fileExists(atPath: f.root.appendingPathComponent("published").path))
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        #expect(try snapshot(directory) == before && Data(contentsOf: f.source) == original && Data(contentsOf: prior) == priorBytes)
    }


    private final class StageCloses: @unchecked Sendable {
        private let lock = NSLock(); private var roles: [ResultSetStaging.CloseRole] = []
        func add(_ r: ResultSetStaging.CloseRole) { lock.withLock { roles.append(r) } }
        func count(_ r: ResultSetStaging.CloseRole) -> Int { lock.withLock { roles.filter { $0 == r }.count } }
    }
    @Test func nativeTransientStagingCloseReviewPreservesBothModesAndActualCommitAfterLateCancel() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for postCommit in [false, true] {
            let f = try await fixture(), ledger = Ledger(), gate = Gate(), closes = StageCloses()
            defer { print("GENERATED_NATIVE_TRANSIENT_STAGE_REVIEW " + f.root.path) }
            let original = try Data(contentsOf: f.source), prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8)
            try priorBytes.write(to: prior)
            let role = postCommit ? ResultSetStaging.CloseRole.member("manifest.json") : .directoryStream
            let task = Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                                try await ResultSetStaging.$testBoundary.withValue(.init(afterCommit: { if postCommit { gate.hold() } }, closed: { closes.add($0) }, refuseClose: { $0 == role })) {
                                    try await execute(f, mode: mode)
                                }
                            }
                        }
                    }
                }
            }
            if postCommit {
                var iterator = gate.entered.makeAsyncIterator(); try #require(await iterator.next() != nil)
                ledger.expectJoined(count: 2); ledger.expectActive(scoped: true)
                task.cancel(); gate.release.signal()
            }
            var reviewID: UUID?, locator: URL?
            do { _ = try await task.value; Issue.record("Transient close refusal returned ordinary result") }
            catch let e as Operation.ReviewFailure {
                reviewID = e.reviewID; locator = e.intendedStage
                let inner = try #require(e.operationError as? OriginalCompanionTransaction.StagingSettlementFailure)
                #expect(inner.operationError.closeFailures.count == 1 && inner.operationError.closeFailures[0].role == role)
                #expect(inner.operationError.closeFailures[0].reportedAfterActualClose && inner.operationError.operationError == nil)
                if postCommit {
                    let actual = try #require(e.published)
                    #expect(actual.directory == f.root.appendingPathComponent("published") && e.intendedStage == actual.directory)
                    #expect(actual.memberCount == mode.limits.count && actual.verifiedBytes > 0 && inner.published?.directory == actual.directory)
                    #expect(e.errorDescription?.contains("was published") == true)
                } else { #expect(e.published == nil && inner.published == nil && e.intendedStage.lastPathComponent.hasPrefix(".staxrip-result-")) }
            }
            let id = try #require(reviewID), directory = try #require(locator), before = try snapshot(directory)
            ledger.expectJoined(count: 2); ledger.expectRetained(); #expect(closes.count(role) == 1)
            if postCommit { for name in mode.limits.keys { #expect(closes.count(.member(name)) == 1) }; #expect(closes.count(.directoryStream) == 2) }
            else { #expect(closes.count(.directoryStream) == 1 && !FileManager.default.fileExists(atPath: f.root.appendingPathComponent("published").path)) }
            await #expect(throws: NativeExportError.self) { try await execute(f) }
            await #expect(throws: NativeExportError.self) { try await review(f) }
            await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
            await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
            try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
            let after = try snapshot(directory), sourceAfter = try Data(contentsOf: f.source), priorAfter = try Data(contentsOf: prior)
            #expect(after == before && sourceAfter == original && priorAfter == priorBytes)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf: directory.appendingPathComponent("original-container.mkv")) == original) }
            // Controlled reports followed real successful closes and fixed children joined.
            // DEBUG isolation is not a production recovery-release or cleanup authority.
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
            #expect(closes.count(role) == 1)
          }
        }
    }
    @Test func combinedStagingAndSourceCloseRefusalRetainsActualCommittedState() async throws {
        let f = try await fixture(), ledger = Ledger(), closes = StageCloses()
        defer { print("GENERATED_COMBINED_STAGE_SOURCE_REVIEW " + f.root.path) }
        let original = try Data(contentsOf: f.source)
        var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose: { true })) {
                                try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.add($0) }, refuseClose: { $0 == .member("manifest.json") })) { try await execute(f) }
                            }
                        }
                    }
                }
            }
            Issue.record("Combined close refusal returned success")
        } catch let e as Operation.ReviewFailure {
            reviewID = e.reviewID
            let inner = try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)
            let stage = try #require(inner.operationError as? ResultSetStaging.SettlementFailure), actual = try #require(e.published)
            #expect(stage.published?.directory == actual.directory && inner.published?.directory == actual.directory && e.intendedStage == actual.directory)
            #expect(actual.directory == f.root.appendingPathComponent("published") && stage.closeFailures.count == 1)
            #expect(stage.closeFailures[0].reportedAfterActualClose && inner.closeError is OriginalCompanionTransaction.SourceCloseFailure)
        }
        let id = try #require(reviewID), before = try snapshot(f.root.appendingPathComponent("published"))
        ledger.expectJoined(count: 2); ledger.expectRetained(); #expect(closes.count(.member("manifest.json")) == 1)
        try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        let after = try snapshot(f.root.appendingPathComponent("published")), sourceAfter = try Data(contentsOf: f.source)
        #expect(after == before && sourceAfter == original)
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
    }

    @Test func joinedWriterOrdinaryVerifierRefusalWithCleanupStreamUncertaintyRetainsStageAndCause() async throws {
        let f = try await fixture(), ledger = Ledger(), closes = StageCloses()
        defer { print("GENERATED_CLEANUP_STREAM_STAGE_REVIEW " + f.root.path) }
        let original = try Data(contentsOf: f.source), prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8)
        try priorBytes.write(to: prior)
        var reviewID: UUID?, directory: URL?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { if $0 == "verifier" { throw NativeExportError.invalid("Generated verifier admission refused") } }, pinned: { ledger.pinned($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.add($0) }, refuseClose: { $0 == .directoryStream })) { try await execute(f) }
                    }
                }
            }
            Issue.record("Cleanup stream close uncertainty returned success")
        } catch let e as Operation.ReviewFailure {
            reviewID = e.reviewID; directory = e.intendedStage
            let cleanup = try #require(e.operationError as? OriginalCompanionTransaction.CleanupFailure)
            let close = try #require(cleanup.cleanupError as? ResultSetStaging.SettlementFailure)
            #expect(cleanup.operationError is NativeExportError && e.operationError is any CompanionUnsettledOwnership)
            #expect(close.closeFailures.count == 1 && close.closeFailures[0].reportedAfterActualClose && e.published == nil)
        }
        let id = try #require(reviewID), stage = try #require(directory), before = try snapshot(stage)
        ledger.expectJoined(count: 1); ledger.expectRetained(); #expect(closes.count(.directoryStream) == 1)
        #expect(stage.lastPathComponent.hasPrefix(".staxrip-result-") && !FileManager.default.fileExists(atPath: f.root.appendingPathComponent("published").path))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: stage.path)) == Set(OriginalCompanionTransaction.Retention.metadataOnly.limits.keys))
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        let after = try snapshot(stage), sourceAfter = try Data(contentsOf: f.source), priorAfter = try Data(contentsOf: prior)
        #expect(after == before && sourceAfter == original && priorAfter == priorBytes)
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
    }
    @Test func actualNativeCreationTransfersPinsWithoutRollbackAcrossBothModes() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let f = try await fixture(), ledger = Ledger(), opened = StageCloses(), closed = StageCloses()
            defer { f.cleanup() }
            let original = try Data(contentsOf: f.source), prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8)
            try priorBytes.write(to: prior)
            let result = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closed.add($0) }, creation: { _, _ in ledger.expectActive(scoped: true) }, creationOpened: { opened.add($0) })) { try await execute(f, mode: mode) }
                        }
                    }
                }
            }
            ledger.expectJoined(count: 2); ledger.expectEnded(scoped: true); ledger.expectClosed()
            #expect(opened.count(.creationParent) == 1 && opened.count(.creationDirectory) == 1)
            #expect(closed.count(.creationParent) == 0 && closed.count(.creationDirectory) == 0)
            let membership = try FileManager.default.contentsOfDirectory(atPath: result.directory.path)
            #expect(result.memberCount == mode.limits.count && Set(membership) == Set(mode.limits.keys))
            let sourceAfter = try Data(contentsOf: f.source), priorAfter = try Data(contentsOf: prior)
            #expect(sourceAfter == original && priorAfter == priorBytes)
        }
    }
    @Test func creationRollbackReviewRetainsActualStageStateAccessAndStrongerSourceCause() async throws {
        for caseName in ["parent", "created", "combined"] {
            let f = try await fixture(), ledger = Ledger(), closes = StageCloses()
            defer { print("GENERATED_NATIVE_CREATION_REVIEW " + f.root.path) }
            let original = try Data(contentsOf: f.source), prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8)
            try priorBytes.write(to: prior)
            var reviewID: UUID?, locator: URL?
            let operation = Task {
                try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                        try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(closed: { #expect($0 == 1) }, refuseClose: { caseName == "combined" })) {
                            try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.add($0) }, refuseClose: { $0 == .creationParent || $0 == .creationDirectory }, creation: { point, _ in
                                if point == (caseName == "parent" ? "parent-opened" : "before-transfer") {
                                    withUnsafeCurrentTask { $0?.cancel() }; try Task.checkCancellation()
                                }
                            })) { try await execute(f) }
                        }
                    }
                }
            }
            do { _ = try await operation.value; Issue.record("Creation rollback returned ordinary result") }
            catch let e as Operation.ReviewFailure {
                reviewID = e.reviewID; locator = e.intendedStage
                let creation: ResultSetStaging.CreationSettlementFailure
                if caseName == "combined" {
                    let source = try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)
                    creation = try #require(source.operationError as? ResultSetStaging.CreationSettlementFailure)
                    #expect(source.closeError is OriginalCompanionTransaction.SourceCloseFailure && source.published == nil)
                } else { creation = try #require(e.operationError as? OriginalCompanionTransaction.CreationSettlementFailure).operationError }
                #expect(creation.directoryCreated == (caseName != "parent") && creation.identityEstablished == (caseName != "parent"))
                #expect(creation.operationError is CancellationError && creation.closeFailures.count == (caseName == "parent" ? 1 : 2))
                #expect(creation.closeFailures.allSatisfy { $0.reportedAfterActualClose })
                #expect(e.intendedStage == creation.reviewLocator && e.published == nil)
            }
            let id = try #require(reviewID), directory = try #require(locator)
            ledger.expectJoined(count: 0); ledger.expectRetained()
            #expect(closes.count(.creationParent) == 1 && closes.count(.creationDirectory) == (caseName == "parent" ? 0 : 1))
            if caseName == "parent" { #expect(directory == f.root) }
            else { let names = try FileManager.default.contentsOfDirectory(atPath: directory.path); #expect(directory.lastPathComponent.hasPrefix(".staxrip-result-") && names.isEmpty) }
            await #expect(throws: NativeExportError.self) { try await execute(f) }
            await #expect(throws: NativeExportError.self) { try await review(f) }
            try await Task.sleep(for: .milliseconds(100))
            ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
            let sourceAfter = try Data(contentsOf: f.source), priorAfter = try Data(contentsOf: prior)
            #expect(sourceAfter == original && priorAfter == priorBytes)
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
            #expect(closes.count(.creationParent) == 1)
        }
    }

    @Test func actualPublishedTerminalPinsSettleBothModesAndRetainActualCommitOnRefusal() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for refusal in ["none", "directory", "parent"] {
            let f = try await fixture(), ledger = Ledger(), gate = Gate(), closes = StageCloses()
            defer { if refusal == "none" { f.cleanup() } else { print("GENERATED_NATIVE_PUBLISHED_PIN_REVIEW " + f.root.path) } }
            let source = try Data(contentsOf: f.source), prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8)
            try priorBytes.write(to: prior)
            let operation = Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                                try await ResultSetStaging.$testBoundary.withValue(.init(afterCommit: { gate.hold() }, closed: { closes.add($0) }, refuseClose: { role in
                                    (refusal == "directory" && role == .publishedDirectory) || (refusal == "parent" && role == .publishedParent)
                                })) { try await execute(f, mode: mode) }
                            }
                        }
                    }
                }
            }
            var iterator = gate.entered.makeAsyncIterator(); try #require(await iterator.next() != nil)
            ledger.expectJoined(count: 2); ledger.expectActive(scoped: true)
            operation.cancel(); gate.release.signal()
            var reviewID: UUID?
            let actual: ResultSetStaging.Published
            do { actual = try await operation.value; #expect(refusal == "none"); ledger.expectEnded(scoped: true); ledger.expectClosed() }
            catch let e as Operation.ReviewFailure {
                #expect(refusal != "none"); reviewID = e.reviewID
                actual = try #require(e.published)
                let inner = try #require(e.operationError as? OriginalCompanionTransaction.StagingSettlementFailure)
                #expect(inner.operationError.operationError == nil && inner.operationError.closeFailures.count == 1)
                #expect(inner.operationError.closeFailures[0].reportedAfterActualClose)
                #expect(inner.published?.directory == actual.directory && e.intendedStage == actual.directory)
                #expect(inner.operationError.closeFailures[0].role == (refusal == "directory" ? .publishedDirectory : .publishedParent))
            }
            #expect(closes.count(.publishedDirectory) == 1 && closes.count(.publishedParent) == 1)
            #expect(actual.directory == f.root.appendingPathComponent("published") && actual.memberCount == mode.limits.count && actual.verifiedBytes > 0)
            let before = try snapshot(actual.directory), sourceAfter = try Data(contentsOf: f.source), priorAfter = try Data(contentsOf: prior)
            #expect(Set(before.keys) == Set(mode.limits.keys) && sourceAfter == source && priorAfter == priorBytes)
            if let id = reviewID {
                ledger.expectRetained()
                await #expect(throws: NativeExportError.self) { try await execute(f) }
                await #expect(throws: NativeExportError.self) { try await review(f) }
                try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
                #expect(try snapshot(actual.directory) == before)
                Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
            }
            #expect(closes.count(.publishedDirectory) == 1 && closes.count(.publishedParent) == 1)
          }
        }
    }
    @Test func combinedPublishedPinAndSourceCloseRefusalPreservesActualResultAndPriority() async throws {
        let f = try await fixture(), ledger = Ledger(), closes = StageCloses()
        defer { print("GENERATED_COMBINED_PUBLISHED_PIN_REVIEW " + f.root.path) }
        let source = try Data(contentsOf: f.source)
        var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose: { true })) {
                                try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.add($0) }, refuseClose: { $0 == .publishedDirectory || $0 == .publishedParent })) { try await execute(f) }
                            }
                        }
                    }
                }
            }
            Issue.record("Combined published pin/source refusal returned success")
        } catch let e as Operation.ReviewFailure {
            reviewID = e.reviewID
            let inner = try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)
            let stage = try #require(inner.operationError as? ResultSetStaging.SettlementFailure), actual = try #require(e.published)
            #expect(stage.closeFailures.count == 2 && stage.closeFailures.allSatisfy { $0.reportedAfterActualClose })
            #expect(inner.closeError is OriginalCompanionTransaction.SourceCloseFailure && stage.published?.directory == actual.directory && inner.published?.directory == actual.directory)
            #expect(actual.directory == f.root.appendingPathComponent("published") && e.intendedStage == actual.directory)
        }
        let id = try #require(reviewID), before = try snapshot(f.root.appendingPathComponent("published"))
        ledger.expectJoined(count: 2); ledger.expectRetained(); #expect(closes.count(.publishedDirectory) == 1 && closes.count(.publishedParent) == 1)
        try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
        #expect(try snapshot(f.root.appendingPathComponent("published")) == before)
        #expect(try Data(contentsOf: f.source) == source)
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
    }

    @Test func nativeVerifiedRefusalCleanupCarriesActualRemovedStateAndRetainsAccess() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for refusal in ["none", "directory", "parent", "both"] {
            let f = try await fixture(), ledger = Ledger(), closes = StageCloses()
            defer { if refusal == "none" { f.cleanup() } else { print("GENERATED_NATIVE_REMOVED_PIN_REVIEW " + f.root.path) } }
            let source = try Data(contentsOf: f.source), prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8)
            try priorBytes.write(to: prior)
            let initialNames = Set(try FileManager.default.contentsOfDirectory(atPath: f.root.path))
            let operation = Task {
                try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                                try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit: { throw NativeExportError.invalid("Generated refusal after full original verification") }, closed: { role in
                                    closes.add(role)
                                    if role == .removedDirectory { withUnsafeCurrentTask { $0?.cancel() } }
                                }, refuseClose: { role in
                                    (role == .removedDirectory && ["directory", "both"].contains(refusal)) || (role == .removedParent && ["parent", "both"].contains(refusal))
                                })) { try await execute(f, mode: mode) }
                            }
                        }
                    }
                }
            }
            var reviewID: UUID?
            do { _ = try await operation.value; Issue.record("Generated verified refusal returned success") }
            catch let e as Operation.ReviewFailure {
                #expect(refusal != "none"); reviewID = e.reviewID
                let cleanup = try #require(e.operationError as? OriginalCompanionTransaction.CleanupFailure)
                let removed = try #require(e.removed), inner = try #require(cleanup.cleanupError as? ResultSetStaging.RemovalSettlementFailure)
                #expect(cleanup.operationError is NativeExportError && cleanup.operationError.localizedDescription.contains("Generated refusal"))
                #expect(removed.directory == inner.removed.directory && cleanup.removed?.directory == removed.directory && e.intendedStage == removed.directory)
                #expect(removed.entryCount == mode.limits.count && inner.closeFailures.count == (refusal == "both" ? 2 : 1))
                #expect(inner.closeFailures.allSatisfy { $0.reportedAfterActualClose })
                #expect(e.published == nil && e.errorDescription?.contains("was removed") == true && cleanup.errorDescription?.contains("was removed") == true)
                #expect(!FileManager.default.fileExists(atPath: removed.directory.path))
            } catch { #expect(refusal == "none" && error is NativeExportError); ledger.expectEnded(scoped: true); ledger.expectClosed() }
            ledger.expectJoined(count: 2)
            #expect(closes.count(.removedDirectory) == 1 && closes.count(.removedParent) == 1)
            #expect(closes.count(.publishedDirectory) == 0 && closes.count(.publishedParent) == 0)
            let afterNames = Set(try FileManager.default.contentsOfDirectory(atPath: f.root.path)), sourceAfter = try Data(contentsOf: f.source), priorAfter = try Data(contentsOf: prior)
            #expect(afterNames == initialNames && sourceAfter == source && priorAfter == priorBytes)
            #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("published").path))
            if let id = reviewID {
                ledger.expectRetained()
                await #expect(throws: NativeExportError.self) { try await execute(f) }
                await #expect(throws: NativeExportError.self) { try await review(f) }
                try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
                Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
            }
            #expect(closes.count(.removedDirectory) == 1 && closes.count(.removedParent) == 1)
          }
        }
    }
    @Test func strongerSourceUncertaintyPreventsEligibleDiscardAndRemovedClaims() async throws {
        let f = try await fixture(), ledger = Ledger(), closes = StageCloses()
        defer { print("GENERATED_PRE_REMOVAL_SOURCE_REVIEW " + f.root.path) }
        var reviewID: UUID?, directory: URL?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { if $0 == "verifier" { throw NativeExportError.invalid("Generated verifier refusal") } }, pinned: { ledger.pinned($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose: { true })) {
                            try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.add($0) })) { try await execute(f) }
                        }
                    }
                }
            }
            Issue.record("Source uncertainty returned ordinary cleanup")
        } catch let e as Operation.ReviewFailure {
            reviewID = e.reviewID; directory = e.intendedStage
            #expect(e.operationError is OriginalCompanionTransaction.SourceSettlementFailure && e.removed == nil && e.published == nil)
        }
        let id = try #require(reviewID), stage = try #require(directory), before = try snapshot(stage)
        ledger.expectJoined(count: 1); ledger.expectRetained()
        #expect(closes.count(.removedDirectory) == 0 && closes.count(.removedParent) == 0)
        try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
        #expect(try snapshot(stage) == before)
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
    }

    @Test func concreteStageOwnerSurvivesDroppedErrorsExpiryAndConflicts() async throws {
        func retainedFiles(_ directory: URL) throws -> [String: Data] {
            var result: [String: Data] = [:]
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
                let selected = directory.appendingPathComponent(name)
                if name == "blocker" {
                    var info = stat(); try #require(lstat(selected.path, &info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR))
                    let children = try FileManager.default.contentsOfDirectory(atPath: selected.path)
                    #expect(children.isEmpty); result[name] = Data()
                } else { result[name] = try Data(contentsOf: selected) }
            }
            return result
        }
        struct ControlledUnsettled: CompanionUnsettledOwnership {}
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for fault in ["phase", "source", "transient", "cleanup", "substitution"] {
            let f = try await fixture(), ledger = Ledger(), closes = StageCloses()
            defer { print("GENERATED_RETAINED_STAGE_OWNER " + f.root.path) }
            let source = try Data(contentsOf: f.source), prior = f.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8)
            try priorBytes.write(to: prior)
            var reviewID: UUID?, published: URL?
            weak var observed: ResultSetStaging?
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(phase: { phase in
                        if phase == "verifier" && ["phase", "source", "substitution"].contains(fault) {
                            if fault == "phase" { throw ControlledUnsettled() }
                            if fault == "substitution" {
                                let names = try FileManager.default.contentsOfDirectory(atPath: f.root.path)
                                guard let name = names.first(where: { $0.hasPrefix(".staxrip-result-") }) else { throw NativeExportError.invalid("Generated stage missing") }
                                let selected = f.root.appendingPathComponent(name), moved = f.root.appendingPathComponent("moved-owned-stage")
                                try FileManager.default.moveItem(at: selected, to: moved)
                                try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
                                try Data([42]).write(to: selected.appendingPathComponent("sentinel"))
                            }
                            throw NativeExportError.invalid("Generated verifier admission refusal")
                        }
                    }, pinned: { ledger.pinned($0) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                                try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose: { fault == "source" })) {
                                    try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit: {
                                        if fault == "cleanup" {
                                            let names = try FileManager.default.contentsOfDirectory(atPath: f.root.path)
                                            guard let name = names.first(where: { $0.hasPrefix(".staxrip-result-") }) else { throw NativeExportError.invalid("Generated stage missing") }
                                            try FileManager.default.createDirectory(at: f.root.appendingPathComponent(name).appendingPathComponent("blocker"), withIntermediateDirectories: false)
                                            throw NativeExportError.invalid("Generated ordinary refusal after full verification")
                                        }
                                    }, closed: { closes.add($0) }, refuseClose: { fault == "transient" && $0 == .member("manifest.json") })) { try await execute(f, mode: mode) }
                                }
                            }
                        }
                    }
                }
                Issue.record("Generated stage ownership refusal returned success")
            } catch let e as Operation.ReviewFailure {
                reviewID = e.reviewID; published = e.published?.directory
                #expect(e.removed == nil)
                if fault == "phase" { #expect((e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)?.operationError is ControlledUnsettled) }
                if fault == "source" { #expect(e.operationError is OriginalCompanionTransaction.SourceSettlementFailure) }
                if fault == "transient" { #expect(e.operationError is OriginalCompanionTransaction.StagingSettlementFailure && e.published != nil) }
                if ["cleanup", "substitution"].contains(fault) { #expect(e.operationError is OriginalCompanionTransaction.CleanupFailure && e.published == nil) }
                observed = Operation.retainedStageForTesting(e.reviewID)
                #expect(observed != nil)
            }
            // Error and transaction's local owner are gone; only existing Access review retains it.
            let id = try #require(reviewID)
            ledger.expectJoined(count: ["transient", "cleanup"].contains(fault) ? 2 : 1)
            let before = try #require(observed?.retainedPinIdentitiesForTesting())
            #expect(before.count == 2)
            #expect(throws: NativeExportError.self) { try observed?.fileURL("manifest.json") }
            #expect(throws: NativeExportError.self) { try observed?.discard() }
            let selected = try published ?? #require(observed?.originalDirectoryURL)
            let actual = fault == "substitution" ? f.root.appendingPathComponent("moved-owned-stage") : selected
            let files = try retainedFiles(actual)
            var directory = stat(), parent = stat()
            try #require(lstat(actual.path, &directory) == 0 && lstat(f.root.path, &parent) == 0)
            #expect(before[0].0 == UInt64(parent.st_dev) && before[0].1 == UInt64(parent.st_ino))
            #expect(before[1].0 == UInt64(directory.st_dev) && before[1].1 == UInt64(directory.st_ino))
            await #expect(throws: NativeExportError.self) { try await execute(f) }
            await #expect(throws: NativeExportError.self) { try await review(f) }
            try await Task.sleep(for: .milliseconds(100))
            ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id) && observed != nil)
            let after = try #require(observed?.retainedPinIdentitiesForTesting()), filesAfter = try retainedFiles(actual)
            #expect(after.count == before.count && zip(after,before).allSatisfy { $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 } && filesAfter == files)
            #expect(closes.count(.publishedDirectory) == 0 && closes.count(.publishedParent) == 0 && closes.count(.removedDirectory) == 0 && closes.count(.removedParent) == 0)
            let sourceAfter = try Data(contentsOf: f.source), priorAfter = try Data(contentsOf: prior)
            #expect(sourceAfter == source && priorAfter == priorBytes)
            if fault == "substitution" { let sentinel = try Data(contentsOf: selected.appendingPathComponent("sentinel")); #expect(sentinel == Data([42])) }
            // All generated phases/children above are joined; isolation has no production
            // recovery/cleanup authority and does not qualify remaining fallback closes.
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
            #expect(observed == nil)
          }
        }
    }

    private nonisolated static var cropDecoderDirectory: String? {
        ProcessInfo.processInfo.environment["STAXRIP_TEST_CROP_DECODER_DIRECTORY"]
    }
    private func cropAccessTool(in root: URL) throws -> DolbyDecoderProcess.Tool {
        let hash = String(repeating: "a", count: 64)
        return try .developmentCrops(root.appendingPathComponent("Helpers/crop-probe"), expectedSHA256: hash,
            libraries: Dictionary(uniqueKeysWithValues: ["libavcodec.63.dylib", "libavformat.63.dylib", "libavutil.61.dylib"].map { ($0, hash) }), versions: [1,1,1])
    }
    private func associateCrops(_ f: Fixture, tool: DolbyDecoderProcess.Tool) async throws -> CompanionDiskCheck.SourceCropReceipt {
        try await Operation.associateOriginalCrops(source: f.source, spoolDirectory: f.stage, tool: tool, request: DolbyCropProcessTests.request())
    }
    @Test func cropAssociationAcquisitionRollbackPrecancelAndActualReadWriteDenials() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        let tool = try cropAccessTool(in: f.root), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], starts = 0, ends = 0
        let failed = Operation.Environment(access: { url in
            requested.append(url)
            if url == f.stage { throw NativeExportError.invalid("Generated spool grant refusal") }
            return { stopped.append(url) }
        }, activity: { _ in starts += 1; return { ends += 1 } })
        await Operation.$testEnvironment.withValue(failed) {
            await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.source] && starts == 0)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await Operation.$testEnvironment.withValue(failed) { try await associateCrops(f, tool: tool) } }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(requested == [f.source, f.stage])
        let env = Operation.Environment(activity: { _ in starts += 1; return { ends += 1 } })
        if geteuid() != 0 {
            var info = stat(); try #require(lstat(f.source.path, &info) == 0)
            let mode = info.st_mode & 0o7777
            defer { _ = chmod(f.source.path, mode); _ = chmod(f.stage.path, 0o700) }
            for (url, deniedMode) in [(f.source, mode_t(0)), (f.stage, mode_t(0))] {
                try #require(chmod(url.path, deniedMode) == 0)
                await Operation.$testEnvironment.withValue(env) {
                    await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied source/spool launched decoder") })) {
                        await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
                    }
                }
                try #require(chmod(url.path, url == f.source ? mode : 0o700) == 0)
            }
            #expect(starts == 0 && ends == 0)
            // Keep strict private POSIX mode while actual generated ACL denies
            // creation of the fixed member. Remove only this fixture's new ACL.
            let acl = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["+a", "everyone deny add_file", f.stage.path])
            try #require(acl.status == 0)
            defer { let result = chmod(f.stage.path, 0o700); #expect(result == 0) }
            await Operation.$testEnvironment.withValue(env) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied spool write launched decoder") })) {
                    await #expect(throws: DolbyAssociationSpool.Failure.self) { try await associateCrops(f, tool: tool) }
                }
            }
            let removed = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["-N", f.stage.path])
            try #require(removed.status == 0)
            #expect(starts == 1 && ends == 1)
        }
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func cropAssociationSourceRefusalClosesPinsAndBalancesOnlyExplicitGrants() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger()
        let tool = try cropAccessTool(in: f.root), invalid = Data("Generated invalid source".utf8)
        try invalid.write(to: f.source)
        var requested: [URL] = [], stopped: [URL] = []
        var env = environment(ledger, fakeScopes: true)
        env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } }
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(phase: { phase in #expect(phase == "crop-association"); ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Invalid source launched decoder") })) {
                    await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
                }
            }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.stage, f.source])
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source crop association"))
        #expect(try Data(contentsOf: f.source) == invalid)
        // A partial disposable SQLite file is still owned by this explicit caller.
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test func cropControlledUnsettledAssociationRetainsAccessAndExcludesAllOperationKindsAfterExpiry() async throws {
        struct ControlledUnsettled: CompanionUnsettledOwnership {}
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), tool = try cropAccessTool(in: f.root)
        let original = try Data(contentsOf: f.source); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in throw ControlledUnsettled() }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) { try await associateCrops(f, tool: tool) }
            }
            Issue.record("Controlled uncertain association returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.intendedStage == f.stage) }
        let id = try #require(reviewID); ledger.expectRetained(); ledger.expectActive(scoped: true)
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
        try await Task.sleep(for: .milliseconds(100))
        ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }

    @Test func cropActiveSourcePassCancellationSettlesBeforeGrantAndPinRelease() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), gate = Gate(), tool = try cropAccessTool(in: f.root)
        let original = try Data(contentsOf: f.source)
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled source pass launched decoder") })) {
                        try await CompanionDiskCheck.$testBoundary.withValue(.init(progress: { phase, _ in if phase == "source" { gate.holdFirst() } })) { try await associateCrops(f, tool: tool) }
                    }
                }
            }
        }
        for await _ in gate.entered { break }; ledger.expectActive(scoped: true)
        task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func cropReportedOuterCloseRefusalRetainsGrantsAfterActualCloses() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let tool = try cropAccessTool(in: f.root)
        try Data("Generated invalid source".utf8).write(to: f.source)
        final class Reports: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let reports = Reports()
        var scopes = 0, stops = 0, energy = 0, reviewID: UUID?
        let env = Operation.Environment(access: { _ in scopes += 1; return { stops += 1 } }, activity: { _ in energy += 1; return { energy -= 1 } }, retainedActivitySeconds: 0.05)
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(associationClosed: { _ in Issue.record("Reported close refusal released access") }, refuseAssociationClose: { reports.report() })) {
                    try await associateCrops(f, tool: tool)
                }
            }
            Issue.record("Reported outer close uncertainty returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID)
        #expect(scopes == 2 && stops == 0 && energy == 1 && reports.value == 1 && Operation.retainedForTesting(id))
        // Actual closes have consumed numbers; no FD-number absence probe. A
        // subsequent independent FD must not be closed by controlled isolation.
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(energy == 0 && stops == 0)
        Operation.releaseGeneratedReviewForTesting(id)
        var info = stat(); #expect(fstat(later, &info) == 0 && stops == 2 && reports.value == 1)
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test(.enabled(if: cropDecoderDirectory != nil), .timeLimit(.minutes(2)))
    func actualCropAssociationOwnsActivityClosesBothThreadsCancellationAndFinalSelection() async throws {
        let runtime = URL(fileURLWithPath: try #require(Self.cropDecoderDirectory), isDirectory: true)
        func digest(_ url: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: url))) }
        let exe = runtime.appendingPathComponent("Helpers/crop-probe"), originalExe = try digest(exe)
        var hashes: [String: String] = [:]
        for name in ["libavcodec.63.dylib", "libavformat.63.dylib", "libavutil.61.dylib"] { hashes[name] = try digest(runtime.appendingPathComponent("Frameworks/" + name)) }
        let tool = try DolbyDecoderProcess.Tool.developmentCrops(exe, expectedSHA256: originalExe, libraries: hashes, versions: [4129126,4129126,3998054])
        let request = try DolbyCropProcessTests.request(.coded)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-crop-access-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var keep = true
        defer { if keep { print("GENERATED_CROP_ACCESS_REVIEW " + root.path) } else { try? FileManager.default.removeItem(at: root) } }
        _ = try await RustFixtureBuild.generate(.reference, at: root, copiesIn: root)
        let original = root.appendingPathComponent("single.mkv"), originalBytes = try Data(contentsOf: original)
        let prior = root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8); try priorBytes.write(to: prior)
        func folder() throws -> URL {
            let url = root.appendingPathComponent("spool-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); return url
        }
        for name in ["single", "conformance", "whole-gop"] {
          let selected = root.appendingPathComponent(name + ".mkv"), selectedBytes = try Data(contentsOf: selected)
          for space in [DolbyDecoderStream.CropRequest.Space.coded, .codecVisible] {
          let request = try DolbyCropProcessTests.request(space)
          for threads in [1, 4] {
            let spool = try folder(), ledger = Ledger(), closes = DecoderCloseObservations(); var requested: [URL] = [], stopped: [URL] = []
            var env = environment(ledger, fakeScopes: threads == 1)
            if threads == 1 { env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } } }
            let result = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); closes.launch($0) }, settled: { ledger.join($0); closes.settle($0) }, closed: { closes.close($0,$1,$2) })) {
                        try await Operation.associateOriginalCrops(source: selected, spoolDirectory: spool, tool: tool, request: request, threads: threads)
                    }
                }
            }
            #expect(result.independentSourceFrameAssociationVerified && result.originalSourceAndCallerCropAgreementVerified && !result.independentSourceROIProvenanceVerified && !result.independentSampleValuesVerified && !result.editedPictureSemanticsVerified && result.decoder.frames == (name == "whole-gop" ? 24 : 4))
            if threads == 1 { #expect(requested == [selected, spool] && stopped == [spool, selected]) }
            closes.expect(Set(DolbyDecoderProcess.DescriptorRole.allCases), launched: true)
            ledger.expectJoined(count: 1); ledger.expectEnded(scoped: threads == 1); ledger.expectClosed()
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: spool.path)) == ["association.sqlite"])
            #expect(result.decoder.cropFrameSummaryCount == result.decoder.frames)
            #expect(try Data(contentsOf: selected) == selectedBytes)
            if name == "conformance" { #expect(result.decoder.geometry.crop == [0,14,0,14]) }
          }
        }
        }
        for role in [DolbyDecoderProcess.DescriptorRole.stdoutWrite, .nullInput] {
            let spool = try folder(), ledger = Ledger(), closes = DecoderCloseObservations(refused: role)
            var reviewID: UUID?
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { _ in Issue.record("Uncertain helper released access") })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); closes.launch($0) }, settled: { ledger.join($0); closes.settle($0) }, closed: { closes.close($0,$1,$2) }, refuseClose: { r,_,_ in closes.inject(r) })) {
                            try await Operation.associateOriginalCrops(source: original, spoolDirectory: spool, tool: tool, request: request)
                        }
                    }
                }
                Issue.record("Reported helper close uncertainty released crop access")
            } catch let e as Operation.ReviewFailure {
                reviewID = e.reviewID
                #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "descriptor-close")
            }
            let id = try #require(reviewID)
            closes.expect(Set(DolbyDecoderProcess.DescriptorRole.allCases), launched: true)
            ledger.expectJoined(count: 1); ledger.expectRetained(); ledger.expectActive(scoped: true)
            await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalCrops(source: original, spoolDirectory: spool, tool: tool, request: request) }
            try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
            // Controlled reported refusal after real closes and fixed-child join;
            // test registry isolation is not production recovery/cleanup authority.
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        }
        // Actual source/crop success must still refuse ordinary return when
        // the reported outer close follows both successful real close calls.
        final class OuterReport: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let outerSpool = try folder(), outerLedger = Ledger(), outerReport = OuterReport()
        var outerReview: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(outerLedger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { outerLedger.pinned($0) }, associationClosed: { _ in Issue.record("Reported outer close released successful crop access") }, refuseAssociationClose: { outerReport.report() })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { outerLedger.launch($0) }, settled: { outerLedger.join($0) })) {
                        try await Operation.associateOriginalCrops(source: original, spoolDirectory: outerSpool, tool: tool, request: request)
                    }
                }
            }
            Issue.record("Reported outer close admitted a complete-looking crop receipt")
        } catch let e as Operation.ReviewFailure { outerReview = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let outerID = try #require(outerReview)
        outerLedger.expectJoined(count: 1); outerLedger.expectRetainedGrants(); #expect(outerReport.value == 1)
        #expect(Operation.retainedForTesting(outerID))
        try await Task.sleep(for: .milliseconds(100)); outerLedger.expectEnded(); outerLedger.expectRetainedGrants()
        await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalCrops(source: original, spoolDirectory: outerSpool, tool: tool, request: request) }
        Operation.releaseGeneratedReviewForTesting(outerID); outerLedger.expectEnded(scoped: true)
        let outerMembers = Set(try FileManager.default.contentsOfDirectory(atPath: outerSpool.path))
        #expect(outerReport.value == 1 && outerMembers == ["association.sqlite"])
        // All these final selected-path refusals occur after the real decoder join.
        for changeSource in [false, true] {
            let source = root.appendingPathComponent("final-source-" + UUID().uuidString); try originalBytes.write(to: source)
            let spool = try folder(), ledger = Ledger(), moved = root.appendingPathComponent("retained-selection-" + UUID().uuidString)
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
                                do {
                                    let selected = changeSource ? source : spool
                                    try FileManager.default.moveItem(at: selected, to: moved)
                                    if changeSource { try originalBytes.write(to: selected) }
                                    else { try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                                } catch { Issue.record("Generated association selection substitution failed") }
                            })) { try await Operation.associateOriginalCrops(source: source, spoolDirectory: spool, tool: tool, request: request) }
                        }
                    }
                }
                Issue.record("Changed outer association selection returned success")
            } catch let e as Operation.ReviewFailure {
                #expect(e.intendedStage == spool); ledger.expectJoined(count: 1); ledger.expectRetained()
                #expect(Operation.retainedForTesting(e.reviewID))
                Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
            }
            #expect(try Data(contentsOf: source) == originalBytes)
            if changeSource { #expect(try Data(contentsOf: moved) == originalBytes) }
            else { #expect(Set(try FileManager.default.contentsOfDirectory(atPath: moved.path)) == ["association.sqlite"]) }
        }
        // Cancellation after direct-child join is a refusal with balanced release.
        let lateSpool = try folder(), lateLedger = Ledger(), lateGate = Gate()
        let late = Task {
            defer { lateGate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(lateLedger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { lateLedger.pinned($0) }, associationClosed: { lateLedger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { lateLedger.launch($0) }, settled: { lateLedger.join($0) }, beforeReceipt: { lateGate.hold() })) {
                        try await Operation.associateOriginalCrops(source: original, spoolDirectory: lateSpool, tool: tool, request: request)
                    }
                }
            }
        }
        for await _ in lateGate.entered { break }; lateLedger.expectJoined(count: 1); lateLedger.expectActive(scoped: true)
        late.cancel(); lateGate.release.signal()
        await #expect(throws: CancellationError.self) { try await late.value }
        lateLedger.expectEnded(scoped: true); lateLedger.expectClosed()
        // A long generated source keeps the actual decoder live at a frame gate.
        let view = CompanionDiskCheck.ReadView(sourceBytes: Int64(originalBytes.count), source: { o, n in originalBytes.subdata(in: Int(o)..<(Int(o) + n)) }, component: { _ in throw NativeExportError.invalid("Generated source-only fixture") }, checkpoint: {})
        let walker = CompanionOriginalTrackCheck.Walker(view), header = try walker.element(0, end: view.sourceBytes)
        let segment = try walker.element(header.end, end: view.sourceBytes)
        var prefix = Data(), clusters = Data(), offset = segment.payload
        while offset < segment.end {
            let element = try walker.element(offset, end: segment.end)
            let bytes = originalBytes.subdata(in: Int(offset)..<Int(element.end))
            if element.id == 0x1f43b675 { clusters.append(bytes) } else { prefix.append(bytes) }
            offset = element.end
        }
        var longBytes = originalBytes.prefix(Int(header.end)) + Data([0x18,0x53,0x80,0x67,0xff]) + prefix
        for _ in 0..<2000 { longBytes.append(clusters) }
        let source = root.appendingPathComponent("live-source.mkv"); try longBytes.write(to: source)
        let spool = try folder(), ledger = Ledger(), gate = Gate()
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, row: { d in if String(decoding: d, as: UTF8.self).contains("\"kind\":\"crop-frame\"") { gate.holdFirst() } }, settled: { ledger.join($0) })) {
                        try await Operation.associateOriginalCrops(source: source, spoolDirectory: spool, tool: tool, request: request)
                    }
                }
            }
        }
        for await _ in gate.entered { break }
        ledger.expectActive(scoped: true)
        #expect(ownAssertion(try assertions(), reason: "StaxRip original source crop association"))
        let pid = try #require(ledger.latestPID)
        let state = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
        #expect(state.status == 0 && !String(decoding: state.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
        await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalCrops(source: original, spoolDirectory: spool, tool: tool, request: request) }
        task.cancel(); ledger.expectActive(scoped: true); gate.release.signal()
        var uncertain = false
        do { _ = try await task.value; Issue.record("Cancelled live association returned success") }
        catch is CancellationError { ledger.expectEnded(scoped: true); ledger.expectClosed() }
        catch let e as Operation.ReviewFailure {
            uncertain = true
            #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "group-1-joined-true")
            ledger.expectJoined(count: 1); ledger.expectRetained(); #expect(Operation.retainedForTesting(e.reviewID))
            // Controlled registry isolation after fixed-child join; retain files.
            // This is not process-group settlement or production cleanup authority.
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
        }
        ledger.expectJoined(count: 1)
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source crop association"))
        #expect(try Data(contentsOf: original) == originalBytes && Data(contentsOf: source) == longBytes && Data(contentsOf: prior) == priorBytes)
        #expect(try digest(exe) == originalExe)
        for (name, hash) in hashes { #expect(try digest(runtime.appendingPathComponent("Frameworks/" + name)) == hash) }
        keep = true
        print("Generated concrete crop access: twelve accepted trials/both spaces-threads, nineteen joined decoders, final/late/live refusal; uncertain group=\(uncertain)")
    }

    @Test func cropPartialAcquisitionCheckedRollbackRetainsGrantsOnReportedUncertainty() async throws {
        final class Reports: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let f = try await fixture(); defer { f.cleanup() }; let tool = try cropAccessTool(in: f.root)
        let request = try DolbyCropProcessTests.request()
        let missing = f.root.appendingPathComponent("missing-spool"), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], activities = 0
        let env = Operation.Environment(access: { url in requested.append(url); return { stopped.append(url) } }, activity: { _ in activities += 1; return {} }, retainedActivitySeconds: 0.05)
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(acquisitionClosed: { #expect($0 == 1) })) {
                await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalCrops(source: f.source, spoolDirectory: missing, tool: tool, request: request) }
            }
        }
        #expect(requested == [f.source, missing] && stopped == [missing, f.source] && activities == 0)
        requested.removeAll(); stopped.removeAll()
        let reports = Reports(); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(refuseAssociationClose: { reports.report() }, acquisitionClosed: { _ in Issue.record("Uncertain rollback released grants") })) {
                    try await Operation.associateOriginalCrops(source: f.source, spoolDirectory: missing, tool: tool, request: request)
                }
            }
            Issue.record("Partial acquisition uncertainty returned ordinary refusal/success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID)
        #expect(requested == [f.source, missing] && stopped.isEmpty && activities == 0 && reports.value == 1)
        #expect(Operation.retainedForTesting(id))
        await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(stopped.isEmpty && activities == 0)
        Operation.releaseGeneratedReviewForTesting(id)
        var info = stat(); #expect(fstat(later, &info) == 0 && stopped == [missing, f.source] && reports.value == 1)
        #expect(try Data(contentsOf: f.source) == original && !FileManager.default.fileExists(atPath: missing.path))
    }

    private func associateVideoCrops(_ f: Fixture, tool: DolbyDecoderProcess.Tool) async throws -> CompanionDiskCheck.SourceVideoCropReceipt {
        try await Operation.associateOriginalVideoCrops(source: f.source, spoolDirectory: f.stage, tool: tool, request: DolbyCropProcessTests.request())
    }
    @Test func videoCropAssociationAcquisitionRollbackPrecancelAndActualReadWriteDenials() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        let tool = try cropAccessTool(in: f.root), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], starts = 0, ends = 0
        let failed = Operation.Environment(access: { url in
            requested.append(url)
            if url == f.stage { throw NativeExportError.invalid("Generated spool grant refusal") }
            return { stopped.append(url) }
        }, activity: { _ in starts += 1; return { ends += 1 } })
        await Operation.$testEnvironment.withValue(failed) {
            await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.source] && starts == 0)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await Operation.$testEnvironment.withValue(failed) { try await associateVideoCrops(f, tool: tool) } }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(requested == [f.source, f.stage])
        let env = Operation.Environment(activity: { _ in starts += 1; return { ends += 1 } })
        if geteuid() != 0 {
            var info = stat(); try #require(lstat(f.source.path, &info) == 0)
            let mode = info.st_mode & 0o7777
            defer { _ = chmod(f.source.path, mode); _ = chmod(f.stage.path, 0o700) }
            for (url, deniedMode) in [(f.source, mode_t(0)), (f.stage, mode_t(0))] {
                try #require(chmod(url.path, deniedMode) == 0)
                await Operation.$testEnvironment.withValue(env) {
                    await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied source/spool launched decoder") })) {
                        await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
                    }
                }
                try #require(chmod(url.path, url == f.source ? mode : 0o700) == 0)
            }
            #expect(starts == 0 && ends == 0)
            // Keep strict private POSIX mode while actual generated ACL denies
            // creation of the fixed member. Remove only this fixture's new ACL.
            let acl = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["+a", "everyone deny add_file", f.stage.path])
            try #require(acl.status == 0)
            defer { let result = chmod(f.stage.path, 0o700); #expect(result == 0) }
            await Operation.$testEnvironment.withValue(env) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied spool write launched decoder") })) {
                    await #expect(throws: DolbyAssociationSpool.Failure.self) { try await associateVideoCrops(f, tool: tool) }
                }
            }
            let removed = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["-N", f.stage.path])
            try #require(removed.status == 0)
            #expect(starts == 1 && ends == 1)
        }
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func videoCropAssociationSourceRefusalClosesPinsAndBalancesOnlyExplicitGrants() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger()
        let tool = try cropAccessTool(in: f.root), invalid = Data("Generated invalid source".utf8)
        try invalid.write(to: f.source)
        var requested: [URL] = [], stopped: [URL] = []
        var env = environment(ledger, fakeScopes: true)
        env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } }
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(phase: { phase in #expect(phase == "video-crop-association"); ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Invalid source launched decoder") })) {
                    await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
                }
            }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.stage, f.source])
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source Video/crop association"))
        #expect(try Data(contentsOf: f.source) == invalid)
        // A partial disposable SQLite file is still owned by this explicit caller.
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test func videoCropControlledUnsettledAssociationRetainsAccessAndExcludesAllOperationKindsAfterExpiry() async throws {
        struct ControlledUnsettled: CompanionUnsettledOwnership {}
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), tool = try cropAccessTool(in: f.root)
        let original = try Data(contentsOf: f.source); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in throw ControlledUnsettled() }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) { try await associateVideoCrops(f, tool: tool) }
            }
            Issue.record("Controlled uncertain association returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.intendedStage == f.stage) }
        let id = try #require(reviewID); ledger.expectRetained(); ledger.expectActive(scoped: true)
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
        try await Task.sleep(for: .milliseconds(100))
        ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }

    @Test func videoCropActiveSourcePassCancellationSettlesBeforeGrantAndPinRelease() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), gate = Gate(), tool = try cropAccessTool(in: f.root)
        let original = try Data(contentsOf: f.source)
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled source pass launched decoder") })) {
                        try await CompanionDiskCheck.$testBoundary.withValue(.init(progress: { phase, _ in if phase == "source" { gate.holdFirst() } })) { try await associateVideoCrops(f, tool: tool) }
                    }
                }
            }
        }
        for await _ in gate.entered { break }; ledger.expectActive(scoped: true)
        task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func videoCropReportedOuterCloseRefusalRetainsGrantsAfterActualCloses() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let tool = try cropAccessTool(in: f.root)
        try Data("Generated invalid source".utf8).write(to: f.source)
        final class Reports: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let reports = Reports()
        var scopes = 0, stops = 0, energy = 0, reviewID: UUID?
        let env = Operation.Environment(access: { _ in scopes += 1; return { stops += 1 } }, activity: { _ in energy += 1; return { energy -= 1 } }, retainedActivitySeconds: 0.05)
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(associationClosed: { _ in Issue.record("Reported close refusal released access") }, refuseAssociationClose: { reports.report() })) {
                    try await associateVideoCrops(f, tool: tool)
                }
            }
            Issue.record("Reported outer close uncertainty returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID)
        #expect(scopes == 2 && stops == 0 && energy == 1 && reports.value == 1 && Operation.retainedForTesting(id))
        // Actual closes have consumed numbers; no FD-number absence probe. A
        // subsequent independent FD must not be closed by controlled isolation.
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(energy == 0 && stops == 0)
        Operation.releaseGeneratedReviewForTesting(id)
        var info = stat(); #expect(fstat(later, &info) == 0 && stops == 2 && reports.value == 1)
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test(.enabled(if: cropDecoderDirectory != nil), .timeLimit(.minutes(2)))
    func actualVideoCropAssociationOwnsActivityClosesBothThreadsCancellationAndFinalSelection() async throws {
        let runtime = URL(fileURLWithPath: try #require(Self.cropDecoderDirectory), isDirectory: true)
        func digest(_ url: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: url))) }
        let exe = runtime.appendingPathComponent("Helpers/crop-probe"), originalExe = try digest(exe)
        var hashes: [String: String] = [:]
        for name in ["libavcodec.63.dylib", "libavformat.63.dylib", "libavutil.61.dylib"] { hashes[name] = try digest(runtime.appendingPathComponent("Frameworks/" + name)) }
        let tool = try DolbyDecoderProcess.Tool.developmentCrops(exe, expectedSHA256: originalExe, libraries: hashes, versions: [4129126,4129126,3998054])
        let request = try DolbyCropProcessTests.request(.coded)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-video-crop-access-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var keep = true
        defer { if keep { print("GENERATED_VIDEO_CROP_ACCESS_REVIEW " + root.path) } else { try? FileManager.default.removeItem(at: root) } }
        _ = try await RustFixtureBuild.generate(.reference, at: root, copiesIn: root)
        let original = root.appendingPathComponent("single.mkv"), originalBytes = try Data(contentsOf: original)
        let prior = root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8); try priorBytes.write(to: prior)
        func folder() throws -> URL {
            let url = root.appendingPathComponent("spool-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); return url
        }
        for name in ["single", "conformance", "whole-gop"] {
          let selected = root.appendingPathComponent(name + ".mkv"), selectedBytes = try Data(contentsOf: selected)
          for space in [DolbyDecoderStream.CropRequest.Space.coded, .codecVisible] {
          let request = try DolbyCropProcessTests.request(space)
          for threads in [1, 4] {
            let spool = try folder(), ledger = Ledger(), closes = DecoderCloseObservations(); var requested: [URL] = [], stopped: [URL] = []
            var env = environment(ledger, fakeScopes: threads == 1)
            if threads == 1 { env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } } }
            let result = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); closes.launch($0) }, settled: { ledger.join($0); closes.settle($0) }, closed: { closes.close($0,$1,$2) })) {
                        try await Operation.associateOriginalVideoCrops(source: selected, spoolDirectory: spool, tool: tool, request: request, threads: threads)
                    }
                }
            }
            #expect(result.originalVideoDeclarationsBoundToSource && result.independentSourceFrameAssociationVerified && result.originalSourceAndCallerCropAgreementVerified && !result.independentSourceROIProvenanceVerified && !result.independentSampleValuesVerified && !result.editedPictureSemanticsVerified && result.decoder.frames == (name == "whole-gop" ? 24 : 4))
            if threads == 1 { #expect(requested == [selected, spool] && stopped == [spool, selected]) }
            closes.expect(Set(DolbyDecoderProcess.DescriptorRole.allCases), launched: true)
            ledger.expectJoined(count: 1); ledger.expectEnded(scoped: threads == 1); ledger.expectClosed()
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: spool.path)) == ["association.sqlite"])
            #expect(result.decoder.cropFrameSummaryCount == result.decoder.frames)
            #expect(try Data(contentsOf: selected) == selectedBytes)
            #expect(result.declarations.crop[2] == 1 && result.declarations.unit == 3 && result.declarations.display == [16,9])
            #expect(result.decoder.geometry.sampleAspectRatio == nil)
            if name == "conformance" {
                #expect(result.decoder.geometry.crop == [0,14,0,14] && result.declaredPixelsEqualDecoderCodecVisiblePixels && !result.declaredPixelsEqualDecoderCodedPixels)
            }
          }
        }
        }
        for role in [DolbyDecoderProcess.DescriptorRole.stdoutWrite, .nullInput] {
            let spool = try folder(), ledger = Ledger(), closes = DecoderCloseObservations(refused: role)
            var reviewID: UUID?
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { _ in Issue.record("Uncertain helper released access") })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); closes.launch($0) }, settled: { ledger.join($0); closes.settle($0) }, closed: { closes.close($0,$1,$2) }, refuseClose: { r,_,_ in closes.inject(r) })) {
                            try await Operation.associateOriginalVideoCrops(source: original, spoolDirectory: spool, tool: tool, request: request)
                        }
                    }
                }
                Issue.record("Reported helper close uncertainty released crop access")
            } catch let e as Operation.ReviewFailure {
                reviewID = e.reviewID
                #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "descriptor-close")
            }
            let id = try #require(reviewID)
            closes.expect(Set(DolbyDecoderProcess.DescriptorRole.allCases), launched: true)
            ledger.expectJoined(count: 1); ledger.expectRetained(); ledger.expectActive(scoped: true)
            await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalVideoCrops(source: original, spoolDirectory: spool, tool: tool, request: request) }
            try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
            // Controlled reported refusal after real closes and fixed-child join;
            // test registry isolation is not production recovery/cleanup authority.
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        }
        // Actual source/crop success must still refuse ordinary return when
        // the reported outer close follows both successful real close calls.
        final class OuterReport: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let outerSpool = try folder(), outerLedger = Ledger(), outerReport = OuterReport()
        var outerReview: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(outerLedger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { outerLedger.pinned($0) }, associationClosed: { _ in Issue.record("Reported outer close released successful crop access") }, refuseAssociationClose: { outerReport.report() })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { outerLedger.launch($0) }, settled: { outerLedger.join($0) })) {
                        try await Operation.associateOriginalVideoCrops(source: original, spoolDirectory: outerSpool, tool: tool, request: request)
                    }
                }
            }
            Issue.record("Reported outer close admitted a complete-looking crop receipt")
        } catch let e as Operation.ReviewFailure { outerReview = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let outerID = try #require(outerReview)
        outerLedger.expectJoined(count: 1); outerLedger.expectRetainedGrants(); #expect(outerReport.value == 1)
        #expect(Operation.retainedForTesting(outerID))
        try await Task.sleep(for: .milliseconds(100)); outerLedger.expectEnded(); outerLedger.expectRetainedGrants()
        await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalVideoCrops(source: original, spoolDirectory: outerSpool, tool: tool, request: request) }
        Operation.releaseGeneratedReviewForTesting(outerID); outerLedger.expectEnded(scoped: true)
        let outerMembers = Set(try FileManager.default.contentsOfDirectory(atPath: outerSpool.path))
        #expect(outerReport.value == 1 && outerMembers == ["association.sqlite"])
        // All these final selected-path refusals occur after the real decoder join.
        for changeSource in [false, true] {
            let source = root.appendingPathComponent("final-source-" + UUID().uuidString); try originalBytes.write(to: source)
            let spool = try folder(), ledger = Ledger(), moved = root.appendingPathComponent("retained-selection-" + UUID().uuidString)
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
                                do {
                                    let selected = changeSource ? source : spool
                                    try FileManager.default.moveItem(at: selected, to: moved)
                                    if changeSource { try originalBytes.write(to: selected) }
                                    else { try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                                } catch { Issue.record("Generated association selection substitution failed") }
                            })) { try await Operation.associateOriginalVideoCrops(source: source, spoolDirectory: spool, tool: tool, request: request) }
                        }
                    }
                }
                Issue.record("Changed outer association selection returned success")
            } catch let e as Operation.ReviewFailure {
                #expect(e.intendedStage == spool); ledger.expectJoined(count: 1); ledger.expectRetained()
                #expect(Operation.retainedForTesting(e.reviewID))
                Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
            }
            #expect(try Data(contentsOf: source) == originalBytes)
            if changeSource { #expect(try Data(contentsOf: moved) == originalBytes) }
            else { #expect(Set(try FileManager.default.contentsOfDirectory(atPath: moved.path)) == ["association.sqlite"]) }
        }
        // Cancellation after direct-child join is a refusal with balanced release.
        let lateSpool = try folder(), lateLedger = Ledger(), lateGate = Gate()
        let late = Task {
            defer { lateGate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(lateLedger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { lateLedger.pinned($0) }, associationClosed: { lateLedger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { lateLedger.launch($0) }, settled: { lateLedger.join($0) }, beforeReceipt: { lateGate.hold() })) {
                        try await Operation.associateOriginalVideoCrops(source: original, spoolDirectory: lateSpool, tool: tool, request: request)
                    }
                }
            }
        }
        for await _ in lateGate.entered { break }; lateLedger.expectJoined(count: 1); lateLedger.expectActive(scoped: true)
        late.cancel(); lateGate.release.signal()
        await #expect(throws: CancellationError.self) { try await late.value }
        lateLedger.expectEnded(scoped: true); lateLedger.expectClosed()
        // A long generated source keeps the actual decoder live at a frame gate.
        let view = CompanionDiskCheck.ReadView(sourceBytes: Int64(originalBytes.count), source: { o, n in originalBytes.subdata(in: Int(o)..<(Int(o) + n)) }, component: { _ in throw NativeExportError.invalid("Generated source-only fixture") }, checkpoint: {})
        let walker = CompanionOriginalTrackCheck.Walker(view), header = try walker.element(0, end: view.sourceBytes)
        let segment = try walker.element(header.end, end: view.sourceBytes)
        var prefix = Data(), clusters = Data(), offset = segment.payload
        while offset < segment.end {
            let element = try walker.element(offset, end: segment.end)
            let bytes = originalBytes.subdata(in: Int(offset)..<Int(element.end))
            if element.id == 0x1f43b675 { clusters.append(bytes) } else { prefix.append(bytes) }
            offset = element.end
        }
        var longBytes = originalBytes.prefix(Int(header.end)) + Data([0x18,0x53,0x80,0x67,0xff]) + prefix
        for _ in 0..<2000 { longBytes.append(clusters) }
        let source = root.appendingPathComponent("live-source.mkv"); try longBytes.write(to: source)
        let spool = try folder(), ledger = Ledger(), gate = Gate()
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, row: { d in if String(decoding: d, as: UTF8.self).contains("\"kind\":\"crop-frame\"") { gate.holdFirst() } }, settled: { ledger.join($0) })) {
                        try await Operation.associateOriginalVideoCrops(source: source, spoolDirectory: spool, tool: tool, request: request)
                    }
                }
            }
        }
        for await _ in gate.entered { break }
        ledger.expectActive(scoped: true)
        #expect(ownAssertion(try assertions(), reason: "StaxRip original source Video/crop association"))
        let pid = try #require(ledger.latestPID)
        let state = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
        #expect(state.status == 0 && !String(decoding: state.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
        await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalVideoCrops(source: original, spoolDirectory: spool, tool: tool, request: request) }
        task.cancel(); ledger.expectActive(scoped: true); gate.release.signal()
        var uncertain = false
        do { _ = try await task.value; Issue.record("Cancelled live association returned success") }
        catch is CancellationError { ledger.expectEnded(scoped: true); ledger.expectClosed() }
        catch let e as Operation.ReviewFailure {
            uncertain = true
            #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "group-1-joined-true")
            ledger.expectJoined(count: 1); ledger.expectRetained(); #expect(Operation.retainedForTesting(e.reviewID))
            // Controlled registry isolation after fixed-child join; retain files.
            // This is not process-group settlement or production cleanup authority.
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
        }
        ledger.expectJoined(count: 1)
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source Video/crop association"))
        #expect(try Data(contentsOf: original) == originalBytes && Data(contentsOf: source) == longBytes && Data(contentsOf: prior) == priorBytes)
        #expect(try digest(exe) == originalExe)
        for (name, hash) in hashes { #expect(try digest(runtime.appendingPathComponent("Frameworks/" + name)) == hash) }
        keep = true
        print("Generated concrete joint Video/crop access: twelve accepted trials/both spaces-threads, nineteen joined decoders, final/late/live refusal; uncertain group=\(uncertain)")
    }

    @Test func videoCropPartialAcquisitionCheckedRollbackRetainsGrantsOnReportedUncertainty() async throws {
        final class Reports: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let f = try await fixture(); defer { f.cleanup() }; let tool = try cropAccessTool(in: f.root)
        let request = try DolbyCropProcessTests.request()
        let missing = f.root.appendingPathComponent("missing-spool"), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], activities = 0
        let env = Operation.Environment(access: { url in requested.append(url); return { stopped.append(url) } }, activity: { _ in activities += 1; return {} }, retainedActivitySeconds: 0.05)
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(acquisitionClosed: { #expect($0 == 1) })) {
                await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalVideoCrops(source: f.source, spoolDirectory: missing, tool: tool, request: request) }
            }
        }
        #expect(requested == [f.source, missing] && stopped == [missing, f.source] && activities == 0)
        requested.removeAll(); stopped.removeAll()
        let reports = Reports(); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(refuseAssociationClose: { reports.report() }, acquisitionClosed: { _ in Issue.record("Uncertain rollback released grants") })) {
                    try await Operation.associateOriginalVideoCrops(source: f.source, spoolDirectory: missing, tool: tool, request: request)
                }
            }
            Issue.record("Partial acquisition uncertainty returned ordinary refusal/success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID)
        #expect(requested == [f.source, missing] && stopped.isEmpty && activities == 0 && reports.value == 1)
        #expect(Operation.retainedForTesting(id))
        await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(stopped.isEmpty && activities == 0)
        Operation.releaseGeneratedReviewForTesting(id)
        var info = stat(); #expect(fstat(later, &info) == 0 && stopped == [missing, f.source] && reports.value == 1)
        #expect(try Data(contentsOf: f.source) == original && !FileManager.default.fileExists(atPath: missing.path))
    }

    private func associateParameterCrops(_ f: Fixture, tool: DolbyDecoderProcess.Tool) async throws -> CompanionDiskCheck.SourceParameterCropReceipt {
        try await Operation.associateOriginalParameterCrops(source: f.source, spoolDirectory: f.stage, tool: tool, request: DolbyCropProcessTests.request())
    }
    @Test func parameterCropAssociationAcquisitionRollbackPrecancelAndActualReadWriteDenials() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        let tool = try cropAccessTool(in: f.root), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], starts = 0, ends = 0
        let failed = Operation.Environment(access: { url in
            requested.append(url)
            if url == f.stage { throw NativeExportError.invalid("Generated spool grant refusal") }
            return { stopped.append(url) }
        }, activity: { _ in starts += 1; return { ends += 1 } })
        await Operation.$testEnvironment.withValue(failed) {
            await #expect(throws: NativeExportError.self) { try await associateParameterCrops(f, tool: tool) }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.source] && starts == 0)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await Operation.$testEnvironment.withValue(failed) { try await associateParameterCrops(f, tool: tool) } }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(requested == [f.source, f.stage])
        let env = Operation.Environment(activity: { _ in starts += 1; return { ends += 1 } })
        if geteuid() != 0 {
            var info = stat(); try #require(lstat(f.source.path, &info) == 0)
            let mode = info.st_mode & 0o7777
            defer { _ = chmod(f.source.path, mode); _ = chmod(f.stage.path, 0o700) }
            for (url, deniedMode) in [(f.source, mode_t(0)), (f.stage, mode_t(0))] {
                try #require(chmod(url.path, deniedMode) == 0)
                await Operation.$testEnvironment.withValue(env) {
                    await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied source/spool launched decoder") })) {
                        await #expect(throws: NativeExportError.self) { try await associateParameterCrops(f, tool: tool) }
                    }
                }
                try #require(chmod(url.path, url == f.source ? mode : 0o700) == 0)
            }
            #expect(starts == 0 && ends == 0)
            // Keep strict private POSIX mode while actual generated ACL denies
            // creation of the fixed member. Remove only this fixture's new ACL.
            let acl = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["+a", "everyone deny add_file", f.stage.path])
            try #require(acl.status == 0)
            defer { let result = chmod(f.stage.path, 0o700); #expect(result == 0) }
            await Operation.$testEnvironment.withValue(env) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Denied spool write launched decoder") })) {
                    await #expect(throws: DolbyAssociationSpool.Failure.self) { try await associateParameterCrops(f, tool: tool) }
                }
            }
            let removed = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/chmod"), arguments: ["-N", f.stage.path])
            try #require(removed.status == 0)
            #expect(starts == 1 && ends == 1)
        }
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func parameterCropAssociationSourceRefusalClosesPinsAndBalancesOnlyExplicitGrants() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger()
        let tool = try cropAccessTool(in: f.root), invalid = Data("Generated invalid source".utf8)
        try invalid.write(to: f.source)
        var requested: [URL] = [], stopped: [URL] = []
        var env = environment(ledger, fakeScopes: true)
        env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } }
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(phase: { phase in #expect(phase == "parameter-crop-association"); ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Invalid source launched decoder") })) {
                    await #expect(throws: NativeExportError.self) { try await associateParameterCrops(f, tool: tool) }
                }
            }
        }
        #expect(requested == [f.source, f.stage] && stopped == [f.stage, f.source])
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source parameter/crop association"))
        #expect(try Data(contentsOf: f.source) == invalid)
        // A partial disposable SQLite file is still owned by this explicit caller.
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test func parameterCropControlledUnsettledAssociationRetainsAccessAndExcludesAllOperationKindsAfterExpiry() async throws {
        struct ControlledUnsettled: CompanionUnsettledOwnership {}
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), tool = try cropAccessTool(in: f.root)
        let original = try Data(contentsOf: f.source); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in throw ControlledUnsettled() }, pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) { try await associateParameterCrops(f, tool: tool) }
            }
            Issue.record("Controlled uncertain association returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.intendedStage == f.stage) }
        let id = try #require(reviewID); ledger.expectRetained(); ledger.expectActive(scoped: true)
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associateParameterCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
        try await Task.sleep(for: .milliseconds(100))
        ledger.expectEnded(); ledger.expectRetained(); #expect(Operation.retainedForTesting(id))
        Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }

    @Test func parameterCropActiveSourcePassCancellationSettlesBeforeGrantAndPinRelease() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let ledger = Ledger(), gate = Gate(), tool = try cropAccessTool(in: f.root)
        let original = try Data(contentsOf: f.source)
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled source pass launched decoder") })) {
                        try await CompanionDiskCheck.$testBoundary.withValue(.init(progress: { phase, _ in if phase == "source" { gate.holdFirst() } })) { try await associateParameterCrops(f, tool: tool) }
                    }
                }
            }
        }
        for await _ in gate.entered { break }; ledger.expectActive(scoped: true)
        task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        ledger.expectEnded(scoped: true); ledger.expectClosed()
        #expect(try Data(contentsOf: f.source) == original && FileManager.default.contentsOfDirectory(atPath: f.stage.path).isEmpty)
    }
    @Test func parameterCropReportedOuterCloseRefusalRetainsGrantsAfterActualCloses() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let tool = try cropAccessTool(in: f.root)
        try Data("Generated invalid source".utf8).write(to: f.source)
        final class Reports: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let reports = Reports()
        var scopes = 0, stops = 0, energy = 0, reviewID: UUID?
        let env = Operation.Environment(access: { _ in scopes += 1; return { stops += 1 } }, activity: { _ in energy += 1; return { energy -= 1 } }, retainedActivitySeconds: 0.05)
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(associationClosed: { _ in Issue.record("Reported close refusal released access") }, refuseAssociationClose: { reports.report() })) {
                    try await associateParameterCrops(f, tool: tool)
                }
            }
            Issue.record("Reported outer close uncertainty returned success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID)
        #expect(scopes == 2 && stops == 0 && energy == 1 && reports.value == 1 && Operation.retainedForTesting(id))
        // Actual closes have consumed numbers; no FD-number absence probe. A
        // subsequent independent FD must not be closed by controlled isolation.
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(energy == 0 && stops == 0)
        Operation.releaseGeneratedReviewForTesting(id)
        var info = stat(); #expect(fstat(later, &info) == 0 && stops == 2 && reports.value == 1)
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test(.enabled(if: cropDecoderDirectory != nil), .timeLimit(.minutes(2)))
    func actualParameterCropAssociationOwnsActivityClosesBothThreadsCancellationAndFinalSelection() async throws {
        let runtime = URL(fileURLWithPath: try #require(Self.cropDecoderDirectory), isDirectory: true)
        func digest(_ url: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: url))) }
        let exe = runtime.appendingPathComponent("Helpers/crop-probe"), originalExe = try digest(exe)
        var hashes: [String: String] = [:]
        for name in ["libavcodec.63.dylib", "libavformat.63.dylib", "libavutil.61.dylib"] { hashes[name] = try digest(runtime.appendingPathComponent("Frameworks/" + name)) }
        let tool = try DolbyDecoderProcess.Tool.developmentCrops(exe, expectedSHA256: originalExe, libraries: hashes, versions: [4129126,4129126,3998054])
        let request = try DolbyCropProcessTests.request(.coded)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-parameter-crop-access-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var keep = true
        defer { if keep { print("GENERATED_PARAMETER_CROP_ACCESS_REVIEW " + root.path) } else { try? FileManager.default.removeItem(at: root) } }
        _ = try await RustFixtureBuild.generate(.reference, at: root, copiesIn: root)
        let original = root.appendingPathComponent("single.mkv"), originalBytes = try Data(contentsOf: original)
        let prior = root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior".utf8); try priorBytes.write(to: prior)
        func folder() throws -> URL {
            let url = root.appendingPathComponent("spool-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); return url
        }
        for name in ["single", "conformance", "whole-gop"] {
          let selected = root.appendingPathComponent(name + ".mkv"), selectedBytes = try Data(contentsOf: selected)
          for space in [DolbyDecoderStream.CropRequest.Space.coded, .codecVisible] {
          let request = try DolbyCropProcessTests.request(space)
          for threads in [1, 4] {
            let spool = try folder(), ledger = Ledger(), closes = DecoderCloseObservations(); var requested: [URL] = [], stopped: [URL] = []
            var env = environment(ledger, fakeScopes: threads == 1)
            if threads == 1 { env.access = { url in requested.append(url); ledger.beginScope(); return { stopped.append(url); ledger.endScope() } } }
            let result = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); closes.launch($0) }, settled: { ledger.join($0); closes.settle($0) }, closed: { closes.close($0,$1,$2) })) {
                        try await Operation.associateOriginalParameterCrops(source: selected, spoolDirectory: spool, tool: tool, request: request, threads: threads)
                    }
                }
            }
            #expect(result.originalVideoDeclarationsBoundToSource && result.independentSourceFrameAssociationVerified && result.originalSourceAndCallerCropAgreementVerified && !result.independentSourceROIProvenanceVerified && !result.independentSampleValuesVerified && !result.editedPictureSemanticsVerified && result.decoder.frames == (name == "whole-gop" ? 24 : 4))
            if threads == 1 { #expect(requested == [selected, spool] && stopped == [spool, selected]) }
            closes.expect(Set(DolbyDecoderProcess.DescriptorRole.allCases), launched: true)
            ledger.expectJoined(count: 1); ledger.expectEnded(scoped: threads == 1); ledger.expectClosed()
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: spool.path)) == ["association.sqlite"])
            #expect(result.decoder.cropFrameSummaryCount == result.decoder.frames && result.vcl.prefixes == result.decoder.frames)
            #expect(result.originalFirstSlicePPSPrefixesBoundToSource && result.selectedPacketParameterSetNALsAbsent)
            #expect(result.sourceSPSPrefixEqualsDecoderCodedGeometry && result.sourceSPSPrefixEqualsDecoderConformanceWindow)
            #expect(!result.activePictureParameterSetSelectionVerified && !result.completeSliceAndParameterConformanceVerified)
            #expect(try Data(contentsOf: selected) == selectedBytes)
            #expect(result.declarations.crop[2] == 1 && result.declarations.unit == 3 && result.declarations.display == [16,9])
            #expect(result.decoder.geometry.sampleAspectRatio == nil)
            if name == "conformance" {
                #expect(result.decoder.geometry.crop == [0,14,0,14] && result.parameters.geometry.conformanceCrop == [0,14,0,14] && result.parameters.geometry.codedWidth == 176)
            }
          }
        }
        }
        for role in [DolbyDecoderProcess.DescriptorRole.stdoutWrite, .nullInput] {
            let spool = try folder(), ledger = Ledger(), closes = DecoderCloseObservations(refused: role)
            var reviewID: UUID?
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { _ in Issue.record("Uncertain helper released access") })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0); closes.launch($0) }, settled: { ledger.join($0); closes.settle($0) }, closed: { closes.close($0,$1,$2) }, refuseClose: { r,_,_ in closes.inject(r) })) {
                            try await Operation.associateOriginalParameterCrops(source: original, spoolDirectory: spool, tool: tool, request: request)
                        }
                    }
                }
                Issue.record("Reported helper close uncertainty released crop access")
            } catch let e as Operation.ReviewFailure {
                reviewID = e.reviewID
                #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "descriptor-close")
            }
            let id = try #require(reviewID)
            closes.expect(Set(DolbyDecoderProcess.DescriptorRole.allCases), launched: true)
            ledger.expectJoined(count: 1); ledger.expectRetained(); ledger.expectActive(scoped: true)
            await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalParameterCrops(source: original, spoolDirectory: spool, tool: tool, request: request) }
            try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
            // Controlled reported refusal after real closes and fixed-child join;
            // test registry isolation is not production recovery/cleanup authority.
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
        }
        // Actual source/crop success must still refuse ordinary return when
        // the reported outer close follows both successful real close calls.
        final class OuterReport: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let outerSpool = try folder(), outerLedger = Ledger(), outerReport = OuterReport()
        var outerReview: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(environment(outerLedger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { outerLedger.pinned($0) }, associationClosed: { _ in Issue.record("Reported outer close released successful crop access") }, refuseAssociationClose: { outerReport.report() })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { outerLedger.launch($0) }, settled: { outerLedger.join($0) })) {
                        try await Operation.associateOriginalParameterCrops(source: original, spoolDirectory: outerSpool, tool: tool, request: request)
                    }
                }
            }
            Issue.record("Reported outer close admitted a complete-looking crop receipt")
        } catch let e as Operation.ReviewFailure { outerReview = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let outerID = try #require(outerReview)
        outerLedger.expectJoined(count: 1); outerLedger.expectRetainedGrants(); #expect(outerReport.value == 1)
        #expect(Operation.retainedForTesting(outerID))
        try await Task.sleep(for: .milliseconds(100)); outerLedger.expectEnded(); outerLedger.expectRetainedGrants()
        await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalParameterCrops(source: original, spoolDirectory: outerSpool, tool: tool, request: request) }
        Operation.releaseGeneratedReviewForTesting(outerID); outerLedger.expectEnded(scoped: true)
        let outerMembers = Set(try FileManager.default.contentsOfDirectory(atPath: outerSpool.path))
        #expect(outerReport.value == 1 && outerMembers == ["association.sqlite"])
        // All these final selected-path refusals occur after the real decoder join.
        for changeSource in [false, true] {
            let source = root.appendingPathComponent("final-source-" + UUID().uuidString); try originalBytes.write(to: source)
            let spool = try folder(), ledger = Ledger(), moved = root.appendingPathComponent("retained-selection-" + UUID().uuidString)
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
                                do {
                                    let selected = changeSource ? source : spool
                                    try FileManager.default.moveItem(at: selected, to: moved)
                                    if changeSource { try originalBytes.write(to: selected) }
                                    else { try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                                } catch { Issue.record("Generated association selection substitution failed") }
                            })) { try await Operation.associateOriginalParameterCrops(source: source, spoolDirectory: spool, tool: tool, request: request) }
                        }
                    }
                }
                Issue.record("Changed outer association selection returned success")
            } catch let e as Operation.ReviewFailure {
                #expect(e.intendedStage == spool); ledger.expectJoined(count: 1); ledger.expectRetained()
                #expect(Operation.retainedForTesting(e.reviewID))
                Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
            }
            #expect(try Data(contentsOf: source) == originalBytes)
            if changeSource { #expect(try Data(contentsOf: moved) == originalBytes) }
            else { #expect(Set(try FileManager.default.contentsOfDirectory(atPath: moved.path)) == ["association.sqlite"]) }
        }
        // Cancellation after direct-child join is a refusal with balanced release.
        let lateSpool = try folder(), lateLedger = Ledger(), lateGate = Gate()
        let late = Task {
            defer { lateGate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(lateLedger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { lateLedger.pinned($0) }, associationClosed: { lateLedger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { lateLedger.launch($0) }, settled: { lateLedger.join($0) }, beforeReceipt: { lateGate.hold() })) {
                        try await Operation.associateOriginalParameterCrops(source: original, spoolDirectory: lateSpool, tool: tool, request: request)
                    }
                }
            }
        }
        for await _ in lateGate.entered { break }; lateLedger.expectJoined(count: 1); lateLedger.expectActive(scoped: true)
        late.cancel(); lateGate.release.signal()
        await #expect(throws: CancellationError.self) { try await late.value }
        lateLedger.expectEnded(scoped: true); lateLedger.expectClosed()
        // A long generated source keeps the actual decoder live at a frame gate.
        let view = CompanionDiskCheck.ReadView(sourceBytes: Int64(originalBytes.count), source: { o, n in originalBytes.subdata(in: Int(o)..<(Int(o) + n)) }, component: { _ in throw NativeExportError.invalid("Generated source-only fixture") }, checkpoint: {})
        let walker = CompanionOriginalTrackCheck.Walker(view), header = try walker.element(0, end: view.sourceBytes)
        let segment = try walker.element(header.end, end: view.sourceBytes)
        var prefix = Data(), clusters = Data(), offset = segment.payload
        while offset < segment.end {
            let element = try walker.element(offset, end: segment.end)
            let bytes = originalBytes.subdata(in: Int(offset)..<Int(element.end))
            if element.id == 0x1f43b675 { clusters.append(bytes) } else { prefix.append(bytes) }
            offset = element.end
        }
        var longBytes = originalBytes.prefix(Int(header.end)) + Data([0x18,0x53,0x80,0x67,0xff]) + prefix
        for _ in 0..<2000 { longBytes.append(clusters) }
        let source = root.appendingPathComponent("live-source.mkv"); try longBytes.write(to: source)
        let spool = try folder(), ledger = Ledger(), gate = Gate()
        let task = Task {
            defer { gate.signal.finish() }
            return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, row: { d in if String(decoding: d, as: UTF8.self).contains("\"kind\":\"crop-frame\"") { gate.holdFirst() } }, settled: { ledger.join($0) })) {
                        try await Operation.associateOriginalParameterCrops(source: source, spoolDirectory: spool, tool: tool, request: request)
                    }
                }
            }
        }
        for await _ in gate.entered { break }
        ledger.expectActive(scoped: true)
        #expect(ownAssertion(try assertions(), reason: "StaxRip original source parameter/crop association"))
        let pid = try #require(ledger.latestPID)
        let state = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
        #expect(state.status == 0 && !String(decoding: state.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
        await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalParameterCrops(source: original, spoolDirectory: spool, tool: tool, request: request) }
        task.cancel(); ledger.expectActive(scoped: true); gate.release.signal()
        var uncertain = false
        do { _ = try await task.value; Issue.record("Cancelled live association returned success") }
        catch is CancellationError { ledger.expectEnded(scoped: true); ledger.expectClosed() }
        catch let e as Operation.ReviewFailure {
            uncertain = true
            #expect((e.operationError as? DolbyDecoderProcess.OwnershipFailure)?.reason == "group-1-joined-true")
            ledger.expectJoined(count: 1); ledger.expectRetained(); #expect(Operation.retainedForTesting(e.reviewID))
            // Controlled registry isolation after fixed-child join; retain files.
            // This is not process-group settlement or production cleanup authority.
            Operation.releaseGeneratedReviewForTesting(e.reviewID); ledger.expectEnded(scoped: true)
        }
        ledger.expectJoined(count: 1)
        #expect(!ownAssertion(try assertions(), reason: "StaxRip original source parameter/crop association"))
        #expect(try Data(contentsOf: original) == originalBytes && Data(contentsOf: source) == longBytes && Data(contentsOf: prior) == priorBytes)
        #expect(try digest(exe) == originalExe)
        for (name, hash) in hashes { #expect(try digest(runtime.appendingPathComponent("Frameworks/" + name)) == hash) }
        keep = true
        print("Generated concrete joint parameter/crop access: twelve accepted trials/both spaces-threads, nineteen joined decoders, final/late/live refusal; uncertain group=\(uncertain)")
    }

    @Test func parameterCropPartialAcquisitionCheckedRollbackRetainsGrantsOnReportedUncertainty() async throws {
        final class Reports: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func report() -> Bool { lock.withLock { count += 1 }; return true }
            var value: Int { lock.withLock { count } }
        }
        let f = try await fixture(); defer { f.cleanup() }; let tool = try cropAccessTool(in: f.root)
        let request = try DolbyCropProcessTests.request()
        let missing = f.root.appendingPathComponent("missing-spool"), original = try Data(contentsOf: f.source)
        var requested: [URL] = [], stopped: [URL] = [], activities = 0
        let env = Operation.Environment(access: { url in requested.append(url); return { stopped.append(url) } }, activity: { _ in activities += 1; return {} }, retainedActivitySeconds: 0.05)
        await Operation.$testEnvironment.withValue(env) {
            await Operation.$testBoundary.withValue(.init(acquisitionClosed: { #expect($0 == 1) })) {
                await #expect(throws: NativeExportError.self) { try await Operation.associateOriginalParameterCrops(source: f.source, spoolDirectory: missing, tool: tool, request: request) }
            }
        }
        #expect(requested == [f.source, missing] && stopped == [missing, f.source] && activities == 0)
        requested.removeAll(); stopped.removeAll()
        let reports = Reports(); var reviewID: UUID?
        do {
            _ = try await Operation.$testEnvironment.withValue(env) {
                try await Operation.$testBoundary.withValue(.init(refuseAssociationClose: { reports.report() }, acquisitionClosed: { _ in Issue.record("Uncertain rollback released grants") })) {
                    try await Operation.associateOriginalParameterCrops(source: f.source, spoolDirectory: missing, tool: tool, request: request)
                }
            }
            Issue.record("Partial acquisition uncertainty returned ordinary refusal/success")
        } catch let e as Operation.ReviewFailure { reviewID = e.reviewID; #expect(e.operationError is any CompanionUnsettledOwnership) }
        let id = try #require(reviewID)
        #expect(requested == [f.source, missing] && stopped.isEmpty && activities == 0 && reports.value == 1)
        #expect(Operation.retainedForTesting(id))
        await #expect(throws: NativeExportError.self) { try await associateParameterCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await execute(f) }
        await #expect(throws: NativeExportError.self) { try await review(f) }
        await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
        await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
        let later = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        try #require(later >= 0); defer { #expect(Darwin.close(later) == 0) }
        try await Task.sleep(for: .milliseconds(100)); #expect(stopped.isEmpty && activities == 0)
        Operation.releaseGeneratedReviewForTesting(id)
        var info = stat(); #expect(fstat(later, &info) == 0 && stopped == [missing, f.source] && reports.value == 1)
        #expect(try Data(contentsOf: f.source) == original && !FileManager.default.fileExists(atPath: missing.path))
    }

    private final class ConstructorCloses: @unchecked Sendable {
        private let lock = NSLock(); private var roles: [String] = []
        func add(_ role: String, _ status: Int32, _ code: Int32) { lock.withLock { #expect(status == 0 && code == 0); roles.append(role) } }
        func expect(_ expected: [String]) { lock.withLock { #expect(roles == expected) } }
    }
    @Test func reportedInternalAdmissionCloseRetainsCropGrantsFactsAfterDropAndExpiry() async throws {
        for variant in ["source", "folder", "file", "both"] {
            let f = try await fixture(), ledger = Ledger(), closes = ConstructorCloses(), tool = try cropAccessTool(in: f.root)
            let original = try Data(contentsOf: f.source); var reviewID: UUID?
            do {
                _ = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { _ in Issue.record("Uncertain admission released outer access") })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Refused constructor launched decoder") })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(fileOpened: { _ in if variant == "source" { throw NativeExportError.invalid("Generated source admission refusal") } }, admissionClosed: { _, status, code in closes.add("source",status,code) }, refuseAdmissionClose: { _ in variant == "source" })) {
                                try await DolbyAssociationSpool.$testAdmissionBoundary.withValue(.init(step: { step in
                                    if variant == "folder" && step == .folderObserved || ["file","both"].contains(variant) && step == .fileObserved { throw CancellationError() }
                                }, closed: { closes.add($0.rawValue,$1,$2) }, refuseClose: { variant == "folder" || variant == "both" || variant == "file" && $0 == .file })) { try await associateCrops(f, tool: tool) }
                            }
                        }
                    }
                }
                Issue.record("Reported internal close returned ordinary result")
            } catch let error as Operation.ReviewFailure {
                reviewID = error.reviewID; #expect(error.intendedStage == f.stage)
                if variant == "source" {
                    let inner = try #require(error.operationError as? CompanionDiskCheck.FileAdmissionFailure)
                    #expect(inner.operationError is NativeExportError && inner.reportedAfterActualClose)
                } else {
                    let inner = try #require(error.operationError as? DolbyAssociationSpool.AdmissionFailure)
                    #expect(inner.operationError is CancellationError && inner.createdMember == (variant != "folder"))
                    #expect(inner.observedFolderID != nil && (inner.observedFileID != nil) == (variant != "folder"))
                    #expect(inner.closeFailures.count == (variant == "both" ? 2 : 1) && inner.closeFailures.allSatisfy { $0.reportedAfterActualClose })
                }
            }
            let id = try #require(reviewID)
            closes.expect(variant == "source" ? ["source"] : variant == "folder" ? ["folder"] : ["file","folder"])
            ledger.expectRetained(); ledger.expectActive(scoped: true); ledger.expectJoined(count: 0)
            await #expect(throws: NativeExportError.self) { try await execute(f) }
            await #expect(throws: NativeExportError.self) { try await review(f) }
            await #expect(throws: NativeExportError.self) { try await associateCrops(f, tool: tool) }
        await #expect(throws: NativeExportError.self) { try await associateVideoCrops(f, tool: tool) }
            await #expect(throws: NativeExportError.self) { try await associate(f, tool: try associationTool(in: f.root)) }
            await #expect(throws: NativeExportError.self) { try await associateSamples(f, tool: try sampleAccessTool(in: f.root)) }
            try await Task.sleep(for: .milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
            let currentSource = try Data(contentsOf: f.source)
            #expect(Operation.retainedForTesting(id) && currentSource == original)
            let names = try FileManager.default.contentsOfDirectory(atPath: f.stage.path)
            #expect(names == (["file","both"].contains(variant) ? [DolbyAssociationSpool.name] : []))
            let later = Darwin.open("/dev/null",O_RDONLY | O_CLOEXEC); try #require(later >= 0)
            Operation.releaseGeneratedReviewForTesting(id); ledger.expectEnded(scoped: true)
            var info = stat(); #expect(fstat(later,&info) == 0 && Darwin.close(later) == 0)
            print("GENERATED_RETAINED_CROP_CONSTRUCTOR \(f.root.path)")
        }
    }
    @Test func actualTaskCancellationDuringConstructorChecksRollbackBeforeReverseRelease() async throws {
        for phase in ["source", "folder", "file"] {
            let f = try await fixture(); defer { f.cleanup() }
            let ledger = Ledger(), closes = ConstructorCloses(), gate = Gate(), tool = try cropAccessTool(in: f.root)
            let task = Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, associationClosed: { ledger.closed($0) })) {
                        try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled admission launched decoder") })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(fileOpened: { _ in if phase == "source" { gate.holdFirst() } }, admissionClosed: { _,status,code in closes.add("source",status,code) })) {
                                try await DolbyAssociationSpool.$testAdmissionBoundary.withValue(.init(step: { step in
                                    if phase == "folder" && step == .folderOpened || phase == "file" && step == .fileOpened { gate.holdFirst() }
                                }, closed: { closes.add($0.rawValue,$1,$2) })) { try await associateCrops(f, tool: tool) }
                            }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped: true)
            task.cancel(); gate.release.signal()
            await #expect(throws: CancellationError.self) { try await task.value }
            closes.expect(phase == "source" ? ["source"] : phase == "folder" ? ["folder"] : ["file","folder"])
            ledger.expectEnded(scoped: true); ledger.expectClosed(); ledger.expectJoined(count: 0)
            let names = try FileManager.default.contentsOfDirectory(atPath: f.stage.path)
            #expect(names == (phase == "file" ? [DolbyAssociationSpool.name] : []))
        }
    }

    // Both fields remain weak: this test witness cannot keep either retained
    // concrete owner alive when the independent registries release their references.
    private final class WeakArchiveWriterOwners {
        weak var pins: CompanionWriterProcess.AdmittedPins?
        weak var stage: ResultSetStaging?
        init(pins: CompanionWriterProcess.AdmittedPins?, stage: ResultSetStaging?) {
            self.pins = pins; self.stage = stage
        }
    }
    @Test func writerPinRefusalsRetainSameOwnerStageAndAccessAfterDropExpiryAndSourcePriority() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly,.entireContainer] {
            for fault in ["one", "all", "source-priority", "opened", "cancel"] {
                let f = try await fixture(), ledger = Ledger(), pinCloses = WriterPinCloses(), gate = Gate()
                defer { print("GENERATED_WRITER_PIN_ACCESS_REVIEW " + f.root.path) }
                let original = try Data(contentsOf: f.source)
                var task: Task<ResultSetStaging.Published,Error>? = Task {
                    defer { gate.signal.finish() }
                    return try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: true)) {
                        try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { _ in Issue.record("Pin refusal released grants") })) {
                            try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, ready: { if fault == "cancel" { gate.hold() } }, settled: { ledger.join($0) },
                                pinClosed: { pinCloses.add($0,$1,$2) }, refusePinClose: { role,_,status in status == 0 && fault != "opened" && (fault == "all" || role == .source) },
                                reportPinSettlementUncertainty: { fault == "opened" })) {
                                try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Pin refusal launched verifier") })) {
                                    try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose: { fault == "source-priority" })) { try await execute(f, mode: mode) }
                                }
                            }
                        }
                    }
                }
                if fault == "cancel" {
                    for await _ in gate.entered { break }
                    ledger.expectActive(scoped: true); #expect(ownAssertion(try assertions()))
                    let pid = try #require(ledger.latestPID)
                    let observed = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
                    #expect(observed.status == 0 && !String(decoding: observed.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
                    task?.cancel(); gate.release.signal()
                }
                var id: UUID?
                do { _ = try await task!.value; Issue.record("Pin refusal published") }
                catch let e as Operation.ReviewFailure {
                    id = e.reviewID; #expect(e.published == nil && e.removed == nil)
                    let cause: (any Error)?
                    if fault == "source-priority" {
                        let source = try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure); cause = source.operationError
                    } else { cause = (try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                    if fault == "opened" { #expect(cause is CompanionWriterProcess.OwnershipFailure) }
                    else {
                        let pin = try #require(cause as? CompanionWriterProcess.PinCloseFailure)
                        #expect((fault == "cancel" ? pin.operationError is CancellationError : pin.operationError == nil) && Set(pin.roles) == Set(fault == "all" ? CompanionWriterProcess.PinRole.allCases : [.source]))
                    }
                }
                task = nil
                let review = try #require(id)
                let witness = WeakArchiveWriterOwners(pins: Operation.retainedWriterPinsForTesting(review),
                                                     stage: Operation.retainedStageForTesting(review))
                #expect(witness.pins != nil && witness.pins === CompanionWriterProcess.retainedPins(source: f.source) && witness.stage != nil)
                ledger.expectJoined(count: 1); ledger.expectRetained()
                if fault == "opened" {
                    for fd in try #require(witness.pins?.descriptorsForTesting) { var info = stat(); #expect(fd >= 0 && fstat(fd,&info) == 0) }
                } else { pinCloses.expectOnce(); #expect(witness.pins?.descriptorsForTesting == [-1,-1,-1]) }
                await #expect(throws: NativeExportError.self) { try await execute(f, mode: mode) }
                try await Task.sleep(for: .milliseconds(100))
                ledger.expectEnded(); ledger.expectRetained(); #expect(witness.pins != nil && witness.stage != nil && Operation.retainedForTesting(review))
                #expect(try Data(contentsOf: f.source) == original)
                #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("published").path))
                CompanionWriterProcess.isolateGeneratedPinsForTesting(try #require(witness.pins))
                #expect(witness.pins != nil) // Existing Access still owns the SAME concrete pins.
                Operation.releaseGeneratedReviewForTesting(review)
                ledger.expectEnded(scoped: true); #expect(witness.pins == nil && witness.stage == nil)
            }
        }
    }

    private final class WriterAdmissionCloses: @unchecked Sendable {
        private let lock = NSLock(); private var values: [(CompanionWriterProcess.PinRole,Int32,Int32)] = []
        func add(_ role: CompanionWriterProcess.PinRole, _ fd: Int32, _ status: Int32) { lock.withLock { values.append((role,fd,status)) } }
        func expect(_ roles: [CompanionWriterProcess.PinRole]) { lock.withLock {
            #expect(values.map { $0.0 } == roles && values.allSatisfy { $0.1 >= 0 && $0.2 == 0 })
            #expect(Set(values.map { $0.1 }).count == values.count)
        } }
    }
    @Test func writerPartialPinRollbackReportRetainsSameAccessStageAfterTaskDropExpiryAndSourcePriority() async throws {
        for phase in ["source","stage","executable","prelaunch","source-priority"] {
            let f = try await fixture(), ledger = Ledger(), closes = WriterAdmissionCloses(), original = try Data(contentsOf:f.source)
            defer { print("GENERATED_ARCHIVE_WRITER_ADMISSION_REVIEW " + f.root.path) }
            let expected: [CompanionWriterProcess.PinRole] = phase == "source" ? [.source] : phase == "stage" ? [.source,.stage] : CompanionWriterProcess.PinRole.allCases
            var task: Task<ResultSetStaging.Published,Error>? = Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { _ in Issue.record("Uncertain admission released access") })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Refused admission launched writer") },
                            pinOpened: { role in if role.rawValue == phase || phase == "source-priority" && role == .executable { throw CancellationError() } },
                            beforeSpawn: { if phase == "prelaunch" { throw CancellationError() } },
                            pinClosed: { ledger.expectActive(scoped:true); closes.add($0,$1,$2) }, refusePinClose: { _,_,status in status == 0 })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Admission uncertainty launched verifier") })) {
                                try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose: { phase == "source-priority" })) { try await execute(f) }
                            }
                        }
                    }
                }
            }
            var id: UUID?
            do { _ = try await task!.value; Issue.record("Admission uncertainty published") }
            catch let e as Operation.ReviewFailure {
                id = e.reviewID; #expect(e.published == nil && e.removed == nil)
                let cause: any Error
                if phase == "source-priority" { cause = (try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)).operationError }
                else { cause = (try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                let pin = try #require(cause as? CompanionWriterProcess.PinCloseFailure)
                #expect(pin.roles == expected && pin.operationError is CancellationError)
            }
            task = nil; closes.expect(expected); let review = try #require(id)
            let witness = WeakArchiveWriterOwners(pins:Operation.retainedWriterPinsForTesting(review),stage:Operation.retainedStageForTesting(review))
            #expect(witness.pins != nil && witness.pins === CompanionWriterProcess.retainedPins(source:f.source) && witness.stage != nil)
            #expect(witness.pins?.descriptorsForTesting == [-1,-1,-1]); ledger.expectJoined(count:0); ledger.expectRetained()
            await #expect(throws: NativeExportError.self) { try await execute(f) }
            try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
            #expect(witness.pins != nil && witness.stage != nil && Operation.retainedForTesting(review))
            #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            CompanionWriterProcess.isolateGeneratedPinsForTesting(try #require(witness.pins)); #expect(witness.pins != nil)
            Operation.releaseGeneratedReviewForTesting(review); ledger.expectEnded(scoped:true); #expect(witness.pins == nil && witness.stage == nil)
        }
    }
    @Test func actualWriterPinAdmissionCancellationClosesBeforeOrdinaryReverseAccessRelease() async throws {
        for phase in ["source","stage","executable","prelaunch"] {
            let f = try await fixture(); defer { f.cleanup() }
            let ledger = Ledger(), closes = WriterAdmissionCloses(), gate = Gate(), original = try Data(contentsOf:f.source)
            let expected: [CompanionWriterProcess.PinRole] = phase == "source" ? [.source] : phase == "stage" ? [.source,.stage] : CompanionWriterProcess.PinRole.allCases
            let task = Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0); closes.expect(expected) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled admission launched writer") },
                            pinOpened: { role in if role.rawValue == phase { gate.holdFirst() } }, beforeSpawn: { if phase == "prelaunch" { gate.holdFirst() } },
                            pinClosed: { ledger.expectActive(scoped:true); closes.add($0,$1,$2) })) { try await execute(f) }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped:true); #expect(ownAssertion(try assertions()))
            task.cancel(); gate.release.signal(); await #expect(throws: CancellationError.self) { try await task.value }
            closes.expect(expected); ledger.expectJoined(count:0); ledger.expectClosed(); ledger.expectEnded(scoped:true)
            #expect(!ownAssertion(try assertions()) && CompanionWriterProcess.retainedPins(source:f.source) == nil)
            #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
        }
    }

    private final class WriterPrelaunchPipeCloses: @unchecked Sendable {
        private let lock = NSLock(); private var values: [(CompanionWriterProcess.PipeRole,Int32,Int32)] = []
        func add(_ role: CompanionWriterProcess.PipeRole, _ fd: Int32, _ status: Int32) { lock.withLock { values.append((role,fd,status)) } }
        func expect(_ roles: [CompanionWriterProcess.PipeRole]) { lock.withLock { #expect(values.map { $0.0 } == roles && values.allSatisfy { $0.1 >= 0 && $0.2 == 0 }); #expect(Set(values.map { $0.1 }).count == values.count) } }
    }
    private func writerPrelaunchRoles(_ phase: String) -> [CompanionWriterProcess.PipeRole] {
        phase == "stdinOpened" ? [.stdinRead,.stdinWrite] : phase == "stdoutOpened" ? [.stdinRead,.stdinWrite,.stdoutRead,.stdoutWrite] : CompanionWriterProcess.PipeRole.allCases
    }
    @Test func writerPrelaunchPipeReportsRetainSameOwnerAccessAfterDropExpiryAndStrongerSource() async throws {
        for phase in ["stdinOpened","stdoutOpened","stderrOpened","stderrNonblocking","prelaunch","source-priority","mixed-pins"] {
            let f = try await fixture(); defer { print("GENERATED_ARCHIVE_PRELAUNCH_PIPE_REVIEW " + f.root.path) }
            let ledger = Ledger(), pipes = WriterPrelaunchPipeCloses(), pins = WriterAdmissionCloses(), original = try Data(contentsOf:f.source), roles = writerPrelaunchRoles(phase)
            var task: Task<ResultSetStaging.Published,Error>? = Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { _ in Issue.record("Uncertain pipe released access") })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Refused pipe launched writer") },
                            closed: { ledger.expectActive(scoped:true); pipes.add($0,$1,$2) }, refuseClose: { _,_,status in status == 0 },
                            pipeAdmission: { step in if step.rawValue == phase || ["source-priority","mixed-pins"].contains(phase) && step == .stderrOpened { throw CancellationError() } },
                            beforeSpawn: { if phase == "prelaunch" { throw CancellationError() } }, pinClosed: { role,fd,status in pipes.expect(roles); pins.add(role,fd,status) },
                            refusePinClose: { _,_,status in phase == "mixed-pins" && status == 0 })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Uncertain pipe launched verifier") })) {
                                try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose: { phase == "source-priority" })) { try await execute(f) }
                            }
                        }
                    }
                }
            }
            var id: UUID?
            do { _ = try await task!.value; Issue.record("Uncertain pipe published") }
            catch let e as Operation.ReviewFailure {
                id=e.reviewID; #expect(e.published == nil && e.removed == nil)
                var cause: any Error
                if phase == "source-priority" { cause=(try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)).operationError }
                else { cause=(try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                if phase == "mixed-pins" { let pin = try #require(cause as? CompanionWriterProcess.PinCloseFailure); #expect(pin.roles == CompanionWriterProcess.PinRole.allCases); cause=try #require(pin.operationError) }
                let pipe = try #require(cause as? CompanionWriterProcess.PipeCloseFailure); #expect(pipe.roles == roles && pipe.operationError is CancellationError)
            }
            task=nil; let review=try #require(id); pipes.expect(roles); pins.expect(CompanionWriterProcess.PinRole.allCases)
            let witness=WeakArchiveWriterOwners(pins:Operation.retainedWriterPinsForTesting(review),stage:Operation.retainedStageForTesting(review))
            #expect(witness.pins != nil && witness.pins === CompanionWriterProcess.retainedPins(source:f.source) && witness.stage != nil)
            #expect(witness.pins?.pipeDescriptorsForTesting == Array(repeating:-1,count:6)); ledger.expectJoined(count:0); ledger.expectRetained()
            await #expect(throws: NativeExportError.self) { try await execute(f) }
            try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(witness.pins != nil && witness.stage != nil)
            #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            CompanionWriterProcess.isolateGeneratedPinsForTesting(try #require(witness.pins)); #expect(witness.pins != nil)
            Operation.releaseGeneratedReviewForTesting(review); ledger.expectEnded(scoped:true); #expect(witness.pins == nil && witness.stage == nil)
        }
    }
    @Test func actualPipeAdmissionCancellationChecksAllPairsBeforeOrdinaryAccessRelease() async throws {
        for phase in ["stdinOpened","stdoutOpened","stderrOpened","stderrNonblocking","prelaunch"] {
            let f = try await fixture(); defer { f.cleanup() }
            let ledger=Ledger(), pipes=WriterPrelaunchPipeCloses(), pins=WriterAdmissionCloses(), gate=Gate(), roles=writerPrelaunchRoles(phase)
            let task=Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) }, archiveClosed: { ledger.closed($0); pipes.expect(roles); pins.expect(CompanionWriterProcess.PinRole.allCases) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Cancelled pipe launched writer") },
                            closed: { pipes.add($0,$1,$2) }, pipeAdmission: { step in if step.rawValue == phase { gate.holdFirst() } },
                            beforeSpawn: { if phase == "prelaunch" { gate.holdFirst() } }, pinClosed: { role,fd,status in pipes.expect(roles); pins.add(role,fd,status) })) { try await execute(f) }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped:true); #expect(ownAssertion(try assertions()))
            task.cancel(); gate.release.signal(); await #expect(throws: CancellationError.self) { try await task.value }
            ledger.expectJoined(count:0); ledger.expectClosed(); ledger.expectEnded(scoped:true)
            #expect(!ownAssertion(try assertions()) && CompanionWriterProcess.retainedPins(source:f.source) == nil)
        }
    }

    private final class DiskEnumerationCloses: @unchecked Sendable {
        private let lock=NSLock(); private var values:[String]=[]
        func add(_ pass:CompanionDiskCheck.EnumerationPass,_ role:CompanionDiskCheck.EnumerationRole,_ status:Int32,_ code:Int32) {
            lock.withLock { #expect(status == 0 && code == 0); values.append(pass.rawValue+"/"+role.rawValue) }
        }
        func expect(_ expected:[String]) { lock.withLock { #expect(values == expected) } }
    }
    private final class WeakDiskEnumerationOwner {
        weak var directory: CompanionDiskCheck.Directory?
        weak var stage: ResultSetStaging?
    }
    private func checkRetainedEnumeration(_ witness:WeakDiskEnumerationOwner,_ review:UUID) throws {
        let directory=try #require(witness.directory)
        #expect(directory === Operation.retainedEnumerationDirectoryForTesting(review))
        #expect(directory.enumerationConsumedForTesting && witness.stage != nil)
        var info=stat(); #expect(fstat(directory.descriptorForTesting,&info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR))
    }
    @Test func checkedMembershipEnumerationPrecedesBothModeOriginalSemanticPublication() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly,.entireContainer] {
            let f=try await fixture(), ledger=Ledger(), closes=DiskEnumerationCloses(), original=try Data(contentsOf:f.source)
            let result=try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ ledger.closed($0); closes.expect(["initial/stream","final/stream"]) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(enumerationOpened:{ _,_ in ledger.expectActive(scoped:true) },enumerationClosed:{ closes.add($0,$1,$2,$3) })) {
                                try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit:{ closes.expect(["initial/stream","final/stream"]); ledger.expectActive(scoped:true) })) { try await execute(f,mode:mode) }
                            }
                        }
                    }
                }
            }
            ledger.expectJoined(count:2); ledger.expectClosed(); ledger.expectEnded(scoped:true)
            #expect(try Data(contentsOf:f.source) == original)
            let names=try FileManager.default.contentsOfDirectory(atPath:result.directory.path); #expect(Set(names) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf:result.directory.appendingPathComponent("original-container.mkv")) == original) }
            f.cleanup()
        }
    }
    @Test func membershipEnumerationReportsRetainSameDirectoryAndAccessAfterDropExpiryAndSourcePriority() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly,.entireContainer] {
          for point in ["initial/stream","final/stream","initial/duplicate","final/duplicate","initial/source-priority","final/source-priority"] {
            let f=try await fixture(), ledger=Ledger(), closes=DiskEnumerationCloses(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
            defer { print("GENERATED_ENUMERATION_ACCESS_REVIEW " + f.root.path) }
            let prior=f.root.appendingPathComponent("prior-output"), priorBytes=Data("Generated prior output".utf8); try priorBytes.write(to:prior)
            let pass=point.hasPrefix("initial") ? CompanionDiskCheck.EnumerationPass.initial : .final
            let role=point.hasSuffix("duplicate") ? CompanionDiskCheck.EnumerationRole.duplicate : .stream
            let expected=pass == .initial ? ["initial/"+role.rawValue] : ["initial/stream","final/"+role.rawValue]
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ _ in Issue.record("Uncertain enumeration released outer pins") })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                                try await CompanionDiskCheck.$testBoundary.withValue(.init(allowEnumerationStream:{ current in !(current == pass && role == .duplicate) },
                                    enumerationClosed:{ ledger.expectActive(scoped:true); closes.add($0,$1,$2,$3) },refuseEnumerationClose:{ current,currentRole in current == pass && currentRole == role })) {
                                    try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose:{ point.hasSuffix("source-priority") })) { try await execute(f,mode:mode) }
                                }
                            }
                        }
                    }
                }
            }
            var id:UUID?
            do { _=try await task!.value; Issue.record("Uncertain enumeration published") }
            catch let e as Operation.ReviewFailure {
                id=e.reviewID; #expect(e.published == nil && e.removed == nil)
                let cause:any Error
                if point.hasSuffix("source-priority") { cause=(try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)).operationError }
                else { cause=(try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                let fault=try #require(cause as? CompanionDiskCheck.EnumerationCloseFailure)
                #expect(fault.pass == pass && fault.role == role && fault.closeStatus == 0 && fault.closeErrno == 0 && fault.reportedAfterActualClose)
                if role == .duplicate { #expect(fault.operationError is NativeExportError) } else { #expect(fault.operationError == nil) }
                witness.directory=fault.directory; witness.stage=Operation.retainedStageForTesting(e.reviewID)
            }
            task=nil; let review=try #require(id); closes.expect(expected); ledger.expectJoined(count:pass == .initial ? 1 : 2)
            try checkRetainedEnumeration(witness,review); ledger.expectRetained()
            await #expect(throws:NativeExportError.self) { try await execute(f,mode:mode) }
            try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); try checkRetainedEnumeration(witness,review)
            #expect(try Data(contentsOf:f.source) == original && Data(contentsOf:prior) == priorBytes)
            #expect(!FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            Operation.isolateGeneratedEnumerationReviewForTesting(review)
            #expect(witness.directory != nil && witness.stage != nil); ledger.expectRetained()
            // Original Directory fd retirement is unqualified. Preserve registry,
            // concrete owner/access/stage and root; no DEBUG release or cleanup.
          }
        }
    }
    @Test func actualMembershipCancellationConsumesStreamBeforeReleaseOrRetainedReview() async throws {
        for point in ["initial/duplicate","initial/stream","final/duplicate","final/stream"] {
          for reported in [false,true] {
            let f=try await fixture(), ledger=Ledger(), closes=DiskEnumerationCloses(), gate=Gate(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
            let expected=point.hasPrefix("initial") ? [point] : ["initial/stream",point]
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in if reported { Issue.record("Uncertain cancelled enumeration released access") }; ledger.closed(count); closes.expect(expected) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                                try await CompanionDiskCheck.$testBoundary.withValue(.init(enumerationOpened:{ pass,role in if point == pass.rawValue+"/"+role.rawValue { gate.hold() } },
                                    enumerationClosed:{ closes.add($0,$1,$2,$3) },refuseEnumerationClose:{ pass,role in reported && point == pass.rawValue+"/"+role.rawValue })) { try await execute(f) }
                            }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped:true); #expect(ownAssertion(try assertions()))
            task!.cancel(); gate.release.signal(); var id:UUID?
            do { _=try await task!.value; Issue.record("Cancelled enumeration published") }
            catch let e as Operation.ReviewFailure {
                #expect(reported); id=e.reviewID
                let phase=try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)
                let fault=try #require(phase.operationError as? CompanionDiskCheck.EnumerationCloseFailure); #expect(fault.operationError is CancellationError)
                witness.directory=fault.directory; witness.stage=Operation.retainedStageForTesting(e.reviewID)
            } catch { if error is any CompanionUnsettledOwnership { print("GENERATED_UNEXPECTED_ENUMERATION_REVIEW " + f.root.path); throw error }; #expect(!reported && error is CancellationError) }
            task=nil; closes.expect(expected); ledger.expectJoined(count:point.hasPrefix("initial") ? 1 : 2)
            #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            if reported {
                let review=try #require(id); try checkRetainedEnumeration(witness,review); ledger.expectRetained()
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); try checkRetainedEnumeration(witness,review)
                Operation.isolateGeneratedEnumerationReviewForTesting(review)
                #expect(witness.directory != nil && witness.stage != nil); ledger.expectRetained()
                print("GENERATED_CANCELLED_ENUMERATION_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); #expect(!ownAssertion(try assertions())); f.cleanup() }
          }
        }
    }

    private final class AdmissionDirectoryClose: @unchecked Sendable {
        private let lock=NSLock(); private var count=0
        func add(_ status:Int32,_ code:Int32) { lock.withLock { #expect(status == 0 && code == 0); count += 1 } }
        func expect(_ expected:Int) { lock.withLock { #expect(count == expected) } }
    }
    @Test func directoryAdmissionReportsRetainSamePartialOwnerAndSourcePriorityBothModes() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly,.entireContainer] {
            let ordinary=try await fixture(), normal=Ledger()
            _=try await Operation.$testEnvironment.withValue(environment(normal,fakeScopes:true)) {
                try await Operation.$testBoundary.withValue(.init(pinned:{ normal.pinned($0) },archiveClosed:{ normal.closed($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ normal.launch($0) },settled:{ normal.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ normal.launch($0) },settled:{ normal.join($0) })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(directoryAdmissionOpened:{ _ in normal.expectActive(scoped:true) },directoryAdmissionClosed:{ _,_ in Issue.record("Ordinary admission rolled back") })) { try await execute(ordinary,mode:mode) }
                        }
                    }
                }
            }
            normal.expectJoined(count:2); normal.expectClosed(); normal.expectEnded(scoped:true); ordinary.cleanup()
            for point in ["guard","callback","source-priority","substitution"] {
                let f=try await fixture(), ledger=Ledger(), closes=AdmissionDirectoryClose(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
                defer { print("GENERATED_DIRECTORY_ADMISSION_REVIEW " + f.root.path) }
                var task:Task<ResultSetStaging.Published,Error>?=Task {
                    try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                        try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ _ in Issue.record("Uncertain admission released access") })) {
                            try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                                try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ _ in Issue.record("Refused admission launched verifier") })) {
                                    try await CompanionDiskCheck.$testBoundary.withValue(.init(directoryAdmissionOpened:{ directory in
                                        ledger.expectActive(scoped:true)
                                        if point == "callback" { throw NativeExportError.invalid("Generated directory admission refusal") }
                                        if point == "substitution" { try FileManager.default.moveItem(at:directory.selectedURLForTesting,to:f.root.appendingPathComponent("retained-original-directory")); try FileManager.default.createDirectory(at:directory.selectedURLForTesting,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]) }
                                        else { try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:directory.selectedURLForTesting.path) }
                                    },directoryAdmissionClosed:{ closes.add($0,$1) },refuseDirectoryAdmissionClose:{ true })) {
                                        try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose:{ point == "source-priority" })) { try await execute(f,mode:mode) }
                                    }
                                }
                            }
                        }
                    }
                }
                var id:UUID?
                do { _=try await task!.value; Issue.record("Uncertain directory admission published") }
                catch let e as Operation.ReviewFailure {
                    id=e.reviewID; #expect(e.published == nil && e.removed == nil)
                    let cause:any Error
                    if point == "source-priority" { cause=(try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)).operationError }
                    else { cause=(try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                    let fault=try #require(cause as? CompanionDiskCheck.DirectoryAdmissionFailure)
                    #expect(fault.closeStatus == 0 && fault.closeErrno == 0 && fault.reportedAfterActualClose && fault.operationError is NativeExportError)
                    #expect(fault.directory.descriptorForTesting == -1 && fault.directory.enumerationConsumedForTesting)
                    witness.directory=fault.directory; witness.stage=Operation.retainedStageForTesting(e.reviewID)
                }
                task=nil; let review=try #require(id); closes.expect(1); ledger.expectJoined(count:1)
                #expect(witness.directory != nil && witness.directory === Operation.retainedEnumerationDirectoryForTesting(review) && witness.stage != nil); ledger.expectRetained()
                await #expect(throws:NativeExportError.self) { try await execute(f,mode:mode) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(witness.directory != nil && witness.stage != nil)
                #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
                // Test namespace isolation keeps SAME Access/stage/grants/partial
                // Directory and files. It is not recovery or cleanup authority.
                Operation.isolateGeneratedEnumerationReviewForTesting(review); ledger.expectRetained(); #expect(witness.directory != nil && witness.stage != nil)
            }
        }
    }
    @Test func actualDirectoryAdmissionCancellationChecksRollbackBeforeReleaseOrRetention() async throws {
        for reported in [false,true] {
            let f=try await fixture(), ledger=Ledger(), closes=AdmissionDirectoryClose(), gate=Gate(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in if reported { Issue.record("Uncertain cancelled directory released access") }; closes.expect(1); ledger.closed(count) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ _ in Issue.record("Cancelled admission launched verifier") })) {
                                try await CompanionDiskCheck.$testBoundary.withValue(.init(directoryAdmissionOpened:{ _ in gate.hold() },directoryAdmissionClosed:{ closes.add($0,$1) },refuseDirectoryAdmissionClose:{ reported })) { try await execute(f) }
                            }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped:true); #expect(ownAssertion(try assertions()))
            task!.cancel(); gate.release.signal(); var id:UUID?
            do { _=try await task!.value; Issue.record("Cancelled directory admission published") }
            catch let e as Operation.ReviewFailure {
                #expect(reported && e.published == nil && e.removed == nil); id=e.reviewID
                let phase=try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)
                let fault=try #require(phase.operationError as? CompanionDiskCheck.DirectoryAdmissionFailure)
                #expect(fault.operationError is CancellationError && fault.closeStatus == 0 && fault.closeErrno == 0 && fault.reportedAfterActualClose)
                #expect(fault.directory.descriptorForTesting == -1); witness.directory=fault.directory; witness.stage=Operation.retainedStageForTesting(e.reviewID)
            } catch { if error is any CompanionUnsettledOwnership { print("GENERATED_UNEXPECTED_DIRECTORY_CANCEL_REVIEW " + f.root.path); throw error }; #expect(!reported && error is CancellationError) }
            task=nil; closes.expect(1); ledger.expectJoined(count:1); #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            if reported {
                let review=try #require(id); ledger.expectRetained(); #expect(witness.directory === Operation.retainedEnumerationDirectoryForTesting(review) && witness.stage != nil)
                await #expect(throws:NativeExportError.self) { try await execute(f) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(witness.directory != nil && witness.stage != nil)
                Operation.isolateGeneratedEnumerationReviewForTesting(review); ledger.expectRetained(); #expect(witness.directory != nil && witness.stage != nil)
                print("GENERATED_CANCELLED_DIRECTORY_ADMISSION_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); #expect(!ownAssertion(try assertions())); f.cleanup() }
        }
    }

    private final class MetadataPipeCloses: @unchecked Sendable {
        private let lock = NSLock(); private var roles: [CompanionMetadataProcess.PipeRole] = []
        func add(_ role: CompanionMetadataProcess.PipeRole, _ status: Int32, _ code: Int32) {
            lock.withLock { #expect(status == 0 && code == 0 && !roles.contains(role)); roles.append(role) }
        }
        func expectAll() { lock.withLock { #expect(roles.count == 4 && Set(roles) == Set(CompanionMetadataProcess.PipeRole.allCases)) } }
    }
    @Test func metadataPipeSettlementPrecedesBothModeCommitAndUncertaintyRetainsAccess() async throws {
        typealias Reader = CompanionMetadataProcess
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for point in ["normal"] + Reader.PipeRole.allCases.map({ $0.rawValue }) + ["all", "source-priority"] {
            let f = try await fixture(), ledger = Ledger(), closes = MetadataPipeCloses(), witness = WeakDiskEnumerationOwner(), original = try Data(contentsOf:f.source)
            let reported = point != "normal"
            var task: Task<ResultSetStaging.Published, Error>? = Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in
                        if reported { Issue.record("Uncertain metadata pipe released access") }; closes.expectAll(); ledger.closed(count)
                    })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await Reader.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },
                                beforeReceipt:{ closes.expectAll(); ledger.expectJoined(count:2); ledger.expectActive(scoped:true) },
                                closed:{ closes.add($0,$1,$2) },refuseClose:{ point == "all" || point == "source-priority" || point == $0.rawValue })) {
                                try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose:{ point == "source-priority" })) {
                                    try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit:{
                                        #expect(!reported); closes.expectAll(); ledger.expectJoined(count:2)
                                    })) { try await execute(f,mode:mode) }
                                }
                            }
                        }
                    }
                }
            }
            var id: UUID?
            do { _ = try await task!.value; #expect(!reported) }
            catch let e as Operation.ReviewFailure {
                #expect(reported && e.published == nil && e.removed == nil); id=e.reviewID
                let cause: any Error
                if point == "source-priority" { cause=(try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)).operationError }
                else { cause=(try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                let fault = try #require(cause as? Reader.PipeCloseFailure)
                #expect(fault.operationError == nil)
                let expected = point == "all" || point == "source-priority" ? Set(Reader.PipeRole.allCases) : Set(Reader.PipeRole.allCases.filter({ $0.rawValue == point }))
                #expect(Set(fault.roles) == expected); witness.stage=Operation.retainedStageForTesting(e.reviewID)
            }
            task=nil; closes.expectAll(); ledger.expectJoined(count:2); #expect(try Data(contentsOf:f.source) == original)
            if reported {
                let review=try #require(id); ledger.expectRetained(); #expect(witness.stage != nil)
                #expect(!FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
                await #expect(throws:NativeExportError.self) { try await execute(f,mode:mode) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(witness.stage != nil)
                // Existing generated-review isolation retains access strongly; no release.
                Operation.isolateGeneratedMetadataPipeReviewForTesting(review)
                ledger.expectRetained(); #expect(witness.stage != nil)
                print("GENERATED_OWNING_METADATA_PIPE_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); f.cleanup() }
          }
        }
    }

    @Test func actualLateMetadataCancellationChecksPipesBeforeReleaseOrRetainedAccess() async throws {
        for reported in [false,true] {
            let f=try await fixture(), ledger=Ledger(), closes=MetadataPipeCloses(), gate=Gate(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in
                        if reported { Issue.record("Uncertain cancelled metadata released access") }; closes.expectAll(); ledger.closed(count)
                    })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },
                                beforeReceipt:{ closes.expectAll(); ledger.expectJoined(count:2); gate.hold() },
                                closed:{ closes.add($0,$1,$2) },refuseClose:{ _ in reported })) { try await execute(f) }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped:true); #expect(ownAssertion(try assertions()))
            task!.cancel(); gate.release.signal(); var id:UUID?
            do { _=try await task!.value; Issue.record("Late cancelled metadata published") }
            catch let e as Operation.ReviewFailure {
                #expect(reported && e.published == nil && e.removed == nil); id=e.reviewID
                let phase=try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)
                let fault=try #require(phase.operationError as? CompanionMetadataProcess.PipeCloseFailure)
                #expect(fault.operationError is CancellationError && Set(fault.roles) == Set(CompanionMetadataProcess.PipeRole.allCases)); witness.stage=Operation.retainedStageForTesting(e.reviewID)
            } catch {
                if error is any CompanionUnsettledOwnership { print("GENERATED_UNEXPECTED_LATE_METADATA_REVIEW " + f.root.path); throw error }
                #expect(!reported && error is CancellationError)
            }
            task=nil; closes.expectAll(); ledger.expectJoined(count:2)
            #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            if reported {
                let review=try #require(id); ledger.expectRetained(); #expect(witness.stage != nil)
                await #expect(throws:NativeExportError.self) { try await execute(f) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(witness.stage != nil)
                Operation.isolateGeneratedMetadataPipeReviewForTesting(review); ledger.expectRetained(); #expect(witness.stage != nil)
                print("GENERATED_CANCELLED_OWNING_METADATA_PIPE_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); #expect(!ownAssertion(try assertions())); f.cleanup() }
        }
    }

    private final class MetadataNullClose: @unchecked Sendable {
        private let lock=NSLock(); private var count=0
        func add(_ status:Int32,_ code:Int32) { lock.withLock { #expect(status == 0 && code == 0); count += 1 } }
        func expectOne() { lock.withLock { #expect(count == 1) } }
    }
    @Test func metadataNullAndMixedPipeReportsBlockBothModePublicationAndRetainAccess() async throws {
        typealias Reader=CompanionMetadataProcess
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly,.entireContainer] {
          for point in ["normal","null","mixed","source-priority"] {
            let f=try await fixture(), ledger=Ledger(), pipes=MetadataPipeCloses(), null=MetadataNullClose(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source), reported=point != "normal"
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in
                        if reported { Issue.record("Uncertain null close released access") }; null.expectOne(); ledger.closed(count)
                    })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await Reader.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },closed:{ pipes.add($0,$1,$2) },
                                refuseClose:{ _ in point == "mixed" || point == "source-priority" },nullClosed:{ status,code in
                                    pipes.expectAll(); ledger.expectJoined(count:2); ledger.expectActive(scoped:true); null.add(status,code)
                                },refuseNullClose:{ reported })) {
                                try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose:{ point == "source-priority" })) {
                                    try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit:{ #expect(!reported); null.expectOne(); pipes.expectAll(); ledger.expectJoined(count:2) })) { try await execute(f,mode:mode) }
                                }
                            }
                        }
                    }
                }
            }
            var id:UUID?
            do { _=try await task!.value; #expect(!reported) }
            catch let e as Operation.ReviewFailure {
                #expect(reported && e.published == nil && e.removed == nil); id=e.reviewID
                let cause:any Error
                if point == "source-priority" { cause=(try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)).operationError }
                else { cause=(try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                let fault=try #require(cause as? Reader.NullCloseFailure); #expect(fault.closeStatus == 0 && fault.closeErrno == 0 && fault.reportedAfterActualClose)
                if point == "mixed" || point == "source-priority" { let pipe=try #require(fault.operationError as? Reader.PipeCloseFailure); #expect(pipe.operationError == nil && Set(pipe.roles) == Set(Reader.PipeRole.allCases)) }
                else { #expect(fault.operationError == nil) }; witness.stage=Operation.retainedStageForTesting(e.reviewID)
            }
            task=nil; null.expectOne(); pipes.expectAll(); ledger.expectJoined(count:2); #expect(try Data(contentsOf:f.source) == original)
            if reported {
                let review=try #require(id); ledger.expectRetained(); #expect(witness.stage != nil && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
                await #expect(throws:NativeExportError.self) { try await execute(f,mode:mode) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(witness.stage != nil)
                Operation.isolateGeneratedMetadataPipeReviewForTesting(review); ledger.expectRetained(); #expect(witness.stage != nil)
                print("GENERATED_OWNING_METADATA_NULL_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); f.cleanup() }
          }
        }
    }
    @Test func actualLateMetadataNullCancellationRetainsOriginalPipeCauseAndAccess() async throws {
        for reported in [false,true] {
            let f=try await fixture(), ledger=Ledger(), pipes=MetadataPipeCloses(), null=MetadataNullClose(), gate=Gate(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in
                        if reported { Issue.record("Uncertain cancelled null close released access") }; null.expectOne(); ledger.closed(count)
                    })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },beforeReceipt:{ pipes.expectAll(); ledger.expectJoined(count:2); gate.hold() },
                                closed:{ pipes.add($0,$1,$2) },refuseClose:{ _ in reported },nullClosed:{ status,code in pipes.expectAll(); ledger.expectJoined(count:2); null.add(status,code) },refuseNullClose:{ reported })) { try await execute(f) }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped:true); #expect(ownAssertion(try assertions()))
            task!.cancel(); gate.release.signal(); var id:UUID?
            do { _=try await task!.value; Issue.record("Cancelled null close trial published") }
            catch let e as Operation.ReviewFailure {
                #expect(reported && e.published == nil && e.removed == nil); id=e.reviewID
                let phase=try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure), fault=try #require(phase.operationError as? CompanionMetadataProcess.NullCloseFailure)
                #expect(fault.closeStatus == 0 && fault.closeErrno == 0 && fault.reportedAfterActualClose)
                let pipe=try #require(fault.operationError as? CompanionMetadataProcess.PipeCloseFailure); #expect(pipe.operationError is CancellationError && Set(pipe.roles) == Set(CompanionMetadataProcess.PipeRole.allCases)); witness.stage=Operation.retainedStageForTesting(e.reviewID)
            } catch { if error is any CompanionUnsettledOwnership { print("GENERATED_UNEXPECTED_OWNING_NULL_CANCEL_REVIEW " + f.root.path); throw error }; #expect(!reported && error is CancellationError) }
            task=nil; null.expectOne(); pipes.expectAll(); ledger.expectJoined(count:2); #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            if reported {
                let review=try #require(id); ledger.expectRetained(); #expect(witness.stage != nil)
                await #expect(throws:NativeExportError.self) { try await execute(f) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(witness.stage != nil)
                Operation.isolateGeneratedMetadataPipeReviewForTesting(review); ledger.expectRetained(); #expect(witness.stage != nil)
                print("GENERATED_CANCELLED_OWNING_METADATA_NULL_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); #expect(!ownAssertion(try assertions())); f.cleanup() }
        }
    }


    private final class MetadataPinCloses: @unchecked Sendable {
        private let lock=NSLock(); private var roles:[CompanionMetadataProcess.PinRole]=[]
        func add(_ role:CompanionMetadataProcess.PinRole,_ status:Int32,_ code:Int32) { lock.withLock { #expect(status == 0 && code == 0); #expect(!roles.contains(role)); roles.append(role) } }
        func expectPair() { lock.withLock { #expect(roles == [.source,.executable]) } }
    }
    private final class WeakMetadataPins {
        weak var source, executable: CompanionMetadataProcess.Pin?
        weak var stage: ResultSetStaging?
    }
    private func expectRetainedMetadataPair(_ witness:WeakMetadataPins,_ id:UUID) throws {
        let source=try #require(witness.source), executable=try #require(witness.executable), pair=Operation.retainedMetadataPinsForTesting(id)
        #expect(source === pair.0 && executable === pair.1 && source !== executable)
        #expect(source.descriptorForTesting == -1 && executable.descriptorForTesting == -1)
    }
    @Test func metadataPinPairReportsRetainSameObjectsAcrossBothModePublicationAndSourcePriority() async throws {
        typealias Reader=CompanionMetadataProcess
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly,.entireContainer] {
          for point in ["normal","source","executable","both","mixed","source-priority"] {
            let f=try await fixture(), ledger=Ledger(), pipes=MetadataPipeCloses(), null=MetadataNullClose(), pins=MetadataPinCloses(), witness=WeakMetadataPins(), original=try Data(contentsOf:f.source), reported=point != "normal"
            let refused:Set<Reader.PinRole> = point == "normal" ? [] : point == "source" ? [.source] : point == "executable" ? [.executable] : Set(Reader.PinRole.allCases)
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in
                        if reported { Issue.record("Uncertain metadata pin pair released access") }; pins.expectPair(); ledger.closed(count)
                    })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await Reader.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },closed:{ pipes.add($0,$1,$2) },refuseClose:{ _ in point == "mixed" || point == "source-priority" },nullClosed:{ status,code in pipes.expectAll(); ledger.expectJoined(count:2); null.add(status,code) },refuseNullClose:{ point == "mixed" || point == "source-priority" },pinClosed:{ role,status,code in
                                pipes.expectAll(); null.expectOne(); ledger.expectJoined(count:2); ledger.expectActive(scoped:true); pins.add(role,status,code)
                            },refusePinClose:{ refused.contains($0) })) {
                                try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose:{ point == "source-priority" })) {
                                    try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit:{ #expect(!reported); pins.expectPair(); null.expectOne(); pipes.expectAll(); ledger.expectJoined(count:2) })) { try await execute(f,mode:mode) }
                                }
                            }
                        }
                    }
                }
            }
            var id:UUID?
            do { _=try await task!.value; #expect(!reported) }
            catch let e as Operation.ReviewFailure {
                guard reported else { print("GENERATED_UNEXPECTED_NORMAL_OWNING_METADATA_PIN_REVIEW " + f.root.path); throw e }
                #expect(reported && e.published == nil && e.removed == nil); id=e.reviewID
                let cause:any Error
                if point == "source-priority" { cause=(try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)).operationError }
                else { cause=(try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                let fault=try #require(cause as? Reader.PinCloseFailure); #expect(Set(fault.roles) == refused)
                witness.source=fault.sourcePin; witness.executable=fault.executablePin; witness.stage=Operation.retainedStageForTesting(e.reviewID)
                if point == "mixed" || point == "source-priority" { let n=try #require(fault.operationError as? Reader.NullCloseFailure), p=try #require(n.operationError as? Reader.PipeCloseFailure); #expect(n.reportedAfterActualClose && p.operationError == nil && Set(p.roles) == Set(Reader.PipeRole.allCases)) }
                else { #expect(fault.operationError == nil) }
                try expectRetainedMetadataPair(witness,e.reviewID)
            }
            task=nil; pins.expectPair(); null.expectOne(); pipes.expectAll(); ledger.expectJoined(count:2); #expect(try Data(contentsOf:f.source) == original)
            if reported {
                let review=try #require(id); try expectRetainedMetadataPair(witness,review); ledger.expectRetained(); #expect(witness.stage != nil && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
                await #expect(throws:NativeExportError.self) { try await execute(f,mode:mode) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); try expectRetainedMetadataPair(witness,review); #expect(witness.stage != nil)
                Operation.isolateGeneratedMetadataPipeReviewForTesting(review); ledger.expectRetained(); #expect(witness.source != nil && witness.executable != nil && witness.stage != nil)
                print("GENERATED_OWNING_METADATA_PIN_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); f.cleanup() }
          }
        }
    }
    @Test func actualLateMetadataPinCancellationRetainsPairNullPipeCauseAndAccess() async throws {
        typealias Reader=CompanionMetadataProcess
        for reported in [false,true] {
            let f=try await fixture(), ledger=Ledger(), pipes=MetadataPipeCloses(), null=MetadataNullClose(), pins=MetadataPinCloses(), gate=Gate(), witness=WeakMetadataPins(), original=try Data(contentsOf:f.source)
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in if reported { Issue.record("Cancelled pin refusal released access") }; pins.expectPair(); ledger.closed(count) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await Reader.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },beforeReceipt:{ pipes.expectAll(); ledger.expectJoined(count:2); gate.hold() },closed:{ pipes.add($0,$1,$2) },refuseClose:{ _ in reported },nullClosed:{ status,code in pipes.expectAll(); ledger.expectJoined(count:2); null.add(status,code) },refuseNullClose:{ reported },pinClosed:{ role,status,code in null.expectOne(); ledger.expectJoined(count:2); pins.add(role,status,code) },refusePinClose:{ _ in reported })) { try await execute(f) }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped:true); #expect(ownAssertion(try assertions()))
            task!.cancel(); gate.release.signal(); var id:UUID?
            do { _=try await task!.value; Issue.record("Cancelled pin trial published") }
            catch let e as Operation.ReviewFailure {
                guard reported else { print("GENERATED_UNEXPECTED_ORDINARY_OWNING_METADATA_PIN_CANCEL_REVIEW " + f.root.path); throw e }
                #expect(reported && e.published == nil && e.removed == nil); id=e.reviewID
                let phase=try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure), fault=try #require(phase.operationError as? Reader.PinCloseFailure), n=try #require(fault.operationError as? Reader.NullCloseFailure), pipe=try #require(n.operationError as? Reader.PipeCloseFailure)
                #expect(Set(fault.roles) == Set(Reader.PinRole.allCases) && n.reportedAfterActualClose && pipe.operationError is CancellationError && Set(pipe.roles) == Set(Reader.PipeRole.allCases))
                witness.source=fault.sourcePin; witness.executable=fault.executablePin; witness.stage=Operation.retainedStageForTesting(e.reviewID)
            } catch { if error is any CompanionUnsettledOwnership { print("GENERATED_UNEXPECTED_OWNING_METADATA_PIN_CANCEL_REVIEW " + f.root.path); throw error }; #expect(!reported && error is CancellationError) }
            task=nil; pins.expectPair(); null.expectOne(); pipes.expectAll(); ledger.expectJoined(count:2); #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            if reported {
                let review=try #require(id); ledger.expectRetained(); try expectRetainedMetadataPair(witness,review); #expect(witness.stage != nil)
                await #expect(throws:NativeExportError.self) { try await execute(f) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); try expectRetainedMetadataPair(witness,review); #expect(witness.stage != nil)
                Operation.isolateGeneratedMetadataPipeReviewForTesting(review); #expect(witness.source != nil && witness.executable != nil && witness.stage != nil); ledger.expectRetained()
                print("GENERATED_CANCELLED_OWNING_METADATA_PIN_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); #expect(!ownAssertion(try assertions())); f.cleanup() }
        }
    }
    @Test func actualReadOnlyCandidatePinRefusalRetainsPairWithoutAdoptionOrCleanup() async throws {
        typealias Reader=CompanionMetadataProcess
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly,.entireContainer] {
            let f=try await candidate(mode), ledger=Ledger(), pipes=MetadataPipeCloses(), null=MetadataNullClose(), pins=MetadataPinCloses(), witness=WeakMetadataPins(), original=try Data(contentsOf:f.source)
            var task:Task<CompanionDiskCheck.Receipt,Error>?=Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ _ in Issue.record("Candidate pin uncertainty released access") })) {
                        try await Reader.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },closed:{ pipes.add($0,$1,$2) },nullClosed:{ status,code in pipes.expectAll(); ledger.expectJoined(count:1); null.add(status,code) },pinClosed:{ role,status,code in null.expectOne(); ledger.expectJoined(count:1); pins.add(role,status,code) },refusePinClose:{ _ in true })) { try await review(f,mode:mode) }
                    }
                }
            }
            var id:UUID?
            do { _=try await task!.value; Issue.record("Uncertain candidate pair returned receipt") }
            catch let e as Operation.ReviewFailure {
                #expect(e.published == nil && e.removed == nil); id=e.reviewID; let fault=try #require(e.operationError as? Reader.PinCloseFailure)
                #expect(fault.operationError == nil && Set(fault.roles) == Set(Reader.PinRole.allCases)); witness.source=fault.sourcePin; witness.executable=fault.executablePin
            }
            task=nil; let reviewID=try #require(id); pins.expectPair(); null.expectOne(); pipes.expectAll(); ledger.expectJoined(count:1); ledger.expectRetained(); try expectRetainedMetadataPair(witness,reviewID)
            #expect(try Data(contentsOf:f.source) == original && FileManager.default.fileExists(atPath:f.stage.appendingPathComponent("manifest.json").path))
            await #expect(throws:NativeExportError.self) { try await review(f,mode:mode) }
            try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); try expectRetainedMetadataPair(witness,reviewID)
            Operation.isolateGeneratedMetadataPipeReviewForTesting(reviewID); #expect(witness.source != nil && witness.executable != nil); ledger.expectRetained()
            print("GENERATED_READ_ONLY_METADATA_PIN_REVIEW " + f.root.path)
        }
    }


    private func expectRetainedTerminalDirectory(_ witness: WeakDiskEnumerationOwner, _ id: UUID) throws {
        let directory = try #require(witness.directory)
        #expect(directory === Operation.retainedEnumerationDirectoryForTesting(id))
        #expect(directory.descriptorForTesting == -1 && directory.enumerationConsumedForTesting)
    }
    @Test func verifiedDirectoryTerminalClosePrecedesBothModeCommitAndRetainsSameOwner() async throws {
        typealias Disk = CompanionDiskCheck
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
          for point in ["normal", "reported", "source-priority"] {
            let f = try await fixture(), ledger = Ledger(), pipes = MetadataPipeCloses(), null = MetadataNullClose(), pins = MetadataPinCloses(), names = DiskEnumerationCloses(), close = AdmissionDirectoryClose(), witness = WeakDiskEnumerationOwner(), original = try Data(contentsOf:f.source), reported = point != "normal"
            var task: Task<ResultSetStaging.Published,Error>? = Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in #expect(!reported); close.expect(1); ledger.closed(count) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },closed:{ pipes.add($0,$1,$2) },nullClosed:{ null.add($0,$1) },pinClosed:{ pins.add($0,$1,$2) })) {
                                try await Disk.$testBoundary.withValue(.init(beforeDirectoryTerminal:{ directory in
                                    ledger.expectJoined(count:2); ledger.expectActive(scoped:true); pipes.expectAll(); null.expectOne(); pins.expectPair(); names.expect(["initial/stream","final/stream"])
                                    var info = stat(); #expect(fstat(directory.descriptorForTesting,&info) == 0)
                                },directoryTerminalClosed:{ close.add($0,$1) },refuseDirectoryTerminalClose:{ reported },enumerationClosed:{ names.add($0,$1,$2,$3) })) {
                                    try await OriginalCompanionTransaction.$sourceBoundary.withValue(.init(refuseClose:{ point == "source-priority" })) {
                                        try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit:{ #expect(!reported); close.expect(1) })) { try await execute(f,mode:mode) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            var id:UUID?
            do { _ = try await task!.value; #expect(!reported) }
            catch let e as Operation.ReviewFailure {
                guard reported else { print("GENERATED_UNEXPECTED_DIRECTORY_TERMINAL_REVIEW " + f.root.path); throw e }
                id=e.reviewID; #expect(e.published == nil && e.removed == nil)
                let cause:any Error
                if point == "source-priority" { cause=(try #require(e.operationError as? OriginalCompanionTransaction.SourceSettlementFailure)).operationError }
                else { cause=(try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure)).operationError }
                let fault=try #require(cause as? Disk.DirectoryTerminalFailure)
                #expect(fault.operationError == nil && fault.closeStatus == 0 && fault.closeErrno == 0 && fault.reportedAfterActualClose)
                witness.directory=fault.directory; witness.stage=Operation.retainedStageForTesting(e.reviewID)
            }
            task=nil; close.expect(1); ledger.expectJoined(count:2); #expect(try Data(contentsOf:f.source) == original)
            if reported {
                let reviewID=try #require(id); try expectRetainedTerminalDirectory(witness,reviewID); ledger.expectRetained(); #expect(witness.stage != nil && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
                await #expect(throws:NativeExportError.self) { try await execute(f,mode:mode) }
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); try expectRetainedTerminalDirectory(witness,reviewID)
                Operation.isolateGeneratedEnumerationReviewForTesting(reviewID); #expect(witness.directory != nil && witness.stage != nil); ledger.expectRetained()
                print("GENERATED_DIRECTORY_TERMINAL_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); f.cleanup() }
          }
        }
    }
    @Test func verifiedDirectoryLateCancellationChecksCloseBeforeReleaseOrRetainedReview() async throws {
        for reported in [false,true] {
            let f=try await fixture(), ledger=Ledger(), close=AdmissionDirectoryClose(), gate=Gate(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
            var task:Task<ResultSetStaging.Published,Error>?=Task {
                defer { gate.signal.finish() }
                return try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in #expect(!reported); close.expect(1); ledger.closed(count) })) {
                        try await CompanionWriterProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                                try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeDirectoryTerminal:{ _ in ledger.expectJoined(count:2); gate.hold() },directoryTerminalClosed:{ close.add($0,$1) },refuseDirectoryTerminalClose:{ reported })) { try await execute(f) }
                            }
                        }
                    }
                }
            }
            for await _ in gate.entered { break }; ledger.expectActive(scoped:true); #expect(ownAssertion(try assertions()))
            task!.cancel(); gate.release.signal(); var id:UUID?
            do { _=try await task!.value; Issue.record("Cancelled directory terminal published") }
            catch let e as Operation.ReviewFailure {
                guard reported else { print("GENERATED_UNEXPECTED_DIRECTORY_CANCEL_REVIEW " + f.root.path); throw e }
                id=e.reviewID; let phase=try #require(e.operationError as? OriginalCompanionTransaction.UnsettledPhaseFailure), fault=try #require(phase.operationError as? CompanionDiskCheck.DirectoryTerminalFailure)
                #expect(fault.operationError is CancellationError && fault.reportedAfterActualClose && e.published == nil && e.removed == nil)
                witness.directory=fault.directory; witness.stage=Operation.retainedStageForTesting(e.reviewID)
            } catch { if error is any CompanionUnsettledOwnership { print("GENERATED_UNEXPECTED_DIRECTORY_CANCEL_OWNERSHIP " + f.root.path); throw error }; #expect(!reported && error is CancellationError) }
            task=nil; close.expect(1); ledger.expectJoined(count:2); #expect(try Data(contentsOf:f.source) == original && !FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
            if reported {
                let reviewID=try #require(id); try expectRetainedTerminalDirectory(witness,reviewID); ledger.expectRetained()
                try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); try expectRetainedTerminalDirectory(witness,reviewID)
                Operation.isolateGeneratedEnumerationReviewForTesting(reviewID); #expect(witness.directory != nil && witness.stage != nil); print("GENERATED_DIRECTORY_CANCEL_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); #expect(!ownAssertion(try assertions())); f.cleanup() }
        }
    }
    @Test func candidateDirectoryTerminalReportRetainsDirectOwnerAndEarlierEnumerationNeverRetires() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly,.entireContainer] {
          for earlier in [false,true] {
            let f=try await candidate(mode), ledger=Ledger(), close=AdmissionDirectoryClose(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
            var task:Task<CompanionDiskCheck.Receipt,Error>?=Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ _ in Issue.record("Candidate uncertainty released access") })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeDirectoryTerminal:{ _ in #expect(!earlier); ledger.expectJoined(count:1) },directoryTerminalClosed:{ close.add($0,$1) },refuseDirectoryTerminalClose:{ true },refuseEnumerationClose:{ pass,_ in earlier && pass == .final })) { try await review(f,mode:mode) }
                        }
                    }
                }
            }
            var id:UUID?
            do { _=try await task!.value; Issue.record("Candidate uncertainty returned receipt") }
            catch let e as Operation.ReviewFailure {
                id=e.reviewID; #expect(e.published == nil && e.removed == nil)
                if earlier { witness.directory=(try #require(e.operationError as? CompanionDiskCheck.EnumerationCloseFailure)).directory }
                else { witness.directory=(try #require(e.operationError as? CompanionDiskCheck.DirectoryTerminalFailure)).directory }
            }
            task=nil; let reviewID=try #require(id); close.expect(earlier ? 0:1); ledger.expectJoined(count:1); ledger.expectRetained()
            if earlier { let directory=try #require(witness.directory); #expect(directory === Operation.retainedEnumerationDirectoryForTesting(reviewID)); var info=stat(); #expect(fstat(directory.descriptorForTesting,&info) == 0) }
            else { try expectRetainedTerminalDirectory(witness,reviewID) }
            #expect(try Data(contentsOf:f.source) == original && FileManager.default.fileExists(atPath:f.stage.appendingPathComponent("manifest.json").path))
            await #expect(throws:NativeExportError.self) { try await review(f,mode:mode) }
            try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained(); #expect(witness.directory != nil)
            Operation.isolateGeneratedEnumerationReviewForTesting(reviewID); #expect(witness.directory != nil); print("GENERATED_CANDIDATE_DIRECTORY_REVIEW " + f.root.path)
          }
        }
    }


    @Test func earlierVerifierRefusalsNeverEnterDirectoryTerminalRetirement() async throws {
        for point in ["admission", "admission-report", "initial-enumeration", "metadata-pin", "final-source"] {
            let f=try await candidate(), ledger=Ledger(), close=AdmissionDirectoryClose(), witness=WeakDiskEnumerationOwner(), original=try Data(contentsOf:f.source)
            let uncertain=["admission-report","initial-enumeration","metadata-pin","final-source"].contains(point)
            var task:Task<CompanionDiskCheck.Receipt,Error>?=Task {
                try await Operation.$testEnvironment.withValue(environment(ledger,fakeScopes:true)) {
                    try await Operation.$testBoundary.withValue(.init(pinned:{ ledger.pinned($0) },archiveClosed:{ count in #expect(!uncertain); ledger.closed(count) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ ledger.launch($0) },settled:{ ledger.join($0) },refusePinClose:{ _ in point == "metadata-pin" })) {
                            try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{
                                if point == "final-source" {
                                    do { let old=f.root.appendingPathComponent("previous-source"); try FileManager.default.moveItem(at:f.source,to:old); try original.write(to:f.source) }
                                    catch { Issue.record("Generated source replacement failed") }
                                }
                            },directoryAdmissionOpened:{ _ in if point.hasPrefix("admission") { throw CancellationError() } },beforeDirectoryTerminal:{ _ in Issue.record("Earlier refusal entered terminal retirement") },directoryTerminalClosed:{ close.add($0,$1) },refuseDirectoryAdmissionClose:{ point == "admission-report" },refuseEnumerationClose:{ pass,_ in point == "initial-enumeration" && pass == .initial })) { try await review(f) }
                        }
                    }
                }
            }
            var id:UUID?
            do { _=try await task!.value; Issue.record("Earlier verifier refusal returned receipt") }
            catch let e as Operation.ReviewFailure {
                guard uncertain else { print("GENERATED_UNEXPECTED_EARLIER_DIRECTORY_REVIEW " + f.root.path); throw e }
                id=e.reviewID
                if point == "admission-report" { let fault=try #require(e.operationError as? CompanionDiskCheck.DirectoryAdmissionFailure); witness.directory=fault.directory; #expect(fault.operationError is CancellationError && fault.reportedAfterActualClose && fault.closeStatus == 0) }
                else if point == "initial-enumeration" { let fault=try #require(e.operationError as? CompanionDiskCheck.EnumerationCloseFailure); witness.directory=fault.directory; #expect(fault.pass == .initial && fault.reportedAfterActualClose) }
                else if point == "metadata-pin" { #expect(e.operationError is CompanionMetadataProcess.PinCloseFailure) }
                else { #expect(point == "final-source" && e.operationError is NativeExportError) }
            } catch { if error is any CompanionUnsettledOwnership { print("GENERATED_UNEXPECTED_EARLIER_DIRECTORY_OWNERSHIP " + f.root.path); throw error }; #expect(point == "admission" && error is CancellationError) }
            task=nil; close.expect(0); ledger.expectJoined(count:["metadata-pin","final-source"].contains(point) ? 1:0); #expect(try Data(contentsOf:f.source) == original)
            if uncertain {
                let reviewID=try #require(id); ledger.expectRetained(); try await Task.sleep(for:.milliseconds(100)); ledger.expectEnded(); ledger.expectRetained()
                if point == "initial-enumeration" { let directory=try #require(witness.directory); #expect(directory === Operation.retainedEnumerationDirectoryForTesting(reviewID)); var info=stat(); #expect(fstat(directory.descriptorForTesting,&info) == 0) }
                Operation.isolateGeneratedMetadataPipeReviewForTesting(reviewID); ledger.expectRetained(); print("GENERATED_EARLIER_DIRECTORY_REVIEW " + f.root.path)
            } else { ledger.expectClosed(); ledger.expectEnded(scoped:true); f.cleanup() }
        }
    }

}
