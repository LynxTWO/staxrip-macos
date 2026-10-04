import Foundation

/// Actual persisted index/manifest source admission on the owned native disk worker.
/// Still partial: source-audit/metadata validity are NOT checked or implied.
enum CompanionOriginalIndexCheck {
    typealias JSON = CompanionArchiveJSON
    typealias PacketCheck = CompanionOriginalPacketCheck
    typealias Transaction = OriginalCompanionTransaction
    struct Receipt: Sendable {
        let packets: PacketCheck.Receipt
        let originalIndexMatchesSource = true
        let manifestClaimsMatchObservedSourceAndComponents = true
        let originalPacketRPUSemanticsVerified = false
        let originalMetadataSemanticsVerified = false
    }
    private static func refused() -> NativeExportError { .invalid("Original index/manifest verification refused. No complete semantic receipt.") }
    static func read(_ view: CompanionDiskCheck.ReadView, track: CompanionOriginalTrackCheck.Receipt,
                     contents: Transaction.Contents,
                     observe: @escaping (PacketCheck.Observation) throws -> Void = { _ in },
                     begin: @escaping (UInt64, Bool) throws -> Void = { _, _ in }) throws -> Receipt {
        try view.checkpoint()
        guard (1...(1 << 40)).contains(contents.sourceBytes), view.sourceBytes == contents.sourceBytes,
              (1...2_000_000).contains(contents.packets), (1...2_000_000).contains(contents.records),
              (0...4_000_000_000_000).contains(contents.enhancementNALs), track.originalPayloadOffset >= 0 else { throw refused() }
        let manifestBytes = try view.componentBytes("manifest.json")
        guard (1...(1 << 20)).contains(manifestBytes) else { throw refused() }
        let m = try JSON.object(view.componentRead("manifest.json", 0, Int(manifestBytes)), maximum: 1 << 20)
        try manifest(m, track: track, contents: contents)
        let rows = try Rows(view)
        let source = try PacketCheck.read(view, track: track, begin: begin, observe: { observation in
            if case .rpu(let rpu) = observation {
                guard let row = try rows.next() else { throw refused() }
                try index(row, original: rpu)
            }
            try observe(observation)
        })
        guard try rows.next() == nil, source.packets == contents.packets, source.records == contents.records,
              source.enhancementNALs == contents.enhancementNALs else { throw refused() }
        try view.checkpoint(); return .init(packets: source)
    }
    private static func manifest(_ m: JSON.Object, track: CompanionOriginalTrackCheck.Receipt, contents c: Transaction.Contents) throws {
        let keys: Set<String> = ["kind", "version", "retention", "source_bytes", "source_sha256", "track_payload_original_offset",
            "packets", "records", "enhancement_nals", "association", "decoded_frame_association", "source_content_recheck",
            "source_path_identity_bound", "metadata_rewritten", "components"]
        let mode = c.retention == .metadataOnly ? "rpu-and-original-track-metadata-only" : "entire-original-container"
        guard Set(m.keys) == keys, try JSON.string(m, "kind") == "development-original-companion",
              try JSON.unsigned(m, "version", 0...0) == 0, try JSON.string(m, "retention") == mode,
              try JSON.string(m, "association") == "original-encoded-packet-order",
              try JSON.string(m, "decoded_frame_association") == "not-established",
              try JSON.unsigned(m, "source_bytes", 1...(1 << 40)) == UInt64(c.sourceBytes),
              try JSON.digest(m, "source_sha256") == c.sourceSHA256,
              try JSON.unsigned(m, "track_payload_original_offset", 0...(1 << 40)) == UInt64(track.originalPayloadOffset),
              try JSON.unsigned(m, "packets", 1...2_000_000) == UInt64(c.packets),
              try JSON.unsigned(m, "records", 1...2_000_000) == UInt64(c.records),
              try JSON.unsigned(m, "enhancement_nals", 0...4_000_000_000_000) == UInt64(c.enhancementNALs) else { throw refused() }
        try JSON.bool(m, "source_content_recheck", true); try JSON.bool(m, "source_path_identity_bound", false)
        try JSON.bool(m, "metadata_rewritten", false)
        let limits = c.retention.limits, expected = Set(limits.keys).subtracting(["manifest.json"])
        guard case .array(let components)? = m["components"], components.count == expected.count else { throw refused() }
        var actual: [String: ResultSetStaging.Member] = [:], seen: Set<String> = []
        for member in c.members {
            guard actual[member.name] == nil else { throw refused() }; actual[member.name] = member
        }
        guard Set(actual.keys) == expected.union(["manifest.json"]) else { throw refused() }
        for value in components {
            guard case .object(let object) = value, Set(object.keys) == ["name", "bytes", "sha256"] else { throw refused() }
            let name = try JSON.string(object, "name")
            guard expected.contains(name), seen.insert(name).inserted, let member = actual[name], let maximum = limits[name], (1...maximum).contains(member.byteCount),
                  try JSON.unsigned(object, "bytes", 1...UInt64(maximum)) == UInt64(member.byteCount),
                  try JSON.digest(object, "sha256") == member.sha256 else { throw refused() }
        }
        guard seen == expected else { throw refused() }
    }
    private static func index(_ row: JSON.Object, original r: PacketCheck.RPU) throws {
        let keys: Set<String> = ["kind", "index", "packet_index", "nal_index", "pts_ns", "original_payload_offset",
                                  "archive_delimiter_offset", "payload_bytes", "payload_sha256"]
        guard Set(row.keys) == keys, try JSON.string(row, "kind") == "original-rpu-reference",
              try JSON.unsigned(row, "index", 0...1_999_999) == UInt64(r.index),
              try JSON.unsigned(row, "packet_index", 0...1_999_999) == UInt64(r.packetIndex),
              try JSON.unsigned(row, "nal_index", 0...(16 << 20)) == UInt64(r.nalIndex),
              try JSON.signed(row, "pts_ns") == r.ptsNS,
              try JSON.unsigned(row, "original_payload_offset", 0...(1 << 40)) == UInt64(r.inputOffset),
              try JSON.unsigned(row, "archive_delimiter_offset", 0...(1 << 29)) == UInt64(r.archiveDelimiterOffset),
              try JSON.unsigned(row, "payload_bytes", 1...65_536) == UInt64(r.payloadBytes),
              try JSON.digest(row, "payload_sha256") == r.sha256 else { throw refused() }
    }
    /// One fixed pinned component, bounded row count/line/chunk; no arbitrary file
    /// names, seekable archive-selected paths or unbounded whole-file capture.
    final class Rows {
        enum Fixed { case index, audit
            var name: String { self == .index ? "rpu-index.jsonl" : "source-audit.jsonl" }
            var maximum: Int64 { self == .index ? 1 << 29 : 1 << 30 }
            var rows: Int { self == .index ? 2_000_000 : 4_000_002 }
        }
        private let view: CompanionDiskCheck.ReadView, size: Int64, fixed: Fixed
        private var offset: Int64 = 0, buffer: [UInt8] = [], position = 0, count = 0
        init(_ view: CompanionDiskCheck.ReadView, fixed: Fixed = .index) throws {
            self.view = view; self.fixed = fixed; size = try view.componentBytes(fixed.name)
            guard (1...fixed.maximum).contains(size) else { throw refused() }
        }
        func next() throws -> JSON.Object? {
            try view.checkpoint(); var line = Data()
            while true {
                if position == buffer.count {
                    if offset == size {
                        guard line.isEmpty else { throw refused() }; return nil
                    }
                    try view.checkpoint()
                    let n = Int(min(65_536, size - offset))
                    let data = try view.componentRead(fixed.name, offset, n)
                    guard data.count == n else { throw refused() }
                    buffer = Array(data); position = 0; offset += Int64(n)
                }
                let byte = buffer[position]; position += 1
                if byte == 10 {
                    guard count < fixed.rows, !line.isEmpty else { throw refused() }; count += 1
                    try view.checkpoint(); return try JSON.object(line, maximum: 65_535, auditNullable: fixed == .audit)
                }
                guard line.count < 65_535 else { throw refused() }; line.append(byte)
            }
        }
    }
}
