import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionOriginalIndexCheckTests {
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
            let cargo = repo.appendingPathComponent("Tools/DolbyMetadataAudit/Cargo.toml")
            let f = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "STAXRIP_GENERATED_COMPANION_FIXTURE_DIRECTORY=" + generated.path, "cargo", "test", "--locked",
                "--manifest-path", cargo.path, "original_companions_preserve_raw_bytes_encoded_order_and_distinct_retention"])
            try #require(f.status == 0)
            let b = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "cargo", "build", "--release", "--locked", "--features", "development-companion-writer", "--bin",
                "staxrip-dolby-companion-writer", "--manifest-path", cargo.path])
            try #require(b.status == 0)
            let executable = root.appendingPathComponent("staxrip-dolby-companion-writer")
            try FileManager.default.copyItem(at: repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/release/staxrip-dolby-companion-writer"), to: executable)
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
        try String(contentsOf: f.stage.appendingPathComponent("rpu-index.jsonl"), encoding: .utf8).split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }
    private func writeRows(_ rows: [[String: Any]], _ f: Fixture) throws {
        var data = Data()
        for row in rows { data.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])); data.append(10) }
        try data.write(to: f.stage.appendingPathComponent("rpu-index.jsonl"))
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
        _ = try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: c)
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: f.stage, contents: c) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).count == c.members.count)
    }
    @Test func actualNativeWriterBothModesAdmitIndexAndManifestAgainstIndependentOracle() async throws {
        for mode in [Transaction.Retention.metadataOnly, .entireContainer] {
            let (f, c) = try await staged(mode); defer { f.cleanup() }
            let original = try Data(contentsOf: f.source)
            let r = try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: f.stage, contents: c)
            let checked = try #require(r.originalIndex)
            #expect(checked.originalIndexMatchesSource && checked.manifestClaimsMatchObservedSourceAndComponents)
            #expect(!checked.originalPacketRPUSemanticsVerified && !checked.originalMetadataSemanticsVerified && !r.originalMetadataSemanticsVerified)
            #expect(checked.packets.packets == 4 && checked.packets.records == 5 && checked.packets.enhancementNALs == 1)
            #expect(try #require(r.originalPackets).packetSequenceSHA256 == checked.packets.packetSequenceSHA256)
            let refs = try rows(f); #expect(refs.contains { ($0["pts_ns"] as? NSNumber)?.int64Value ?? 0 < 0 })
            #expect(Set(refs.compactMap { ($0["pts_ns"] as? NSNumber)?.int64Value }).count < refs.count)
            let oracle = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["python3",
                Self.repo.appendingPathComponent("Tools/DolbyCompanionCheck/native_transaction_fixture.py").path,
                "verify", f.source.path, f.stage.path, mode == .metadataOnly ? "metadata" : "full", f.executable.path,
                Self.repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/release/staxrip-dolby-metadata-audit").path], stdoutLimit: 16384)
            try #require(oracle.status == 0 && !oracle.truncated) // Independent test oracle only, not a native bridge.
            #expect(try Data(contentsOf: f.source) == original)
            #expect(try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: c).originalIndex == nil)
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
    @Test func actualWriterSignedExtremeSourcesHaveExactPersistedIndexAssociations() async throws {
        let cases: [(UInt64, Int16, UInt64, Int64)] = [(0, -1, 1 << 63, Int64.min), (UInt64(Int64.max) + 10, -10, 1, Int64.max)]
        for (cluster, relative, scale, expected) in cases {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let originalComponents = f.root.appendingPathComponent("generated/metadata")
            let track = try Data(contentsOf: originalComponents.appendingPathComponent("original-track-entry-payload.bin"))
            let cfg = try Data(contentsOf: originalComponents.appendingPathComponent("hevc-configuration.bin"))
            try #require(Int(cfg[21] & 3) + 1 == 4)
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
            let source = header + element(0x18538067, info + element(0x1654ae6b, element(0xae, track)) + element(0x1f43b675, element(0xe7, unsigned(cluster)) + block))
            try source.write(to: f.source)
            let c = try await Writer.run(tool: f.tool, source: f.source, stage: f.stage, retention: .metadataOnly).contents
            let admitted = try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: f.stage, contents: c)
            #expect(try #require(admitted.originalIndex).originalIndexMatchesSource)
            let actual = try #require(try rows(f).first)
            #expect((actual["pts_ns"] as? NSNumber)?.int64Value == expected)
            #expect(try Data(contentsOf: f.source) == source)
        }
    }
    @Test func manifestComponentOrderAndPermittedWhitespaceDoNotAlterAdmittedMeaning() async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }; var m = try manifest(f)
        m["components"] = Array(try #require(m["components"] as? [[String: Any]]).reversed())
        let bytes = try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys, .prettyPrinted])
        try bytes.write(to: f.stage.appendingPathComponent("manifest.json"))
        let checked = try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: f.stage, contents: refreshed(f, c))
        #expect(try #require(checked.originalIndex).manifestClaimsMatchObservedSourceAndComponents)
    }
    @Test(arguments: ["kind", "version", "version-bool", "source-bytes", "source-hash", "track-offset", "packets", "records", "enhancement", "association", "decoded", "recheck", "identity", "rewrite", "retention", "extra", "members", "member-self", "member-path", "member-duplicate", "member-bytes", "member-hash", "member-extra", "bool-number", "fraction", "root-array", "duplicate-key"])
    func rehashedManifestForgeriesRefuseActualNativeClaims(field: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        var m = try manifest(f), components = try #require(m["components"] as? [[String: Any]])
        switch field {
        case "kind": m["kind"] = "original-companion"
        case "version": m["version"] = 1
        case "version-bool": m["version"] = false
        case "source-bytes": m["source_bytes"] = c.sourceBytes + 1
        case "source-hash": m["source_sha256"] = String(repeating: "0", count: 64)
        case "track-offset": m["track_payload_original_offset"] = 0
        case "packets": m["packets"] = c.packets + 1
        case "records": m["records"] = c.records + 1
        case "enhancement": m["enhancement_nals"] = c.enhancementNALs + 1
        case "association": m["association"] = "decoded-frame-order"
        case "decoded": m["decoded_frame_association"] = "qualified"
        case "recheck": m["source_content_recheck"] = false
        case "identity": m["source_path_identity_bound"] = true
        case "rewrite": m["metadata_rewritten"] = true
        case "retention": m["retention"] = "entire-original-container"
        case "extra": m["extra"] = 0
        case "members": components.removeLast()
        case "member-self": components[0]["name"] = "manifest.json"
        case "member-path": components[0]["name"] = "../outside"
        case "member-duplicate": components[1] = components[0]
        case "member-bytes": components[0]["bytes"] = 1
        case "member-hash": components[0]["sha256"] = String(repeating: "f", count: 64)
        case "member-extra": components[0]["extra"] = 0
        case "bool-number": m["source_content_recheck"] = 1
        case "fraction": m["packets"] = 4.25
        default: break
        }
        m["components"] = components
        let path = f.stage.appendingPathComponent("manifest.json")
        if field == "root-array" { try write([], path) }
        else if field == "duplicate-key" {
            var bytes = try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]); bytes.removeLast()
            bytes.append(Data(",\"version\":0}".utf8)); try bytes.write(to: path)
        } else { try write(m, path) }
        try await refuse(f, refreshed(f, c))
    }
    @Test(arguments: ["kind", "index", "packet", "nal", "pts", "source-offset", "archive-offset", "size", "hash", "extra", "bool", "reorder", "missing", "extra-row", "missing-lf", "blank-row", "duplicate-key", "overflow", "negative-overflow", "negative-zero"])
    func rehashedIndexForgeriesRefuseActualOriginalAssociations(field: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }; var values = try rows(f)
        switch field {
        case "kind": values[0]["kind"] = "rpu-reference"
        case "index": values[0]["index"] = 1
        case "packet": values[0]["packet_index"] = 1
        case "nal": values[0]["nal_index"] = 100
        case "pts": values[0]["pts_ns"] = -1
        case "source-offset": values[0]["original_payload_offset"] = 0
        case "archive-offset": values[0]["archive_delimiter_offset"] = 1
        case "size": values[0]["payload_bytes"] = 1
        case "hash": values[0]["payload_sha256"] = String(repeating: "0", count: 64)
        case "extra": values[0]["extra"] = 0
        case "bool": values[0]["index"] = false
        case "reorder": values.reverse()
        case "missing": values.removeLast()
        case "extra-row": values.append(values[0])
        default: break
        }
        try writeRows(values, f); let path = f.stage.appendingPathComponent("rpu-index.jsonl")
        if ["missing-lf", "blank-row", "duplicate-key", "overflow", "negative-overflow", "negative-zero"].contains(field) {
            var bytes = try Data(contentsOf: path)
            if field == "missing-lf" { bytes.removeLast() }
            else if field == "blank-row" { bytes.append(10) }
            else if field == "duplicate-key" {
                let stop = try #require(bytes.firstIndex(of: 10)); bytes.insert(contentsOf: Data(",\"index\":0".utf8), at: stop - 1)
            } else {
                var line = String(decoding: bytes, as: UTF8.self).split(separator: "\n").map(String.init)
                let pts = try #require(values[0]["pts_ns"] as? NSNumber).int64Value
                let value = field == "overflow" ? "9223372036854775808" : (field == "negative-overflow" ? "-9223372036854775809" : "-0")
                line[0] = line[0].replacingOccurrences(of: "\"pts_ns\":\(pts)", with: "\"pts_ns\":\(value)")
                bytes = Data((line.joined(separator: "\n") + "\n").utf8)
            }
            try bytes.write(to: path)
        }
        try await refuse(f, refreshed(f, c, repairManifest: true))
    }
    @Test func repairedSourceAuditForgeryRemainsExplicitlyOutsidePartialAdmission() async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        try Data("{}\n".utf8).write(to: f.stage.appendingPathComponent("source-audit.jsonl"))
        let changed = try refreshed(f, c, repairManifest: true)
        let partial = try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: f.stage, contents: changed)
        #expect(try #require(partial.originalIndex).originalIndexMatchesSource)
        #expect(!partial.originalMetadataSemanticsVerified)
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>; private let signal: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value: 0)
        init() { let p = AsyncStream<Void>.makeStream(); entered = p.stream; signal = p.continuation }
        func hold() { signal.yield(()); signal.finish(); if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated index read gate expired") } }
    }
    @Test(arguments: ["manifest.json", "rpu-index.jsonl"])
    func cancellationDuringActualComponentReadSettlesBeforeReturn(name: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }; let gate = Gate()
        let task = Task {
            try await CompanionDiskCheck.$testBoundary.withValue(.init(originalComponentRead: { n, _, _ in if n == name { gate.hold() } })) {
                try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: f.stage, contents: c)
            }
        }
        for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).count == c.members.count)
    }
    @Test(arguments: ["manifest.json", "rpu-index.jsonl", "source", "stage"])
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
            await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: f.stage, contents: c) }
        }
    }
    @Test func matchingPartialIndexManifestCannotAdmitFullNativeTransaction() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }; let tool = try f.tool
        let original = try Data(contentsOf: f.source)
        await #expect(throws: (any Error).self) {
            try await Transaction.execute(source: f.source, in: f.root, destinationName: "result", retention: .metadataOnly,
                produce: { directory in try await Writer.run(tool: tool, source: f.source, stage: directory, retention: .metadataOnly).contents },
                verify: { directory, c in
                    let checked = try await CompanionDiskCheck.verifyOriginalIndexAndManifest(source: f.source, stage: directory, contents: c)
                    #expect(try #require(checked.originalIndex).originalIndexMatchesSource)
                    return .init(contents: checked.contents, originalComponentsMatchSource: checked.originalMetadataSemanticsVerified,
                        sourceIdentityChecked: true, decodedFrameAssociation: "not-established", immutableSnapshot: false, stableImporter: false)
                })
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("result").path))
        #expect(try Data(contentsOf: f.source) == original)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: f.root.path)) == ["generated", "stage", "staxrip-dolby-companion-writer"])
    }
    @Test func signedJSONExtremesAndStrictTypeGrammar() throws {
        typealias JSON = CompanionArchiveJSON
        let object = try JSON.object(Data("{\"min\":-9223372036854775808,\"max\":9223372036854775807,\"u\":18446744073709551615,\"flag\":false}".utf8), maximum: 65535)
        #expect(try JSON.signed(object, "min") == Int64.min && JSON.signed(object, "max") == Int64.max)
        #expect(try JSON.unsigned(object, "u", 0...UInt64.max) == UInt64.max)
        #expect(throws: (any Error).self) { try JSON.unsigned(object, "flag", 0...1) }
        for text in ["{}{}", "{\"a\":0,\"a\":0}", "{\"a\":00}", "{\"a\":-0}", "{\"a\":1.0}", "{\"a\":1e0}", "{\"a\":null}", "{\"a\":NaN}", "{\"a\":\"\\u0061\"}", "{\"a\":18446744073709551616}", "{\"a\":-9223372036854775809}", "{\"a\":truex}", "{\"a\":[[[[[0]]]]]}"] {
            #expect(throws: (any Error).self) { try JSON.object(Data(text.utf8), maximum: 65535) }
        }
    }
    @Test func boundedJSONLChunksLongWhitespaceRowsAndIncompleteOrOversizedRecords() throws {
        func reader(_ data: Data) throws -> CompanionOriginalIndexCheck.Rows {
            try .init(.init(sourceBytes: 1, source: { _, _ in Data() }, component: { _ in Data() }, checkpoint: {}, componentBytes: { _ in Int64(data.count) },
                componentRead: { _, offset, count in
                    #expect(count <= 65536)
                    return data.subdata(in: Int(offset)..<(Int(offset) + count))
                }))
        }
        // A second valid row crosses the fixed read-chunk boundary, without whole-file capture.
        let line = Data(repeating: 32, count: 65533) + Data("{}\n".utf8)
        let stream = try reader(line + Data("{\"i\":1}\n".utf8))
        let first = try #require(try stream.next()), second = try #require(try stream.next())
        #expect(first.isEmpty)
        #expect(try CompanionArchiveJSON.unsigned(second, "i", 0...1) == 1)
        #expect(try stream.next() == nil)
        for data in [Data("{}".utf8), Data("\n".utf8), Data(repeating: 32, count: 65536) + Data("{}\n".utf8)] {
            let bad = try reader(data); #expect(throws: (any Error).self) { try bad.next() }
        }
        #expect(throws: (any Error).self) { try CompanionArchiveJSON.object(Data(repeating: 32, count: (1 << 20) + 1), maximum: 1 << 20) }
    }
}
