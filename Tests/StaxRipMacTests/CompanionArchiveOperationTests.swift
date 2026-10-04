import Foundation
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
        func expectRetained() { lock.withLock { #expect(scopes == 2 && stopped == 0); checkPins() } }
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
        init() { let p = AsyncStream<Void>.makeStream(); entered = p.stream; signal = p.continuation }
        func hold() { signal.yield(()); signal.finish(); if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated access gate expired") } }
    }
    private func fixture() async throws -> Fixture {
        try await CompanionOriginalMetadataCheckTests.fixture(targetName: "native-companion-access-fixtures")
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
        try await Operation.execute(source: f.source, in: f.root, destinationName: "published", retention: mode, writer: f.tool, reader: f.readerTool)
    }
    private func assertions() throws -> String {
        let p = Process(), pipe = Pipe(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]; p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        try #require(p.terminationStatus == 0 && data.count < 1 << 20)
        return String(decoding: data, as: UTF8.self)
    }
    private func ownAssertion(_ text: String) -> Bool {
        text.split(separator: "\n").contains { $0.contains("pid \(getpid())(") && $0.contains("PreventUserIdleSystemSleep") && $0.contains("StaxRip original companion preservation") }
    }
    @Test func actualNativeBothModesHoldAccessActivityThroughJoinedPhasesAndExclusiveCommit() async throws {
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let f = try await fixture(); defer { f.cleanup() }
            let ledger = Ledger(), original = try Data(contentsOf: f.source)
            let result = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: false)) {
                try await Operation.$testBoundary.withValue(.init(phase: { _ in ledger.expectActive() }, pinned: { ledger.pinned($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit: { ledger.expectActive() }, afterCommit: { ledger.expectActive() })) {
                                try await execute(f, mode: mode)
                            }
                        }
                    }
                }
            }
            ledger.expectJoined(count: 2); ledger.expectEnded()
            #expect(!ownAssertion(try assertions()))
            #expect(try Data(contentsOf: f.source) == original)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: result.directory.path)) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf: result.directory.appendingPathComponent("original-container.mkv")) == original) }
            let prior = try Data(contentsOf: result.directory.appendingPathComponent("manifest.json"))
            await #expect(throws: (any Error).self) { try await execute(f, mode: mode) }
            #expect(try Data(contentsOf: result.directory.appendingPathComponent("manifest.json")) == prior)
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
                await #expect(throws: NativeExportError.self) { try await Operation.execute(source: source, in: parent, destinationName: "refused", retention: .metadataOnly, writer: writer, reader: reader) }
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
                try await Operation.execute(source: f.source, in: f.root, destinationName: "refused", retention: .metadataOnly, writer: writer, reader: reader)
            }
        }
        #expect(starts == 0 && ends == 0)
        try #require(chmod(f.source.path, sourceMode) == 0)
        await Operation.$testEnvironment.withValue(env) {
            await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { _ in Issue.record("Permission denial launched writer") })) {
                await #expect(throws: NativeExportError.self) {
                    try await Operation.execute(source: f.source, in: denied, destinationName: "refused", retention: .metadataOnly, writer: writer, reader: reader)
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
}
