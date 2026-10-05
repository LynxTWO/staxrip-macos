import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionOriginalTrackCheckTests {
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
            let helpers = try await RustFixtureBuild.generate(.staged, at: generated, copiesIn: root)
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
    @Test func actualNativeWriterBothModesMatchSelectedOriginalTrackWithoutClaimingFullSemantics() async throws {
        for mode in [Transaction.Retention.metadataOnly, .entireContainer] {
            let (f, c) = try await staged(mode); defer { f.cleanup() }
            let original = try Data(contentsOf: f.source)
            let r = try await CompanionDiskCheck.verifyOriginalTrack(source: f.source, stage: f.stage, contents: c)
            let track = try #require(r.originalTrack)
            #expect(track.originalTrackAndConfigurationMatch && !track.originalPacketRPUSemanticsVerified)
            #expect(!r.originalMetadataSemanticsVerified && r.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
            let payload = try Data(contentsOf: f.stage.appendingPathComponent("original-track-entry-payload.bin"))
            let config = try Data(contentsOf: f.stage.appendingPathComponent("hevc-configuration.bin"))
            #expect(track.payloadBytes == payload.count && track.configurationBytes == config.count)
            #expect(original.subdata(in: Int(track.originalPayloadOffset)..<(Int(track.originalPayloadOffset) + payload.count)) == payload)
            #expect(track.payloadSHA256 == DolbyInspection.hex(SHA256.hash(data: payload)))
            #expect(track.configurationSHA256 == DolbyInspection.hex(SHA256.hash(data: config)))
            #expect(track.trackNumber == 1 && track.nalLengthBytes == 4)
            let adapter = Self.repo.appendingPathComponent("Tools/DolbyCompanionCheck/native_transaction_fixture.py")
            let reader = f.root.appendingPathComponent("staxrip-dolby-metadata-audit")
            let oracle = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["python3", adapter.path,
                "verify", f.source.path, f.stage.path, mode == .metadataOnly ? "metadata" : "full", f.executable.path, reader.path], stdoutLimit: 16384)
            try #require(oracle.status == 0 && !oracle.truncated) // Explicit test-only original semantic oracle.
            #expect(try Data(contentsOf: f.source) == original)
            #expect(try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: c).originalTrack == nil)
        }
    }
    @Test(arguments: ["original-track-entry-payload.bin", "hevc-configuration.bin"])
    func rehashedSubstitutedComponentsPassIntegrityButRefuseOriginalMatch(name: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        let target = f.stage.appendingPathComponent(name)
        var bytes = try Data(contentsOf: target); bytes[bytes.count - 1] ^= 1; try bytes.write(to: target)
        let changed = c.members.map { m in m.name == name ? ResultSetStaging.Member(name: name, byteCount: Int64(bytes.count),
            sha256: DolbyInspection.hex(SHA256.hash(data: bytes))) : m }
        let forged = Transaction.Contents(retention: c.retention, sourceID: c.sourceID, stageID: c.stageID,
            sourceBytes: c.sourceBytes, sourceSHA256: c.sourceSHA256, packets: c.packets, records: c.records,
            enhancementNALs: c.enhancementNALs, members: changed)
        _ = try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: forged)
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalTrack(source: f.source, stage: f.stage, contents: forged) }
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test func matchingPartialOriginalTrackCannotAdmitNativeTransaction() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }
        let original = try Data(contentsOf: f.source), tool = try f.tool
        let prior = f.root.appendingPathComponent("prior-result"); try Data("keep prior generated result".utf8).write(to: prior)
        await #expect(throws: (any Error).self) {
            try await Transaction.execute(source: f.source, in: f.root, destinationName: "result", retention: .metadataOnly,
                produce: { directory in try await Writer.run(tool: tool, source: f.source, stage: directory, retention: .metadataOnly).contents },
                verify: { directory, c in
                    let partial = try await CompanionDiskCheck.verifyOriginalTrack(source: f.source, stage: directory, contents: c)
                    #expect(try #require(partial.originalTrack).originalTrackAndConfigurationMatch)
                    return .init(contents: partial.contents, originalComponentsMatchSource: partial.originalMetadataSemanticsVerified,
                        sourceIdentityChecked: true, decodedFrameAssociation: "not-established", immutableSnapshot: false, stableImporter: false)
                })
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("result").path))
        #expect(try Data(contentsOf: prior) == Data("keep prior generated result".utf8))
        #expect(try Data(contentsOf: f.source) == original)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: f.root.path)) == ["generated", "stage", "staxrip-dolby-companion-writer", "staxrip-dolby-metadata-audit", "prior-result"])
    }

    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>; private let signal: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value: 0)
        init() { let p = AsyncStream<Void>.makeStream(); entered = p.stream; signal = p.continuation }
        func hold() { signal.yield(()); signal.finish(); if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated native track read gate expired") } }
    }
    @Test func cancellationDuringActualNativeEBMLReadSettlesWithoutRemovingComponents() async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }; let gate = Gate()
        let task = Task {
            try await CompanionDiskCheck.$testBoundary.withValue(.init(originalTrackRead: { offset, _ in if offset == 0 { gate.hold() } })) {
                try await CompanionDiskCheck.verifyOriginalTrack(source: f.source, stage: f.stage, contents: c)
            }
        }
        for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).count == c.members.count)
    }
    @Test(arguments: ["source", "stage", "component"])
    func finalObservationsStillRefuseChangesAfterNativeTrackCheck(change: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
            do {
                if change == "stage" {
                    try FileManager.default.moveItem(at: f.stage, to: f.root.appendingPathComponent("retained-stage"))
                    try FileManager.default.createDirectory(at: f.stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                } else {
                    let target = change == "source" ? f.source : f.stage.appendingPathComponent("hevc-configuration.bin")
                    let h = try FileHandle(forWritingTo: target); try h.write(contentsOf: Data([0xfe])); try h.close()
                }
            } catch { Issue.record("Generated native track mutation failed") }
        })) {
            await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verifyOriginalTrack(source: f.source, stage: f.stage, contents: c) }
        }
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    private func element(_ id: UInt64, _ payload: Data) -> Data {
        var value = id, idBytes: [UInt8] = []
        repeat { idBytes.insert(UInt8(value & 255), at: 0); value >>= 8 } while value != 0
        var width = 1
        while UInt64(payload.count) >= (UInt64(1) << (7 * width)) - 1 { width += 1 }
        let length = UInt64(payload.count) | UInt64(1) << (7 * width)
        let sizes = (0..<width).reversed().map { UInt8((length >> (8 * $0)) & 255) }
        return Data(idBytes + sizes) + payload
    }
    private func config() -> Data {
        var data = Data(repeating: 0, count: 23); data[0] = 1; data[21] = 3; data[22] = 1
        return data + Data([0xa0, 0, 1, 0, 3, 0x40, 1, 0xaa]) // Structurally valid type32 NAL, not decoded VPS proof.
    }
    private func entry(number: UInt8 = 1, codec: String = "V_MPEGH/ISO/HEVC", configuration: Data? = nil, extra: Data = Data()) -> Data {
        element(0xd7, Data([number])) + element(0x83, Data([1])) + element(0x86, Data(codec.utf8)) +
            element(0x63a2, configuration ?? config()) + element(0xe0, element(0xb0, Data([2])) + element(0xba, Data([2]))) + extra
    }
    private func source(_ tracks: Data, prefix: Data = Data(), suffix: Data = Data(), unknownSegment: Bool = false) -> Data {
        let header = element(0x1a45dfa3, element(0x4282, Data("matroska".utf8)))
        let body = prefix + element(0x1654ae6b, tracks) + suffix + element(0x1f43b675, Data())
        return header + (unknownSegment ? Data([0x18,0x53,0x80,0x67,0xff]) + body : element(0x18538067, body))
    }
    private func read(_ source: Data, track: Data, configuration: Data, checkpoint: @escaping () throws -> Void = {}) throws -> CompanionOriginalTrackCheck.Receipt {
        try CompanionOriginalTrackCheck.read(.init(sourceBytes: Int64(source.count), source: { offset, count in
            guard offset >= 0, count >= 0, count <= 1 << 20, offset + Int64(count) <= source.count else { throw NativeExportError.invalid("Generated source read bound") }
            return source.subdata(in: Int(offset)..<(Int(offset) + count))
        }, component: { name in name == "hevc-configuration.bin" ? configuration : track }, checkpoint: checkpoint))
    }
    @Test func finiteAndUnknownSegmentsWithOpaqueFieldsMatchExactly() throws {
        let track = entry(extra: element(0x536e, Data("generated embedded name".utf8)))
        for unknown in [false, true] {
            let data = source(element(0xae, track), prefix: element(0xec, Data([0xaa])), unknownSegment: unknown)
            let result = try read(data, track: track, configuration: config())
            #expect(result.trackNumber == 1 && result.nalLengthBytes == 4 && !result.originalPacketRPUSemanticsVerified)
            #expect(data.subdata(in: Int(result.originalPayloadOffset)..<(Int(result.originalPayloadOffset) + track.count)) == track)
        }
    }
    @Test func nonVideoTracksAreNotMistakenForSelectedOriginalAndTrackCountIsBounded() throws {
        func audio(_ number: Int) -> Data {
            let numeric = number < 256 ? Data([UInt8(number)]) : Data([UInt8(number >> 8), UInt8(number & 255)])
            return element(0xae, element(0xd7, numeric) + element(0x83, Data([2])) + element(0x86, Data("A_PCM/INT/LIT".utf8)))
        }
        let track = entry()
        let r = try read(source(audio(2) + element(0xae, track) + audio(3)), track: track, configuration: config())
        #expect(r.trackNumber == 1)
        let many = (2...258).reduce(into: Data()) { data, n in data.append(audio(n)) } + element(0xae, track)
        #expect(throws: (any Error).self) { try read(source(many), track: track, configuration: config()) }
    }
    @Test func emptyRPUArrayAndAllNativeLengthWidthsRemainStructurallySupported() throws {
        for width in 1...4 {
            var cfg = Data(repeating: 0, count: 23); cfg[0] = 1; cfg[21] = UInt8(width - 1); cfg[22] = 1
            cfg.append(contentsOf: [0xbe, 0, 0]) // Empty type62 array retains no RPU; matches existing reader semantics.
            let track = entry(configuration: cfg)
            #expect(try read(source(element(0xae, track)), track: track, configuration: cfg).nalLengthBytes == width)
        }
    }
    @Test(arguments: ["critical", "tracks", "video", "number", "codec", "missing", "unknown-child", "truncated", "parent", "zero-id"])
    func ambiguousOrMalformedOriginalSelectionRefuses(change: String) throws {
        let track = entry(); var data = source(element(0xae, track))
        switch change {
        case "critical": data = source(element(0xae, entry(extra: element(0xd7, Data([1])))))
        case "tracks": data = source(element(0xae, track), suffix: element(0x1654ae6b, element(0xae, track)))
        case "video": data = source(element(0xae, track) + element(0xae, entry(number: 2)))
        case "number": data = source(element(0xae, track) + element(0xae, track))
        case "codec": data = source(element(0xae, entry(codec: "V_AV1")))
        case "missing": data = source(Data())
        case "unknown-child": data = source(element(0xae, track), prefix: Data([0xec,0xff]))
        case "truncated": data.removeLast()
        case "parent": data = Data([0x1a,0x45,0xdf,0xa3,0xfe,0])
        default: data[0] = 0
        }
        #expect(throws: (any Error).self) { try read(data, track: track, configuration: config()) }
    }
    @Test(arguments: ["version", "short", "length", "type", "forbidden", "temporal", "rpu", "trailing", "array-count"])
    func malformedOriginalHVCCRefusesEvenWhenRetainedBytesMatch(change: String) throws {
        var cfg = config()
        switch change {
        case "version": cfg[0] = 2
        case "short": cfg = Data([1])
        case "length": cfg[27] = 0xff
        case "type": cfg[28] = 0x42
        case "forbidden": cfg[28] = 0xc0
        case "temporal": cfg[29] = 0
        case "rpu": cfg[23] = 0xbe
        case "trailing": cfg.append(0)
        default: cfg[22] = 2
        }
        let track = entry(configuration: cfg)
        #expect(throws: (any Error).self) { try read(source(element(0xae, track)), track: track, configuration: cfg) }
    }
    @Test func elementAndTrackBoundsRefuseWithoutUnboundedCapture() throws {
        let track = entry()
        let many = Data(repeating: 0xec, count: 0) + (0..<100_000).reduce(into: Data()) { data, _ in data.append(contentsOf: [0xec, 0x80]) }
        #expect(throws: (any Error).self) { try read(source(element(0xae, track), prefix: many), track: track, configuration: config()) }
        let large = entry(extra: element(0xec, Data(repeating: 0, count: 1 << 20)))
        #expect(throws: (any Error).self) { try read(source(element(0xae, large)), track: large, configuration: config()) }
    }
}
