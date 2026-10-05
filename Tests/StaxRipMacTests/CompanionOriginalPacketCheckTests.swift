import Foundation
import CryptoKit
import Darwin
import SQLite3
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionOriginalPacketCheckTests {
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
    private func rows(_ path: URL) throws -> [[String: Any]] {
        try String(contentsOf: path, encoding: .utf8).split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }
    private func view(_ f: Fixture) throws -> CompanionDiskCheck.ReadView {
        let data = try Data(contentsOf: f.source)
        let track = try Data(contentsOf: f.stage.appendingPathComponent("original-track-entry-payload.bin"))
        let cfg = try Data(contentsOf: f.stage.appendingPathComponent("hevc-configuration.bin"))
        let raw = try Data(contentsOf: f.stage.appendingPathComponent("original-rpu.bin"))
        return readView(data, track: track, cfg: cfg, raw: raw)
    }
    @Test func actualWriterBothModesMatchNativePacketAndRawObservationsAgainstIndependentOracle() async throws {
        for mode in [Transaction.Retention.metadataOnly, .entireContainer] {
            let (f, c) = try await staged(mode); defer { f.cleanup() }
            let r = try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: c)
            let facts = try #require(r.originalPackets)
            #expect(facts.packets == 4 && facts.records == 5 && facts.enhancementNALs == 1)
            #expect(facts.originalEscapedRPUBytesMatch && facts.sourceEncodedPacketFramingReconstructed && !facts.originalPacketRPUSemanticsVerified)
            #expect(!r.originalMetadataSemanticsVerified)
            let audit = try rows(f.stage.appendingPathComponent("source-audit.jsonl"))
            let indexes = try rows(f.stage.appendingPathComponent("rpu-index.jsonl"))
            let v = try view(f), track = try CompanionOriginalTrackCheck.read(v)
            var packets: [CompanionOriginalPacketCheck.Packet] = [], rpus: [CompanionOriginalPacketCheck.RPU] = []
            let direct = try CompanionOriginalPacketCheck.read(v, track: track, observe: { observation in
                switch observation { case .packet(let p): packets.append(p); case .rpu(let p): rpus.append(p) }
            })
            let packetRows = audit.filter { $0["kind"] as? String == "packet" }
            #expect(packets.count == packetRows.count && rpus.count == indexes.count)
            for (p, row) in zip(packets, packetRows) {
                #expect(p.index == (row["index"] as? NSNumber)?.int64Value)
                #expect(p.ptsNS == (row["pts_ns"] as? NSNumber)?.int64Value)
                #expect(p.inputOffset == (row["input_byte_offset"] as? NSNumber)?.int64Value)
                #expect(p.blockOffset == (row["block_input_byte_offset"] as? NSNumber)?.int64Value)
                #expect(p.encodedBytes == (row["encoded_bytes"] as? NSNumber)?.int64Value && p.sha256 == row["sha256"] as? String)
                #expect(p.durationNS == (row["duration_ns"] as? NSNumber)?.uint64Value)
                #expect(p.invisible == (row["invisible"] as? Bool) && p.keyframe == (row["keyframe"] as? Bool) && p.discardable == (row["discardable"] as? Bool))
            }
            for (p, row) in zip(rpus, indexes) {
                #expect(p.index == (row["index"] as? NSNumber)?.int64Value && p.packetIndex == (row["packet_index"] as? NSNumber)?.int64Value)
                #expect(p.nalIndex == (row["nal_index"] as? NSNumber)?.int64Value && p.ptsNS == (row["pts_ns"] as? NSNumber)?.int64Value)
                #expect(p.inputOffset == (row["original_payload_offset"] as? NSNumber)?.int64Value)
                #expect(p.archiveDelimiterOffset == (row["archive_delimiter_offset"] as? NSNumber)?.int64Value)
                #expect(p.payloadBytes == (row["payload_bytes"] as? NSNumber)?.intValue && p.sha256 == row["payload_sha256"] as? String)
            }
            let spoolDirectory = f.root.appendingPathComponent("association-stage")
            try FileManager.default.createDirectory(at: spoolDirectory, withIntermediateDirectories:false, attributes:[.posixPermissions:0o700])
            try DolbyAssociationSpool.withSpool(in:spoolDirectory,sourceBytes:v.sourceBytes) { spool in
                let reconstructed = try CompanionOriginalPacketCheck.read(v,track:track,observe:{ try spool.append($0) })
                _ = try spool.finishSourcePass(expected:.init(packets:reconstructed.packets,rpus:reconstructed.records))
                for p in packets { #expect(try spool.packet(p.index) == p) }
                for r in rpus { #expect(try spool.rpu(r.index) == r) }
            }
            #expect(direct.packetSequenceSHA256 == audit.last?["packet_sequence_sha256"] as? String)
            #expect(direct.packetSequenceSHA256 == facts.packetSequenceSHA256)
            #expect(Set(packets.map(\.ptsNS)).count < packets.count && packets.contains { $0.ptsNS < 0 })
            #expect(zip(packets, packets.dropFirst()).contains { $0.ptsNS > $1.ptsNS })
            let oracle = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["python3",
                Self.repo.appendingPathComponent("Tools/DolbyCompanionCheck/native_transaction_fixture.py").path,
                "verify", f.source.path, f.stage.path, mode == .metadataOnly ? "metadata" : "full", f.executable.path,
                f.root.appendingPathComponent("staxrip-dolby-metadata-audit").path], stdoutLimit: 16384)
            try #require(oracle.status == 0 && !oracle.truncated) // Test-only independent original semantic oracle, never runtime admission.
            #expect(try await CompanionDiskCheck.verifyOriginalTrack(source: f.source, stage: f.stage, contents: c).originalPackets == nil)
            // Remove only this fixture's completed companion. The new native
            // pass must operate from the original source alone.
            try FileManager.default.removeItem(at:f.stage)
            let sourceStage=f.root.appendingPathComponent("source-only-spool")
            try FileManager.default.createDirectory(at:sourceStage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let original=try Data(contentsOf:f.source)
            let sourceResult=try await CompanionDiskCheck.spoolOriginalSource(source:f.source,in:sourceStage)
            #expect(sourceResult.packets.packetSequenceSHA256 == direct.packetSequenceSHA256)
            #expect(sourceResult.packets.packets == 4 && sourceResult.packets.records == 5 && sourceResult.packets.enhancementNALs == 1)
            #expect(!sourceResult.track.originalTrackAndConfigurationMatch && !sourceResult.packets.originalEscapedRPUBytesMatch)
            let storedPackets=try storedRows(sourceStage,table:"packets"), storedRPUs=try storedRows(sourceStage,table:"rpus")
            let expectedPackets: [[String?]]=packets.map { p in
                [String(p.index),String(p.ptsNS),String(p.inputOffset),String(p.blockOffset),String(p.encodedBytes),p.sha256,
                 p.durationNS.map { String($0,radix:16) },p.invisible ? "1" : "0",p.keyframe.map { $0 ? "1" : "0" },p.discardable.map { $0 ? "1" : "0" }]
            }
            let expectedRPUs: [[String?]]=rpus.map { r in
                [String(r.index),String(r.packetIndex),String(r.nalIndex),String(r.ptsNS),String(r.inputOffset),String(r.archiveDelimiterOffset),String(r.payloadBytes),r.sha256]
            }
            #expect(storedPackets == expectedPackets && storedRPUs == expectedRPUs)
            #expect(sourceResult.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data:original)))
        }
    }
    // Test-only reread of a finished disposable spool. Not a runtime importer.
    private func storedRows(_ directory: URL, table: String) throws -> [[String?]] {
        var db: OpaquePointer?
        // Test-only native descriptor path, preserving SQLite's no-follow flag.
        let fd=open(directory.appendingPathComponent(DolbyAssociationSpool.name).path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        try #require(fd >= 0); defer { #expect(Darwin.close(fd) == 0) }
        var pathBytes=[CChar](repeating:0,count:Int(MAXPATHLEN))
        try #require(fcntl(fd,F_GETPATH,&pathBytes) == 0)
        let path=String(cString:pathBytes)
        let opened=sqlite3_open_v2(path,&db,SQLITE_OPEN_READONLY | SQLITE_OPEN_NOFOLLOW,nil)
        defer { if let db { #expect(sqlite3_close(db) == SQLITE_OK) } }
        try #require(opened == SQLITE_OK)
        var query: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "SELECT * FROM " + table + " ORDER BY idx", -1, &query, nil) == SQLITE_OK)
        defer { #expect(sqlite3_finalize(query) == SQLITE_OK) }
        var rows: [[String?]] = []
        while true {
            let code = sqlite3_step(query)
            if code == SQLITE_DONE { break }
            try #require(code == SQLITE_ROW && rows.count < 10_000)
            rows.append((0..<sqlite3_column_count(query)).map { i in
                guard sqlite3_column_type(query,i) != SQLITE_NULL else { return nil }
                return String(cString:sqlite3_column_text(query,i))
            })
        }
        return rows
    }
    private func sourceOnlyView(_ data: Data) -> CompanionDiskCheck.ReadView {
        .init(sourceBytes:Int64(data.count),source:{ offset,count in
            guard offset >= 0, count >= 0, count <= 1 << 20, offset <= data.count,
                  Int64(count) <= Int64(data.count)-offset else { throw NativeExportError.invalid("Generated source bounds") }
            return data.subdata(in:Int(offset)..<(Int(offset)+count))
        },component:{ _ in throw NativeExportError.invalid("No retained components") },checkpoint:{})
    }
    private func generatedRoot(_ data: Data) throws -> (URL, URL, URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-observations-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let input=root.appendingPathComponent("generated.mkv"), stage=root.appendingPathComponent("spool")
        try data.write(to:input)
        try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        return (root,input,stage)
    }
    private func generatedSource(repeated: Int = 1) -> Data {
        let payload=nal(62,Data([0xaa,0,0,3,1,0xbb]),width:4)
        let cluster=element(0x1f43b675,element(0xe7,unsigned(0))+block(payload,relative:-10))
        return source(track(config()),clusters:Data((0..<repeated).flatMap { _ in Array(cluster) }))
    }
    @Test func sourceOnlyNativeWorkerPreservesAllWidthsSignedOrderAndNoCompanionClaims() async throws {
        for width in 1...4 { for unknown in [false,true] {
            let payload=nal(62,Data([0xaa,0,0,3,1,0xbb]),width:width)
            let blocks=block(payload,relative:-10)+block(payload,relative:-10)+element(0xa0,block(payload,relative:-20,flags:8,id:0xa1)+element(0x9b,unsigned(7)))
            let data=source(track(config(width)),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+blocks),unknown:unknown)
            let (root,input,stage)=try generatedRoot(data); defer { try? FileManager.default.removeItem(at:root) }
            let r=try await CompanionDiskCheck.spoolOriginalSource(source:input,in:stage)
            #expect(r.timestampScale == 1_000_000 && r.unknownSegment == unknown)
            #expect(r.sourceBytes == data.count && r.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data:data)))
            #expect(r.track.nalLengthBytes == width && !r.track.originalTrackAndConfigurationMatch)
            #expect(r.packets.packets == 3 && r.packets.records == 3 && !r.packets.originalEscapedRPUBytesMatch)
            #expect(!r.independentSourceFrameAssociationVerified && !r.editedPictureSemanticsVerified)
            let packets=try storedRows(stage,table:"packets"), rpus=try storedRows(stage,table:"rpus")
            #expect(packets.map { $0[1] } == ["-10000000","-10000000","-20000000"])
            #expect(packets[2][6] == String(7_000_000,radix:16) && packets[2][8] == nil && packets[2][9] == nil)
            #expect(rpus.map { $0[1] } == ["0","1","2"] && rpus.map { $0[0] } == ["0","1","2"])
            #expect(try Data(contentsOf:input) == data)
        } }
    }
    @Test func sourceOnlyWorkerPreservesSignedTimeExtremesAndUnsignedDuration() async throws {
        let cases: [(UInt64,Int16,UInt64,UInt64,Int64)] = [(0,-1,1 << 63,1,.min),(UInt64(Int64.max)+10,-10,1,UInt64.max,.max)]
        for (cluster,relative,scale,duration,pts) in cases {
            let payload=nal(62,Data([0xaa]),width:4)
            let group=element(0xa0,block(payload,relative:relative,flags:0,id:0xa1)+element(0x9b,unsigned(duration)))
            let data=source(track(config(),extra:element(0x23e383,unsigned(UInt64.max))),
                clusters:element(0x1f43b675,element(0xe7,unsigned(cluster))+group),
                info:element(0x1549a966,element(0x2ad7b1,unsigned(scale))),unknown:true)
            let (root,input,stage)=try generatedRoot(data); defer { try? FileManager.default.removeItem(at:root) }
            let result=try await CompanionDiskCheck.spoolOriginalSource(source:input,in:stage)
            let packets=try storedRows(stage,table:"packets"), rpus=try storedRows(stage,table:"rpus")
            #expect(packets.count == 1 && packets[0][1] == String(pts) && rpus[0][3] == String(pts))
            #expect(packets[0][6] == String(duration*scale,radix:16))
            #expect(result.timestampScale == scale && result.unknownSegment)
        }
    }
    @Test func sourceOnlyFramingDoesNotNeedComponentsAndRefusesForgedTrackSelection() throws {
        let data=generatedSource(), view=sourceOnlyView(data), original=try CompanionOriginalTrackCheck.readSource(view)
        let facts=try CompanionOriginalPacketCheck.readSource(view,track:original)
        #expect(facts.records == 1 && !facts.originalEscapedRPUBytesMatch)
        #expect(throws:(any Error).self) { try CompanionOriginalTrackCheck.read(view) }
        #expect(throws:(any Error).self) { try CompanionOriginalPacketCheck.read(view,track:original) }
        let changed=CompanionOriginalTrackCheck.Receipt(trackNumber:original.trackNumber,
            originalPayloadOffset:original.originalPayloadOffset,payloadBytes:original.payloadBytes,
            configurationBytes:original.configurationBytes,nalLengthBytes:original.nalLengthBytes,
            payloadSHA256:String(repeating:"0",count:64),configurationSHA256:original.configurationSHA256,
            originalTrackAndConfigurationMatch:false)
        #expect(throws:(any Error).self) { try CompanionOriginalPacketCheck.readSource(view,track:changed) }
    }
    @Test func sourceOnlyWorkerCancellationUnwindsAtActualReadAndFinalBoundary() async throws {
        for final in [false,true] {
            let data=generatedSource(), (root,input,stage)=try generatedRoot(data), gate=Gate()
            defer { try? FileManager.default.removeItem(at:root) }
            let task=Task {
                let boundary=final ? CompanionDiskCheck.Boundary(beforeFinal:{ gate.hold() }) :
                    CompanionDiskCheck.Boundary(originalTrackRead:{ offset,_ in if offset == 0 { gate.hold() } })
                return try await CompanionDiskCheck.$testBoundary.withValue(boundary) {
                    try await CompanionDiskCheck.spoolOriginalSource(source:input,in:stage)
                }
            }
            for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
            await #expect(throws:CancellationError.self) { try await task.value }
            #expect(try Data(contentsOf:input) == data)
            // Awaited refusal leaves a closed caller-owned partial database.
            let db=stage.appendingPathComponent(DolbyAssociationSpool.name)
            #expect(FileManager.default.fileExists(atPath:db.path))
            #expect(unlink(db.path) == 0)
        }
    }
    @Test func sourceOnlyFinalMutationAndConfiguredStorageFullCannotYieldReceipt() async throws {
        for variant in 0..<4 {
            let data=generatedSource(repeated:variant == 3 ? 1000 : 1), (root,input,stage)=try generatedRoot(data)
            defer { try? FileManager.default.removeItem(at:root) }
            let boundary=CompanionDiskCheck.Boundary(beforeFinal:{
                do {
                    switch variant {
                    case 0: let file=try FileHandle(forWritingTo:input); try file.write(contentsOf:Data([0xff])); try file.close()
                    case 1: try Data([0xff]).write(to:stage.appendingPathComponent("extra"))
                    case 2:
                        try FileManager.default.moveItem(at:stage.appendingPathComponent(DolbyAssociationSpool.name),to:stage.appendingPathComponent("retained.sqlite"))
                        try Data("prior".utf8).write(to:stage.appendingPathComponent(DolbyAssociationSpool.name))
                    default: Issue.record("storage-full source unexpectedly reached final boundary")
                    }
                } catch { Issue.record("Generated source/spool mutation failed") }
            })
            if variant == 3 {
                await #expect(throws:DolbyAssociationSpool.Failure.storageFull) {
                    try await CompanionDiskCheck.spoolOriginalSource(source:input,in:stage,limits:.init(pages:8))
                }
            } else {
                await CompanionDiskCheck.$testBoundary.withValue(boundary) {
                    await #expect(throws:(any Error).self) { try await CompanionDiskCheck.spoolOriginalSource(source:input,in:stage) }
                }
            }
            if variant != 0 { #expect(try Data(contentsOf:input) == data) }
            #expect(FileManager.default.fileExists(atPath:stage.path))
        }
    }
    @Test func sourceOnlyPreCancelUnsafeSourceAndExistingSpoolRefuseWithoutOverwrite() async throws {
        let data=generatedSource(), (root,input,stage)=try generatedRoot(data)
        defer { try? FileManager.default.removeItem(at:root) }
        let gate=Gate(), task=Task {
            gate.hold(); return try await CompanionDiskCheck.spoolOriginalSource(source:input,in:stage)
        }
        for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
        await #expect(throws:CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath:stage.path).isEmpty)
        let alias=root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:input)
        await #expect(throws:(any Error).self) { try await CompanionDiskCheck.spoolOriginalSource(source:alias,in:stage) }
        #expect(try FileManager.default.contentsOfDirectory(atPath:stage.path).isEmpty)
        let file=stage.appendingPathComponent(DolbyAssociationSpool.name)
        try Data("prior".utf8).write(to:file)
        await #expect(throws:(any Error).self) { try await CompanionDiskCheck.spoolOriginalSource(source:input,in:stage) }
        #expect(try Data(contentsOf:file) == Data("prior".utf8) && Data(contentsOf:input) == data)
    }
    @Test func rehashedRawForgeryPassesDiskIntegrityButFailsOriginalBytes() async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        let path = f.stage.appendingPathComponent("original-rpu.bin")
        var bytes = try Data(contentsOf: path); bytes[bytes.count - 1] ^= 1; try bytes.write(to: path)
        let members = c.members.map { m in m.name == "original-rpu.bin" ? ResultSetStaging.Member(name: m.name, byteCount: Int64(bytes.count), sha256: DolbyInspection.hex(SHA256.hash(data: bytes))) : m }
        let forged = Transaction.Contents(retention: c.retention, sourceID: c.sourceID, stageID: c.stageID, sourceBytes: c.sourceBytes,
            sourceSHA256: c.sourceSHA256, packets: c.packets, records: c.records, enhancementNALs: c.enhancementNALs, members: members)
        _ = try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: forged)
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: forged) }
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test func matchingNativePacketReceiptStillCannotAdmitFullTransaction() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }; let tool = try f.tool
        let original = try Data(contentsOf: f.source)
        await #expect(throws: (any Error).self) {
            try await Transaction.execute(source: f.source, in: f.root, destinationName: "result", retention: .metadataOnly,
                produce: { directory in try await Writer.run(tool: tool, source: f.source, stage: directory, retention: .metadataOnly).contents },
                verify: { directory, c in
                    let r = try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: directory, contents: c)
                    #expect(try #require(r.originalPackets).originalEscapedRPUBytesMatch)
                    return .init(contents: r.contents, originalComponentsMatchSource: r.originalMetadataSemanticsVerified,
                        sourceIdentityChecked: true, decodedFrameAssociation: "not-established", immutableSnapshot: false, stableImporter: false)
                })
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("result").path))
        #expect(try Data(contentsOf: f.source) == original)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: f.root.path)) == ["generated", "stage", "staxrip-dolby-companion-writer", "staxrip-dolby-metadata-audit"])
    }
    @Test(arguments: ["packets", "records", "enhancement"])
    func independentSourceCountsRefuseForgedProducerCounts(field: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        let forged = Transaction.Contents(retention: c.retention, sourceID: c.sourceID, stageID: c.stageID, sourceBytes: c.sourceBytes,
            sourceSHA256: c.sourceSHA256, packets: c.packets + (field == "packets" ? 1 : 0),
            records: c.records + (field == "records" ? 1 : 0), enhancementNALs: c.enhancementNALs + (field == "enhancement" ? 1 : 0), members: c.members)
        _ = try await CompanionDiskCheck.verifyOriginalTrack(source: f.source, stage: f.stage, contents: forged)
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: forged) }
    }
    @Test func rehashedIndexAndManifestAreExplicitlyUnqualifiedDespiteMatchingRawSource() async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        var members = c.members
        for name in ["rpu-index.jsonl", "manifest.json"] {
            let bytes = Data("{}\n".utf8); try bytes.write(to: f.stage.appendingPathComponent(name))
            members = members.map { m in m.name == name ? ResultSetStaging.Member(name: name, byteCount: Int64(bytes.count), sha256: DolbyInspection.hex(SHA256.hash(data: bytes))) : m }
        }
        let changed = Transaction.Contents(retention: c.retention, sourceID: c.sourceID, stageID: c.stageID, sourceBytes: c.sourceBytes,
            sourceSHA256: c.sourceSHA256, packets: c.packets, records: c.records, enhancementNALs: c.enhancementNALs, members: members)
        let partial = try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: changed)
        let packets = try #require(partial.originalPackets)
        #expect(!partial.originalMetadataSemanticsVerified && !packets.originalPacketRPUSemanticsVerified)
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>; private let signal: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value: 0)
        init() { let p = AsyncStream<Void>.makeStream(); entered = p.stream; signal = p.continuation }
        func hold() { signal.yield(()); signal.finish(); if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated packet read gate expired") } }
    }
    @Test func cancellationDuringActualPacketReadJoinsWorkerAndRetainsComponents() async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        let audit = try rows(f.stage.appendingPathComponent("source-audit.jsonl"))
        let first = try #require(audit.first { $0["kind"] as? String == "packet" })
        let offset = try #require(first["input_byte_offset"] as? NSNumber).int64Value
        let count = try #require(first["encoded_bytes"] as? NSNumber).intValue, gate = Gate()
        let task = Task {
            try await CompanionDiskCheck.$testBoundary.withValue(.init(originalTrackRead: { o, n in if o == offset && n == count { gate.hold() } })) {
                try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: c)
            }
        }
        for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).count == c.members.count)
    }
    @Test func finalRawComponentMutationRefusesAfterNativeScan() async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
            do { let h = try FileHandle(forWritingTo: f.stage.appendingPathComponent("original-rpu.bin")); try h.write(contentsOf: Data([0xfe])); try h.close() }
            catch { Issue.record("Generated mutation failed") }
        })) {
            await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalPackets(source: f.source, stage: f.stage, contents: c) }
        }
    }
    @Test func signedIntegerArithmeticHasExactExtremesWithoutFloatingPoint() throws {
        typealias Check = CompanionOriginalPacketCheck
        #expect(try Check.pts(cluster: 0, relative: -1, scale: 1 << 63) == Int64.min)
        #expect(try Check.pts(cluster: UInt64(Int64.max) + 10, relative: -10, scale: 1) == Int64.max)
        #expect(try Check.pts(cluster: 3, relative: -4, scale: 1_000_000) == -1_000_000)
        for (c, r, s) in [(UInt64.max, Int16(1), UInt64(1)), (UInt64(Int64.max), Int16(1), UInt64(1)),
                          (0, -2, 1 << 63), (2, 0, UInt64.max), (0, 0, 0)] {
            #expect(throws: (any Error).self) { try Check.pts(cluster: c, relative: r, scale: s) }
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
    private func config(_ width: Int = 4) -> Data { var d = Data(repeating: 0, count: 23); d[0] = 1; d[21] = UInt8(width - 1); return d }
    private func track(_ cfg: Data, extra: Data = Data()) -> Data {
        element(0xd7, Data([1])) + element(0x83, Data([1])) + element(0x86, Data("V_MPEGH/ISO/HEVC".utf8)) + element(0x63a2, cfg) + extra
    }
    private func nal(_ type: UInt8, _ data: Data, width: Int) -> Data {
        let n = data.count + 2
        return Data((0..<width).reversed().map { UInt8(truncatingIfNeeded: n >> (8 * $0)) }) + Data([type << 1, 1]) + data
    }
    private func block(_ data: Data, relative: Int16 = 0, flags: UInt8 = 0x80, number: UInt8 = 1, id: UInt64 = 0xa3) -> Data {
        let r = UInt16(bitPattern: relative)
        return element(id, Data([0x80 | number, UInt8(r >> 8), UInt8(r & 255), flags]) + data)
    }
    private func source(_ track: Data, clusters: Data, info: Data? = nil, suffix: Data = Data(), unknown: Bool = false, header: Data? = nil, extraTracks: Data = Data()) -> Data {
        let body = (info ?? element(0x1549a966, element(0x2ad7b1, unsigned(1_000_000)))) + element(0x1654ae6b, element(0xae, track) + extraTracks) + clusters
        return (header ?? element(0x1a45dfa3, element(0x4282, Data("matroska".utf8)))) + (unknown ? Data([0x18,0x53,0x80,0x67,0xff]) + body : element(0x18538067, body)) + suffix
    }
    private func readView(_ source: Data, track: Data, cfg: Data, raw: Data, checkpoint: @escaping () throws -> Void = {}) -> CompanionDiskCheck.ReadView {
        .init(sourceBytes: Int64(source.count), source: { offset, count in
            guard offset >= 0, count >= 0, count <= 1 << 20, offset <= source.count, Int64(count) <= Int64(source.count) - offset else { throw NativeExportError.invalid("Generated source read bound") }
            return source.subdata(in: Int(offset)..<(Int(offset) + count))
        }, component: { name in name == "hevc-configuration.bin" ? cfg : track }, checkpoint: checkpoint,
              componentBytes: { _ in Int64(raw.count) }, componentRead: { _, offset, count in
            guard offset >= 0, count >= 0, offset <= raw.count, Int64(count) <= Int64(raw.count) - offset else { throw NativeExportError.invalid("Generated raw read bound") }
            return raw.subdata(in: Int(offset)..<(Int(offset) + count))
        })
    }
    private func scan(_ data: Data, track: Data, cfg: Data, raw: Data, observe: @escaping (CompanionOriginalPacketCheck.Observation) throws -> Void = { _ in }) throws -> CompanionOriginalPacketCheck.Receipt {
        let v = readView(data, track: track, cfg: cfg, raw: raw)
        return try CompanionOriginalPacketCheck.read(v, track: CompanionOriginalTrackCheck.read(v), observe: observe)
    }
    @Test func allLengthWidthsPreserveSignedDuplicateAndNonmonotonicPacketOrderAndGroupDuration() throws {
        let escaped = Data([0xaa,0,0,3,1,0xbb]), raw = Data([0,0,0,1]) + escaped
        for width in 1...4 { for unknown in [false, true] {
            let cfg = config(width), t = track(cfg), payload = nal(62, escaped, width: width)
            let b = block(payload, relative: -10) + block(payload, relative: -10) +
                element(0xa0, block(payload, relative: -20, flags: 8, id: 0xa1) + element(0x9b, unsigned(7)))
            let data = source(t, clusters: element(0x1f43b675, element(0xe7, unsigned(0)) + b), suffix: element(0xec, Data([0xaa])), unknown: unknown)
            var packets: [CompanionOriginalPacketCheck.Packet] = [], records: [CompanionOriginalPacketCheck.RPU] = []
            let r = try scan(data, track: t, cfg: cfg, raw: raw + raw + raw) { o in
                switch o { case .packet(let p): packets.append(p); case .rpu(let p): records.append(p) }
            }
            #expect(packets.map(\.ptsNS) == [-10_000_000,-10_000_000,-20_000_000])
            #expect(packets[2].durationNS == 7_000_000 && packets[2].keyframe == nil && packets[2].discardable == nil && packets[2].invisible)
            #expect(records.map(\.packetIndex) == [0,1,2] && records.map(\.index) == [0,1,2])
            #expect(r.rawArchiveBytes == raw.count * 3 && r.peakRecordBytes == escaped.count && !r.originalPacketRPUSemanticsVerified)
        } }
    }
    @Test(arguments: ["lacing", "reserved", "unknown-track", "missing-time", "duplicate-time", "nested-cluster", "no-block", "duplicate-block", "duration-zero", "duration-overflow", "codec-state", "delay", "offset", "scale", "encodings", "operation", "zero-default", "info-late", "tracks-late", "trailing", "bad-doctype", "unknown-cluster", "empty-packet", "packet-bound", "nal-truncated", "nal-length", "nal-header", "nal-temporal", "rpu-layer", "rpu-empty", "rpu-bound", "raw-trailing", "raw-changed", "zero-scale", "missing-info", "duplicate-scale", "header-version", "duplicate-header", "group-reserved"])
    func unsupportedOrMalformedSourceAndRawAssociationRefuses(change: String) throws {
        let cfg = config(), escaped = Data([0xaa,0xbb]), raw = Data([0,0,0,1]) + escaped
        var t = track(cfg), p = nal(62, escaped, width: 4), b: Data?, timestamp = element(0xe7, unsigned(0))
        var extra = Data(), suffix = Data(), header: Data?, info: Data?, retained = raw
        switch change {
        case "lacing": b = block(p, flags: 0x82)
        case "reserved": b = block(p, flags: 0x90)
        case "unknown-track": b = block(p, number: 2)
        case "missing-time": timestamp = Data()
        case "duplicate-time": timestamp += timestamp
        case "nested-cluster": b = element(0x1f43b675, timestamp)
        case "no-block": b = element(0xa0, element(0x9b, unsigned(1)))
        case "duplicate-block": b = element(0xa0, block(p, flags: 0, id: 0xa1) + block(p, flags: 0, id: 0xa1))
        case "duration-zero", "duration-overflow", "codec-state":
            let group = block(p, flags: 0, id: 0xa1)
            b = element(0xa0, group + (change == "codec-state" ? element(0xa4, Data()) : element(0x9b, unsigned(change == "duration-zero" ? 0 : UInt64.max))))
        case "delay": t = track(cfg, extra: element(0x56aa, unsigned(1)))
        case "offset": t = track(cfg, extra: element(0x537f, Data([0xff])))
        case "scale": t = track(cfg, extra: element(0x23314f, Data([0x40,0,0,0])))
        case "encodings": t = track(cfg, extra: element(0x6d80, Data()))
        case "operation": t = track(cfg, extra: element(0xe2, Data()))
        case "zero-default": t = track(cfg, extra: element(0x23e383, unsigned(0)))
        case "info-late": extra = element(0x1549a966, Data())
        case "tracks-late": extra = element(0x1654ae6b, element(0xae, t))
        case "trailing": suffix = element(0x18538067, Data())
        case "bad-doctype": header = element(0x1a45dfa3, element(0x4282, Data("webm".utf8)))
        case "unknown-cluster": b = Data([0x1f,0x43,0xb6,0x75,0xff])
        case "empty-packet": p = Data()
        case "packet-bound": p = Data(repeating: 0, count: (16 << 20) + 1)
        case "nal-truncated": p = Data([0,0,0])
        case "nal-length": p[3] = 0xff
        case "nal-header": p[4] |= 0x80
        case "nal-temporal": p[5] = 0
        case "rpu-layer": p[5] = 9
        case "rpu-empty": p = nal(62, Data(), width: 4)
        case "rpu-bound": p = nal(62, Data(repeating: 0xaa, count: 65_537), width: 4)
        case "zero-scale": info = element(0x1549a966, element(0x2ad7b1, unsigned(0)))
        case "missing-info": info = Data()
        case "duplicate-scale": info = element(0x1549a966, element(0x2ad7b1, unsigned(1)) + element(0x2ad7b1, unsigned(1)))
        case "header-version": header = element(0x1a45dfa3, element(0x4282, Data("matroska".utf8)) + element(0x42f7, unsigned(2)))
        case "duplicate-header": header = element(0x1a45dfa3, element(0x4282, Data("matroska".utf8)) + element(0x4282, Data("matroska".utf8)))
        case "group-reserved": b = element(0xa0, block(p, flags: 0x80, id: 0xa1))
        case "raw-trailing": retained.append(0)
        default: retained[retained.count - 1] ^= 1
        }
        let cluster = element(0x1f43b675, timestamp + (b ?? block(p))) + extra
        let data = source(t, clusters: cluster, info: info, suffix: suffix, header: header)
        #expect(throws: (any Error).self) { try scan(data, track: t, cfg: cfg, raw: retained) }
        if !["raw-trailing","raw-changed"].contains(change) {
            let v=sourceOnlyView(data)
            #expect(throws:(any Error).self) { try CompanionOriginalPacketCheck.readSource(v,track:CompanionOriginalTrackCheck.readSource(v)) }
        }
    }
    @Test func otherDeclaredTrackPacketsDoNotBecomeVideoAndSelectedEnhancementIsCounted() throws {
        let cfg = config(), t = track(cfg), escaped = Data([0xaa]), raw = Data([0,0,0,1]) + escaped
        let audio = element(0xae, element(0xd7, Data([2])) + element(0x83, Data([2])))
        let other = element(0xa0, block(Data([0xff]), flags: 6, number: 2, id: 0xa1) + element(0xa4, Data()))
        let selected = block(nal(63, Data([0xbb]), width: 4) + nal(62, escaped, width: 4))
        let r = try scan(source(t, clusters: element(0x1f43b675, element(0xe7, unsigned(0)) + other + selected), extraTracks: audio), track: t, cfg: cfg, raw: raw)
        #expect(r.packets == 1 && r.records == 1 && r.enhancementNALs == 1)
    }
    @Test func largePicturePacketIsHashedInBoundedChunksBeforeMaximumEscapedRPU() throws {
        let cfg = config(), t = track(cfg), escaped = Data(repeating: 0xaa, count: 65_536)
        let payload = nal(1, Data(repeating: 0xbb, count: (2 << 20) + 17), width: 4) + nal(62, escaped, width: 4)
        let data = source(t, clusters: element(0x1f43b675, element(0xe7, unsigned(0)) + block(payload)))
        var packet: CompanionOriginalPacketCheck.Packet?, rpu: CompanionOriginalPacketCheck.RPU?
        let r = try scan(data, track: t, cfg: cfg, raw: Data([0,0,0,1]) + escaped) { o in
            switch o { case .packet(let p): packet = p; case .rpu(let p): rpu = p }
        }
        #expect(try #require(packet).sha256 == DolbyInspection.hex(SHA256.hash(data: payload)))
        #expect(try #require(rpu).nalIndex == 1 && r.peakRecordBytes == 65_536)
        #expect(r.packets == 1 && r.records == 1)
    }
    private func declaredVideo(_ unit: UInt64 = 0, explicit: Bool = false) -> Data {
        var fields = element(0xb0,unsigned(160)) + element(0xba,unsigned(96))
        fields += element(0x54cc,unsigned(2)) + element(0x54dd,unsigned(4)) + element(0x54bb,unsigned(6)) + element(0x54aa,unsigned(8))
        if explicit { fields += element(0x54b2,unsigned(unit)) + element(0x54b0,unsigned(128)) }
        return element(0xe0,fields)
    }
    @Test func actualNativeBothModeSourceVideoReadbackNeedsNoCompanionOrDecoder() async throws {
        for mode in [Transaction.Retention.metadataOnly, .entireContainer] {
            let (f,c) = try await staged(mode); defer { f.cleanup() }
            let original = try Data(contentsOf:f.source)
            let audit = try await CompanionDiskCheck.verifyOriginalAudit(source:f.source,stage:f.stage,contents:c)
            #expect(try #require(audit.originalAudit).originalDeclaredGeometryMatchesSource)
            let oracle = try await ToolRunner().run(executable:URL(fileURLWithPath:"/usr/bin/env"),arguments:["python3",
                Self.repo.appendingPathComponent("Tools/DolbyCompanionCheck/native_transaction_fixture.py").path,
                "verify",f.source.path,f.stage.path,mode == .metadataOnly ? "metadata":"full",f.executable.path,
                f.root.appendingPathComponent("staxrip-dolby-metadata-audit").path],stdoutLimit:16384)
            try #require(oracle.status == 0 && !oracle.truncated)
            // Only this generated, fully settled companion is removed. The new
            // source worker must reconstruct facts without its retained members.
            try FileManager.default.removeItem(at:f.stage)
            try FileManager.default.createDirectory(at:f.stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let r = try await CompanionDiskCheck.spoolOriginalSourceVideoDeclarations(source:f.source,in:f.stage)
            // Exact declarations of the fixed original Rust fixture, not SPS.
            #expect(r.declarations.width == 160 && r.declarations.height == 96 && r.declarations.crop == [0,0,1,0])
            #expect(r.declarations.display == [16,9] && r.declarations.unit == 3 && r.effectiveDisplayDeclarations == [16,9])
            #expect(r.declarations.presentFields == [0xb0,0xba,0x54bb,0x54b2,0x54b0,0x54ba])
            #expect(r.source.packets.packets == 4 && r.source.packets.records == 5 && r.source.packets.enhancementNALs == 1)
            #expect(!r.independentSourceFrameAssociationVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
            #expect(r.source.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data:original)))
            #expect(try Data(contentsOf:f.source) == original)
        }
    }
    @Test func sourceVideoPresenceUnknownFieldsAndBoundedStorageRemainExplicit() async throws {
        let pixels = element(0xb0,unsigned(160))+element(0xba,unsigned(96))
        for unit in UInt64(0)...4 {
            let video = element(0xe0,pixels+element(0x54b2,unsigned(unit))+element(0x54cc,unsigned(0))+element(0x9a,unsigned(0)))
            let data = source(track(config(),extra:video),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+block(nal(62,Data([0xaa]),width:4))))
            let (root,input,stage) = try generatedRoot(data); defer { try? FileManager.default.removeItem(at:root) }
            let r = try await CompanionDiskCheck.spoolOriginalSourceVideoDeclarations(source:input,in:stage)
            #expect(r.declarations.presentFields == [0xb0,0xba,0x54b2,0x54cc])
            #expect(r.declarations.display == [nil,nil] && r.declarations.crop == [0,0,0,0])
            #expect(r.effectiveDisplayDeclarations == (unit == 0 ? [160,96]:[nil,nil]))
        }
        for full in [false,true] {
            let packets = (0..<1000).reduce(into:Data()) { data,_ in data += block(nal(62,Data([0xaa]),width:4)) }
            let data = source(track(config(),extra:element(0xe0,pixels)),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+packets))
            let (root,input,stage) = try generatedRoot(data); defer { try? FileManager.default.removeItem(at:root) }
            if full {
                await #expect(throws:DolbyAssociationSpool.Failure.storageFull) {
                    try await CompanionDiskCheck.spoolOriginalSourceVideoDeclarations(source:input,in:stage,limits:.init(pages:8))
                }
            } else {
                await #expect(throws:(any Error).self) {
                    try await CompanionDiskCheck.spoolOriginalSourceVideoDeclarations(source:input,in:stage,limits:.init(records:1))
                }
            }
            #expect(try Data(contentsOf:input) == data)
        }
    }
    @Test func sourceVideoWorkerBindsDeclarationsPreservesSignedRowsAndUnitSpecificDefaults() async throws {
        for width in 1...4 { for unknown in [false,true] {
            let raw = nal(62,Data([0xaa,0,0,3,1,0xbb]),width:width)
            let packets = block(raw,relative:-10) + block(raw,relative:-10) + block(raw,relative:-20)
            let data = source(track(config(width),extra:declaredVideo()),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+packets),unknown:unknown)
            let (root,input,stage) = try generatedRoot(data); defer { try? FileManager.default.removeItem(at:root) }
            let r = try await CompanionDiskCheck.spoolOriginalSourceVideoDeclarations(source:input,in:stage)
            #expect(r.originalVideoDeclarationsBoundToSource && !r.independentSourceFrameAssociationVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
            #expect(r.declarations.width == 160 && r.declarations.height == 96 && r.declarations.crop == [2,4,6,8])
            #expect(r.declarations.unit == 0 && r.declarations.display == [nil,nil] && r.effectiveDisplayDeclarations == [154,82])
            #expect(r.declarations.presentFields == [0xb0,0xba,0x54cc,0x54dd,0x54bb,0x54aa])
            #expect(r.source.track.nalLengthBytes == width && r.source.unknownSegment == unknown && r.source.packets.packets == 3 && r.source.packets.records == 3)
            let rows = try storedRows(stage,table:"packets"); #expect(rows.map { $0[1] } == ["-10000000","-10000000","-20000000"])
            #expect(r.source.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data:data)))
            #expect(try Data(contentsOf:input) == data)
        } }
        for unit in UInt64(0)...4 {
            let data = source(track(config(),extra:declaredVideo(unit,explicit:true)+element(0x23e383,unsigned(UInt64.max))),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+block(nal(62,Data([0xaa]),width:4))))
            let (root,input,stage) = try generatedRoot(data); defer { try? FileManager.default.removeItem(at:root) }
            let r = try await CompanionDiskCheck.spoolOriginalSourceVideoDeclarations(source:input,in:stage)
            #expect(r.declarations.unit == unit && r.declarations.display == [128,nil] && r.declarations.duration == UInt64.max)
            #expect(r.effectiveDisplayDeclarations == (unit == 0 ? [128,82] : [128,nil]))
            #expect(r.declarations.presentFields.contains(0x54b2) && r.declarations.presentFields.contains(0x54b0) && !r.declarations.presentFields.contains(0x54ba))
            #expect(!r.independentSourceROIProvenanceVerified && !r.independentSourceFrameAssociationVerified)
        }
    }
    @Test func sourceVideoBindingRefusesPlausibleForgedTrackAndStaleGeometryPayload() throws {
        let video = declaredVideo(), raw = nal(62,Data([0xaa]),width:4)
        let data = source(track(config(),extra:video),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+block(raw)))
        let view = sourceOnlyView(data), original = try CompanionOriginalTrackCheck.readSource(view)
        let real = try CompanionOriginalAuditCheck.sourceDeclarations(view,track:original); #expect(real.width == 160)
        for field in ["number","offset","size","configuration-size","nal-width","payload-hash","configuration-hash"] {
            let forged = CompanionOriginalTrackCheck.Receipt(trackNumber:original.trackNumber+(field == "number" ? 1:0),
                originalPayloadOffset:original.originalPayloadOffset+(field == "offset" ? 1:0),payloadBytes:original.payloadBytes+(field == "size" ? 1:0),
                configurationBytes:original.configurationBytes+(field == "configuration-size" ? 1:0),nalLengthBytes:field == "nal-width" ? 3:original.nalLengthBytes,
                payloadSHA256:field == "payload-hash" ? String(repeating:"0",count:64):original.payloadSHA256,
                configurationSHA256:field == "configuration-hash" ? String(repeating:"0",count:64):original.configurationSHA256,originalTrackAndConfigurationMatch:false)
            #expect(throws:(any Error).self) { try CompanionOriginalAuditCheck.sourceDeclarations(view,track:forged) }
        }
        let changedVideo = element(0xe0,element(0xb0,unsigned(120))+element(0xba,unsigned(96))+element(0x54cc,unsigned(2))+element(0x54dd,unsigned(4))+element(0x54bb,unsigned(6))+element(0x54aa,unsigned(8)))
        let changed = source(track(config(),extra:changedVideo),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+block(raw)))
        let changedView = sourceOnlyView(changed)
        // Same encoded length/configuration and plausible geometry can pass the
        // old local declaration parser; selected payload/source binding refuses.
        let local = try CompanionOriginalAuditCheck.declarations(changedView,track:original); #expect(local.width == 120)
        #expect(throws:(any Error).self) { try CompanionOriginalAuditCheck.sourceDeclarations(changedView,track:original) }
        let repaired = try CompanionOriginalTrackCheck.readSource(changedView)
        #expect(try CompanionOriginalAuditCheck.sourceDeclarations(changedView,track:repaired).width == 120)
    }
    @Test func sourceVideoMalformedFieldsRefuseWhileNarrowerSourceAPIStaysNarrow() async throws {
        let pixels = element(0xb0,unsigned(160))+element(0xba,unsigned(96))
        let invalid = [Data(), element(0xe0,element(0xb0,unsigned(160))), element(0xe0,pixels+element(0xb0,unsigned(160))),
            element(0xe0,pixels+element(0x54b2,unsigned(5))), element(0xe0,pixels+element(0x54cc,unsigned(UInt64.max))+element(0x54dd,unsigned(1))),
            element(0xe0,pixels+element(0x54b0,unsigned(0))), element(0xe0,pixels)+element(0x23e383,unsigned(0))]
        for video in invalid {
            let data = source(track(config(),extra:video),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+block(nal(62,Data([0xaa]),width:4))))
            let (root,input,stage) = try generatedRoot(data); defer { try? FileManager.default.removeItem(at:root) }
            await #expect(throws:(any Error).self) { try await CompanionDiskCheck.spoolOriginalSourceVideoDeclarations(source:input,in:stage) }
            #expect(try Data(contentsOf:input) == data)
        }
        let (root,input,stage) = try generatedRoot(generatedSource()); defer { try? FileManager.default.removeItem(at:root) }
        let narrow = try await CompanionDiskCheck.spoolOriginalSource(source:input,in:stage)
        #expect(narrow.packets.packets == 1 && !narrow.independentSourceFrameAssociationVerified)
    }
    @Test func sourceVideoWorkerCancellationAndFinalSubstitutionCannotReturnBinding() async throws {
        let data = source(track(config(),extra:declaredVideo()),clusters:element(0x1f43b675,element(0xe7,unsigned(0))+block(nal(62,Data([0xaa]),width:4))))
        for phase in ["read","late","source-substitution","spool-extra"] {
            let (root,input,stage) = try generatedRoot(data), gate = Gate()
            defer { try? FileManager.default.removeItem(at:root) }
            let task = Task {
                try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
                    if phase == "late" { gate.hold() }
                    if phase == "source-substitution" {
                        do { try FileManager.default.moveItem(at:input,to:root.appendingPathComponent("original.mkv"));try data.write(to:input) }
                        catch { Issue.record("Generated source replacement failed") }
                    }
                    if phase == "spool-extra" { do { try Data("prior".utf8).write(to:stage.appendingPathComponent("extra")) } catch { Issue.record("Generated spool mutation failed") } }
                }, originalTrackRead: { offset,_ in if phase == "read" && offset == 0 { gate.hold() } })) {
                    try await CompanionDiskCheck.spoolOriginalSourceVideoDeclarations(source:input,in:stage)
                }
            }
            if ["read","late"].contains(phase) {
                for await _ in gate.entered { break };task.cancel();gate.release.signal()
                await #expect(throws:CancellationError.self) { try await task.value }
            } else { await #expect(throws:(any Error).self) { try await task.value } }
            #expect(try Data(contentsOf:input) == data)
        }
    }

}
