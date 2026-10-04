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
    private func ownAssertion(_ text: String, reason: String = "StaxRip original companion preservation") -> Bool {
        text.split(separator: "\n").contains { $0.contains("pid \(getpid())(") && $0.contains("PreventUserIdleSystemSleep") && $0.contains(reason) }
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
                try await Operation.$testBoundary.withValue(.init(phase: { phase in #expect(phase == "reviewer"); ledger.expectActive(scoped: true) }, pinned: { ledger.pinned($0) })) {
                    try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await review(f, mode: mode)
                    }
                }
            }
            #expect(requested == [f.source, f.stage] && stopped == [f.stage, f.source])
            #expect(result.originalMetadataSemanticsVerified && result.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
            ledger.expectJoined(count: 1); ledger.expectEnded(scoped: true)
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
            await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                    await #expect(throws: NativeExportError.self) { try await review(f) }
                }
            }
        }
        ledger.expectJoined(count: 1); ledger.expectEnded(scoped: true)
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
        let b = try await HardenedReaderBundleFixture.make(targetName: "native-relocated-access-bundle-fixtures"); defer { b.cleanup() }
        let original = try Data(contentsOf: b.original.source), (writer, reader) = try b.admit()
        let prior = b.original.root.appendingPathComponent("prior-output"), priorBytes = Data("Generated prior output".utf8)
        try priorBytes.write(to: prior)
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let ledger = Ledger()
            let result = try await Operation.$testEnvironment.withValue(environment(ledger, fakeScopes: false)) {
                try await Operation.$testBoundary.withValue(.init(pinned: { ledger.pinned($0) })) {
                    try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                        try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { ledger.launch($0) }, settled: { ledger.join($0) })) {
                            try await Operation.execute(source: b.original.source, in: b.original.root,
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
        let b = try await HardenedReaderBundleFixture.make(targetName: "native-relocated-access-bundle-fixtures"); var keep = false
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
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let generated = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["STAXRIP_GENERATED_DOLBY_REFERENCE_DIRECTORY=" + root.path, "cargo", "test", "--locked", "--target-dir", repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/owned-NativeFrameAccessTests").path, "--manifest-path", repo.appendingPathComponent("Tools/DolbyMetadataAudit/Cargo.toml").path, "actual_hevc_packets_and_rpu_association_match_independent_ffprobe"])
        try #require(generated.status == 0)
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

}
