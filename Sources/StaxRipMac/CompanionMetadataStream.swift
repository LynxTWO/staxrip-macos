import Foundation
import CryptoKit

/// Fixed fresh mkv-summary protocol. Observed rows are transient until the owning
/// process joins and source observations settle; no archive semantics are inferred.
final class CompanionMetadataStream {
    typealias JSON = CompanionArchiveJSON
    struct Receipt: Sendable {
        let source: SourceFingerprint
        let packets: Int64, records: Int64, enhancementNALs: Int64
        let packetSequenceSHA256: String
        let peakRecordBytes: Int, peakTrackedHeap: Int
        let originalMetadataSemanticsVerified = false
    }
    private let source: SourceFingerprint, observe: (Data) throws -> Void
    private var line = Data(), rows = 0, began = false, resources = false, complete: Receipt?
    private var packets: Int64 = 0, records: Int64 = 0, peak = 0, heap = 0
    private var currentPTS: Int64 = 0, currentOffset: UInt64 = 0, currentBytes: UInt64 = 0
    private var nal: UInt64?, sequence = SHA256()
    init(source: SourceFingerprint, observe: @escaping (Data) throws -> Void = { _ in }) throws {
        guard (1...(1 << 40)).contains(source.byteCount) else { throw Self.refused() }
        _ = try DolbyInspection.hash(source.sha256)
        self.source = source; self.observe = observe
    }
    private static func refused() -> NativeExportError { .invalid("Native metadata stream refused. No successful settled result.") }
    func accept(_ data: Data) throws {
        for byte in data {
            guard complete == nil else { throw Self.refused() }
            if byte == 10 {
                guard !line.isEmpty, rows < 4_000_003 else { throw Self.refused() }; rows += 1
                try consume(line); try observe(line); line.removeAll(keepingCapacity:true)
            } else { guard line.count < 65_535 else { throw Self.refused() }; line.append(byte) }
        }
    }
    func finish(status: Int32) throws -> Receipt {
        guard status == 0, line.isEmpty, let complete else { throw Self.refused() }; return complete
    }
    private func n(_ o: JSON.Object, _ key: String, _ range: ClosedRange<UInt64> = 0...UInt64.max) throws -> UInt64 { try JSON.unsigned(o,key,range) }
    private func optionalNumber(_ o: JSON.Object, _ key: String) throws -> UInt64? {
        switch o[key] { case .null?: return nil; case .unsigned(let n)? where n > 0: return n; default: throw Self.refused() }
    }
    private func optionalBool(_ o: JSON.Object, _ key: String) throws -> Bool? {
        switch o[key] { case .null?: return nil; case .bool(let b)?: return b; default: throw Self.refused() }
    }
    private func consume(_ data: Data) throws {
        let o = try JSON.object(data, maximum:65_535, auditNullable:true), kind = try JSON.string(o,"kind")
        guard !resources || kind == "complete" else { throw Self.refused() }
        switch kind {
        case "begin":
            guard !began, rows == 1, Set(o.keys) == ["kind","version","input_type","parser","track_number","timestamp_scale_ns","declared_pixel_width","declared_pixel_height","declared_crop_left_right_top_bottom","declared_display_width_height","declared_display_unit","default_duration_ns","nal_length_bytes","configuration_bytes","configuration_sha256","segment_unknown_size","packet_limit","file_limit","count_limit"],
                  try n(o,"version") == 3, try JSON.string(o,"input_type") == "matroska-hevc-summary", try JSON.string(o,"parser") == "libdovi 3.3.2",
                  try n(o,"track_number",1...(1 << 40)) > 0, try n(o,"timestamp_scale_ns",1...UInt64.max) > 0,
                  try n(o,"nal_length_bytes",1...4) > 0, try n(o,"configuration_bytes",23...(1 << 20)) >= 23,
                  try n(o,"packet_limit") == 16 << 20, try n(o,"file_limit") == 1 << 40, try n(o,"count_limit") == 2_000_000,
                  case .bool? = o["segment_unknown_size"] else { throw Self.refused() }
            _ = try JSON.digest(o,"configuration_sha256"); _ = try optionalNumber(o,"default_duration_ns")
            let w = try n(o,"declared_pixel_width",2...16384), h = try n(o,"declared_pixel_height",2...16384)
            _ = try n(o,"declared_display_unit",0...4)
            guard case .array(let crop)? = o["declared_crop_left_right_top_bottom"], crop.count == 4,
                  case .array(let display)? = o["declared_display_width_height"], display.count == 2 else { throw Self.refused() }
            var offsets: [UInt64] = []
            for v in crop { guard case .unsigned(let n) = v, n <= 16384 else { throw Self.refused() }; offsets.append(n) }
            guard offsets[0]+offsets[1] < w, offsets[2]+offsets[3] < h else { throw Self.refused() }
            for v in display {
                switch v { case .null: break; case .unsigned(let n) where (1...65536).contains(n): break; default: throw Self.refused() }
            }
            began = true
        case "packet":
            guard began, Set(o.keys) == ["kind","index","input_byte_offset","block_input_byte_offset","pts_ns","duration_ns","invisible","keyframe","discardable","encoded_bytes","sha256"],
                  packets < 2_000_000, try n(o,"index") == UInt64(packets), case .bool? = o["invisible"] else { throw Self.refused() }
            let size = try n(o,"encoded_bytes",1...(16 << 20)), offset = try n(o,"input_byte_offset",1...UInt64(source.byteCount))
            guard size <= UInt64(source.byteCount)-offset, offset >= currentOffset+currentBytes,
                  try n(o,"block_input_byte_offset",1...offset) < offset else { throw Self.refused() }
            let k = try optionalBool(o,"keyframe"), d = try optionalBool(o,"discardable")
            guard (k == nil) == (d == nil) else { throw Self.refused() }; _ = try optionalNumber(o,"duration_ns")
            currentPTS = try JSON.signed(o,"pts_ns"); currentOffset = offset; currentBytes = size; nal = nil
            let digest = try JSON.digest(o,"sha256")
            sequence.update(data: DolbyInspection.proofRecord(pts:currentPTS,bytes:Int64(size),digest:try DolbyInspection.hash(digest))); packets += 1
        case "rpu-summary":
            guard began, packets > 0, records < 2_000_000,
                  Set(o.keys) == ["kind","index","packet_index","nal_index","pts_ns","input_byte_offset","encoded_bytes","sha256","summary"],
                  try n(o,"index") == UInt64(records), try n(o,"packet_index") == UInt64(packets-1), try JSON.signed(o,"pts_ns") == currentPTS else { throw Self.refused() }
            let ordinal = try n(o,"nal_index",0...(16 << 20)), size = try n(o,"encoded_bytes",25...65536), offset = try n(o,"input_byte_offset")
            guard nal.map({ ordinal > $0 }) ?? true, offset >= currentOffset+2, offset <= currentOffset+currentBytes,
                  size <= currentOffset+currentBytes-offset else { throw Self.refused() }
            _ = try JSON.digest(o,"sha256"); try CompanionOriginalAuditCheck.summaryShape(o)
            nal = ordinal; records += 1; peak = max(peak,Int(size))
        case "resources":
            guard began, packets > 0, records > 0, !resources, Set(o.keys) == ["kind","heap_limit","peak_heap_bytes"],
                  try n(o,"heap_limit") == 67_108_864 else { throw Self.refused() }
            heap = Int(try n(o,"peak_heap_bytes",1...67_108_864)); resources = true
        case "complete":
            guard resources, Set(o.keys) == ["kind","version","packets","records","enhancement_nals","input_bytes","input_sha256","peak_record_bytes","source_recheck","packet_sequence_sha256"],
                  try n(o,"version") == 3, try n(o,"packets") == UInt64(packets), try n(o,"records") == UInt64(records),
                  try n(o,"input_bytes") == UInt64(source.byteCount), try JSON.digest(o,"input_sha256") == source.sha256,
                  try n(o,"peak_record_bytes") == UInt64(peak), try JSON.digest(o,"packet_sequence_sha256") == DolbyInspection.hex(sequence.finalize()) else { throw Self.refused() }
            try JSON.bool(o,"source_recheck",true)
            complete = .init(source:source,packets:packets,records:records,enhancementNALs:Int64(try n(o,"enhancement_nals",0...4_000_000_000_000)),
                             packetSequenceSHA256:try JSON.digest(o,"packet_sequence_sha256"),peakRecordBytes:peak,peakTrackedHeap:heap)
        default: throw Self.refused()
        }
    }
}
