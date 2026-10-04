import Foundation

/// Development reference framing only. Rows are transient until owned EOF, zero
/// exit and final input/tool observations. No independent packet/RPU proof yet.
final class DolbyDecoderStream {
    typealias JSON = CompanionArchiveJSON
    struct Geometry: Equatable, Sendable {
        let width: Int, height: Int
        let crop: [Int], sampleAspectRatio: [Int]
    }
    struct Receipt: Sendable {
        let source: SourceFingerprint
        let packets: Int64, frames: Int64, geometry: Geometry
        let configurationSHA256: String, timeBase: [Int]
        let independentSourceFrameAssociationVerified = false
        let editedPictureSemanticsVerified = false
    }
    private let source: SourceFingerprint, threads: Int, versions: [UInt64], observe: (Data) throws -> Void
    private var line = Data(), rows = 0, began = false, complete = false
    private var packets: Int64 = 0, frames: Int64 = 0, lastPacketOffset: UInt64?
    private var lastFramePTS: Int64?, geometry: Geometry?, configuration = "", timeBase = [Int]()
    init(source: SourceFingerprint, threads: Int, versions: [UInt64], observe: @escaping (Data) throws -> Void = { _ in }) throws {
        guard (1...(1 << 40)).contains(source.byteCount), [1,4].contains(threads),
              versions.count == 3, versions.allSatisfy({ (1...UInt64(UInt32.max)).contains($0) }) else { throw Self.refused() }
        _ = try DolbyInspection.hash(source.sha256)
        self.source=source; self.threads=threads; self.versions=versions; self.observe=observe
    }
    private static func refused() -> NativeExportError { .invalid("Development decoder stream refused. No settled frame result.") }
    func accept(_ data: Data) throws {
        for byte in data {
            guard !complete else { throw Self.refused() }
            if byte == 10 {
                guard !line.isEmpty, rows < 4_000_002 else { throw Self.refused() }
                rows += 1; try consume(line); try observe(line); line.removeAll(keepingCapacity:true)
            } else { guard line.count < 65_535 else { throw Self.refused() }; line.append(byte) }
        }
    }
    func finish(status: Int32) throws -> Receipt {
        guard status == 0, complete, line.isEmpty, let geometry else { throw Self.refused() }
        return .init(source:source,packets:packets,frames:frames,geometry:geometry,configurationSHA256:configuration,timeBase:timeBase)
    }
    private func n(_ o: JSON.Object, _ k: String, _ r: ClosedRange<UInt64> = 0...UInt64.max) throws -> UInt64 { try JSON.unsigned(o,k,r) }
    private func signed(_ o: JSON.Object, _ k: String) throws -> Int64 {
        let value = try JSON.signed(o,k); guard value != Int64.min else { throw Self.refused() }; return value
    }
    private func array(_ o: JSON.Object, _ k: String, count: Int, range: ClosedRange<UInt64>) throws -> [Int] {
        guard case .array(let a)? = o[k], a.count == count else { throw Self.refused() }
        return try a.map { guard case .unsigned(let n) = $0, range.contains(n) else { throw Self.refused() }; return Int(n) }
    }
    private func packetBounds(_ o: JSON.Object, sizeKey: String) throws -> UInt64 {
        let p = try n(o,"block_input_byte_offset",0...UInt64(source.byteCount-1)), s = try n(o,sizeKey,1...(16 << 20))
        guard s <= UInt64(source.byteCount)-p else { throw Self.refused() }; return p
    }
    private func consume(_ data: Data) throws {
        let o = try JSON.object(data,maximum:65_535), kind = try JSON.string(o,"kind")
        switch kind {
        case "begin":
            guard rows == 1, !began,
                  Set(o.keys) == ["kind","version","input_bytes","time_base","configuration_bytes","configuration_sha256","decoder","codec_version","format_version","util_version","automatic_codec_crop","threads"],
                  try n(o,"version") == 1, try n(o,"input_bytes") == UInt64(source.byteCount),
                  try JSON.string(o,"decoder") == "hevc", try n(o,"threads") == UInt64(threads),
                  try n(o,"codec_version") == versions[0], try n(o,"format_version") == versions[1], try n(o,"util_version") == versions[2],
                  try n(o,"configuration_bytes",1...(1 << 20)) > 0 else { throw Self.refused() }
            try JSON.bool(o,"automatic_codec_crop",false)
            timeBase = try array(o,"time_base",count:2,range:1...UInt64(Int32.max))
            configuration = try JSON.digest(o,"configuration_sha256"); began=true
        case "packet":
            guard began, packets < 2_000_000,
                  Set(o.keys) == ["kind","index","pts","block_input_byte_offset","encoded_bytes","sha256"],
                  try n(o,"index") == UInt64(packets) else { throw Self.refused() }
            let p = try packetBounds(o,sizeKey:"encoded_bytes")
            guard lastPacketOffset.map({ p > $0 }) ?? true else { throw Self.refused() }
            _ = try signed(o,"pts"); _ = try JSON.digest(o,"sha256")
            lastPacketOffset=p; packets += 1
        case "frame":
            guard began, packets > 0, frames < 2_000_000,
                  Set(o.keys) == ["kind","index","packet_index","block_input_byte_offset","packet_size","packet_pts","pts","best_effort_pts","width","height","pixel_format","interlaced","codec_crop_left_right_top_bottom","sample_aspect_ratio","rpu_bytes","rpu_sha256"],
                  try n(o,"index") == UInt64(frames), try n(o,"packet_index",0...UInt64(packets-1)) < UInt64(packets) else { throw Self.refused() }
            _ = try packetBounds(o,sizeKey:"packet_size")
            let pts = try signed(o,"pts")
            guard pts == (try signed(o,"packet_pts")), pts == (try signed(o,"best_effort_pts")),
                  lastFramePTS.map({ pts > $0 }) ?? true,
                  try JSON.string(o,"pixel_format") == "yuv420p10le", try n(o,"rpu_bytes",1...65536) > 0 else { throw Self.refused() }
            try JSON.bool(o,"interlaced",false); _ = try JSON.digest(o,"rpu_sha256")
            let w = Int(try n(o,"width",1...8192)), h = Int(try n(o,"height",1...8192))
            let crop = try array(o,"codec_crop_left_right_top_bottom",count:4,range:0...8191)
            let sar = try array(o,"sample_aspect_ratio",count:2,range:1...65535)
            guard w*h <= 4096*4096, crop[0]+crop[1] < w, crop[2]+crop[3] < h else { throw Self.refused() }
            let current = Geometry(width:w,height:h,crop:crop,sampleAspectRatio:sar)
            guard geometry.map({ $0 == current }) ?? true else { throw Self.refused() }
            geometry=current; lastFramePTS=pts; frames += 1
        case "complete":
            guard began, packets > 0, frames == packets,
                  Set(o.keys) == ["kind","version","packets","frames","decoder_drained","descriptor_unchanged"],
                  try n(o,"version") == 1, try n(o,"packets") == UInt64(packets), try n(o,"frames") == UInt64(frames) else { throw Self.refused() }
            try JSON.bool(o,"decoder_drained",true); try JSON.bool(o,"descriptor_unchanged",true); complete=true
        default: throw Self.refused()
        }
    }
}
