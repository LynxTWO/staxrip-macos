import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionCandidateReviewTests {
    typealias Fixture = CompanionOriginalMetadataCheckTests.Fixture
    typealias T = OriginalCompanionTransaction
    private func staged(_ mode: T.Retention = .metadataOnly) async throws -> Fixture {
        let f = try await CompanionOriginalMetadataCheckTests.fixture()
        do { _ = try await CompanionWriterProcess.run(tool: f.tool, source: f.source, stage: f.stage, retention: mode); return f }
        catch { f.cleanup(); throw error }
    }
    private func snapshot(_ url: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: url.path).map {
            ($0, try Data(contentsOf: url.appendingPathComponent($0)))
        })
    }
    private func review(_ f: Fixture, _ mode: T.Retention = .metadataOnly) async throws -> CompanionDiskCheck.Receipt {
        try await CompanionDiskCheck.reviewOriginalCandidate(source: f.source, candidate: f.stage, retention: mode, tool: f.readerTool)
    }
    private func manifest(_ f: Fixture) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: f.stage.appendingPathComponent("manifest.json"))) as? [String: Any])
    }
    private func writeManifest(_ m: [String: Any], _ f: Fixture) throws {
        try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]).write(to: f.stage.appendingPathComponent("manifest.json"))
    }
    @Test func actualReceiptlessBothModesMatchSourceWithoutModifyingCandidates() async throws {
        for mode in [T.Retention.metadataOnly, .entireContainer] {
            let f = try await staged(mode); defer { f.cleanup() }
            let source = try Data(contentsOf: f.source), candidate = try snapshot(f.stage)
            let r = try await review(f, mode), metadata = try #require(r.originalMetadata)
            #expect(r.originalMetadataSemanticsVerified && metadata.originalComponentsMatchSource && metadata.originalPacketRPUSemanticsVerified)
            #expect(r.contents.packets == 4 && r.contents.records == 5 && r.contents.enhancementNALs == 1)
            #expect(r.contents.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data: source)))
            #expect(r.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
            #expect(!metadata.immutableSnapshot && !metadata.stableImporter && !metadata.persistedProducerBinding && metadata.decodedFrameAssociation == "not-established")
            #expect(try snapshot(f.stage) == candidate && Data(contentsOf: f.source) == source)
        }
    }
    @Test func untrustedManifestCountsSchemaPathsAndHashesCannotAdmitCandidate() async throws {
        let f = try await staged(); defer { f.cleanup() }
        let base = try manifest(f), original = try Data(contentsOf: f.source)
        let forgeries: [(String, Any)] = [
            ("packets", 3), ("records", 4), ("enhancement_nals", 0), ("packets", true), ("packets", -1),
            ("packets", 2_000_001), ("records", NSNull()), ("records", 1.5), ("enhancement_nals", "1"),
            ("source_bytes", 1), ("source_sha256", String(repeating: "0", count: 64)), ("version", 1),
            ("retention", "entire-original-container"), ("track_payload_original_offset", 0),
            ("source_path_identity_bound", true), ("metadata_rewritten", true), ("decoded_frame_association", "verified"),
            ("untrusted_path", "/generated-untrusted-path"), ("components", [])]
        for (key, value) in forgeries {
            var changed = base; changed[key] = value; try writeManifest(changed, f)
            let before = try snapshot(f.stage)
            await #expect(throws: (any Error).self) { try await review(f) }
            #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
        }
        try writeManifest(base, f)
        for data in [Data("{\"packets\":4,\"packets\":4}".utf8), Data("{}".utf8), Data("{\"packets\":4".utf8), Data(repeating: 0x20, count: (1 << 20) + 1)] {
            try data.write(to: f.stage.appendingPathComponent("manifest.json")); let before = try snapshot(f.stage)
            await #expect(throws: (any Error).self) { try await review(f) }
            #expect(try snapshot(f.stage) == before)
        }
        #expect(try Data(contentsOf: f.source) == original)
    }
    @Test func repairedPlausibleMetadataForgeryRequiresFreshJoinedReaderRefusal() async throws {
        let f = try await staged(); defer { f.cleanup() }
        let audit = f.stage.appendingPathComponent("source-audit.jsonl")
        var rows = try Data(contentsOf: audit).split(separator: 10).map { try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
        let i = try #require(rows.firstIndex { $0["kind"] as? String == "rpu-summary" })
        var summary = try #require(rows[i]["summary"] as? [String: Any]); summary["cmv29_present"] = !(try #require(summary["cmv29_present"] as? Bool)); rows[i]["summary"] = summary
        var data = Data(); for row in rows { data.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])); data.append(10) }; try data.write(to: audit)
        var m = try manifest(f), components = try #require(m["components"] as? [[String: Any]])
        let member = try #require(components.firstIndex { $0["name"] as? String == "source-audit.jsonl" })
        components[member]["bytes"] = data.count; components[member]["sha256"] = DolbyInspection.hex(SHA256.hash(data: data)); m["components"] = components; try writeManifest(m, f)
        let state = State(), before = try snapshot(f.stage), original = try Data(contentsOf: f.source)
        await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) })) {
            await #expect(throws: NativeExportError.self) { try await review(f) }
        }
        state.assertJoined()
        #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
    }
    @Test func missingExtraUnsafeMembersAndExplicitWrongRetentionRefuseReadOnly() async throws {
        let f = try await staged(); defer { f.cleanup() }; let original = try Data(contentsOf: f.source)
        await #expect(throws: (any Error).self) { try await review(f, .entireContainer) }
        let raw = f.stage.appendingPathComponent("original-rpu.bin"), held = f.root.appendingPathComponent("held")
        try FileManager.default.moveItem(at: raw, to: held)
        await #expect(throws: (any Error).self) { try await review(f) }
        try FileManager.default.createSymbolicLink(at: raw, withDestinationURL: held)
        await #expect(throws: (any Error).self) { try await review(f) }
        try FileManager.default.removeItem(at: raw); try FileManager.default.linkItem(at: held, to: raw)
        await #expect(throws: (any Error).self) { try await review(f) }
        try FileManager.default.removeItem(at: raw); try FileManager.default.moveItem(at: held, to: raw)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: raw.path)
        await #expect(throws: (any Error).self) { try await review(f) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: raw.path)
        let extra = f.stage.appendingPathComponent("extra"); try Data([1]).write(to: extra)
        await #expect(throws: (any Error).self) { try await review(f) }
        #expect(try Data(contentsOf: extra) == Data([1]) && Data(contentsOf: f.source) == original)
        try FileManager.default.removeItem(at: extra)
        #expect(try await review(f).originalMetadataSemanticsVerified)
    }
    @Test(arguments: ["source", "stage", "manifest.json"])
    func finalPinnedMutationRefusesAfterActualMetadataMatch(name: String) async throws {
        let f = try await staged(); defer { f.cleanup() }
        await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
            do {
                if name == "stage" {
                    try FileManager.default.moveItem(at: f.stage, to: f.root.appendingPathComponent("moved"))
                    try FileManager.default.createDirectory(at: f.stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                } else {
                    let file = try FileHandle(forWritingTo: name == "source" ? f.source : f.stage.appendingPathComponent(name))
                    try file.write(contentsOf: Data([0xfe])); try file.close()
                }
            } catch { Issue.record("Generated final mutation failed") }
        })) { await #expect(throws: (any Error).self) { try await review(f) } }
    }
    @Test func cancelledActualFreshReadSettlesOrReportsTypedOwnershipWithoutCandidateCleanup() async throws {
        let f = try await staged(); var retain = false
        defer { if retain { print("GENERATED_CANDIDATE_OWNERSHIP_REVIEW " + f.root.path) } else { f.cleanup() } }
        let reader = try f.readerTool, state = State(), gate = Gate()
        let original = try Data(contentsOf: f.source), before = try snapshot(f.stage)
        let task = Task {
            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { state.launch($0) }, settled: { state.settle($0) })) {
                try await CompanionDiskCheck.$testBoundary.withValue(.init(originalComponentRead: { name, _, _ in
                    if name == "source-audit.jsonl" && state.hasLaunched { gate.hold() }
                })) { try await CompanionDiskCheck.reviewOriginalCandidate(source: f.source, candidate: f.stage, retention: .metadataOnly, tool: reader) }
            }
        }
        for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
        do { _ = try await task.value; Issue.record("Cancelled candidate review returned success") }
        catch is CancellationError {}
        catch let error as CompanionMetadataProcess.OwnershipFailure {
            retain = true
            #expect(error.reason == "group-1-joined-true")
        }
        catch { Issue.record("Unexpected candidate cancellation refusal") }
        state.assertJoined(); #expect(try snapshot(f.stage) == before && Data(contentsOf: f.source) == original)
    }
    private final class State: @unchecked Sendable {
        private let lock = NSLock(); private var child: pid_t = 0, joined: pid_t = 0
        var hasLaunched: Bool { lock.withLock { child > 0 } }
        func launch(_ p: pid_t) { lock.withLock { child = p } }
        func settle(_ p: pid_t) { lock.withLock { joined = p } }
        func assertJoined() {
            let p = lock.withLock { (child, joined) }; #expect(p.0 > 0 && p.0 == p.1)
            var status: Int32 = 0; #expect(waitpid(p.0, &status, WNOHANG) == -1 && errno == ECHILD)
        }
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>, release = DispatchSemaphore(value: 0)
        private let next: AsyncStream<Void>.Continuation, lock = NSLock(); private var used = false
        init() { var c: AsyncStream<Void>.Continuation!; entered = AsyncStream { c = $0 }; next = c }
        func hold() {
            if lock.withLock({ if used { return false }; used = true; return true }) { next.yield(()); release.wait(); next.finish() }
        }
    }
}
