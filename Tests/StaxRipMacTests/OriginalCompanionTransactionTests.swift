import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

private typealias Transaction = OriginalCompanionTransaction
struct OriginalCompanionTransactionTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("original-companion-native-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func source(_ root: URL) throws -> URL {
        let source = root.appendingPathComponent("generated-source.bin")
        try Data("generated source only".utf8).write(to: source)
        return source
    }
    private func id(_ url: URL) throws -> Transaction.FileID {
        var info = stat(); try #require(lstat(url.path, &info) == 0)
        return Transaction.FileID(info)
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func synthetic(_ source: URL, _ stage: URL, _ mode: Transaction.Retention) throws -> Transaction.Contents {
        // Opaque phase fixtures model sequencing only; no Dolby semantic claim.
        let members = try mode.limits.keys.sorted().map { name in
            let data = Data(("opaque generated " + name).utf8)
            try data.write(to: stage.appendingPathComponent(name), options: .withoutOverwriting)
            return ResultSetStaging.Member(name: name, byteCount: Int64(data.count), sha256: digest(data))
        }
        let data = try Data(contentsOf: source)
        return .init(retention: mode, sourceID: try id(source), stageID: try id(stage), sourceBytes: Int64(data.count),
                     sourceSHA256: digest(data), packets: 1, records: 2, enhancementNALs: 1, members: members)
    }
    private func verified(_ c: Transaction.Contents) -> Transaction.Verification {
        .init(contents: c, originalComponentsMatchSource: true, sourceIdentityChecked: true,
              decodedFrameAssociation: "not-established", immutableSnapshot: false, stableImporter: false)
    }
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        private var url: URL?
        private var calls = 0
        func set(_ url: URL) { lock.withLock { self.url = url } }
        var value: URL? { lock.withLock { url } }
        func called() { lock.withLock { calls += 1 } }
        var count: Int { lock.withLock { calls } }
    }
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        let entered: AsyncStream<Bool>
        private let signal: AsyncStream<Bool>.Continuation
        init() {
            let pair = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
            entered = pair.stream; signal = pair.continuation
        }
        func pause() async {
            await withCheckedContinuation { c in
                lock.withLock { continuation = c }; signal.yield(true)
                DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
                    guard let self else { return }
                    let expired = self.lock.withLock { () -> CheckedContinuation<Void, Never>? in
                        let waiting = self.continuation; self.continuation = nil; return waiting
                    }
                    if let expired { Issue.record("Generated phase gate was not released"); expired.resume(); self.signal.finish() }
                }
            } // Deliberately ignores cancellation until its owned phase settles.
        }
        func release() { lock.withLock { continuation?.resume(); continuation = nil }; signal.finish() }
    }

    private final class CommitGate: @unchecked Sendable {
        let release = DispatchSemaphore(value: 0)
        let entered: AsyncStream<Bool>
        private let signal: AsyncStream<Bool>.Continuation
        init() {
            let pair = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
            entered = pair.stream; signal = pair.continuation
        }
        func hold() {
            signal.yield(true); signal.finish()
            if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated commit gate was not released") }
        }
    }
    private func remains(_ root: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
    }

    @Test(arguments: ["writer", "verifier"])
    func unsettledOwnershipRetainsStageForReview(phase: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), box = Box(), before = try Data(contentsOf: src)
        do {
            _ = try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                produce: { directory in
                    box.set(directory); let c = try synthetic(src, directory, .metadataOnly)
                    if phase == "writer" { throw CompanionWriterProcess.OwnershipFailure() }; return c
                }, verify: { _, _ in throw CompanionWriterProcess.OwnershipFailure() })
            Issue.record("Unsettled ownership unexpectedly published")
        } catch let error as Transaction.UnsettledPhaseFailure {
            #expect(error.operationError is CompanionWriterProcess.OwnershipFailure)
            #expect(error.intendedStage == box.value)
            #expect(FileManager.default.fileExists(atPath: error.intendedStage.appendingPathComponent("manifest.json").path))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("result").path))
        #expect(try Data(contentsOf: src) == before)
    }

    @Test func unsettledGeneratedWorkerRetainsStageUntilExplicitJoin() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), box = Box(), gate = Gate()
        let worker = Task { await gate.pause() }
        for await _ in gate.entered { break }
        do {
            _ = try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                produce: { directory in
                    box.set(directory); _ = try synthetic(src, directory, .metadataOnly)
                    // Explicit unsettled ownership fault; not an OS signal-denial claim.
                    throw CompanionWriterProcess.OwnershipFailure()
                }, verify: { _, c in verified(c) })
            Issue.record("Unsettled generated worker unexpectedly published")
        } catch let error as Transaction.UnsettledPhaseFailure {
            #expect(error.intendedStage == box.value)
            #expect(FileManager.default.fileExists(atPath: error.intendedStage.appendingPathComponent("manifest.json").path))
        } catch { gate.release(); await worker.value; throw error }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("result").path))
        gate.release(); await worker.value // Test caller joins before any root cleanup.
    }

    @Test func writerAndVerifierFailuresSettleBeforeOwnedCleanup() async throws {
        for phase in ["writer", "verifier"] {
            let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
            let src = try source(root), before = try Data(contentsOf: src)
            await #expect(throws: (any Error).self) {
                try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly, produce: { directory in
                    let c = try synthetic(src, directory, .metadataOnly)
                    if phase == "writer" { throw NativeExportError.invalid("generated writer failure") }
                    return c
                }, verify: { _, _ in throw NativeExportError.invalid("generated verifier failure") })
            }
            #expect(try remains(root) == [src.lastPathComponent])
            #expect(try Data(contentsOf: src) == before)
        }
    }
    @Test(arguments: ["count", "source", "members", "flags", "hash"])
    func mismatchedSemanticReceiptCannotPublish(change: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root)
        await #expect(throws: (any Error).self) {
            try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                produce: { try synthetic(src, $0, .metadataOnly) }, verify: { _, c in
                    let changed = Transaction.Contents(retention: c.retention,
                        sourceID: change == "source" ? .init(device: 0, inode: 0) : c.sourceID, stageID: c.stageID,
                        sourceBytes: c.sourceBytes, sourceSHA256: change == "hash" ? String(repeating: "a", count: 64) : c.sourceSHA256,
                        packets: change == "count" ? 2 : c.packets, records: c.records, enhancementNALs: c.enhancementNALs,
                        members: change == "members" ? Array(c.members.dropLast()) : c.members)
                    return .init(contents: changed, originalComponentsMatchSource: change != "flags", sourceIdentityChecked: true,
                                 decodedFrameAssociation: "not-established", immutableSnapshot: false, stableImporter: false)
                })
        }
        #expect(try remains(root) == [src.lastPathComponent])
    }
    @Test func invalidDestinationAndExistingResultRefuseBeforeWriter() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), box = Box(), existing = root.appendingPathComponent("result")
        try Data("keep".utf8).write(to: existing)
        for name in ["../outside", "result"] {
            await #expect(throws: (any Error).self) {
                try await Transaction.execute(source: src, in: root, destinationName: name, retention: .metadataOnly,
                    produce: { directory in box.called(); return try synthetic(src, directory, .metadataOnly) }, verify: { _, c in verified(c) })
            }
        }
        #expect(box.count == 0)
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
    }
    @Test(arguments: ["write", "verify"])
    func cancellationWaitsForOwnedPhaseBeforeCleanup(phase: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), box = Box(), gate = Gate()
        let task = Task {
            try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                produce: { directory in
                    box.set(directory); let c = try synthetic(src, directory, .metadataOnly)
                    if phase == "write" { await gate.pause() }; return c
                }, verify: { _, c in
                    if phase == "verify" { await gate.pause() }; return verified(c)
                })
        }
        for await _ in gate.entered { break }
        let stage = try #require(box.value); task.cancel()
        #expect(FileManager.default.fileExists(atPath: stage.appendingPathComponent("manifest.json").path))
        gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try remains(root) == [src.lastPathComponent])
    }
    @Test func sourceChangeDuringPublicationIsCaughtAtPrecommit() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), original = try Data(contentsOf: src), box = Box()
        await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit: {
            try Data("changed generated source".utf8).write(to: src)
        })) {
            await #expect(throws: (any Error).self) {
                try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                    produce: { directory in box.set(directory); return try synthetic(src, directory, .metadataOnly) }, verify: { _, c in verified(c) })
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("result").path))
        #expect(try remains(root) == [src.lastPathComponent]); try original.write(to: src)
    }
    @Test func lateDestinationCollisionPreservesExistingBytes() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), destination = root.appendingPathComponent("result")
        await #expect(throws: (any Error).self) {
            try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                produce: { try synthetic(src, $0, .metadataOnly) }, verify: { _, c in
                    try Data("keep late result".utf8).write(to: destination, options: .withoutOverwriting); return verified(c)
                })
        }
        #expect(try Data(contentsOf: destination) == Data("keep late result".utf8))
        #expect(try remains(root) == [src.lastPathComponent, "result"])
    }
    @Test func substitutedStageCleanupErrorRetainsBothDirectories() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), box = Box(), moved = root.appendingPathComponent("moved-stage")
        do {
            _ = try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                produce: { directory in box.set(directory); return try synthetic(src, directory, .metadataOnly) }, verify: { directory, c in
                    try FileManager.default.moveItem(at: directory, to: moved)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                    try Data("keep replacement".utf8).write(to: directory.appendingPathComponent("keep")); return verified(c)
                })
            Issue.record("Substituted stage unexpectedly published")
        } catch let error as Transaction.CleanupFailure {
            #expect(error.intendedStage == box.value)
            #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("manifest.json").path))
            #expect(try Data(contentsOf: error.intendedStage.appendingPathComponent("keep")) == Data("keep replacement".utf8))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("result").path))
    }
    @Test func cancellationAfterCommitReportsPublishedResult() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), gate = CommitGate()
        let task = Task {
            try await ResultSetStaging.$testBoundary.withValue(.init(afterCommit: { gate.hold() })) {
                try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                    produce: { try synthetic(src, $0, .metadataOnly) }, verify: { _, c in verified(c) })
            }
        }
        for await _ in gate.entered { break }
        task.cancel(); gate.release.signal()
        let result = try await task.value
        #expect(task.isCancelled)
        #expect(result.memberCount == 6 && FileManager.default.fileExists(atPath: result.directory.path))
    }

    @Test(arguments: ["unsafe", "create", "writer", "verifier", "ownership"])
    func internalSourceCloseChecksRollbackAndRefusalWithoutRetry(path: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), box = Box(), closes = Box()
        if path == "unsafe" { try Data().write(to: src) }
        let original = try Data(contentsOf: src)
        let parent = path == "create" ? root.appendingPathComponent("missing-parent") : root
        do {
            _ = try await Transaction.$sourceBoundary.withValue(.init(closed: { closes.called(); #expect($0 == 1) }, refuseClose: { true })) {
                try await Transaction.execute(source: src, in: parent, destinationName: "result", retention: .metadataOnly,
                    produce: { directory in
                        box.set(directory)
                        let c = try synthetic(src, directory, .metadataOnly)
                        if path == "writer" { throw NativeExportError.invalid("Generated settled refusal") }
                        if path == "ownership" { throw CompanionWriterProcess.OwnershipFailure() }
                        return c
                    }, verify: { _, _ in throw NativeExportError.invalid("Generated settled verifier refusal") })
            }
            Issue.record("Reported internal source close uncertainty returned ordinary result")
        } catch let e as Transaction.SourceSettlementFailure {
            #expect(e.published == nil)
            #expect((e.closeError as? Transaction.SourceCloseFailure)?.reportedAfterActualClose == true)
            if path == "ownership" { #expect(e.operationError is CompanionWriterProcess.OwnershipFailure) }
            if let stage = box.value {
                #expect(e.intendedStage == stage)
                #expect(FileManager.default.fileExists(atPath: stage.appendingPathComponent("manifest.json").path))
            } else { #expect(e.intendedStage == parent) }
        } catch let e as Transaction.SourceCloseFailure {
            #expect(path == "unsafe" && e.reportedAfterActualClose)
        }
        #expect(closes.count == 1)
        #expect(try Data(contentsOf: src) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("result").path))
        // Known controlled report after real close; this test owns settled opaque
        // phases/root. No spontaneous OS fault or production cleanup claim.
    }

    @Test(arguments: ["unsafe", "create", "writer", "verifier"])
    func ordinaryInternalSourceRollbackClosesBeforeOwnedCleanup(path: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), closes = Box()
        if path == "unsafe" { try Data().write(to: src) }
        let parent = path == "create" ? root.appendingPathComponent("missing-parent") : root
        do {
            _ = try await Transaction.$sourceBoundary.withValue(.init(closed: { closes.called(); #expect($0 == 1) })) {
                try await Transaction.execute(source: src, in: parent, destinationName: "result", retention: .metadataOnly,
                    produce: { directory in
                        let c = try synthetic(src, directory, .metadataOnly)
                        if path == "writer" { throw NativeExportError.invalid("Generated settled refusal") }
                        return c
                    }, verify: { _, _ in throw NativeExportError.invalid("Generated settled verifier refusal") })
            }
            Issue.record("Generated refusal returned success")
        } catch {
            #expect(!(error is any CompanionUnsettledOwnership))
        }
        #expect(closes.count == 1)
        #expect(try remains(root) == [src.lastPathComponent])
    }

    @Test func cancelledSettledPhaseInternalCloseRefusalRetainsStage() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let src = try source(root), box = Box(), closes = Box(), gate = Gate()
        let task = Task {
            try await Transaction.$sourceBoundary.withValue(.init(closed: { _ in closes.called() }, refuseClose: { true })) {
                try await Transaction.execute(source: src, in: root, destinationName: "result", retention: .metadataOnly,
                    produce: { directory in
                        box.set(directory); let c = try synthetic(src, directory, .metadataOnly)
                        await gate.pause(); return c
                    }, verify: { _, c in verified(c) })
            }
        }
        for await _ in gate.entered { break }
        task.cancel(); gate.release()
        do { _ = try await task.value; Issue.record("Cancelled close uncertainty succeeded") }
        catch let e as Transaction.SourceSettlementFailure {
            #expect(e.operationError is CancellationError && e.published == nil && e.intendedStage == box.value)
            #expect(FileManager.default.fileExists(atPath: e.intendedStage.appendingPathComponent("manifest.json").path))
        }
        #expect(closes.count == 1)
    }

    private struct Wire: Decodable {
        struct Member: Decodable { let name: String; let bytes: Int64; let sha256: String }
        let retention: String
        let source_file_id, stage_file_id: [UInt64]
        let source_bytes: Int64
        let source_sha256: String
        let packets, records, enhancement_nals: Int64
        let components: [Member]
        let original_components_match_source, source_identity_checked_at_boundaries: Bool?
        let decoded_frame_association: String?
        let immutable_snapshot, stable_importer: Bool?
        func contents() throws -> Transaction.Contents {
            try #require(source_file_id.count == 2 && stage_file_id.count == 2)
            let mode: Transaction.Retention
            switch retention {
            case "metadata", "rpu-and-original-track-metadata-only": mode = .metadataOnly
            case "full", "entire-original-container": mode = .entireContainer
            default: throw NativeExportError.invalid("Unknown generated retention")
            }
            return .init(retention: mode,
                         sourceID: .init(device: source_file_id[0], inode: source_file_id[1]),
                         stageID: .init(device: stage_file_id[0], inode: stage_file_id[1]),
                         sourceBytes: source_bytes, sourceSHA256: source_sha256, packets: packets,
                         records: records, enhancementNALs: enhancement_nals,
                         members: components.map { .init(name: $0.name, byteCount: $0.bytes, sha256: $0.sha256) })
        }
    }
    @Test(.timeLimit(.minutes(2))) func actualGeneratedWriterSemanticVerificationAndNativePublicationBothModes() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let generated = root.appendingPathComponent("generated")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: false)
        let helpers = try await RustFixtureBuild.generate(.staged, at: generated, copiesIn: root)
        let src = generated.appendingPathComponent("generated-source.mkv"), original = try Data(contentsOf: src)
        let executable = helpers.writer
        let reader = helpers.reader
        let adapter = repo.appendingPathComponent("Tools/DolbyCompanionCheck/native_transaction_fixture.py")
        for (mode, name) in [(Transaction.Retention.metadataOnly, "metadata"), (.entireContainer, "full")] {
            let phase: @Sendable (String, URL) async throws -> Wire = { role, directory in
                let r = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                    "python3", adapter.path, role, src.path, directory.path, name, executable.path, reader.path], stdoutLimit: 16384)
                try #require(r.status == 0 && !r.truncated, "Generated actual phase refused")
                return try JSONDecoder().decode(Wire.self, from: r.stdout)
            }
            let result = try await Transaction.execute(source: src, in: root, destinationName: "result-" + name,
                retention: mode, produce: { try await phase("produce", $0).contents() }, verify: { directory, _ in
                    let r = try await phase("verify", directory)
                    return .init(contents: try r.contents(), originalComponentsMatchSource: try #require(r.original_components_match_source as Bool?),
                                 sourceIdentityChecked: try #require(r.source_identity_checked_at_boundaries as Bool?),
                                 decodedFrameAssociation: try #require(r.decoded_frame_association),
                                 immutableSnapshot: try #require(r.immutable_snapshot as Bool?), stableImporter: try #require(r.stable_importer as Bool?))
                })
            #expect(result.memberCount == (mode == .metadataOnly ? 6 : 7))
            #expect(try Data(contentsOf: src) == original)
            if mode == .entireContainer { #expect(try Data(contentsOf: result.directory.appendingPathComponent("original-container.mkv")) == original) }
            let index = try Data(contentsOf: result.directory.appendingPathComponent("rpu-index.jsonl"))
            let records = try index.split(separator: 10).map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
            #expect(records.count == 2 && records[0]["payload_sha256"] as? String == records[1]["payload_sha256"] as? String)
            #expect(records.allSatisfy { ($0["pts_ns"] as? Int64) == -10_000_000 })
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: result.directory.appendingPathComponent("manifest.json"))) as! [String: Any]
            #expect(manifest["source_path_identity_bound"] as? Bool == false)
        }
        #expect(try remains(root) == ["generated", "result-metadata", "result-full", "staxrip-dolby-companion-writer", "staxrip-dolby-metadata-audit"])
    }
}
