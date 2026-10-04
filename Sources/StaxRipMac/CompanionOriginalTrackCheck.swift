import Foundation
import CryptoKit

/// Independently rereads selected pre-cluster original TrackEntry/hvcC bytes.
/// Partial semantics only: no packet/RPU/index/audit admission or decoder inference.
enum CompanionOriginalTrackCheck {
    struct Receipt: Sendable {
        let trackNumber: UInt64
        let originalPayloadOffset: Int64
        let payloadBytes: Int
        let configurationBytes: Int
        let nalLengthBytes: Int
        let payloadSHA256: String
        let configurationSHA256: String
        let originalTrackAndConfigurationMatch = true
        let originalPacketRPUSemanticsVerified = false
    }
    struct Element { let id: UInt64, payload: Int64, end: Int64, unknown: Bool }
    struct Selected { let number: UInt64, offset: Int64, payload: Data, configuration: Data }
    private static func refused() -> NativeExportError { .invalid("Original companion track verification refused. No complete semantic receipt.") }
    static func read(_ view: CompanionDiskCheck.ReadView) throws -> Receipt {
        let walker = Walker(view)
        let header = try walker.element(0, end: view.sourceBytes)
        guard header.id == 0x1a45dfa3, !header.unknown else { throw refused() }
        let segment = try walker.element(header.end, end: view.sourceBytes)
        guard segment.id == 0x18538067 else { throw refused() }
        var cursor = segment.payload, tracksSeen = false, selected: Selected?
        while cursor < segment.end {
            try view.checkpoint()
            let child = try walker.element(cursor, end: segment.end)
            guard !child.unknown else { throw refused() }
            if child.id == 0x1f43b675 { break } // Packet/after-cluster admission remains a separate gate.
            if child.id == 0x1654ae6b {
                guard !tracksSeen else { throw refused() }; tracksSeen = true
                selected = try walker.tracks(child)
            }
            cursor = child.end
        }
        guard let track = selected,
              try view.component("original-track-entry-payload.bin") == track.payload,
              try view.component("hevc-configuration.bin") == track.configuration else { throw refused() }
        let width = try configuration(track.configuration, checkpoint: view.checkpoint)
        try view.checkpoint()
        return .init(trackNumber: track.number, originalPayloadOffset: track.offset,
                     payloadBytes: track.payload.count, configurationBytes: track.configuration.count,
                     nalLengthBytes: width, payloadSHA256: DolbyInspection.hex(SHA256.hash(data: track.payload)),
                     configurationSHA256: DolbyInspection.hex(SHA256.hash(data: track.configuration)))
    }
    final class Walker {
        let view: CompanionDiskCheck.ReadView
        private var elements = 0
        private let elementLimit: Int
        private(set) var trackNumbers: Set<UInt64> = []
        init(_ view: CompanionDiskCheck.ReadView, elementLimit: Int = 100_000) { self.view = view; self.elementLimit = elementLimit }
        func element(_ offset: Int64, end: Int64) throws -> Element {
            try view.checkpoint()
            guard offset >= 0, offset < end, end <= view.sourceBytes, elements < elementLimit else { throw refused() }
            elements += 1
            let bytes = try view.source(offset, Int(min(12, end - offset)))
            func vint(_ at: Int, identifier: Bool) throws -> (UInt64, Int, Bool) {
                guard at < bytes.count, bytes[at] != 0 else { throw refused() }
                let width = bytes[at].leadingZeroBitCount + 1
                guard width <= (identifier ? 4 : 8), width <= bytes.count - at else { throw refused() }
                var value: UInt64 = 0
                for index in at..<(at + width) { value = (value << 8) | UInt64(bytes[index]) }
                if identifier {
                    guard value != (UInt64(1) << (7 * width + 1)) - 1 else { throw refused() }
                    return (value, width, false)
                }
                let mask = (UInt64(1) << (7 * width)) - 1
                value &= mask; return (value, width, value == mask)
            }
            let (id, idWidth, _) = try vint(0, identifier: true)
            let (length, sizeWidth, unknown) = try vint(idWidth, identifier: false)
            let payload = offset + Int64(idWidth + sizeWidth)
            guard payload <= end, !unknown || id == 0x18538067,
                  unknown || length <= UInt64(end - payload) else { throw refused() }
            return .init(id: id, payload: payload, end: unknown ? end : payload + Int64(length), unknown: unknown)
        }
        func bytes(_ e: Element, maximum: Int = 1 << 20) throws -> Data {
            guard !e.unknown, e.end - e.payload <= maximum else { throw refused() }
            return try view.source(e.payload, Int(e.end - e.payload))
        }
        func unsigned(_ e: Element) throws -> UInt64 {
            let b = try bytes(e, maximum: 8); guard !b.isEmpty else { throw refused() }
            return b.reduce(0) { ($0 << 8) | UInt64($1) }
        }
        func tracks(_ container: Element) throws -> Selected {
            var cursor = container.payload, numbers: Set<UInt64> = [], selected: Selected?
            let critical: Set<UInt64> = [0xd7, 0x83, 0x86, 0x63a2, 0xe0, 0x56aa, 0x23e383, 0x23314f, 0x6d80, 0x537f, 0xe2]
            while cursor < container.end {
                let entry = try element(cursor, end: container.end); guard !entry.unknown else { throw refused() }
                if entry.id == 0xae {
                    guard numbers.count < 256, entry.end - entry.payload <= 1 << 20 else { throw refused() }
                    var fieldOffset = entry.payload, seen: Set<UInt64> = []
                    var number: UInt64 = 0, kind: UInt64 = 0, codec = Data(), config: Data?
                    while fieldOffset < entry.end {
                        let field = try element(fieldOffset, end: entry.end); guard !field.unknown else { throw refused() }
                        if critical.contains(field.id) { guard seen.insert(field.id).inserted else { throw refused() } }
                        switch field.id {
                        case 0xd7: number = try unsigned(field)
                        case 0x83: kind = try unsigned(field)
                        case 0x86: codec = try bytes(field, maximum: 64)
                        case 0x63a2: config = try bytes(field)
                        default: break // Exact opaque payload is retained, not interpreted as packet/geometry semantics.
                        }
                        fieldOffset = field.end
                    }
                    guard number > 0, number <= 1 << 40, kind > 0, numbers.insert(number).inserted else { throw refused() }
                    if kind == 1 {
                        guard selected == nil, codec == Data("V_MPEGH/ISO/HEVC".utf8), let config else { throw refused() }
                        selected = .init(number: number, offset: entry.payload, payload: try bytes(entry), configuration: config)
                    }
                }
                cursor = entry.end
            }
            guard let selected else { throw refused() }; trackNumbers = numbers; return selected
        }
    }
    static func configuration(_ data: Data, checkpoint: () throws -> Void) throws -> Int {
        guard data.count >= 23, data[0] == 1 else { throw refused() }
        let width = Int(data[21] & 3) + 1
        var position = 23
        for _ in 0..<Int(data[22]) {
            try checkpoint()
            guard data.count - position >= 3 else { throw refused() }
            let type = data[position] & 0x3f, count = Int(data[position + 1]) << 8 | Int(data[position + 2])
            position += 3
            for _ in 0..<count {
                try checkpoint()
                guard type != 62, type != 63 else { throw refused() }
                guard data.count - position >= 2 else { throw refused() }
                let length = Int(data[position]) << 8 | Int(data[position + 1]); position += 2
                guard length >= 2, length <= data.count - position,
                      data[position] & 0x80 == 0, data[position + 1] & 7 != 0,
                      data[position] >> 1 & 0x3f == type else { throw refused() }
                position += length
            }
        }
        guard position == data.count else { throw refused() }; try checkpoint(); return width
    }
}
