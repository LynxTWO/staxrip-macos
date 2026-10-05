import Foundation
import CryptoKit

/// Independent source framing and exact escaped raw-RPU origin, not full metadata
/// semantics. Stored index/audit/manifest and decoded associations remain unchecked.
enum CompanionOriginalPacketCheck {
    typealias Track = CompanionOriginalTrackCheck
    typealias Element = Track.Element
    struct Packet: Sendable, Equatable {
        let index: Int64, inputOffset: Int64, blockOffset: Int64, ptsNS: Int64
        let durationNS: UInt64?
        let invisible: Bool, keyframe: Bool?, discardable: Bool?
        let encodedBytes: Int64, sha256: String
    }
    struct RPU: Sendable, Equatable {
        let index: Int64, packetIndex: Int64, nalIndex: Int64, ptsNS: Int64
        let inputOffset: Int64, archiveDelimiterOffset: Int64, payloadBytes: Int
        let sha256: String
    }
    enum Observation: Sendable { case packet(Packet), rpu(RPU) }
    struct Receipt: Sendable {
        let packets: Int64, records: Int64, enhancementNALs: Int64
        let peakRecordBytes: Int, rawArchiveBytes: Int64, packetSequenceSHA256: String
        let originalEscapedRPUBytesMatch: Bool
        let sourceEncodedPacketFramingReconstructed = true
        let originalPacketRPUSemanticsVerified = false
    }
    struct VCLReference: Sendable, Equatable {
        let packetIndex, nalIndex, ptsNS, nalOffset, nalBytes: Int64
        let prefix: CompanionOriginalSPSCheck.FirstSlicePrefix
    }
    struct VCLSummary: Sendable, Equatable {
        let prefixes, irapPrefixes: Int64
        let peakPrefixBytes: Int
        let sequenceSHA256: String
        let sourceFirstSlicePPSReferencesAgree = true
        let completeSliceConformanceVerified = false
        let activePictureParameterSetSelectionVerified = false
    }
    struct VCLReadback: Sendable {
        let packets: Receipt
        let parameters: CompanionOriginalSPSCheck.ParameterReferences
        let summary: VCLSummary
    }
    /// Fresh configuration binding and single first-slice VCL per selected packet.
    /// Observations are streamed; production readback holds no picture/row collection.
    static func readSourceVCLReferences(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt,
        begin: @escaping (UInt64, Bool) throws -> Void = { _, _ in },
        observe: @escaping (Observation) throws -> Void = { _ in },
        observeVCL: @escaping (VCLReference) throws -> Void = { _ in }) throws -> VCLReadback {
        let references = try CompanionOriginalSPSCheck.readSourceReferences(view, track: track)
        let scan = Scanner(view, track, observe, begin, compareRetained: false,
            refuseInBandParameterSets: true, references: references, observeVCL: observeVCL)
        let packets = try scan.read()
        guard scan.vcls == packets.packets else { throw refused() }
        return .init(packets: packets, parameters: references,
            summary: .init(prefixes: scan.vcls, irapPrefixes: scan.iraps,
                peakPrefixBytes: scan.prefixPeak,
                sequenceSHA256: DolbyInspection.hex(scan.vclSequence.finalize())))
    }
    private struct Block {
        let payload: Int64, end: Int64, blockOffset: Int64, pts: Int64
        let invisible: Bool, keyframe: Bool?, discardable: Bool?
    }
    private static func refused() -> NativeExportError { .invalid("Original packet/raw-RPU verification refused. No complete semantic receipt.") }
    static func read(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt,
                     begin: @escaping (UInt64, Bool) throws -> Void = { _, _ in },
                     observe: @escaping (Observation) throws -> Void = { _ in }) throws -> Receipt {
        let scan = Scanner(view, track, observe, begin, compareRetained: true)
        return try scan.read()
    }
    /// Original source observations only. rawArchiveBytes/delimiter offsets are
    /// the potential concatenated size/positions, not a written or matched file.
    static func readSource(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt,
                           begin: @escaping (UInt64, Bool) throws -> Void = { _, _ in },
                           observe: @escaping (Observation) throws -> Void = { _ in },
                           refuseInBandParameterSets: Bool = false) throws -> Receipt {
        let scan = Scanner(view, track, observe, begin, compareRetained: false, refuseInBandParameterSets: refuseInBandParameterSets)
        return try scan.read()
    }
    /// Exact integer arithmetic, including Int64.min and cluster timestamps above
    /// Int64.max brought into range by a negative signed block-relative timestamp.
    static func pts(cluster: UInt64, relative: Int16, scale: UInt64) throws -> Int64 {
        guard scale > 0 else { throw refused() }
        let magnitude: UInt64, negative: Bool
        if relative < 0 {
            let subtract = UInt64(-Int64(relative))
            negative = cluster < subtract
            magnitude = negative ? subtract - cluster : cluster - subtract
        } else {
            let (sum, overflow) = cluster.addingReportingOverflow(UInt64(relative))
            guard !overflow else { throw refused() }; magnitude = sum; negative = false
        }
        let (product, overflow) = magnitude.multipliedReportingOverflow(by: scale)
        let limit = negative ? UInt64(Int64.max) + 1 : UInt64(Int64.max)
        guard !overflow, product <= limit else { throw refused() }
        if negative { return product == UInt64(Int64.max) + 1 ? Int64.min : -Int64(product) }
        return Int64(product)
    }
    private final class Scanner {
        let view: CompanionDiskCheck.ReadView, track: Track.Receipt, walker: Track.Walker
        let observe: (Observation) throws -> Void
        let begin: (UInt64, Bool) throws -> Void
        let compareRetained: Bool, refuseInBandParameterSets: Bool
        var packets: Int64 = 0, records: Int64 = 0, enhancement: Int64 = 0, archive: Int64 = 0
        let references: CompanionOriginalSPSCheck.ParameterReferences?
        let observeVCL: (VCLReference) throws -> Void
        var vcls: Int64 = 0, iraps: Int64 = 0, prefixPeak = 0, vclSequence = SHA256()
        var blocks = 0, peak = 0, sequence = SHA256()
        init(_ view: CompanionDiskCheck.ReadView, _ track: Track.Receipt, _ observe: @escaping (Observation) throws -> Void, _ begin: @escaping (UInt64, Bool) throws -> Void, compareRetained: Bool, refuseInBandParameterSets: Bool = false, references: CompanionOriginalSPSCheck.ParameterReferences? = nil, observeVCL: @escaping (VCLReference) throws -> Void = { _ in }) {
            self.view = view; self.track = track; self.observe = observe; self.begin = begin
            self.compareRetained = compareRetained; self.refuseInBandParameterSets = refuseInBandParameterSets
            self.references = references; self.observeVCL = observeVCL
            walker = Track.Walker(view, elementLimit: 128_000_000)
        }
        func children(_ e: Element, _ body: (Element) throws -> Void) throws {
            var cursor = e.payload
            while cursor < e.end {
                try view.checkpoint()
                let child = try walker.element(cursor, end: e.end)
                guard !child.unknown else { throw refused() }
                try body(child); cursor = child.end
            }
        }
        func read() throws -> Receipt {
            guard (1...(1 << 40)).contains(view.sourceBytes) else { throw refused() }
            let header = try walker.element(0, end: view.sourceBytes)
            guard header.id == 0x1a45dfa3, !header.unknown else { throw refused() }
            var seen: Set<UInt64> = [], docType = false
            try children(header) { e in
                if [UInt64(0x4282), 0x4285, 0x42f7, 0x42f2, 0x42f3].contains(e.id) {
                    guard seen.insert(e.id).inserted else { throw refused() }
                    if e.id == 0x4282 {
                        var bytes = try walker.bytes(e, maximum: 64)
                        while bytes.last == 0 { bytes.removeLast() }
                        docType = bytes == Data("matroska".utf8)
                    } else {
                        let n = try walker.unsigned(e)
                        guard (e.id != 0x4285 || (1...4).contains(n)), (e.id != 0x42f7 || n == 1),
                              (e.id != 0x42f2 || n == 4), (e.id != 0x42f3 || n == 8) else { throw refused() }
                    }
                }
            }
            guard docType else { throw refused() }
            let segment = try walker.element(header.end, end: view.sourceBytes)
            guard segment.id == 0x18538067 else { throw refused() }
            var scale: UInt64?, selected = false, began = false
            try children(segment) { e in
                switch e.id {
                case 0x1549a966:
                    guard scale == nil, !began else { throw refused() }
                    var value: UInt64 = 1_000_000, found = false
                    try children(e) { field in
                        if field.id == 0x2ad7b1 {
                            guard !found else { throw refused() }; found = true
                            value = try walker.unsigned(field); guard value > 0 else { throw refused() }
                        }
                    }
                    scale = value
                case 0x1654ae6b:
                    guard !selected, !began else { throw refused() }
                    let fresh = try walker.tracks(e)
                    guard fresh.number == track.trackNumber, fresh.offset == track.originalPayloadOffset,
                          fresh.payload.count == track.payloadBytes, fresh.configuration.count == track.configurationBytes,
                          DolbyInspection.hex(SHA256.hash(data: fresh.payload)) == track.payloadSHA256,
                          DolbyInspection.hex(SHA256.hash(data: fresh.configuration)) == track.configurationSHA256,
                          try Track.configuration(fresh.configuration, checkpoint: view.checkpoint) == track.nalLengthBytes else { throw refused() }
                    if compareRetained {
                        guard fresh.payload == (try view.component("original-track-entry-payload.bin")),
                              fresh.configuration == (try view.component("hevc-configuration.bin")) else { throw refused() }
                    }
                    try timing(fresh); selected = true
                case 0x1f43b675:
                    guard selected, let scale else { throw refused() }
                    if !began { try begin(scale, segment.unknown) }; began = true
                    try cluster(e, scale: scale)
                case 0x1a45dfa3, 0x18538067, 0xa3, 0xa1, 0xa0: throw refused()
                default: break
                }
            }
            var cursor = segment.end
            while cursor < view.sourceBytes {
                let e = try walker.element(cursor, end: view.sourceBytes)
                guard !e.unknown, e.id == 0xec || e.id == 0xbf else { throw refused() }; cursor = e.end
            }
            guard began, packets > 0, records > 0 else { throw refused() }
            if compareRetained { guard archive == (try view.componentBytes("original-rpu.bin")) else { throw refused() } }
            try view.checkpoint()
            return .init(packets: packets, records: records, enhancementNALs: enhancement,
                         peakRecordBytes: peak, rawArchiveBytes: archive,
                         packetSequenceSHA256: DolbyInspection.hex(sequence.finalize()),
                         originalEscapedRPUBytesMatch: compareRetained)
        }
        func timing(_ selected: Track.Selected) throws {
            // D109 retained these bytes opaquely; before interpreting PTS, explicitly
            // refuse compression/encryption, track operations and timing modifiers.
            let entry = Element(id: 0xae, payload: selected.offset, end: selected.offset + Int64(selected.payload.count), unknown: false)
            try children(entry) { e in
                switch e.id {
                case 0x6d80, 0xe2: throw refused()
                case 0x56aa: guard try walker.unsigned(e) == 0 else { throw refused() }
                case 0x23e383: guard try walker.unsigned(e) > 0 else { throw refused() }
                case 0x537f:
                    let data = try walker.bytes(e, maximum: 8)
                    guard !data.isEmpty, data.allSatisfy({ $0 == 0 }) else { throw refused() }
                case 0x23314f:
                    let data = try walker.bytes(e, maximum: 8)
                    guard data == Data([0x3f,0x80,0,0]) || data == Data([0x3f,0xf0,0,0,0,0,0,0]) else { throw refused() }
                default: break // Geometry and parameter-set decoding are separate gates.
                }
            }
        }
        func cluster(_ e: Element, scale: UInt64) throws {
            var timestamp: UInt64?
            try children(e) { field in
                switch field.id {
                case 0xe7:
                    guard timestamp == nil else { throw refused() }; timestamp = try walker.unsigned(field)
                case 0xa3:
                    guard let timestamp else { throw refused() }
                    if let b = try block(field, timestamp: timestamp, scale: scale) { try emit(b, duration: nil) }
                case 0xa0:
                    guard let timestamp else { throw refused() }
                    var hasBlock = false, b: Block?, duration: UInt64?, unsupported = false
                    try children(field) { child in
                        switch child.id {
                        case 0xa1:
                            guard !hasBlock else { throw refused() }; hasBlock = true
                            b = try block(child, timestamp: timestamp, scale: scale)
                        case 0x9b:
                            guard duration == nil else { throw refused() }
                            let n = try walker.unsigned(child); guard n > 0 else { throw refused() }; duration = n
                        case 0xa4, 0x75a1, 0x75a2: unsupported = true
                        case 0xa3, 0xa0, 0x1f43b675: throw refused()
                        default: break
                        }
                    }
                    guard hasBlock else { throw refused() }
                    if let b {
                        guard !unsupported else { throw refused() }
                        let ns: UInt64?
                        if let duration {
                            let (product, overflow) = duration.multipliedReportingOverflow(by: scale)
                            guard !overflow else { throw refused() }; ns = product
                        } else { ns = nil }
                        try emit(b, duration: ns)
                    }
                case 0xa1, 0x1549a966, 0x1654ae6b, 0x1f43b675: throw refused()
                default: break
                }
            }
            guard timestamp != nil else { throw refused() }
        }
        func block(_ e: Element, timestamp: UInt64, scale: UInt64) throws -> Block? {
            guard blocks < 32_000_000, e.end > e.payload else { throw refused() }; blocks += 1
            let data = try view.source(e.payload, Int(min(11, e.end - e.payload)))
            guard let first = data.first, first != 0 else { throw refused() }
            let width = first.leadingZeroBitCount + 1
            guard width <= 8, data.count >= width + 3 else { throw refused() }
            let mask = (UInt64(1) << (7 * width)) - 1
            let number = data.prefix(width).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } & mask
            guard number != mask, walker.trackNumbers.contains(number) else { throw refused() }
            if number != track.trackNumber { return nil }
            let flags = data[width + 2]
            guard flags & 6 == 0, flags & (e.id == 0xa3 ? 0x70 : 0xf1) == 0 else { throw refused() }
            let relative = Int16(bitPattern: UInt16(data[width]) << 8 | UInt16(data[width + 1]))
            let payload = e.payload + Int64(width + 3)
            guard (1...(16 << 20)).contains(e.end - payload) else { throw refused() }
            return .init(payload: payload, end: e.end, blockOffset: e.payload,
                         pts: try pts(cluster: timestamp, relative: relative, scale: scale), invisible: flags & 8 != 0,
                         keyframe: e.id == 0xa3 ? flags & 0x80 != 0 : nil,
                         discardable: e.id == 0xa3 ? flags & 1 != 0 : nil)
        }
        func emit(_ b: Block, duration: UInt64?) throws {
            guard packets < 2_000_000, references == nil || !b.invisible else { throw refused() }
            var hash = SHA256(), cursor = b.payload
            while cursor < b.end {
                try view.checkpoint()
                let count = Int(min(1 << 20, b.end - cursor))
                hash.update(data: try view.source(cursor, count)); cursor += Int64(count)
            }
            let digest = hash.finalize()
            func little(_ value: Int64) -> Data {
                let bits = UInt64(bitPattern: value)
                return Data((0..<8).map { UInt8(truncatingIfNeeded: bits >> (8 * $0)) })
            }
            sequence.update(data: little(b.pts)); sequence.update(data: little(b.end - b.payload)); sequence.update(data: Data(digest))
            try observe(.packet(.init(index: packets, inputOffset: b.payload, blockOffset: b.blockOffset, ptsNS: b.pts,
                                      durationNS: duration, invisible: b.invisible, keyframe: b.keyframe, discardable: b.discardable,
                                      encodedBytes: b.end - b.payload, sha256: DolbyInspection.hex(digest))))
            cursor = b.payload; var ordinal: Int64 = 0, vcl: VCLReference?
            while cursor < b.end {
                try view.checkpoint()
                guard Int64(track.nalLengthBytes) <= b.end - cursor else { throw refused() }
                let length = try view.source(cursor, track.nalLengthBytes).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                cursor += Int64(track.nalLengthBytes)
                guard length >= 2, length <= UInt64(b.end - cursor) else { throw refused() }
                let h = try view.source(cursor, 2)
                guard h[0] & 0x80 == 0, h[1] & 7 != 0 else { throw refused() }
                let type = h[0] >> 1 & 0x3f
                guard !refuseInBandParameterSets || ![32,33,34].contains(type) else { throw refused() }
                if let references, type <= 31 {
                    guard vcl == nil, length > 2 else { throw refused() }
                    let prefix = try CompanionOriginalSPSCheck.readFirstSlicePrefix(header: h,
                        prefix: view.source(cursor + 2, Int(min(2, length - 2))), payloadBytes: Int64(length - 2))
                    guard prefix.ppsID == references.ppsID else { throw refused() }
                    vcl = .init(packetIndex: packets, nalIndex: ordinal, ptsNS: b.pts,
                        nalOffset: cursor, nalBytes: Int64(length), prefix: prefix)
                }
                switch type {
                case 62:
                    guard h[0] & 1 == 0, h[1] >> 3 == 0, length > 2, length - 2 <= 65_536,
                          records < 2_000_000 else { throw refused() }
                    let size = Int(length - 2), original = try view.source(cursor + 2, size)
                    // No unescape/re-escape, interpretation or deduplication of original bytes.
                    if compareRetained {
                        let retained = try view.componentRead("original-rpu.bin", archive, size + 4)
                        guard retained == Data([0,0,0,1]) + original else { throw refused() }
                    }
                    try observe(.rpu(.init(index: records, packetIndex: packets, nalIndex: ordinal, ptsNS: b.pts,
                                          inputOffset: cursor + 2, archiveDelimiterOffset: archive, payloadBytes: size,
                                          sha256: DolbyInspection.hex(SHA256.hash(data: original)))))
                    archive += Int64(size + 4); records += 1; peak = max(peak, size)
                case 63: enhancement += 1
                default: break
                }
                cursor += Int64(length); ordinal += 1
            }
            if references != nil {
                guard let vcl else { throw refused() }
                vclSequence.update(data: Data(digest))
                for value in [vcl.packetIndex,vcl.nalIndex,vcl.ptsNS,vcl.nalOffset,vcl.nalBytes,
                    Int64(vcl.prefix.nalType),Int64(vcl.prefix.ppsID),Int64(vcl.prefix.prefixBits),
                    Int64(vcl.prefix.encodedPrefixBytes),vcl.prefix.noOutputOfPriorPics.map { $0 ? Int64(1):0 } ?? -1] {
                    vclSequence.update(data: little(value))
                }
                vclSequence.update(data: Data(vcl.prefix.prefixSHA256.utf8))
                try observeVCL(vcl); vcls += 1
                if vcl.prefix.noOutputOfPriorPics != nil { iraps += 1 }
                prefixPeak = max(prefixPeak, vcl.prefix.encodedPrefixBytes)
            }
            packets += 1
        }
    }
}
