import Foundation

/// Development reference framing only. Rows are transient until owned EOF, zero
/// exit and final input/tool observations. Explicit metadata/base-sample/crop profiles;
/// neither row shape nor moments establish independent source/frame/sample truth.
final class DolbyDecoderStream {
    typealias JSON = CompanionArchiveJSON
    enum Profile: Equatable, Sendable { case metadata, baseSamples, cropSamples }
    struct PlaneSummary: Equatable, Sendable {
        let width: Int, height: Int
        let samples: UInt64, minimum: UInt64, maximum: UInt64, sum: UInt64, sumSquares: UInt64
        let sha256: String
    }
    struct ColorDeclarations: Equatable, Sendable {
        let range: Int, primaries: Int, transfer: Int, matrix: Int, chromaLocation: Int
    }
    struct BaseSampleFrame: Sendable {
        let index: Int64, packetIndex: Int64
        let coded: [PlaneSummary], codecVisible: [PlaneSummary]
        let color: ColorDeclarations
    }
    struct CropRequest: Equatable, Sendable {
        enum Space: String, Sendable { case coded, codecVisible = "codec-visible" }
        let space: Space
        let rectangle: [Int]
        init(space: Space, x: Int, y: Int, width: Int, height: Int) throws {
            let r = [x,y,width,height]
            guard r.allSatisfy({ (0...8192).contains($0) && $0 % 2 == 0 }),
                  width > 0, height > 0 else { throw DolbyDecoderStream.refused() }
            self.space=space; self.rectangle=r
        }
        var arguments: [String] { ["--" + space.rawValue + "-roi"] + rectangle.map(String.init) }
    }
    struct CropFrame: Sendable {
        let index: Int64, packetIndex: Int64
        let request: CropRequest, codedRectangle: [Int]
        let planes: [PlaneSummary], color: ColorDeclarations
    }
    struct Geometry: Equatable, Sendable {
        let width: Int, height: Int
        // Crop protocol omits SAR; absence is explicit, never synthesized.
        let crop: [Int], sampleAspectRatio: [Int]?
    }
    struct Receipt: Sendable {
        let source: SourceFingerprint
        let packets: Int64, frames: Int64, geometry: Geometry
        let configurationSHA256: String, timeBase: [Int]
        let independentSourceFrameAssociationVerified = false
        let editedPictureSemanticsVerified = false
        let sampleFrameSummaryCount: Int64
        let sampleColorDeclarations: ColorDeclarations?
        let independentSampleSourceAssociationVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let cropFrameSummaryCount: Int64
        let cropRequest: CropRequest?
        let cropColorDeclarations: ColorDeclarations?
        init(source: SourceFingerprint, packets: Int64, frames: Int64, geometry: Geometry,
             configurationSHA256: String, timeBase: [Int], sampleFrameSummaryCount: Int64 = 0,
             sampleColorDeclarations: ColorDeclarations? = nil, cropFrameSummaryCount: Int64 = 0,
             cropRequest: CropRequest? = nil, cropColorDeclarations: ColorDeclarations? = nil) {
            self.source=source;self.packets=packets;self.frames=frames;self.geometry=geometry
            self.configurationSHA256=configurationSHA256;self.timeBase=timeBase
            self.sampleFrameSummaryCount=sampleFrameSummaryCount;self.sampleColorDeclarations=sampleColorDeclarations
            self.cropFrameSummaryCount=cropFrameSummaryCount;self.cropRequest=cropRequest;self.cropColorDeclarations=cropColorDeclarations
        }
    }
    private let source: SourceFingerprint, threads: Int, versions: [UInt64], observe: (Data) throws -> Void
    private let profile: Profile, observeSamples: (BaseSampleFrame) throws -> Void
    private let cropRequest: CropRequest?, observeCrops: (CropFrame) throws -> Void
    private var color: ColorDeclarations?
    private var line = Data(), rows = 0, began = false, complete = false
    private var packets: Int64 = 0, frames: Int64 = 0, lastPacketOffset: UInt64?
    private var lastFramePTS: Int64?, geometry: Geometry?, configuration = "", timeBase = [Int]()
    init(source: SourceFingerprint, threads: Int, versions: [UInt64], profile: Profile = .metadata,
         cropRequest: CropRequest? = nil, observeCrops: @escaping (CropFrame) throws -> Void = { _ in },
         observeSamples: @escaping (BaseSampleFrame) throws -> Void = { _ in },
         observe: @escaping (Data) throws -> Void = { _ in }) throws {
        guard (1...(1 << 40)).contains(source.byteCount), [1,4].contains(threads),
              versions.count == 3, versions.allSatisfy({ (1...UInt64(UInt32.max)).contains($0) }) else { throw Self.refused() }
        guard (profile == .cropSamples) == (cropRequest != nil) else { throw Self.refused() }
        _ = try DolbyInspection.hash(source.sha256)
        self.source=source; self.threads=threads; self.versions=versions; self.observe=observe
        self.profile=profile; self.observeSamples=observeSamples; self.cropRequest=cropRequest; self.observeCrops=observeCrops
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
        return .init(source:source,packets:packets,frames:frames,geometry:geometry,configurationSHA256:configuration,timeBase:timeBase,
                     sampleFrameSummaryCount:profile == .baseSamples ? frames : 0,
                     sampleColorDeclarations:profile == .baseSamples ? color : nil,
                     cropFrameSummaryCount:profile == .cropSamples ? frames : 0,
                     cropRequest:cropRequest,cropColorDeclarations:profile == .cropSamples ? color : nil)
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
        let o = try JSON.object(data,maximum:65_535,decoderSampleFields:profile != .metadata), kind = try JSON.string(o,"kind")
        switch kind {
        case "begin", "sample-begin", "crop-begin":
            guard kind == (profile == .metadata ? "begin" : profile == .baseSamples ? "sample-begin" : "crop-begin") else { throw Self.refused() }
            guard rows == 1, !began,
                  Set(o.keys) == ["kind","version","input_bytes","time_base","configuration_bytes","configuration_sha256","decoder","codec_version","format_version","util_version","automatic_codec_crop","threads"],
                  try n(o,"version") == 1, try n(o,"input_bytes") == UInt64(source.byteCount),
                  try JSON.string(o,"decoder") == "hevc", try n(o,"threads") == UInt64(threads),
                  try n(o,"codec_version") == versions[0], try n(o,"format_version") == versions[1], try n(o,"util_version") == versions[2],
                  try n(o,"configuration_bytes",1...(1 << 20)) > 0 else { throw Self.refused() }
            try JSON.bool(o,"automatic_codec_crop",false)
            timeBase = try array(o,"time_base",count:2,range:1...UInt64(Int32.max))
            configuration = try JSON.digest(o,"configuration_sha256"); began=true
        case "packet", "crop-packet":
            guard kind == (profile == .cropSamples ? "crop-packet" : "packet") else { throw Self.refused() }
            guard began, packets < 2_000_000,
                  Set(o.keys) == ["kind","index","pts","block_input_byte_offset","encoded_bytes","sha256"],
                  try n(o,"index") == UInt64(packets) else { throw Self.refused() }
            let p = try packetBounds(o,sizeKey:"encoded_bytes")
            guard lastPacketOffset.map({ p > $0 }) ?? true else { throw Self.refused() }
            _ = try signed(o,"pts"); _ = try JSON.digest(o,"sha256")
            lastPacketOffset=p; packets += 1
        case "frame", "sample-frame", "crop-frame":
            guard kind == (profile == .metadata ? "frame" : profile == .baseSamples ? "sample-frame" : "crop-frame") else { throw Self.refused() }
            let baseKeys: Set<String> = ["kind","index","packet_index","block_input_byte_offset","packet_size","packet_pts","pts","best_effort_pts","width","height","pixel_format","interlaced","codec_crop_left_right_top_bottom","sample_aspect_ratio","rpu_bytes","rpu_sha256"]
            let sampleKeys: Set<String> = ["sample_encoding","color_range","color_primaries","color_transfer","color_matrix","chroma_location","container_crop_applied","edited_picture_semantics_verified","coded","codec_visible"]
            let cropKeys: Set<String> = ["sample_encoding","color_range","color_primaries","color_transfer","color_matrix","chroma_location","container_crop_applied","source_roi_provenance_verified","independent_sample_values_verified","edited_picture_semantics_verified","request_space","requested_rect","coded_rect","roi"]
            let expected = profile == .cropSamples ? baseKeys.subtracting(["best_effort_pts","sample_aspect_ratio"]).union(cropKeys) : profile == .metadata ? baseKeys : baseKeys.union(sampleKeys)
            guard Set(o.keys) == expected else { throw Self.refused() }
            guard began, packets > 0, frames < 2_000_000,
                  try n(o,"index") == UInt64(frames), try n(o,"packet_index",0...UInt64(packets-1)) < UInt64(packets) else { throw Self.refused() }
            _ = try packetBounds(o,sizeKey:"packet_size")
            let pts = try signed(o,"pts")
            if profile != .cropSamples { guard pts == (try signed(o,"best_effort_pts")) else { throw Self.refused() } }
            guard pts == (try signed(o,"packet_pts")),
                  lastFramePTS.map({ pts > $0 }) ?? true,
                  try JSON.string(o,"pixel_format") == "yuv420p10le", try n(o,"rpu_bytes",1...65536) > 0 else { throw Self.refused() }
            try JSON.bool(o,"interlaced",false); _ = try JSON.digest(o,"rpu_sha256")
            let w = Int(try n(o,"width",1...8192)), h = Int(try n(o,"height",1...8192))
            let crop = try array(o,"codec_crop_left_right_top_bottom",count:4,range:0...8191)
            let sar: [Int]? = profile == .cropSamples ? nil : try array(o,"sample_aspect_ratio",count:2,range:1...65535)
            guard w*h <= 4096*4096, crop[0]+crop[1] < w, crop[2]+crop[3] < h else { throw Self.refused() }
            let current = Geometry(width:w,height:h,crop:crop,sampleAspectRatio:sar)
            guard geometry.map({ $0 == current }) ?? true else { throw Self.refused() }
            if profile == .baseSamples { try sampleFrame(o,geometry:current) }
            if profile == .cropSamples { try cropFrame(o,geometry:current) }
            geometry=current; lastFramePTS=pts; frames += 1
        case "complete", "sample-complete", "crop-complete":
            guard kind == (profile == .metadata ? "complete" : profile == .baseSamples ? "sample-complete" : "crop-complete") else { throw Self.refused() }
            guard began, packets > 0, frames == packets,
                  Set(o.keys) == ["kind","version","packets","frames","decoder_drained","descriptor_unchanged"],
                  try n(o,"version") == 1, try n(o,"packets") == UInt64(packets), try n(o,"frames") == UInt64(frames) else { throw Self.refused() }
            try JSON.bool(o,"decoder_drained",true); try JSON.bool(o,"descriptor_unchanged",true); complete=true
        default: throw Self.refused()
        }
    }
    private func plane(_ value: JSON.Value, width: Int, height: Int) throws -> PlaneSummary {
        guard case .object(let o) = value,
              Set(o.keys) == ["width","height","samples","minimum","maximum","sum","sum_squares","sha256"],
              try n(o,"width") == UInt64(width), try n(o,"height") == UInt64(height),
              try n(o,"samples") == UInt64(width*height) else { throw Self.refused() }
        let count=UInt64(width*height), low=try n(o,"minimum",0...1023), high=try n(o,"maximum",0...1023)
        let sum=try n(o,"sum",0...(count*1023)), squares=try n(o,"sum_squares",0...(count*1023*1023))
        guard low <= high, sum >= (count-1)*low+high, sum <= (count-1)*high+low,
              squares >= (count-1)*low*low+high*high, squares <= (count-1)*high*high+low*low,
              squares >= sum*low, squares <= sum*high else { throw Self.refused() }
        // Cauchy bound using full-width products; sum squared can exceed UInt64.
        let lhs=sum.multipliedFullWidth(by:sum), rhs=squares.multipliedFullWidth(by:count)
        guard lhs.high < rhs.high || (lhs.high == rhs.high && lhs.low <= rhs.low) else { throw Self.refused() }
        return .init(width:width,height:height,samples:count,minimum:low,maximum:high,sum:sum,
                     sumSquares:squares,sha256:try JSON.digest(o,"sha256"))
    }
    private func sampleFrame(_ o: JSON.Object, geometry g: Geometry) throws {
        guard g.width % 2 == 0, g.height % 2 == 0, g.crop.allSatisfy({ $0 % 2 == 0 }),
              try JSON.string(o,"sample_encoding") == "little-endian-uint16-code-values",
              case .array(let rawCoded)? = o["coded"], rawCoded.count == 3,
              case .array(let rawVisible)? = o["codec_visible"], rawVisible.count == 3 else { throw Self.refused() }
        try JSON.bool(o,"container_crop_applied",false);try JSON.bool(o,"edited_picture_semantics_verified",false)
        let declarations=ColorDeclarations(range:Int(try n(o,"color_range",0...2)),
            primaries:Int(try n(o,"color_primaries",0...255)),transfer:Int(try n(o,"color_transfer",0...255)),
            matrix:Int(try n(o,"color_matrix",0...255)),chromaLocation:Int(try n(o,"chroma_location",0...6)))
        guard color.map({ $0 == declarations }) ?? true else { throw Self.refused() }
        var coded=[PlaneSummary](), visible=[PlaneSummary]()
        for i in 0..<3 {
            let divisor=i == 0 ? 1:2
            let c=try plane(rawCoded[i],width:g.width/divisor,height:g.height/divisor)
            let v=try plane(rawVisible[i],width:(g.width-g.crop[0]-g.crop[1])/divisor,height:(g.height-g.crop[2]-g.crop[3])/divisor)
            guard v.samples <= c.samples, v.minimum >= c.minimum, v.maximum <= c.maximum,
                  v.sum <= c.sum, v.sumSquares <= c.sumSquares,
                  !g.crop.allSatisfy({ $0 == 0 }) || c == v else { throw Self.refused() }
            coded.append(c);visible.append(v)
        }
        color=declarations
        try observeSamples(.init(index:frames,packetIndex:Int64(try n(o,"packet_index",0...UInt64(packets-1))),
                                 coded:coded,codecVisible:visible,color:declarations))
    }

