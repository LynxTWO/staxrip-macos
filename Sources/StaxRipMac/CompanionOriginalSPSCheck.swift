import Foundation
import CryptoKit

/// Original configuration declarations only. PTL constraints and SPS suffix are
/// opaque; this neither validates the complete SPS nor selects an active picture SPS.
enum CompanionOriginalSPSCheck {
    typealias Track = CompanionOriginalTrackCheck
    struct GeometryPrefix: Sendable, Equatable {
        let configurationSHA256, nalSHA256: String
        let nalBytes, rbspBytes, prefixBitCount: Int
        let vpsID, spsID, maxSubLayersMinus1, profileIDC: Int
        let codedWidth, codedHeight: Int
        let conformanceCrop: [Int]
        var visibleWidth: Int { codedWidth - conformanceCrop[0] - conformanceCrop[1] }
        var visibleHeight: Int { codedHeight - conformanceCrop[2] - conformanceCrop[3] }
        let completeSPSConformanceVerified = false
        let activePictureParameterSetSelectionVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    private static func refused() -> NativeExportError {
        .invalid("Original configuration SPS geometry prefix refused. Active picture geometry is not established.")
    }
    static func readSource(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt) throws -> GeometryPrefix {
        let actual = try Track.readSource(view)
        guard actual.trackNumber == track.trackNumber,
              actual.originalPayloadOffset == track.originalPayloadOffset,
              actual.payloadBytes == track.payloadBytes, actual.payloadSHA256 == track.payloadSHA256,
              actual.configurationBytes == track.configurationBytes,
              actual.configurationSHA256 == track.configurationSHA256,
              actual.nalLengthBytes == track.nalLengthBytes else { throw refused() }
        let walker = Track.Walker(view), end = actual.originalPayloadOffset + Int64(actual.payloadBytes)
        var cursor = actual.originalPayloadOffset, configuration: Data?
        while cursor < end {
            let e = try walker.element(cursor, end: end)
            if e.id == 0x63a2 {
                guard configuration == nil else { throw refused() }
                configuration = try walker.bytes(e)
            }
            cursor = e.end
        }
        guard let configuration, configuration.count == actual.configurationBytes,
              DolbyInspection.hex(SHA256.hash(data: configuration)) == actual.configurationSHA256 else { throw refused() }
        return try readConfiguration(configuration, checkpoint: view.checkpoint)
    }
    /// Finite base-layer 10-bit 4:2:0 prefix subset. Exactly one SPS occurrence,
    /// including duplicate byte-identical occurrences; never choose the first.
    static func readConfiguration(_ data: Data, checkpoint: () throws -> Void = {}) throws -> GeometryPrefix {
        guard data.count <= 1 << 20 else { throw refused() }
        _ = try Track.configuration(data, checkpoint: checkpoint)
        var cursor = 23, sps: Data?
        for _ in 0..<Int(data[22]) {
            try checkpoint()
            let type = data[cursor] & 63, count = Int(data[cursor+1]) << 8 | Int(data[cursor+2])
            cursor += 3
            for _ in 0..<count {
                try checkpoint()
                let length = Int(data[cursor]) << 8 | Int(data[cursor+1]); cursor += 2
                if type == 33 {
                    guard sps == nil else { throw refused() }
                    sps = data.subdata(in: cursor..<(cursor+length))
                }
                cursor += length
            }
        }
        guard let nal = sps, nal.count > 2, nal[0] == 0x42, nal[1] == 1,
              nal.last != 0 else { throw refused() }
        var rbsp = Data(), zeros = 0, i = 2
        while i < nal.count {
            try checkpoint()
            let b = nal[i]
            if zeros == 2 {
                guard b >= 3 else { throw refused() }
                if b == 3 {
                    guard i+1 < nal.count, nal[i+1] <= 3 else { throw refused() }
                    zeros = 0; i += 1; continue
                }
            }
            rbsp.append(b); zeros = b == 0 ? zeros+1 : 0; i += 1
        }
        var bits = Bits(data: rbsp)
        let vps = try bits.read(4), sub = try bits.read(3), nesting = try bits.read(1)
        guard sub <= 6, sub > 0 || nesting == 1 else { throw refused() }
        // H.265 7.3.3: fixed-width profile region, constraints retained opaque.
        _ = try bits.read(3); let profile = try bits.read(5)
        try bits.skip(80); _ = try bits.read(8)
        var presence: [(Int, Int)] = []
        for _ in 0..<sub { presence.append((try bits.read(1), try bits.read(1))) }
        if sub > 0 { for _ in sub..<8 { guard try bits.read(2) == 0 else { throw refused() } } }
        for (p,l) in presence {
            if p == 1 { try bits.skip(88) }
            if l == 1 { try bits.skip(8) }
        }
        let id = try bits.ue(maximum: 15), chroma = try bits.ue(maximum: 3)
        guard chroma == 1 else { throw refused() } // No separate colour-plane interpretation.
        let width = try bits.ue(maximum: 16_384), height = try bits.ue(maximum: 16_384)
        guard width >= 2, height >= 2, width.isMultiple(of: 2), height.isMultiple(of: 2) else { throw refused() }
        var crop = [Int](repeating: 0, count: 4)
        if try bits.read(1) == 1 {
            for j in 0..<4 { crop[j] = try bits.ue(maximum: 8192) * 2 }
        }
        guard crop[0] < width, crop[1] < width-crop[0], crop[2] < height, crop[3] < height-crop[2],
              try bits.ue(maximum: 8) == 2, try bits.ue(maximum: 8) == 2,
              bits.position < rbsp.count*8 else { throw refused() }
        try checkpoint()
        return .init(configurationSHA256: DolbyInspection.hex(SHA256.hash(data: data)),
            nalSHA256: DolbyInspection.hex(SHA256.hash(data: nal)), nalBytes: nal.count,
            rbspBytes: rbsp.count, prefixBitCount: bits.position, vpsID: vps, spsID: id,
            maxSubLayersMinus1: sub, profileIDC: profile, codedWidth: width, codedHeight: height,
            conformanceCrop: crop)
    }
    private struct Bits {
        let data: Data
        var position = 0
        mutating func read(_ count: Int) throws -> Int {
            guard (0...16).contains(count), count <= data.count*8-position else { throw refused() }
            var value = 0
            for _ in 0..<count {
                value = value << 1 | Int(data[position/8] >> (7-position%8) & 1); position += 1
            }
            return value
        }
        mutating func skip(_ count: Int) throws {
            guard count >= 0, count <= data.count*8-position else { throw refused() }; position += count
        }
        mutating func ue(maximum: Int) throws -> Int {
            var zeros = 0
            while try read(1) == 0 {
                zeros += 1
                guard zeros <= 15 else { throw refused() }
            }
            let value = (1 << zeros)-1 + (try read(zeros))
            guard value <= maximum else { throw refused() }; return value
        }
    }
}
