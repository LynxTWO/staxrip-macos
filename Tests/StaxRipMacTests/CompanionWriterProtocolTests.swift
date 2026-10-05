import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

struct CompanionWriterProtocolTests {
    typealias ProtocolReader = CompanionWriterProtocol
    typealias Transaction = OriginalCompanionTransaction
    private static let operation = String(repeating: "a", count: 32)
    private static let sourceID = Transaction.FileID(device: 1, inode: UInt64.max)
    private static let stageID = Transaction.FileID(device: 2, inode: 3)
    private static func reader(_ mode: Transaction.Retention = .metadataOnly, bytes: Int64 = 100,
                               source: Transaction.FileID = sourceID, stage: Transaction.FileID = stageID) throws -> ProtocolReader {
        try .init(operation: operation, retention: mode, sourceID: source, stageID: stage, sourceBytes: bytes)
    }
    private static func data(_ value: [String: Any]) throws -> Data { var d = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]); d.append(10); return d }
    private static func ready() throws -> Data { try data(["kind": "ready", "protocol": 1, "operation": operation]) }
    private static func staged(_ mode: Transaction.Retention = .metadataOnly) -> [String: Any] {
        ["kind": "staged", "protocol": 1, "operation": operation, "retention": mode == .metadataOnly ? "metadata" : "full",
         "source_file_id": [sourceID.device, sourceID.inode], "stage_file_id": [stageID.device, stageID.inode],
         "source_bytes": 100, "source_sha256": String(repeating: "b", count: 64), "packets": 1, "records": 2,
         "enhancement_nals": 1, "heap_limit": 67_108_864, "peak_heap_bytes": 20_000, "semantic_verification": false,
         "components": mode.limits.keys.sorted().map { ["name": $0, "bytes": 1, "sha256": String(repeating: "c", count: 64)] as [String: Any] }]
    }
    private static func started(_ mode: Transaction.Retention = .metadataOnly) throws -> ProtocolReader {
        let parser = try reader(mode); _ = try parser.accept(ready()); let response = try parser.authorizeStart()
        #expect(response == Data("start \(operation)\n".utf8)); return parser
    }
    @Test(arguments: [1, 2, 7, 256, 16384]) func boundedChunkPartitionsAdmitBothModes(chunk: Int) throws {
        for mode in [Transaction.Retention.metadataOnly, .entireContainer] {
            let parser = try Self.reader(mode)
            var events: [ProtocolReader.Event] = []
            for row in [try Self.ready(), try Self.data(Self.staged(mode))] {
                for offset in stride(from: 0, to: row.count, by: chunk) { events += try parser.accept(row.subdata(in: offset..<min(offset + chunk, row.count))) }
                if events.count == 1 { #expect(try parser.authorizeStart() == Data("start \(Self.operation)\n".utf8)) }
            }
            #expect(events.count == 2)
            let receipt = try parser.finish(status: 0)
            #expect(receipt.contents.sourceID == Self.sourceID && receipt.contents.stageID == Self.stageID)
            #expect(receipt.contents.records == 2 && receipt.contents.retention == mode)
            #expect(receipt.contents.members.count == mode.limits.count && receipt.peakTrackedHeap == 20_000)
            #expect(throws: (any Error).self) { try parser.finish(status: 0) }
        }
    }
    @Test func readinessAndStartAreNotSuccess() throws {
        let early = try Self.reader()
        #expect(throws: (any Error).self) { try early.authorizeStart() }
        #expect(throws: (any Error).self) { try early.accept(Self.ready()) }
        let awaiting = try Self.reader(); _ = try awaiting.accept(Self.ready())
        #expect(throws: (any Error).self) { try awaiting.accept(Self.data(Self.staged())) }
        let repeated = try Self.started()
        #expect(throws: (any Error).self) { try repeated.authorizeStart() }
        #expect(throws: (any Error).self) { try repeated.finish(status: 0) }
        let partial = try Self.reader(); _ = try partial.accept(Self.ready())
        #expect(throws: (any Error).self) { try partial.finish(status: 0) }
        let started = try Self.started()
        #expect(throws: (any Error).self) { try started.finish(status: 0) }
    }
    @Test func forgedRootFieldsTypesAndBoundsRefuse() throws {
        let changes: [(String, Any)] = [
            ("kind", "complete"), ("protocol", 2), ("protocol", true), ("operation", String(repeating: "d", count: 32)),
            ("retention", "full"), ("source_file_id", [1, 2]), ("source_file_id", [1, true]),
            ("stage_file_id", [2, 3, 4]), ("source_bytes", 101), ("source_bytes", 0),
            ("source_sha256", String(repeating: "B", count: 64)), ("source_sha256", "abc"),
            ("packets", 0), ("packets", 2_000_001), ("records", false), ("records", 2_000_001),
            ("enhancement_nals", 4_000_000_000_001 as Int64), ("heap_limit", 1),
            ("peak_heap_bytes", 0), ("peak_heap_bytes", 67_108_865), ("semantic_verification", true),
            ("semantic_verification", 0), ("unknown", 1), ("components", [])]
        for (key, value) in changes {
            var forged = Self.staged(); forged[key] = value
            let parser = try Self.started()
            #expect(throws: (any Error).self) { try parser.accept(Self.data(forged)) }
            #expect(throws: (any Error).self) { try parser.finish(status: 0) }
        }
        for key in Self.staged().keys {
            var forged = Self.staged(); forged.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try Self.started().accept(Self.data(forged)) }
        }
    }
    @Test func forgedComponentsRefuse() throws {
        for change in ["duplicate", "unknown", "escape", "zero", "maximum", "digest", "extra", "bool", "missing", "count"] {
            var forged = Self.staged(), members = forged["components"] as! [[String: Any]]
            switch change {
            case "duplicate": members[1] = members[0]
            case "unknown": members[0]["name"] = "other.bin"
            case "escape": members[0]["name"] = "../outside"
            case "zero": members[0]["bytes"] = 0
            case "maximum": members[0]["bytes"] = Int64(1 << 40) + 1
            case "digest": members[0]["sha256"] = String(repeating: "z", count: 64)
            case "extra": members[0]["unknown"] = true
            case "bool": members[0]["bytes"] = true
            case "missing": members[0].removeValue(forKey: "sha256")
            default: members.removeLast()
            }
            forged["components"] = members
            #expect(throws: (any Error).self) { try Self.started().accept(Self.data(forged)) }
        }
    }
    @Test func duplicateKeysAndNarrowJSONSyntaxRefuse() throws {
        let ready = String(decoding: try Self.ready(), as: UTF8.self)
        let invalid = [
            ready.replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":1,\"protocol\":1"),
            ready.replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":1.0"),
            ready.replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":1e0"),
            ready.replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":-1"),
            ready.replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":01"),
            ready.replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":18446744073709551616"),
            ready.replacingOccurrences(of: "ready", with: "r\\u0065ady"),
            "{\"x\":[[[[[[1]]]]]]}\n", "{\"x\":[" + Array(repeating: "1", count: 17).joined(separator: ",") + "]}\n",
            "{\"x\":null}\n", "{\"x\":\"é\"}\n", "{\"x\":true,}\n", "[1]\n", "{}{}\n"]
        for text in invalid { #expect(throws: (any Error).self) { try Self.reader().accept(Data(text.utf8)) } }
        let staged = String(decoding: try Self.data(Self.staged()), as: UTF8.self)
        let duplicate = staged.replacingOccurrences(of: "\"bytes\":1", with: "\"bytes\":1,\"bytes\":1")
        #expect(throws: (any Error).self) { try Self.started().accept(Data(duplicate.utf8)) }
    }
    @Test func incompleteExtraNonzeroAndOversizedResultsRefuse() throws {
        for suffix in [Data([10]), Data("x".utf8), try Self.ready(), try Self.data(Self.staged())] {
            let parser = try Self.started(); var wire = try Self.data(Self.staged()); wire.append(suffix)
            #expect(throws: (any Error).self) { try parser.accept(wire) }
            #expect(throws: (any Error).self) { try parser.finish(status: 0) }
        }
        let partial = try Self.started(); _ = try partial.accept(Self.data(Self.staged()).dropLast())
        #expect(throws: (any Error).self) { try partial.finish(status: 0) }
        let nonzero = try Self.started(); _ = try nonzero.accept(Self.data(Self.staged()))
        #expect(throws: (any Error).self) { try nonzero.finish(status: 1) }
        #expect(throws: (any Error).self) { try Self.reader().accept(Data(repeating: 32, count: 16384)) }
        let large = try Self.reader()
        _ = try large.accept(Data(repeating: 32, count: 16383))
        #expect(throws: (any Error).self) { try large.accept(Data([32])) }
        #expect(throws: (any Error).self) { try large.accept(Self.ready()) }
    }
    @Test func invalidExpectedContextRefusesAndDiagnosticsAreGeneric() throws {
        #expect(throws: (any Error).self) { try Self.reader(bytes: 0) }
        #expect(throws: (any Error).self) { try Self.reader(bytes: Int64(1 << 40) + 1) }
        #expect(throws: (any Error).self) { try ProtocolReader(operation: "secret", retention: .metadataOnly, sourceID: Self.sourceID, stageID: Self.stageID, sourceBytes: 1) }
        do { _ = try Self.reader().accept(Data("secret-source-name\n".utf8)); Issue.record("Malformed frame accepted") }
        catch { #expect(!error.localizedDescription.contains("secret-source-name")) }
    }
    @Test(.timeLimit(.minutes(2))) func actualGeneratedWriterRowsMatchNativeAdmissionAndDiskBothModes() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("companion-protocol-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let generated = root.appendingPathComponent("generated")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: false)
        let helpers = try await RustFixtureBuild.generate(.staged, at: generated, copiesIn: root)
        let source = generated.appendingPathComponent("generated-source.mkv"), original = try Data(contentsOf: source)
        var src = stat(); try #require(lstat(source.path, &src) == 0)
        let sourceID = Transaction.FileID(src)
        for (mode, modeName) in [(Transaction.Retention.metadataOnly, "metadata"), (.entireContainer, "full")] {
            let stage = root.appendingPathComponent(modeName)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            var st = stat(); try #require(lstat(stage.path, &st) == 0); let stageID = Transaction.FileID(st)
            let actual = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "python3", repo.appendingPathComponent("Tools/DolbyCompanionCheck/protocol_fixture.py").path,
                helpers.writer.path,
                modeName, source.path, stage.path, Self.operation,
                String(sourceID.device), String(sourceID.inode), String(stageID.device), String(stageID.inode)], stdoutLimit: 32768)
            try #require(actual.status == 0 && !actual.truncated)
            let rows = actual.stdout.split(separator: 10, omittingEmptySubsequences: false)
            try #require(rows.count == 3 && rows[2].isEmpty)
            let parser = try Self.reader(mode, bytes: Int64(original.count), source: sourceID, stage: stageID)
            var first = Data(rows[0]); first.append(10); _ = try parser.accept(first)
            #expect(try parser.authorizeStart() == Data("start \(Self.operation)\n".utf8))
            var second = Data(rows[1]); second.append(10); _ = try parser.accept(second)
            let receipt = try parser.finish(status: actual.status)
            #expect(receipt.contents.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data: original)))
            #expect(receipt.contents.packets == 1 && receipt.contents.records == 2)
            for member in receipt.contents.members {
                let data = try Data(contentsOf: stage.appendingPathComponent(member.name))
                #expect(Int64(data.count) == member.byteCount && DolbyInspection.hex(SHA256.hash(data: data)) == member.sha256)
            }
            #expect(try Data(contentsOf: source) == original)
            if mode == .entireContainer { #expect(try Data(contentsOf: stage.appendingPathComponent("original-container.mkv")) == original) }
        }
    }
}