    private func cropFrame(_ o: JSON.Object, geometry g: Geometry) throws {
        guard let request=cropRequest, g.width % 2 == 0, g.height % 2 == 0,
              g.crop.allSatisfy({ $0 % 2 == 0 }),
              try JSON.string(o,"sample_encoding") == "little-endian-uint16-code-values",
              try JSON.string(o,"request_space") == request.space.rawValue,
              try array(o,"requested_rect",count:4,range:0...8192) == request.rectangle,
              case .array(let raw)? = o["roi"], raw.count == 3 else { throw Self.refused() }
        for key in ["container_crop_applied","source_roi_provenance_verified","independent_sample_values_verified","edited_picture_semantics_verified"] { try JSON.bool(o,key,false) }
        let r=request.rectangle
        let x=request.space == .coded ? 0 : g.crop[0], y=request.space == .coded ? 0 : g.crop[2]
        let w=request.space == .coded ? g.width : g.width-g.crop[0]-g.crop[1]
        let h=request.space == .coded ? g.height : g.height-g.crop[2]-g.crop[3]
        guard r[0] < w, r[1] < h, r[2] <= w-r[0], r[3] <= h-r[1] else { throw Self.refused() }
        let absolute=[x+r[0],y+r[1],r[2],r[3]]
        guard try array(o,"coded_rect",count:4,range:0...8192) == absolute else { throw Self.refused() }
        let declarations=ColorDeclarations(range:Int(try n(o,"color_range",0...2)),
            primaries:Int(try n(o,"color_primaries",0...255)),transfer:Int(try n(o,"color_transfer",0...255)),
            matrix:Int(try n(o,"color_matrix",0...255)),chromaLocation:Int(try n(o,"chroma_location",0...6)))
        guard color.map({ $0 == declarations }) ?? true else { throw Self.refused() }
        var planes=[PlaneSummary]()
        for i in 0..<3 { let d=i == 0 ? 1:2; planes.append(try plane(raw[i],width:r[2]/d,height:r[3]/d)) }
        color=declarations
        try observeCrops(.init(index:frames,packetIndex:Int64(try n(o,"packet_index",0...UInt64(packets-1))),
            request:request,codedRectangle:absolute,planes:planes,color:declarations))
    }

}
