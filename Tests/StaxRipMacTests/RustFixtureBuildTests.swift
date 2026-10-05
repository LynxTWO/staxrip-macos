import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

struct RustFixtureBuildTests {
    private final class Counts: @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0, maximum = 0, acquired = 0, released = 0, preparations: [String] = []
        func enter() { lock.withLock { active += 1; acquired += 1; maximum = max(maximum, active) } }
        func leave() { lock.withLock { active -= 1; released += 1 } }
        func prepare(_ p: String) { lock.withLock { preparations.append(p) } }
        func check(_ n: Int) { lock.withLock { #expect(active == 0 && maximum == 1 && acquired == n && released == n); #expect(preparations == ["release", "tests"]) } }
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>
        private let signal: AsyncStream<Void>.Continuation
        private let lock = NSLock()
        private var waiter: CheckedContinuation<Void, Never>?, held = false
        init() { let p = AsyncStream<Void>.makeStream(); entered = p.stream; signal = p.continuation }
        var hasHeld: Bool { lock.withLock { held } }
        func holdOnce() async {
            guard lock.withLock({ if held { return false }; held = true; return true }) else { return }
            await withCheckedContinuation { c in
                lock.withLock { waiter = c }; signal.yield(()); signal.finish()
                DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                    let expired = self.lock.withLock { let value = self.waiter; self.waiter = nil; return value }
                    if let expired { Issue.record("Generated fixture copy gate expired"); expired.resume() }
                }
            }
        }
        func release() { lock.withLock { waiter?.resume(); waiter = nil }; signal.finish() }
    }
    private func folder(_ parent: URL, _ name: String) throws -> URL {
        let value = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return value
    }
    private func root() throws -> URL {
        try folder(FileManager.default.temporaryDirectory, "shared-rust-fixture-test-" + UUID().uuidString)
    }
    private func digest(_ file: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: file))) }
    private func reader(_ helpers: RustFixtureBuild.Helpers) throws -> CompanionMetadataProcess.Tool {
        try .development(helpers.reader, expectedSHA256: digest(helpers.reader))
    }

    @Test(.timeLimit(.minutes(2))) func concurrentGeneratedRequestsUseOnePreparedOwnerAndPrivateCopies() async throws {
        let cold = ProcessInfo.processInfo.environment["STAXRIP_TEST_COLD_FIXTURE_BUILD"] == "1"
        let root = try root(); defer { if cold { print("GENERATED_COLD_FIXTURE_BUILD " + root.path) } else { try? FileManager.default.removeItem(at: root) } }
        let target = cold ? root.appendingPathComponent("build") : RustFixtureBuild.repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/native-development-fixtures")
        if cold { #expect(!FileManager.default.fileExists(atPath: target.path)) }
        let counts = Counts(), coordinator = RustFixtureBuild.Coordinator(repo: RustFixtureBuild.repo, target: target,
            boundary: .init(acquired: { counts.enter() }, preparing: { counts.prepare($0) }, released: { counts.leave() }))
        let a = try folder(root, "staged"), b = try folder(root, "original"), c = try folder(root, "reference")
        let ga = try folder(a, "generated"), gb = try folder(b, "generated"), gc = try folder(c, "generated")
        async let ha = coordinator.generate(.staged, at: ga, copiesIn: a)
        async let hb = coordinator.generate(.original, at: gb, copiesIn: b)
        async let hc = coordinator.generate(.reference, at: gc, copiesIn: c)
        let helpers = try await [ha, hb, hc]
        counts.check(3)
        #expect(Set(helpers.map(\.writer)).count == 3 && Set(helpers.map(\.reader)).count == 3)
        let writerHashes = try helpers.map { try digest($0.writer) }, readerHashes = try helpers.map { try digest($0.reader) }
        #expect(Set(writerHashes).count == 1 && Set(readerHashes).count == 1)
        for (i, source) in [ga.appendingPathComponent("generated-source.mkv"), gb.appendingPathComponent("generated-source.mkv"), gc.appendingPathComponent("single.mkv")].enumerated() {
            let before = try Data(contentsOf: source)
            let result = try await CompanionMetadataProcess.run(tool: reader(helpers[i]), source: source)
            #expect(result.packets == (i == 0 ? 1 : 4) && result.records == (i == 0 ? 2 : i == 1 ? 5 : 4))
            #expect(try Data(contentsOf: source) == before)
        }
        // Private mutation never changes the shared release artifacts or other copies.
        let sharedHash = try digest(target.appendingPathComponent("release/staxrip-dolby-metadata-audit"))
        try Data("Generated private substitution".utf8).write(to: helpers[0].reader)
        #expect(try digest(helpers[1].reader) == readerHashes[1])
        #expect(try digest(target.appendingPathComponent("release/staxrip-dolby-metadata-audit")) == sharedHash)
        print("Shared fixture acquisition: cold=\(cold), three native generators, one preparation pair, exclusive private copies")
    }

    @Test(.timeLimit(.minutes(2))) func cancelledQueuedRequestAndCopyRefusalReleaseNativeLock() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(), counts = Counts()
        let waiting = AsyncStream<Void>.makeStream()
        let coordinator = RustFixtureBuild.Coordinator(repo: RustFixtureBuild.repo,
            target: RustFixtureBuild.repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/native-development-fixtures"),
            boundary: .init(acquired: { counts.enter() }, preparing: { counts.prepare($0) }, waiting: { waiting.continuation.yield(()) }, beforeCopy: { await gate.holdOnce() }, released: { counts.leave() }))
        let a = try folder(root, "first"), b = try folder(root, "cancelled"), c = try folder(root, "refused"), d = try folder(root, "last")
        let ga = try folder(a, "generated"), gb = try folder(b, "generated"), gc = try folder(c, "generated"), gd = try folder(d, "generated")
        let first = Task { do { return try await coordinator.generate(.staged, at: ga, copiesIn: a) } catch { gate.release(); throw error } }
        for await _ in gate.entered { break }
        guard gate.hasHeld else { _ = try await first.value; throw NativeExportError.invalid("Fixture copy gate never entered") }
        let queued = Task { try await coordinator.generate(.staged, at: gb, copiesIn: b) }
        for await _ in waiting.stream { break }
        waiting.continuation.finish()
        queued.cancel()
        do { _ = try await queued.value; Issue.record("Cancelled fixture request returned artifacts") }
        catch is CancellationError {}
        catch { gate.release(); _ = try await first.value; throw error }
        #expect(try FileManager.default.contentsOfDirectory(atPath: gb.path).isEmpty)
        gate.release(); let original = try await first.value, before = try digest(original.writer)
        let existing = c.appendingPathComponent("staxrip-dolby-companion-writer"), bytes = Data("Generated prior artifact".utf8)
        try bytes.write(to: existing)
        await #expect(throws: (any Error).self) { try await coordinator.generate(.staged, at: gc, copiesIn: c) }
        #expect(try Data(contentsOf: existing) == bytes)
        let last = try await coordinator.generate(.staged, at: gd, copiesIn: d)
        let lastHash = try digest(last.writer), originalHash = try digest(original.writer)
        #expect(lastHash == before && originalHash == before)
        counts.check(3) // Cancelled requester never enters the ownership interval.
    }
}
