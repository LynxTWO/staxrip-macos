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
    /// Configuration prefix relationships only, not active picture selection.
    struct ParameterReferences: Sendable, Equatable {
        let geometry: GeometryPrefix
        let vpsNALSHA256, ppsNALSHA256: String
        let vpsID, vpsMaxSubLayersMinus1, ppsID, ppsSPSID: Int
        let dependentSliceSegmentsEnabled, outputFlagPresent: Bool
        let extraSliceHeaderBits: Int
        let vpsArrayComplete, spsArrayComplete, ppsArrayComplete: Bool
        let configurationReferencePrefixesAgree = true
        let completeParameterSetConformanceVerified = false
        let activePictureParameterSetSelectionVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Finite SPS coding-tree prefix; ordering records retain only present syntax.
    /// Complete SPS/VPS/level constraints, transform suffix and active use remain opaque.
    struct CodingTreePrefix: Sendable, Equatable {
        struct Ordering: Sendable, Equatable {
            let subLayer, bufferingMinus1, reorderPictures, latencyIncreasePlus1: Int
        }
        let parameters: ParameterReferences
        let pocLSBBits, prefixBitCount: Int
        let orderingInfoPresentForAllSubLayers: Bool
        let presentOrdering: [Ordering]
        let minCbLog2Size, ctbLog2Size, columns, rows, ctbs, addressBits: Int
        let completeSPSConformanceVerified = false
        let activePictureParameterSetSelectionVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    static func readSourceCodingTreePrefix(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt) throws -> CodingTreePrefix {
        try readConfigurationCodingTreePrefix(sourceConfiguration(view, track: track), checkpoint: view.checkpoint)
    }
    static func readConfigurationCodingTreePrefix(_ data: Data, checkpoint: () throws -> Void = {}) throws -> CodingTreePrefix {
        let parameters = try readConfigurationReferences(data, checkpoint: checkpoint)
        let entry = try arrays(data, checkpoint: checkpoint).filter { $0.type == 33 }
        guard entry.count == 1, entry[0].units.count == 1 else { throw refused() }
        var bits = Bits(data: try rbsp(entry[0].units[0], type: 33, checkpoint: checkpoint))
        try bits.skip(parameters.geometry.prefixBitCount)
        let poc = try bits.ue(maximum: 12) + 4, all = try bits.read(1) == 1
        let highest = parameters.geometry.maxSubLayersMinus1
        var ordering: [CodingTreePrefix.Ordering] = []
        for layer in (all ? 0 : highest)...highest {
            try checkpoint()
            // Explicit finite subset; not normative VPS/level DPB qualification.
            let buffering = try bits.ue(maximum: 15), reorder = try bits.ue(maximum: 15)
            let latency = try bits.ue(maximum: 65_534)
            guard reorder <= buffering else { throw refused() }
            if let previous = ordering.last {
                guard buffering >= previous.bufferingMinus1, reorder >= previous.reorderPictures else { throw refused() }
            }
            ordering.append(.init(subLayer: layer, bufferingMinus1: buffering,
                                  reorderPictures: reorder, latencyIncreasePlus1: latency))
        }
        let minCb = try bits.ue(maximum: 3) + 3, diff = try bits.ue(maximum: 3)
        let ctb = minCb + diff, geometry = parameters.geometry
        guard (4...6).contains(ctb), geometry.codedWidth.isMultiple(of: 1 << minCb),
              geometry.codedHeight.isMultiple(of: 1 << minCb), bits.position < bits.data.count*8 else { throw refused() }
        let size = 1 << ctb
        // Subtraction first avoids width+size-1 overflow; crop never changes this grid.
        let columns = (geometry.codedWidth-1)/size+1, rows = (geometry.codedHeight-1)/size+1
        let product = columns.multipliedReportingOverflow(by: rows)
        guard !product.overflow, product.partialValue > 0, product.partialValue <= 1 << 20 else { throw refused() }
        let count = product.partialValue
        let addressBits = count == 1 ? 0 : Int.bitWidth-(count-1).leadingZeroBitCount
        try checkpoint()
        return .init(parameters: parameters, pocLSBBits: poc, prefixBitCount: bits.position,
            orderingInfoPresentForAllSubLayers: all, presentOrdering: ordering,
            minCbLog2Size: minCb, ctbLog2Size: ctb, columns: columns, rows: rows,
            ctbs: count, addressBits: addressBits)
    }
    private static func refused() -> NativeExportError {
        .invalid("Original configuration SPS geometry prefix refused. Active picture geometry is not established.")
    }
    static func readSource(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt) throws -> GeometryPrefix {
        try readConfiguration(sourceConfiguration(view, track: track), checkpoint: view.checkpoint)
    }
    static func readSourceReferences(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt) throws -> ParameterReferences {
        try readConfigurationReferences(sourceConfiguration(view, track: track), checkpoint: view.checkpoint)
    }
    private static func sourceConfiguration(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt) throws -> Data {
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
        return configuration
    }
    private struct ArrayEntry {
        let type: UInt8, complete: Bool, reserved: Bool, units: [Data]
    }
    private static func arrays(_ data: Data, checkpoint: () throws -> Void) throws -> [ArrayEntry] {
        guard data.count <= 1 << 20 else { throw refused() }
        _ = try Track.configuration(data, checkpoint: checkpoint)
        var cursor = 23, entries: [ArrayEntry] = []
        for _ in 0..<Int(data[22]) {
            try checkpoint()
            let header = data[cursor], count = Int(data[cursor+1]) << 8 | Int(data[cursor+2])
            cursor += 3; var units: [Data] = []
            for _ in 0..<count {
                try checkpoint()
                let length = Int(data[cursor]) << 8 | Int(data[cursor+1]); cursor += 2
                units.append(data.subdata(in: cursor..<(cursor+length))); cursor += length
            }
            entries.append(.init(type: header & 63, complete: header & 128 != 0, reserved: header & 64 != 0, units: units))
        }
        return entries
    }
    /// Existing SPS-only subset keeps its admission; reference checking is explicit.
    static func readConfiguration(_ data: Data, checkpoint: () throws -> Void = {}) throws -> GeometryPrefix {
        let units = try arrays(data, checkpoint: checkpoint).filter { $0.type == 33 }.flatMap(\.units)
        guard units.count == 1, let nal = units.first else { throw refused() }
        return try geometry(data, nal: nal, checkpoint: checkpoint)
    }
    /// One base-layer VPS/SPS/PPS occurrence and matching reference prefixes only.
    /// Array-completeness bits are recorded, never update or activation authority.
    static func readConfigurationReferences(_ data: Data, checkpoint: () throws -> Void = {}) throws -> ParameterReferences {
        let entries = try arrays(data, checkpoint: checkpoint)
        func one(_ type: UInt8) throws -> ArrayEntry {
            let matches = entries.filter { $0.type == type }
            guard matches.count == 1, let entry = matches.first, !entry.reserved, entry.units.count == 1 else { throw refused() }
            return entry
        }
        let vps = try one(32), sps = try one(33), pps = try one(34)
        let geom = try geometry(data, nal: sps.units[0], checkpoint: checkpoint)
        var v = Bits(data: try rbsp(vps.units[0], type: 32, checkpoint: checkpoint))
        let vpsID = try v.read(4), internalBase = try v.read(1), availableBase = try v.read(1), layers = try v.read(6)
        let sub = try v.read(3), nesting = try v.read(1)
        guard internalBase == 1, availableBase == 1, layers == 0, sub <= 6,
              sub > 0 || nesting == 1, try v.read(16) == 65535,
              v.position < v.data.count*8, geom.vpsID == vpsID else { throw refused() }
        var p = Bits(data: try rbsp(pps.units[0], type: 34, checkpoint: checkpoint))
        let ppsID = try p.ue(maximum: 63), spsID = try p.ue(maximum: 15)
        let dependent = try p.read(1), output = try p.read(1), extra = try p.read(3)
        guard p.position < p.data.count*8, spsID == geom.spsID else { throw refused() }
        try checkpoint()
        return .init(geometry: geom, vpsNALSHA256: DolbyInspection.hex(SHA256.hash(data: vps.units[0])),
            ppsNALSHA256: DolbyInspection.hex(SHA256.hash(data: pps.units[0])), vpsID: vpsID,
            vpsMaxSubLayersMinus1: sub, ppsID: ppsID, ppsSPSID: spsID,
            dependentSliceSegmentsEnabled: dependent == 1, outputFlagPresent: output == 1,
            extraSliceHeaderBits: extra, vpsArrayComplete: vps.complete,
            spsArrayComplete: sps.complete, ppsArrayComplete: pps.complete)
    }
    struct FirstSlicePrefix: Sendable, Equatable {
        let nalType, ppsID, prefixBits, encodedPrefixBytes: Int
        let noOutputOfPriorPics: Bool?
        let prefixSHA256: String
        let firstSliceSegmentInPicture = true
        let completeSliceConformanceVerified = false
        let activePictureParameterSetSelectionVerified = false
    }
    /// Explicit TemporalId0 base-layer first-slice subset. Its first bit is one;
    /// at most 15 bits follow through PPS ID, so no EPB fits this two-byte prefix.
    /// Never run the whole-parameter-NAL unescaper over a picture buffer.
    static func readFirstSlicePrefix(header: Data, prefix: Data, payloadBytes: Int64) throws -> FirstSlicePrefix {
        guard header.count == 2, header[0] & 0x81 == 0, header[1] == 1,
              payloadBytes > 0, payloadBytes <= 1 << 40,
              prefix.count == Int(min(2, payloadBytes)) else { throw refused() }
        let type = Int(header[0] >> 1 & 63)
        guard (0...1).contains(type) || (6...9).contains(type) || (16...21).contains(type) else { throw refused() }
        var bits = Bits(data: prefix)
        guard try bits.read(1) == 1 else { throw refused() }
        let prior = (16...21).contains(type) ? try bits.read(1) == 1 : nil
        let ppsID = try bits.ue(maximum: 63)
        guard Int64(bits.position) < payloadBytes*8 else { throw refused() }
        return .init(nalType: type, ppsID: ppsID, prefixBits: bits.position,
            encodedPrefixBytes: prefix.count, noOutputOfPriorPics: prior,
            prefixSHA256: DolbyInspection.hex(SHA256.hash(data: header + prefix)))
    }
    /// Prefix declarations only. Nil records syntax absence, not an inferred value.
    struct SliceSegmentPrefix: Sendable, Equatable {
        let nalType, ppsID, prefixBits, encodedPrefixBytes: Int
        let firstSliceSegmentInPicture: Bool
        let noOutputOfPriorPics, dependentSliceSegment: Bool?
        let address: Int?
        let prefixSHA256: String
        let completeSliceConformanceVerified = false
        let activePictureParameterSetSelectionVerified = false
    }
    /// At most36 syntax bits plus one opaque following bit = five RBSP bytes.
    /// At most two EPBs can precede them: seven encoded payload bytes, never pictures.
    static func readSliceSegmentPrefix(header: Data, payloadBytes: Int64,
        grid: CodingTreePrefix, readByte: @escaping (Int) throws -> UInt8) throws -> SliceSegmentPrefix {
        guard header.count == 2, header[0] & 0x81 == 0, header[1] == 1,
              payloadBytes > 0, payloadBytes <= 1 << 40, (1...(1 << 20)).contains(grid.ctbs),
              grid.addressBits == (grid.ctbs == 1 ? 0 : Int.bitWidth-(grid.ctbs-1).leadingZeroBitCount) else { throw refused() }
        let type = Int(header[0] >> 1 & 63)
        guard (0...1).contains(type) || (6...9).contains(type) || (16...21).contains(type) else { throw refused() }
        var bits = SegmentBits(payloadBytes: payloadBytes, byte: readByte)
        let first = try bits.read(1) == 1
        let prior = (16...21).contains(type) ? try bits.read(1) == 1 : nil
        let pps = try bits.ppsID()
        guard pps == grid.parameters.ppsID else { throw refused() }
        let dependent: Bool?, address: Int?
        if first { dependent = nil; address = nil }
        else {
            dependent = grid.parameters.dependentSliceSegmentsEnabled ? try bits.read(1) == 1 : nil
            let value = try bits.read(grid.addressBits)
            guard value < grid.ctbs else { throw refused() }
            address = value
        }
        let count = bits.position
        _ = try bits.read(1) // Presence of an opaque following bit; no suffix semantics.
        return .init(nalType: type, ppsID: pps, prefixBits: count, encodedPrefixBytes: bits.encoded.count,
            firstSliceSegmentInPicture: first, noOutputOfPriorPics: prior,
            dependentSliceSegment: dependent, address: address,
            prefixSHA256: DolbyInspection.hex(SHA256.hash(data: header + bits.encoded)))
    }
    private struct SegmentBits {
        let payloadBytes: Int64, byte: (Int) throws -> UInt8
        var encoded = Data(), position = 0, zeros = 0, remaining = 0
        var current: UInt8 = 0
        mutating func encodedByte() throws -> UInt8 {
            guard encoded.count < 7, Int64(encoded.count) < payloadBytes else { throw refused() }
            let b = try byte(encoded.count); encoded.append(b); return b
        }
        mutating func rbspByte() throws -> UInt8 {
            var b = try encodedByte()
            if zeros == 2 {
                guard b >= 3 else { throw refused() }
                if b == 3 {
                    b = try encodedByte(); guard b <= 3 else { throw refused() }; zeros = 0
                }
            }
            zeros = b == 0 ? zeros+1 : 0
            return b
        }
        mutating func read(_ count: Int) throws -> Int {
            guard (0...20).contains(count), count <= 37-position else { throw refused() }
            var value = 0
            for _ in 0..<count {
                if remaining == 0 { current = try rbspByte(); remaining = 8 }
                remaining -= 1; value = value << 1 | Int(current >> remaining & 1); position += 1
            }
            return value
        }
        mutating func ppsID() throws -> Int {
            var zeros = 0
            while try read(1) == 0 { zeros += 1; guard zeros <= 6 else { throw refused() } }
            let value = (1 << zeros)-1 + (try read(zeros))
            guard value <= 63 else { throw refused() }; return value
        }
    }
    private static func rbsp(_ nal: Data, type: UInt8, checkpoint: () throws -> Void) throws -> Data {
        guard nal.count > 2, nal[0] == type << 1, nal[1] == 1, nal.last != 0 else { throw refused() }
        var result = Data(), zeros = 0, i = 2
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
            result.append(b); zeros = b == 0 ? zeros+1 : 0; i += 1
        }
        return result
    }
    private static func geometry(_ data: Data, nal: Data, checkpoint: () throws -> Void) throws -> GeometryPrefix {
        let rbsp = try rbsp(nal, type: 33, checkpoint: checkpoint)
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
