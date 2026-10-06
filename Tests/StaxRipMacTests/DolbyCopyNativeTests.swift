import Foundation
import CryptoKit
import Testing
@testable import StaxRipMac

struct DolbyCopyNativeTests {
    private func element(_ id: UInt64, _ bytes: Data) -> Data {
        let width = (64 - id.leadingZeroBitCount + 7) / 8
        let identifier = Data((0..<width).reversed().map { UInt8(truncatingIfNeeded: id >> ($0 * 8)) })
        precondition(bytes.count < 16383)
        return identifier + Data([0x40 | UInt8(bytes.count >> 8), UInt8(truncatingIfNeeded: bytes.count)]) + bytes
    }
    private func nal(_ type: UInt8, layer: UInt8 = 0, body: UInt8 = 0x80) -> Data {
        Data([0,0,0,3,type << 1 | layer >> 5,(layer & 31) << 3 | 1,body])
    }
    private func fixture(source: Bool, packets: [Data]? = nil, mapping: Bool? = nil, relative: Int16 = -1, scale: UInt64 = 1_000_000, extra: Data = Data()) -> Data {
        var config = Data(repeating: 0, count: 23); config[0] = 1; config[21] = 3; config[22] = 3
        for type: UInt8 in [32,33,34] { config += Data([type,0,1,0,3]) + nal(type).suffix(3) }
        var track = element(0xd7, Data([1])) + element(0x83, Data([1])) + element(0x86, Data("V_MPEGH/ISO/HEVC".utf8)) + element(0x63a2, config)
        track += element(0x23e383, Data([0x02,0x7c,0x9b,0x55])) + extra
        if mapping ?? source {
            track += element(0x55ee, Data([1])) + element(0x41e4,
                element(0x41f0, Data([1])) + element(0x41e7, Data("dvcC".utf8)) + element(0x41ed, Data([1,0,14,55,96] + Array(repeating: 0, count: 19))))
        }
        let contents = packets ?? [nal(32) + nal(1) + (source ? nal(62) + nal(63) : Data())]
        let blocks = contents.reduce(Data()) { result, packet in
            let bits = UInt16(bitPattern: relative)
            return result + element(0xa3, Data([0x81,UInt8(bits >> 8),UInt8(truncatingIfNeeded: bits),0x80]) + packet)
        }
        let scaleBytes = Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: scale >> ($0 * 8)) })
        return element(0x1a45dfa3, element(0x4282, Data("matroska".utf8))) + element(0x18538067,
            element(0x1549a966, element(0x2ad7b1, scaleBytes)) + element(0x1654ae6b, element(0xae, track)) +
            element(0x1f43b675, element(0xe7, Data([0])) + blocks))
    }
    private func view(_ data: Data, checkpoint: @escaping () throws -> Void = {}) -> CompanionDiskCheck.ReadView {
        .init(sourceBytes: Int64(data.count), source: { offset, count in
            data.subdata(in: Int(offset)..<(Int(offset) + count))
        }, component: { _ in throw DolbyCopyNative.failure() }, checkpoint: checkpoint)
    }
    private func read(_ data: Data, _ role: DolbyCopyNative.Role) throws -> DolbyCopyNative.Receipt {
        try DolbyCopyNative.read(view(data), role: role, timeBase: HDRFraction("1/1000"))
    }
    @Test func sourceProjectionBindsWholePacketsAndPreservesInBandParametersAndSignedDuplicates() throws {
        let retained = nal(32) + nal(1), original = retained + nal(62) + nal(63)
        let source = try read(fixture(source: true, packets: [original,original]), .source)
        let output = try read(fixture(source: false, packets: [retained,retained]), .output)
        try source.requireCopy(output)
        #expect(source.packets == 2 && source.rpus == 2 && source.enhancement == 2)
        for (receipt, packet) in [(source, original),(output,retained)] {
            let parser = try DolbyCopyTiming.Stream(timeBase: HDRFraction("1/1000"))
            let hash = DolbyInspection.hex(SHA256.hash(data: packet))
            let line = "pts=-1|dts=-2|duration=41|size=\(packet.count)|data_hash=SHA256:\(hash)\n"
            parser.accept(Data((line + line).utf8)); try receipt.bind(parser.finish())
            let altered = try DolbyCopyTiming.Stream(timeBase: HDRFraction("1/1000"))
            altered.accept(Data((line + line.replacingOccurrences(of: "pts=-1", with: "pts=0")).utf8))
            #expect(throws: NativeExportError.self) { try receipt.bind(altered.finish()) }
        }
        let changed = try read(fixture(source: false, packets: [nal(32) + nal(1, body: 0x81),retained]), .output)
        #expect(throws: NativeExportError.self) { try source.requireCopy(changed) }
        #expect(throws: NativeExportError.self) { try source.requireCopy(read(fixture(source: false), .output)) }
    }
    @Test func combinedConsumerRequiresExplicitDTSAndDurationEquality() throws {
        let a = nal(32) + nal(1) + nal(62) + nal(63), b = nal(32) + nal(1)
        let source = try read(fixture(source: true), .source), output = try read(fixture(source: false), .output)
        func timing(_ data: Data, dts: Int64 = -2, duration: Int64 = 41) throws -> DolbyCopyTiming.Receipt {
            let parser = try DolbyCopyTiming.Stream(timeBase: HDRFraction("1/1000"))
            parser.accept(Data("pts=-1|dts=\(dts)|duration=\(duration)|size=\(data.count)|data_hash=SHA256:\(DolbyInspection.hex(SHA256.hash(data: data)))\n".utf8))
            return try parser.finish()
        }
        try DolbyCopyNative.verify(source: source, output: output, sourceTiming: timing(a), outputTiming: timing(b))
        for altered in [try timing(b, dts: -1), try timing(b, duration: 42)] {
            try output.bind(altered) // Payload/PTS binding alone cannot detect these changes.
            #expect(throws: NativeExportError.self) {
                try DolbyCopyNative.verify(source: source, output: output, sourceTiming: timing(a), outputTiming: altered)
            }
        }
    }
    @Test func outputDolbyMappingLayersMalformedNALsAndClockMismatchRefuse() throws {
        for data in [fixture(source: false, extra: element(0x537f, Data())), fixture(source: false, mapping: true), fixture(source: false, packets: [nal(1) + nal(62)]), fixture(source: false, packets: [nal(1) + nal(63)]), fixture(source: false, packets: [nal(1, layer: 1)]), fixture(source: false, packets: [Data([0,0,0,9,2,1])]), fixture(source: false, packets: [nal(32)]), fixture(source: false, scale: 1), Data(fixture(source: false).dropLast())] {
            #expect(throws: NativeExportError.self) { _ = try read(data, .output) }
        }
        #expect(throws: NativeExportError.self) { _ = try read(fixture(source: true, mapping: false), .source) }
        #expect(throws: NativeExportError.self) { _ = try read(fixture(source: true, packets: [nal(1) + nal(63)]), .source) }
        #expect(throws: NativeExportError.self) { _ = try read(fixture(source: true, packets: [nal(1) + nal(62) + nal(62) + nal(63)]), .source) }
    }
    private final class Uncertain: CompanionUnsettledOwnership {}
    @Test func cancellationReadErrorsAndShortReadsPropagateWithoutReceipt() throws {
        let data = fixture(source: true)
        #expect(throws: CancellationError.self) {
            _ = try DolbyCopyNative.read(view(data, checkpoint: { throw CancellationError() }), role: .source, timeBase: HDRFraction("1/1000"))
        }
        let uncertain = Uncertain()
        do {
            _ = try DolbyCopyNative.read(view(data, checkpoint: { throw uncertain }), role: .source, timeBase: HDRFraction("1/1000"))
            Issue.record("Expected same uncertainty")
        } catch let caught as Uncertain { #expect(caught === uncertain) }
        let short = CompanionDiskCheck.ReadView(sourceBytes: Int64(data.count), source: { _, _ in Data() }, component: { _ in Data() }, checkpoint: {})
        #expect(throws: NativeExportError.self) { _ = try DolbyCopyNative.read(short, role: .source, timeBase: HDRFraction("1/1000")) }
    }
}
