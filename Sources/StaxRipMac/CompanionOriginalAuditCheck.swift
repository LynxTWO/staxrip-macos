import Foundation

/// Source-audit framing/source relationships only. Compact metadata is bounded
/// and typed but NOT freshly decoded; full original semantic admission stays false.
enum CompanionOriginalAuditCheck {
    typealias JSON = CompanionArchiveJSON
    typealias Track = CompanionOriginalTrackCheck
    typealias Packets = CompanionOriginalPacketCheck
    struct Receipt: Sendable {
        let index: CompanionOriginalIndexCheck.Receipt
        let originalAuditFramingMatchesSource = true
        let originalDeclaredGeometryMatchesSource = true
        let compactMetadataSummaryVerified = false
        let originalPacketRPUSemanticsVerified = false
        let originalMetadataSemanticsVerified = false
    }
    struct Declarations: Sendable, Equatable {
        var width: UInt64 = 0, height: UInt64 = 0, unit: UInt64 = 0
        var crop: [UInt64] = [0,0,0,0], display: [UInt64?] = [nil,nil]
        var duration: UInt64?
    }
    private static func refused() -> NativeExportError { .invalid("Original audit source verification refused. No complete semantic receipt.") }
    static func declarations(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt) throws -> Declarations {
        let walker = Track.Walker(view)
        var result = Declarations(), video = false, duration = false
        func children(_ start: Int64, _ end: Int64, body: (Track.Element) throws -> Void) throws {
            var cursor = start
            while cursor < end {
                try view.checkpoint(); let field = try walker.element(cursor, end: end)
                guard !field.unknown else { throw refused() }; try body(field); cursor = field.end
            }
        }
        guard track.originalPayloadOffset >= 0, (1...(1 << 20)).contains(track.payloadBytes),
              track.originalPayloadOffset <= view.sourceBytes,
              Int64(track.payloadBytes) <= view.sourceBytes - track.originalPayloadOffset else { throw refused() }
        try children(track.originalPayloadOffset, track.originalPayloadOffset + Int64(track.payloadBytes)) { field in
            if field.id == 0x23e383 {
                guard !duration else { throw refused() }; duration = true
                result.duration = try walker.unsigned(field); guard result.duration != 0 else { throw refused() }
            } else if field.id == 0xe0 {
                guard !video else { throw refused() }; video = true; var seen: Set<UInt64> = []
                try children(field.payload, field.end) { f in
                    guard [UInt64(0xb0),0xba,0x54cc,0x54dd,0x54bb,0x54aa,0x54b0,0x54ba,0x54b2].contains(f.id) else { return }
                    guard seen.insert(f.id).inserted else { throw refused() }; let n = try walker.unsigned(f)
                    switch f.id {
                    case 0xb0: result.width = n
                    case 0xba: result.height = n
                    case 0x54cc: result.crop[0] = n
                    case 0x54dd: result.crop[1] = n
                    case 0x54bb: result.crop[2] = n
                    case 0x54aa: result.crop[3] = n
                    case 0x54b0: result.display[0] = n
                    case 0x54ba: result.display[1] = n
                    default: result.unit = n
                    }
                }
            }
        }
        guard video, (2...16384).contains(result.width), (2...16384).contains(result.height), result.unit <= 4,
              result.display.allSatisfy({ $0 == nil || (1...65536).contains($0!) }) else { throw refused() }
        let (horizontal, hOverflow) = result.crop[0].addingReportingOverflow(result.crop[1])
        let (vertical, vOverflow) = result.crop[2].addingReportingOverflow(result.crop[3])
        guard !hOverflow, !vOverflow, horizontal < result.width, vertical < result.height else { throw refused() }
        return result
    }
    static func read(_ view: CompanionDiskCheck.ReadView, track: Track.Receipt,
                     contents: OriginalCompanionTransaction.Contents) throws -> Receipt {
        let rows = try CompanionOriginalIndexCheck.Rows(view, fixed: .audit)
        let geometry = try declarations(view, track: track)
        func next(_ kind: String, _ keys: Set<String>) throws -> JSON.Object {
            guard let row = try rows.next(), Set(row.keys) == keys, try JSON.string(row, "kind") == kind else { throw refused() }; return row
        }
        let index = try CompanionOriginalIndexCheck.read(view, track: track, contents: contents, observe: { observation in
            switch observation {
            case .packet(let p):
                let row = try next("packet", ["kind","index","input_byte_offset","block_input_byte_offset","pts_ns","duration_ns","invisible","keyframe","discardable","encoded_bytes","sha256"])
                guard try number(row,"index") == UInt64(p.index), try number(row,"input_byte_offset") == UInt64(p.inputOffset),
                      try number(row,"block_input_byte_offset") == UInt64(p.blockOffset), try JSON.signed(row,"pts_ns") == p.ptsNS,
                      try optionalNumber(row,"duration_ns") == p.durationNS, try optionalBool(row,"keyframe") == p.keyframe,
                      try optionalBool(row,"discardable") == p.discardable, try number(row,"encoded_bytes") == UInt64(p.encodedBytes),
                      try JSON.digest(row,"sha256") == p.sha256 else { throw refused() }
                try JSON.bool(row,"invisible",p.invisible)
            case .rpu(let r):
                let row = try next("rpu-summary", ["kind","index","packet_index","nal_index","pts_ns","input_byte_offset","encoded_bytes","sha256","summary"])
                guard try number(row,"index") == UInt64(r.index), try number(row,"packet_index") == UInt64(r.packetIndex),
                      try number(row,"nal_index") == UInt64(r.nalIndex), try JSON.signed(row,"pts_ns") == r.ptsNS,
                      try number(row,"input_byte_offset") == UInt64(r.inputOffset), try number(row,"encoded_bytes") == UInt64(r.payloadBytes),
                      try JSON.digest(row,"sha256") == r.sha256 else { throw refused() }
                try summaryShape(row)
            }
        }, begin: { scale, unknown in
            let row = try next("begin", ["kind","version","input_type","parser","track_number","timestamp_scale_ns","declared_pixel_width","declared_pixel_height","declared_crop_left_right_top_bottom","declared_display_width_height","declared_display_unit","default_duration_ns","nal_length_bytes","configuration_bytes","configuration_sha256","segment_unknown_size","packet_limit","file_limit","count_limit"])
            guard try number(row,"version") == 3, try JSON.string(row,"input_type") == "matroska-hevc-summary",
                  try JSON.string(row,"parser") == "libdovi 3.3.2", try number(row,"track_number") == track.trackNumber,
                  try number(row,"timestamp_scale_ns") == scale, try number(row,"declared_pixel_width") == geometry.width,
                  try number(row,"declared_pixel_height") == geometry.height, try number(row,"declared_display_unit") == geometry.unit,
                  try optionalNumber(row,"default_duration_ns") == geometry.duration,
                  try number(row,"nal_length_bytes") == UInt64(track.nalLengthBytes), try number(row,"configuration_bytes") == UInt64(track.configurationBytes),
                  try JSON.digest(row,"configuration_sha256") == track.configurationSHA256,
                  try number(row,"packet_limit") == 16 << 20, try number(row,"file_limit") == 1 << 40, try number(row,"count_limit") == 2_000_000 else { throw refused() }
            try JSON.bool(row,"segment_unknown_size",unknown)
            try array(row,"declared_crop_left_right_top_bottom", expected: geometry.crop.map(Optional.some))
            try array(row,"declared_display_width_height", expected: geometry.display)
        })
        let complete = try next("complete", ["kind","version","packets","records","enhancement_nals","input_bytes","input_sha256","peak_record_bytes","source_recheck","packet_sequence_sha256"])
        let source = index.packets
        guard try number(complete,"version") == 3, try number(complete,"packets") == UInt64(source.packets),
              try number(complete,"records") == UInt64(source.records), try number(complete,"enhancement_nals") == UInt64(source.enhancementNALs),
              try number(complete,"input_bytes") == UInt64(contents.sourceBytes), try JSON.digest(complete,"input_sha256") == contents.sourceSHA256,
              try number(complete,"peak_record_bytes") == UInt64(source.peakRecordBytes),
              try JSON.digest(complete,"packet_sequence_sha256") == source.packetSequenceSHA256, try rows.next() == nil else { throw refused() }
        try JSON.bool(complete,"source_recheck",true); try view.checkpoint(); return .init(index: index)
    }
    private static func number(_ o: JSON.Object, _ key: String) throws -> UInt64 { try JSON.unsigned(o,key,0...UInt64.max) }
    private static func optionalNumber(_ o: JSON.Object, _ key: String) throws -> UInt64? {
        switch o[key] { case .null?: return nil; case .unsigned(let n)?: return n; default: throw refused() }
    }
    private static func optionalBool(_ o: JSON.Object, _ key: String) throws -> Bool? {
        switch o[key] { case .null?: return nil; case .bool(let b)?: return b; default: throw refused() }
    }
    private static func array(_ o: JSON.Object, _ key: String, expected: [UInt64?]) throws {
        guard case .array(let a)? = o[key], a.count == expected.count else { throw refused() }
        for (v, n) in zip(a,expected) {
            switch (v,n) { case (.null,nil): break; case (.unsigned(let actual),.some(let expected)) where actual == expected: break; default: throw refused() }
        }
    }
    static func summaryShape(_ o: JSON.Object) throws {
        guard case .object(let s)? = o["summary"], Set(s.keys) == ["mapping_profile","enhancement_type","scene_refresh","active_areas_left_right_top_bottom","cmv29_present","cmv40_present"],
              try number(s,"mapping_profile") <= 10, case .array(let areas)? = s["active_areas_left_right_top_bottom"], areas.count <= 4 else { throw refused() }
        switch s["enhancement_type"] { case .null?: break; case .string(let v)? where ["MEL","FEL"].contains(v): break; default: throw refused() }
        _ = try optionalBool(s,"scene_refresh")
        guard case .bool? = s["cmv29_present"], case .bool? = s["cmv40_present"] else { throw refused() }
        for area in areas {
            guard case .array(let offsets) = area, offsets.count == 4 else { throw refused() }
            for v in offsets { guard case .unsigned(let n) = v, n <= 8191 else { throw refused() } }
        }
    }
}
