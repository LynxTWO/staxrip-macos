import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionOriginalAuditCheckTests {
    typealias Writer = CompanionWriterProcess
    typealias Transaction = OriginalCompanionTransaction
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
            let helpers = try await RustFixtureBuild.generate(.original, at: generated, copiesIn: root)
            let executable = helpers.writer
            let stage = root.appendingPathComponent("stage")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return .init(root: root, source: generated.appendingPathComponent("generated-source.mkv"), stage: stage, executable: executable)
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
    private func refuse(_ f: Fixture, _ c: Transaction.Contents) async throws {
        _ = try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: f.stage, contents: c)
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalAudit(source: f.source, stage: f.stage, contents: c) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).count == c.members.count)
    }
    @Test func actualWriterBothModesAuditSourceFactsAndIndependentOracle() async throws {
        for mode in [Transaction.Retention.metadataOnly, .entireContainer] {
            let (f, c) = try await staged(mode); defer { f.cleanup() }
            let original = try Data(contentsOf: f.source)
            let r = try await CompanionDiskCheck.verifyOriginalAudit(source: f.source, stage: f.stage, contents: c)
            let checked = try #require(r.originalAudit)
            #expect(checked.originalAuditFramingMatchesSource && checked.originalDeclaredGeometryMatchesSource && !checked.compactMetadataSummaryVerified)
            #expect(!checked.originalPacketRPUSemanticsVerified && !checked.originalMetadataSemanticsVerified && !r.originalMetadataSemanticsVerified)
            #expect(checked.index.packets.packets == 4 && checked.index.packets.records == 5 && checked.index.packets.enhancementNALs == 1)
            #expect(try #require(r.originalPackets).packetSequenceSHA256 == checked.index.packets.packetSequenceSHA256)
            let refs = try rows(f).filter { $0["pts_ns"] != nil }; #expect(refs.contains { ($0["pts_ns"] as? NSNumber)?.int64Value ?? 0 < 0 })
            #expect(Set(refs.compactMap { ($0["pts_ns"] as? NSNumber)?.int64Value }).count < refs.count)
            let oracle = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["python3",
                Self.repo.appendingPathComponent("Tools/DolbyCompanionCheck/native_transaction_fixture.py").path,
                "verify", f.source.path, f.stage.path, mode == .metadataOnly ? "metadata" : "full", f.executable.path,
                f.root.appendingPathComponent("staxrip-dolby-metadata-audit").path], stdoutLimit: 16384)
            try #require(oracle.status == 0 && !oracle.truncated) // Independent test oracle only, not a native bridge.
            #expect(try Data(contentsOf: f.source) == original)
            #expect(try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: c).originalAudit == nil)
        }
    }
    private func element(_ id: UInt64, _ payload: Data) -> Data {
        var value = id, ids: [UInt8] = []
        repeat { ids.insert(UInt8(value & 255), at: 0); value >>= 8 } while value != 0
        var width = 1; while UInt64(payload.count) >= (UInt64(1) << (7 * width)) - 1 { width += 1 }
        let length = UInt64(payload.count) | UInt64(1) << (7 * width)
        return Data(ids + (0..<width).reversed().map { UInt8(truncatingIfNeeded: length >> (8 * $0)) }) + payload
    }
    private func unsigned(_ n: UInt64) -> Data {
        var n = n, b: [UInt8] = []; repeat { b.insert(UInt8(n & 255), at: 0); n >>= 8 } while n > 0; return Data(b)
    }
    @Test func actualWriterSignedExtremeAuditAndDeclaredGeometry() async throws {
        let cases: [(UInt64, Int16, UInt64, Int64)] = [(0, -1, 1 << 63, Int64.min), (UInt64(Int64.max) + 10, -10, 1, Int64.max)]
        for (cluster, relative, scale, expected) in cases {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let originalComponents = f.root.appendingPathComponent("generated/metadata")
            let videoFields: [Data] = [element(0xb0,unsigned(4096)), element(0xba,unsigned(2160)),
                element(0x54cc,unsigned(2)), element(0x54dd,unsigned(4)), element(0x54bb,unsigned(6)),
                element(0x54aa,unsigned(8)), element(0x54b0,unsigned(65536)), element(0x54ba,unsigned(2160)), element(0x54b2,unsigned(4))]
            let video = element(0xe0, videoFields.reduce(into:Data()) { $0.append($1) })
            let cfg = try Data(contentsOf: originalComponents.appendingPathComponent("hevc-configuration.bin"))
            try #require(Int(cfg[21] & 3) + 1 == 4)
            let track = element(0xd7,unsigned(1)) + element(0x83,unsigned(1)) + element(0x86,Data("V_MPEGH/ISO/HEVC".utf8)) + element(0x63a2,cfg) + video + element(0x23e383,unsigned(UInt64.max))
            let indexData = try Data(contentsOf: originalComponents.appendingPathComponent("rpu-index.jsonl"))
            let firstLine = try #require(String(decoding: indexData, as: UTF8.self).split(separator: "\n").first)
            let index = try #require(JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any])
            let size = try #require(index["payload_bytes"] as? NSNumber).intValue
            let raw = try Data(contentsOf: originalComponents.appendingPathComponent("original-rpu.bin"))
            let payload = raw.subdata(in: 4..<(4 + size)), length = payload.count + 2
            let prefix = Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: length >> (8 * $0)) })
            let nal = prefix + Data([0x7c,1]) + payload
            let ticks = UInt16(bitPattern: relative)
            let block = element(0xa3, Data([0x81,UInt8(ticks >> 8),UInt8(ticks & 255),0x80]) + nal)
            let header = element(0x1a45dfa3, element(0x4282, Data("matroska".utf8)))
            let info = element(0x1549a966, element(0x2ad7b1, unsigned(scale)))
            let source = header + Data([0x18,0x53,0x80,0x67,0xff]) + info + element(0x1654ae6b, element(0xae, track)) + element(0x1f43b675, element(0xe7, unsigned(cluster)) + block)
            try source.write(to: f.source)
            let c = try await Writer.run(tool: f.tool, source: f.source, stage: f.stage, retention: .metadataOnly).contents
            let admitted = try await CompanionDiskCheck.verifyOriginalAudit(source: f.source, stage: f.stage, contents: c)
            #expect(try #require(admitted.originalAudit).originalAuditFramingMatchesSource)
            let actual = try #require(try rows(f).first { $0["kind"] as? String == "packet" })
            #expect((actual["pts_ns"] as? NSNumber)?.int64Value == expected)
            #expect(try Data(contentsOf: f.source) == source)
        }
    }
    @Test func rehashedAuditSourceClaimsAndMalformedRowsRefuseAfterIndexAdmission() async throws {
        let (f,c) = try await staged(); defer { f.cleanup() }
        let original = try rows(f)
        let fields = ["version","parser","input_type","track_number","timestamp_scale_ns","declared_pixel_width","declared_pixel_height","declared_display_unit","default_duration_ns","nal_length_bytes","configuration_bytes","configuration_sha256","segment_unknown_size","packet_limit","file_limit","count_limit","crop","display","begin-extra","begin-missing","index","input_byte_offset","block_input_byte_offset","pts_ns","duration_ns","invisible","keyframe","discardable","encoded_bytes","sha256","packet_index","nal_index","rpu-pts","summary-extra","summary-profile","summary-bool","summary-area","summary-el","summary-scene","packets","records","enhancement_nals","input_bytes","input_sha256","peak_record_bytes","packet_sequence_sha256","source_recheck","complete-version","extra-row","missing-row","reorder","truncated","duplicate-key","resources"]
        for field in fields {
            var a = original
            let packet = try #require(a.firstIndex { $0["kind"] as? String == "packet" })
            let rpu = try #require(a.firstIndex { $0["kind"] as? String == "rpu-summary" })
            let last = a.count - 1
            switch field {
            case "parser", "input_type": a[0][field] = "unsupported"
            case "version": a[0][field] = true
            case "configuration_sha256": a[0][field] = String(repeating:"0",count:64)
            case "segment_unknown_size": a[0][field] = !(try #require(a[0][field] as? Bool))
            case "default_duration_ns": a[0][field] = 1
            case "crop": a[0]["declared_crop_left_right_top_bottom"] = [1,0,0,0]
            case "display": a[0]["declared_display_width_height"] = [false,NSNull()]
            case "begin-extra": a[0]["extra"] = 0
            case "begin-missing": a[0].removeValue(forKey:"default_duration_ns")
            case "track_number","timestamp_scale_ns","declared_pixel_width","declared_pixel_height","declared_display_unit","nal_length_bytes","configuration_bytes","packet_limit","file_limit","count_limit":
                a[0][field] = try #require(a[0][field] as? NSNumber).uint64Value + 1
            case "pts_ns": a[packet][field] = true
            case "duration_ns": a[packet][field] = 1
            case "invisible","keyframe","discardable": a[packet][field] = 0
            case "sha256": a[packet][field] = String(repeating:"0",count:64)
            case "index","input_byte_offset","block_input_byte_offset","encoded_bytes": a[packet][field] = try #require(a[packet][field] as? NSNumber).uint64Value + 1
            case "packet_index","nal_index": a[rpu][field] = try #require(a[rpu][field] as? NSNumber).uint64Value + 1
            case "rpu-pts": a[rpu]["pts_ns"] = 1234
            case "summary-extra","summary-profile","summary-bool","summary-area","summary-el","summary-scene":
                var s = try #require(a[rpu]["summary"] as? [String:Any])
                switch field {
                case "summary-extra": s["extra"] = false
                case "summary-profile": s["mapping_profile"] = 11
                case "summary-bool": s["cmv29_present"] = 0
                case "summary-area": s["active_areas_left_right_top_bottom"] = [[0,0,0,8192]]
                case "summary-el": s["enhancement_type"] = "unknown"
                default: s["scene_refresh"] = 0
                }
                a[rpu]["summary"] = s
            case "input_sha256","packet_sequence_sha256": a[last][field] = String(repeating:"0",count:64)
            case "source_recheck": a[last][field] = false
            case "complete-version": a[last]["version"] = 4
            case "packets","records","enhancement_nals","input_bytes","peak_record_bytes": a[last][field] = try #require(a[last][field] as? NSNumber).uint64Value + 1
            case "extra-row": a.append(a[last])
            case "missing-row": a.remove(at:rpu)
            case "reorder": a.swapAt(packet,rpu)
            case "resources": a.append(["kind":"resources","heap_limit":67108864,"peak_heap_bytes":1])
            default: break
            }
            try writeRows(a,f)
            let path = f.stage.appendingPathComponent("source-audit.jsonl")
            if field == "truncated" { var d = try Data(contentsOf:path); d.removeLast(); try d.write(to:path) }
            if field == "duplicate-key" {
                var text = try String(contentsOf:path,encoding:.utf8)
                text.insert(contentsOf:"\"version\":3,",at:text.index(after:text.startIndex)); try Data(text.utf8).write(to:path)
            }
            try await refuse(f,refreshed(f,c,repairManifest:true))
        }
    }
    @Test func plausibleChangedCompactSummaryRemainsExplicitlyUnverified() async throws {
        let (f,c) = try await staged(); defer { f.cleanup() }; var a = try rows(f)
        let i = try #require(a.firstIndex { $0["kind"] as? String == "rpu-summary" })
        var s = try #require(a[i]["summary"] as? [String:Any]); s["mapping_profile"] = 0
        a[i]["summary"] = s; try writeRows(a,f)
        let checked = try await CompanionDiskCheck.verifyOriginalAudit(source:f.source,stage:f.stage,contents:refreshed(f,c,repairManifest:true))
        #expect(try #require(checked.originalAudit).originalAuditFramingMatchesSource)
        let partial = try #require(checked.originalAudit)
        #expect(!checked.originalMetadataSemanticsVerified && !partial.compactMetadataSummaryVerified)
    }
    @Test func actualDeclaredSourceGeometryDefaultsBoundsAndMalformedFields() throws {
        typealias Track = CompanionOriginalTrackCheck
        func check(_ payload: Data) throws -> CompanionOriginalAuditCheck.Declarations {
            let view = CompanionDiskCheck.ReadView(sourceBytes:Int64(payload.count),source: { offset,count in
                try #require(count <= 1 << 20)
                return payload.subdata(in:Int(offset)..<(Int(offset)+count))
            },component: { _ in throw NativeExportError.invalid("No component read authorized") },checkpoint:{})
            let track = Track.Receipt(trackNumber:1,originalPayloadOffset:0,payloadBytes:payload.count,configurationBytes:23,nalLengthBytes:4,payloadSHA256:"",configurationSHA256:"",originalTrackAndConfigurationMatch:false)
            return try CompanionOriginalAuditCheck.declarations(view,track:track)
        }
        let base = element(0xb0,unsigned(16384)) + element(0xba,unsigned(2))
        let defaults = try check(element(0xe0,base))
        #expect(defaults.width == 16384 && defaults.height == 2 && defaults.crop == [0,0,0,0] && defaults.display == [nil,nil] && defaults.duration == nil)
        let explicit = element(0xe0,base + element(0x54cc,unsigned(16383)) + element(0x54aa,unsigned(1)) + element(0x54b0,unsigned(65536)) + element(0x54b2,unsigned(4))) + element(0x23e383,unsigned(UInt64.max))
        let valid = try check(explicit)
        #expect(valid.crop == [16383,0,0,1] && valid.display == [65536,nil] && valid.unit == 4 && valid.duration == UInt64.max)
        let malformed: [Data] = [
            element(0xd7,unsigned(1)), element(0xe0,element(0xb0,unsigned(2))),
            element(0xe0,element(0xb0,unsigned(1))+element(0xba,unsigned(2))),
            element(0xe0,element(0xb0,unsigned(16385))+element(0xba,unsigned(2))),
            element(0xe0,base+element(0xb0,unsigned(2))), element(0xe0,base)+element(0xe0,base),
            element(0xe0,base+element(0x54cc,unsigned(16384))),
            element(0xe0,base+element(0x54bb,unsigned(2))),
            element(0xe0,base+element(0x54cc,unsigned(UInt64.max))+element(0x54dd,unsigned(1))),
            element(0xe0,base+element(0x54b0,unsigned(0))),
            element(0xe0,base+element(0x54ba,unsigned(65537))),
            element(0xe0,base+element(0x54b2,unsigned(5))),
            element(0xe0,base+element(0x54cc,Data())),
            element(0xe0,base+element(0x54dd,Data(repeating:0,count:9))),
            element(0xe0,base)+element(0x23e383,unsigned(0)),
            element(0xe0,base)+element(0x23e383,unsigned(1))+element(0x23e383,unsigned(1)),
            element(0xe0,base)+Data([0xec,0xff]), element(0xe0,base)+Data([0x54])
        ]
        for payload in malformed { #expect(throws:(any Error).self) { try check(payload) } }
        for id: UInt64 in [0x54cc,0x54dd,0x54bb,0x54aa,0x54b0,0x54ba,0x54b2] {
            let duplicated = element(0xe0,base+element(id,unsigned(1))+element(id,unsigned(1)))
            #expect(throws:(any Error).self) { try check(duplicated) }
        }
    }
    @Test func auditRowsUseFixedBoundedReadsAndExactLF() throws {
        func stream(_ data: Data) throws -> CompanionOriginalIndexCheck.Rows {
            try .init(.init(sourceBytes:1,source:{ _,_ in Data() },component:{ _ in Data() },checkpoint:{},componentBytes:{ name in
                #expect(name == "source-audit.jsonl"); return Int64(data.count)
            },componentRead:{ name,offset,count in
                #expect(name == "source-audit.jsonl" && count <= 65536)
                return data.subdata(in:Int(offset)..<(Int(offset)+count))
            }),fixed:.audit)
        }
        let rows = try stream(Data(repeating:32,count:65523)+Data("{\"a\":null}\n{\"b\":true}\n".utf8))
        #expect(try rows.next() != nil); #expect(try rows.next() != nil); #expect(try rows.next() == nil)
        for data in [Data("{}".utf8),Data("\n".utf8),Data(repeating:32,count:65536)+Data("{}\n".utf8)] {
            let rows = try stream(data); #expect(throws:(any Error).self) { try rows.next() }
        }
    }
    @Test func nullableGrammarIsAuditOnlyAndPreservesStrictTypes() throws {
        let d = Data("{\"a\":null,\"b\":[0,null,true],\"c\":-9223372036854775808}".utf8)
        #expect(throws:(any Error).self) { try CompanionArchiveJSON.object(d,maximum:65535) }
        let o = try CompanionArchiveJSON.object(d,maximum:65535,auditNullable:true)
        #expect(try CompanionArchiveJSON.signed(o,"c") == Int64.min)
        #expect(throws:(any Error).self) { try CompanionArchiveJSON.unsigned(o,"a",0...1) }
        for text in ["{\"a\":nullx}","{\"a\":null,\"a\":null}","{\"a\":1.0}","{\"a\":-0}"] {
            #expect(throws:(any Error).self) { try CompanionArchiveJSON.object(Data(text.utf8),maximum:65535,auditNullable:true) }
        }
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>; private let signal: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value: 0)
        init() { let p = AsyncStream<Void>.makeStream(); entered = p.stream; signal = p.continuation }
        func hold() { signal.yield(()); signal.finish(); if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated index read gate expired") } }
    }
    @Test(arguments: ["source-audit.jsonl"])
    func cancellationDuringActualComponentReadSettlesBeforeReturn(name: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }; let gate = Gate()
        let task = Task {
            try await CompanionDiskCheck.$testBoundary.withValue(.init(originalComponentRead: { n, _, _ in if n == name { gate.hold() } })) {
                try await CompanionDiskCheck.verifyOriginalAudit(source: f.source, stage: f.stage, contents: c)
            }
        }
        for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).count == c.members.count)
    }
    @Test(arguments: ["source-audit.jsonl", "source", "stage"])
    func finalObservationsRefuseChangesAfterIndexManifestCheck(name: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
            do {
                if name == "stage" {
                    try FileManager.default.moveItem(at: f.stage, to: f.root.appendingPathComponent("retained-stage"))
                    try FileManager.default.createDirectory(at: f.stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                } else {
                    let h = try FileHandle(forWritingTo: name == "source" ? f.source : f.stage.appendingPathComponent(name))
                    try h.write(contentsOf: Data([0xfe])); try h.close()
                }
            } catch { Issue.record("Generated index mutation failed") }
        })) {
            await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalAudit(source: f.source, stage: f.stage, contents: c) }
        }
    }
    @Test func matchingPartialAuditCannotAdmitFullNativeTransaction() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }; let tool = try f.tool
        let original = try Data(contentsOf: f.source)
        await #expect(throws: (any Error).self) {
            try await Transaction.execute(source: f.source, in: f.root, destinationName: "result", retention: .metadataOnly,
                produce: { directory in try await Writer.run(tool: tool, source: f.source, stage: directory, retention: .metadataOnly).contents },
                verify: { directory, c in
                    let checked = try await CompanionDiskCheck.verifyOriginalAudit(source: f.source, stage: directory, contents: c)
                    #expect(try #require(checked.originalAudit).originalAuditFramingMatchesSource)
                    return .init(contents: checked.contents, originalComponentsMatchSource: checked.originalMetadataSemanticsVerified,
                        sourceIdentityChecked: true, decodedFrameAssociation: "not-established", immutableSnapshot: false, stableImporter: false)
                })
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("result").path))
        #expect(try Data(contentsOf: f.source) == original)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: f.root.path)) == ["generated", "stage", "staxrip-dolby-companion-writer", "staxrip-dolby-metadata-audit"])
    }
}
