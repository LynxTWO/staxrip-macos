import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionOriginalMetadataCheckTests {
    typealias Writer = CompanionWriterProcess
    typealias Transaction = OriginalCompanionTransaction
    private struct Fixture {
        let root, source, stage, executable, reader: URL
        var tool: Writer.Tool { get throws { try .development(executable, expectedSHA256: DolbyInspection.hex(SHA256.hash(data: Data(contentsOf: executable)))) } }
        var readerTool: CompanionMetadataProcess.Tool { get throws { try .development(reader, expectedSHA256: DolbyInspection.hex(SHA256.hash(data: Data(contentsOf:reader)))) } }
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
            // This serialized suite owns its feature-specific artifacts. Other suites
            // must not replace binaries between a successful Cargo build and copy.
            let buildTarget = repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/native-original-metadata-fixtures")
            let f = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "STAXRIP_GENERATED_COMPANION_FIXTURE_DIRECTORY=" + generated.path, "cargo", "test", "--locked",
                "--target-dir",buildTarget.path,"--manifest-path", cargo.path, "original_companions_preserve_raw_bytes_encoded_order_and_distinct_retention"])
            try #require(f.status == 0)
            let b = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "cargo", "build", "--release", "--locked", "--features", "development-companion-writer", "--bin",
                "staxrip-dolby-companion-writer", "--target-dir",buildTarget.path,"--manifest-path", cargo.path])
            try #require(b.status == 0)
            let executable = root.appendingPathComponent("staxrip-dolby-companion-writer")
            try FileManager.default.copyItem(at: buildTarget.appendingPathComponent("release/staxrip-dolby-companion-writer"), to: executable)
            let rb = try await ToolRunner().run(executable: URL(fileURLWithPath:"/usr/bin/env"), arguments:["cargo","build","--release","--locked","--features","development-companion-writer","--bin","staxrip-dolby-metadata-audit","--target-dir",buildTarget.path,"--manifest-path",cargo.path])
            try #require(rb.status == 0)
            let reader = root.appendingPathComponent("staxrip-dolby-metadata-audit")
            try FileManager.default.copyItem(at: buildTarget.appendingPathComponent("release/staxrip-dolby-metadata-audit"),to:reader)
            let stage = root.appendingPathComponent("stage")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return .init(root: root, source: generated.appendingPathComponent("generated-source.mkv"), stage: stage, executable: executable, reader: reader)
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }

    private func staged(_ mode: Transaction.Retention = .metadataOnly) async throws -> (Fixture, Transaction.Contents) {
        let f = try await Self.fixture()
        do { return (f, try await Writer.run(tool: f.tool, source: f.source, stage: f.stage, retention: mode).contents) }
        catch { f.cleanup(); throw error }
    }
    private func manifest(_ f: Fixture) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: f.stage.appendingPathComponent("manifest.json"))) as? [String: Any])
    }
    private func write(_ object: Any, _ path: URL) throws { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]).write(to: path) }
    private func rows(_ f: Fixture) throws -> [[String: Any]] {
        try String(contentsOf: f.stage.appendingPathComponent("source-audit.jsonl"), encoding: .utf8).split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }
    private func writeRows(_ rows: [[String: Any]], _ f: Fixture) throws {
        var data = Data()
        for row in rows { data.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])); data.append(10) }
        try data.write(to: f.stage.appendingPathComponent("source-audit.jsonl"))
    }
    private func refreshed(_ f: Fixture, _ c: Transaction.Contents, repairManifest: Bool = false) throws -> Transaction.Contents {
        if repairManifest {
            var m = try manifest(f)
            m["components"] = try c.members.filter { $0.name != "manifest.json" }.map { item -> [String: Any] in
                let data = try Data(contentsOf: f.stage.appendingPathComponent(item.name))
                return ["name":item.name,"bytes":data.count,"sha256":DolbyInspection.hex(SHA256.hash(data: data))]
            }
            try write(m, f.stage.appendingPathComponent("manifest.json"))
        }
        let members = try c.members.map { m -> ResultSetStaging.Member in
            let data = try Data(contentsOf: f.stage.appendingPathComponent(m.name))
            return .init(name: m.name, byteCount: Int64(data.count), sha256: DolbyInspection.hex(SHA256.hash(data: data)))
        }
        return .init(retention: c.retention, sourceID: c.sourceID, stageID: c.stageID, sourceBytes: c.sourceBytes,
            sourceSHA256: c.sourceSHA256, packets: c.packets, records: c.records, enhancementNALs: c.enhancementNALs, members: members)
    }
    private final class State: @unchecked Sendable {
        private let lock=NSLock();private var child:pid_t=0,joined:pid_t=0
        func launch(_ p:pid_t) { lock.withLock { child=p } }
        var hasLaunched:Bool { lock.withLock { child > 0 } }
        func settle(_ p:pid_t) { lock.withLock { joined=p } }
        func assertJoined() {
            let p=lock.withLock { (child,joined) };#expect(p.0 > 0 && p.0 == p.1)
            var status:Int32=0;#expect(waitpid(p.0,&status,WNOHANG) == -1 && errno == ECHILD)
        }
    }
    private final class Gate: @unchecked Sendable {
        let entered:AsyncStream<Void>,signal:AsyncStream<Void>.Continuation
        let release=DispatchSemaphore(value:0)
        init() { let p=AsyncStream<Void>.makeStream();entered=p.stream;signal=p.continuation }
        func hold() { signal.yield(());signal.finish();if release.wait(timeout:.now()+30) != .success { Issue.record("Generated metadata comparison gate expired") } }
    }
    private func checked(_ f:Fixture,_ c:Transaction.Contents) async throws -> CompanionDiskCheck.Receipt {
        try await CompanionDiskCheck.verifyOriginalMetadata(source:f.source,stage:f.stage,contents:c,tool:f.readerTool)
    }
    @Test func actualBothModeNativeMetadataAdmissionRequiresFreshOriginalSourceMatch() async throws {
        for mode in [Transaction.Retention.metadataOnly,.entireContainer] {
            let (f,c)=try await staged(mode);defer { f.cleanup() };let original=try Data(contentsOf:f.source),state=State()
            let result=try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ state.launch($0) },settled:{ state.settle($0) })) { try await checked(f,c) }
            let metadata=try #require(result.originalMetadata)
            #expect(result.originalMetadataSemanticsVerified && metadata.compactMetadataSummaryMatchesOriginalSource && metadata.originalPacketRPUSemanticsVerified && metadata.originalComponentsMatchSource)
            #expect(metadata.fresh.packets == 4 && metadata.fresh.records == 5 && metadata.fresh.enhancementNALs == 1)
            #expect(metadata.decodedFrameAssociation == "not-established" && !metadata.immutableSnapshot && !metadata.stableImporter && !metadata.persistedProducerBinding)
            #expect(result.fullContainerMatchesOriginalBytes == (mode == .entireContainer));state.assertJoined()
            #expect(try Data(contentsOf:f.source) == original)
            #expect(try await CompanionDiskCheck.verifyOriginalAudit(source:f.source,stage:f.stage,contents:c).originalMetadata == nil)
        }
    }
    @Test func plausibleRehashedCompactSummaryForgeriesPassPartialButFailFreshComparisonAfterJoin() async throws {
        let (f,c)=try await staged();defer { f.cleanup() };let original=try rows(f)
        let i=try #require(original.firstIndex { $0["kind"] as? String == "rpu-summary" })
        for key in ["mapping_profile","enhancement_type","scene_refresh","active_areas_left_right_top_bottom","cmv29_present","cmv40_present"] {
            var a=original,s=try #require(a[i]["summary"] as? [String:Any])
            switch key {
            case "mapping_profile": s[key]=(try #require(s[key] as? NSNumber).intValue+1)%11
            case "enhancement_type": s[key]=(s[key] as? String) == "MEL" ? "FEL":"MEL"
            case "scene_refresh": s[key]=(s[key] as? Bool).map { !$0 } ?? true
            case "active_areas_left_right_top_bottom": s[key]=[[1,2,3,4]]
            default: s[key] = !(try #require(s[key] as? Bool))
            }
            a[i]["summary"]=s;try writeRows(a,f);let repaired=try refreshed(f,c,repairManifest:true)
            #expect(try await CompanionDiskCheck.verifyOriginalAudit(source:f.source,stage:f.stage,contents:repaired).originalAudit != nil)
            let state=State()
            await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ state.launch($0) },settled:{ state.settle($0) })) {
                await #expect(throws:NativeExportError.self) { try await checked(f,repaired) }
            }
            state.assertJoined();#expect(try FileManager.default.contentsOfDirectory(atPath:f.stage.path).count == c.members.count)
        }
    }
    @Test func semanticFieldOrderWhitespaceAndExactTypedValuesAreHandledWithoutCoercion() async throws {
        let (f,c)=try await staged();defer { f.cleanup() };var data=Data()
        for row in try rows(f) { data.append(try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys,.prettyPrinted]).filter { $0 != 10 });data.append(10) }
        try data.write(to:f.stage.appendingPathComponent("source-audit.jsonl"))
        #expect(try await checked(f,refreshed(f,c,repairManifest:true)).originalMetadataSemanticsVerified)
        typealias JSON=CompanionArchiveJSON
        let one=try JSON.object(Data("{\"a\":null,\"b\":false,\"c\":-1}".utf8),maximum:65535,auditNullable:true)
        let reordered=try JSON.object(Data("{ \"c\": -1, \"b\": false, \"a\": null }".utf8),maximum:65535,auditNullable:true)
        let coerced=try JSON.object(Data("{\"a\":null,\"b\":0,\"c\":-1}".utf8),maximum:65535,auditNullable:true)
        #expect(one == reordered && one != coerced)
    }
    @Test func actualNativeWriterMetadataVerifierExclusivePublicationBothModesAndPriorDestination() async throws {
        for mode in [Transaction.Retention.metadataOnly,.entireContainer] {
            let f=try await Self.fixture();defer { f.cleanup() };let writer=try f.tool,reader=try f.readerTool,original=try Data(contentsOf:f.source)
            let result=try await Transaction.execute(source:f.source,in:f.root,destinationName:"published",retention:mode,
                produce:{ directory in try await Writer.run(tool:writer,source:f.source,stage:directory,retention:mode).contents },verify:{ directory,c in
                    let r=try await CompanionDiskCheck.verifyOriginalMetadata(source:f.source,stage:directory,contents:c,tool:reader)
                    let m=try #require(r.originalMetadata)
                    return .init(contents:r.contents,originalComponentsMatchSource:r.originalMetadataSemanticsVerified && m.originalComponentsMatchSource,
                        sourceIdentityChecked:true,decodedFrameAssociation:m.decodedFrameAssociation,immutableSnapshot:m.immutableSnapshot,stableImporter:m.stableImporter)
                })
            #expect(result.directory == f.root.appendingPathComponent("published",isDirectory:true))
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath:result.directory.path)) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf:result.directory.appendingPathComponent("original-container.mkv")) == original) }
            let manifest=try Data(contentsOf:result.directory.appendingPathComponent("manifest.json"))
            await #expect(throws:(any Error).self) {
                try await Transaction.execute(source:f.source,in:f.root,destinationName:"published",retention:mode,produce:{ _ in Issue.record("Prior destination launched producer");throw NativeExportError.invalid("refuse") },verify:{ _,_ in throw NativeExportError.invalid("refuse") })
            }
            #expect(try Data(contentsOf:result.directory.appendingPathComponent("manifest.json")) == manifest)
            #expect(try Data(contentsOf:f.source) == original)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath:f.root.path)) == ["generated","stage","published","staxrip-dolby-companion-writer","staxrip-dolby-metadata-audit"])
        }
    }
    @Test(arguments:["source-audit.jsonl","source","stage"])
    func finalPinnedObservationsRefuseAfterSuccessfulFreshMetadataComparison(name:String) async throws {
        let (f,c)=try await staged();defer { f.cleanup() }
        await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{
            do {
                if name == "stage" { try FileManager.default.moveItem(at:f.stage,to:f.root.appendingPathComponent("moved-stage"));try FileManager.default.createDirectory(at:f.stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]) }
                else { let h=try FileHandle(forWritingTo:name == "source" ? f.source:f.stage.appendingPathComponent(name));try h.write(contentsOf:Data([0xfe]));try h.close() }
            } catch { Issue.record("Generated post-metadata mutation failed") }
        })) { await #expect(throws:(any Error).self) { try await checked(f,c) } }
    }
    @Test func cancellationDuringActualFreshMemberReadPropagatesToJoinedReaderBeforeReturn() async throws {
        let (f,c)=try await staged();defer { f.cleanup() };let state=State(),gate=Gate(),reader=try f.readerTool
        let task=Task {
            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ state.launch($0) },settled:{ state.settle($0) })) {
                try await CompanionDiskCheck.$testBoundary.withValue(.init(originalComponentRead:{ name,_,_ in if name == "source-audit.jsonl" && state.hasLaunched { gate.hold() } })) {
                    try await CompanionDiskCheck.verifyOriginalMetadata(source:f.source,stage:f.stage,contents:c,tool:reader)
                }
            }
        }
        for await _ in gate.entered { break };task.cancel();gate.release.signal()
        do { _ = try await task.value;Issue.record("Cancelled metadata comparison returned success") }
        catch is CancellationError {}
        catch let e as CompanionMetadataProcess.OwnershipFailure { #expect(e.reason == "group-1-joined-true") }
        catch { Issue.record("Unexpected generated metadata comparison cancellation error") }
        state.assertJoined();#expect(try FileManager.default.contentsOfDirectory(atPath:f.stage.path).count == c.members.count)
    }
    @Test func actualTransactionCancellationSettlesReaderOrRetainsTypedUnsettledStage() async throws {
        let f=try await Self.fixture();defer { f.cleanup() }
        let writer=try f.tool,reader=try f.readerTool,state=State(),gate=Gate(),original=try Data(contentsOf:f.source)
        let baseline=Set(try FileManager.default.contentsOfDirectory(atPath:f.root.path))
        let task=Task {
            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched:{ state.launch($0) },settled:{ state.settle($0) })) {
                try await CompanionDiskCheck.$testBoundary.withValue(.init(originalComponentRead:{ name,_,_ in
                    if name == "source-audit.jsonl" && state.hasLaunched { gate.hold() }
                })) {
                    try await Transaction.execute(source:f.source,in:f.root,destinationName:"published",retention:.metadataOnly,
                        produce:{ directory in try await Writer.run(tool:writer,source:f.source,stage:directory,retention:.metadataOnly).contents },
                        verify:{ directory,c in
                            _ = try await CompanionDiskCheck.verifyOriginalMetadata(source:f.source,stage:directory,contents:c,tool:reader)
                            Issue.record("Cancelled transaction admitted metadata")
                            throw NativeExportError.invalid("Generated refusal")
                        })
                }
            }
        }
        for await _ in gate.entered { break };task.cancel();gate.release.signal()
        do { _ = try await task.value;Issue.record("Cancelled transaction published") }
        catch is CancellationError {
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath:f.root.path)) == baseline)
        }
        catch let e as Transaction.UnsettledPhaseFailure {
            let reason=try #require(e.operationError as? CompanionMetadataProcess.OwnershipFailure)
            #expect(reason.reason == "group-1-joined-true")
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath:e.intendedStage.path)) == Set(Transaction.Retention.metadataOnly.limits.keys))
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath:f.root.path)) == baseline.union([e.intendedStage.lastPathComponent]))
        }
        catch { Issue.record("Unexpected generated transaction cancellation error") }
        state.assertJoined()
        #expect(!FileManager.default.fileExists(atPath:f.root.appendingPathComponent("published").path))
        #expect(try Data(contentsOf:f.source) == original)
    }

}
