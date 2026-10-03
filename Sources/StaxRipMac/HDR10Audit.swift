import Foundation

// Exact positive fractions. Bounds keep all cadence arithmetic within Decimal's
// exact integer precision (at most 31 digits); no accumulating floating tolerance.
struct HDRFraction: Equatable, Sendable {
    let numerator: Int64
    let denominator: Int64
    init(_ text: String?) throws {
        let parts = (text ?? "").split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let n = Int64(parts[0]), let d = Int64(parts[1]),
              (0...1_000_000_000).contains(n), (1...1_000_000_000).contains(d) else {
            throw HDR10Audit.failure("Missing or invalid rational metadata.")
        }
        var a = n, b = d
        while b != 0 { (a, b) = (b, a % b) }
        numerator = n / max(1, a); denominator = d / max(1, a)
    }
    var value: Double { Double(numerator) / Double(denominator) }
    func scaled(_ scale: Int64, maximum: Int64) throws -> Int64 {
        let product = numerator * scale
        guard product % denominator == 0, product / denominator <= maximum else {
            throw HDR10Audit.failure("Static metadata cannot be represented exactly in HDR10 units.")
        }
        return product / denominator
    }
}

struct HDRMasteringDisplay: Equatable, Sendable {
    // In HEVC units: xy / 50000; luminance / 10000 cd/m².
    let redX, redY, greenX, greenY, blueX, blueY, whiteX, whiteY, minimum, maximum: Int64
    init(_ data: [String: Any]) throws {
        func coordinate(_ key: String) throws -> Int64 {
            try HDRFraction(data[key] as? String).scaled(50000, maximum: 50000)
        }
        redX = try coordinate("red_x"); redY = try coordinate("red_y")
        greenX = try coordinate("green_x"); greenY = try coordinate("green_y")
        blueX = try coordinate("blue_x"); blueY = try coordinate("blue_y")
        whiteX = try coordinate("white_point_x"); whiteY = try coordinate("white_point_y")
        minimum = try HDRFraction(data["min_luminance"] as? String).scaled(10000, maximum: 4_294_967_295)
        maximum = try HDRFraction(data["max_luminance"] as? String).scaled(10000, maximum: 4_294_967_295)
        guard minimum < maximum, maximum > 0,
              redX + redY <= 50000, greenX + greenY <= 50000, blueX + blueY <= 50000,
              whiteX + whiteY <= 50000, whiteY > 0,
              (redX - blueX) * (greenY - blueY) != (greenX - blueX) * (redY - blueY) else {
            throw HDR10Audit.failure("Invalid mastering display primaries or luminance bounds.")
        }
    }
    var parameter: String {
        "G(\(greenX),\(greenY))B(\(blueX),\(blueY))R(\(redX),\(redY))WP(\(whiteX),\(whiteY))L(\(maximum),\(minimum))"
    }
}

struct HDRContentLight: Equatable, Sendable {
    let maximum, average: Int64
    init(_ data: [String: Any]) throws {
        maximum = try HDR10Audit.integer(data["max_content"], range: 0...65535)
        average = try HDR10Audit.integer(data["max_average"], range: 0...65535)
        guard maximum == 0 || average <= maximum else { throw HDR10Audit.failure("MaxFALL exceeds MaxCLL.") }
    }
}

struct HDR10Contract: Equatable, Sendable {
    let width, height: Int
    let rate: HDRFraction
    let timeBase: HDRFraction
    let mastering: HDRMasteringDisplay
    let light: HDRContentLight?
    let frames: Int64
    let lastPTS: Int64
    var x265Parameters: String {
        "pools=4:frame-threads=2:repeat-headers=1:hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:range=limited:chromaloc=0:master-display=\(mastering.parameter):" +
        (light.map { "max-cll=\($0.maximum),\($0.average)" } ?? "cll=0")
    }
    func verify(_ output: HDR10Contract) throws {
        guard width == output.width, height == output.height, rate == output.rate,
              mastering == output.mastering, light == output.light, frames == output.frames else {
            throw HDR10Audit.failure("Output differs from the audited source's dimensions, cadence, static metadata or frame count. Nothing published.")
        }
        // Each audit already checked every timestamp against this same rational cadence.
    }
    var summary: String {
        "Verified \(frames) frames · source → output: 10-bit PQ / BT.2020 / limited / left chroma unchanged.\n" +
        "Mastering display unchanged: R(\(mastering.redX),\(mastering.redY)) G(\(mastering.greenX),\(mastering.greenY)) B(\(mastering.blueX),\(mastering.blueY)) white(\(mastering.whiteX),\(mastering.whiteY)), coordinates / 50000; luminance \(Double(mastering.minimum) / 10000)–\(Double(mastering.maximum) / 10000) cd/m².\n" +
        (light.map { "MaxCLL \($0.maximum), MaxFALL \($0.average) unchanged" } ?? "content-light metadata absent in both")
    }
}

// Parses exactly {"frames":[{...},...]} incrementally. Only one bounded frame is
// retained. Strict framing, complete closing delimiters and successful process
// exit are independent requirements. Unknown top-level data is not skipped.
final class HDRFrameJSON: @unchecked Sendable {
    static let recordLimit = 1024 * 1024
    private enum State { case prefix, first, next, object, separator, close, done }
    private var state = State.prefix
    private let prefix = Array("{\"frames\":[".utf8)
    private var prefixIndex = 0
    private var record = Data()
    private var depth = 0, tokens = 0, quoted = false, escaped = false
    private var keys: [Set<String>?] = []
    private var key = Data(), readingKey = false
    private var previous: UInt8 = 123
    private let consume: ([String: Any]) throws -> Void
    private(set) var error: Error?
    private(set) var peakRecordBytes = 0
    init(consume: @escaping ([String: Any]) throws -> Void) { self.consume = consume }
    func accept(_ chunk: Data) {
        guard error == nil else { return }
        do { for byte in chunk { try accept(byte) } } catch { self.error = error; record.removeAll() }
    }
    private func accept(_ byte: UInt8) throws {
        if state != .object, [9,10,13,32].contains(byte) {
            guard state != .prefix || !(2...8).contains(prefixIndex) else { throw HDR10Audit.failure("Whitespace inside JSON key.") }
            return
        }
        switch state {
        case .prefix:
            guard byte == prefix[prefixIndex] else { throw HDR10Audit.failure("Malformed audit JSON header.") }
            prefixIndex += 1
            if prefixIndex == prefix.count { state = .first }
        case .first, .next:
            if state == .first && byte == 93 { state = .close; return }
            guard byte == 123 else { throw HDR10Audit.failure("Expected a complete frame record.") }
            record = Data([byte]); depth = 1; tokens = 0; quoted = false; escaped = false; state = .object
            keys = [Set<String>()]; previous = 123; readingKey = false
        case .object:
            guard record.count < Self.recordLimit else { throw HDR10Audit.failure("Frame metadata exceeds the 1 MiB safety limit.") }
            record.append(byte); peakRecordBytes = max(peakRecordBytes, record.count)
            if quoted {
                if readingKey {
                    // ffprobe's selected schema uses short, literal ASCII keys.
                    guard byte != 92, key.count < 128 else { throw HDR10Audit.failure("Unexpected JSON key encoding or size.") }
                    if byte == 34 {
                        let name = String(decoding: key, as: UTF8.self)
                        guard keys[keys.count - 1]?.insert(name).inserted == true else { throw HDR10Audit.failure("Duplicate JSON metadata key.") }
                        readingKey = false
                    } else { key.append(byte) }
                }
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 {
                quoted = true; tokens += 1
                readingKey = keys.last! != nil && (previous == 123 || previous == 44)
                key.removeAll(keepingCapacity: true)
            } else if byte == 44 { tokens += 1 }
            else if byte == 123 || byte == 91 { depth += 1; keys.append(byte == 123 ? Set<String>() : nil) }
            else if byte == 125 || byte == 93 { depth -= 1; if !keys.isEmpty { keys.removeLast() } }
            if !quoted && ![9,10,13,32].contains(byte) { previous = byte }
            guard depth <= 16, tokens <= 2048 else { throw HDR10Audit.failure("Excessive metadata nesting or field count.") }
            if depth == 0 {
                guard let frame = try JSONSerialization.jsonObject(with: record) as? [String: Any] else { throw HDR10Audit.failure("Invalid frame metadata.") }
                try consume(frame)
                record.removeAll(keepingCapacity: true); state = .separator
            }
        case .separator:
            if byte == 44 { state = .next }
            else if byte == 93 { state = .close }
            else { throw HDR10Audit.failure("Invalid frame separator.") }
        case .close:
            guard byte == 125 else { throw HDR10Audit.failure("Incomplete audit document.") }
            state = .done
        case .done: throw HDR10Audit.failure("Unexpected data after audit document.")
        }
    }
    func finish() throws {
        if let error { throw error }
        guard state == .done else { throw HDR10Audit.failure("Incomplete frame audit; nothing published.") }
    }
}

final class HDRFrameAccumulator: @unchecked Sendable {
    let stream: MediaProbe.Stream
    let rate, timeBase: HDRFraction
    private let declaredMastering: HDRMasteringDisplay?
    private let declaredLight: HDRContentLight?
    private var mastering: HDRMasteringDisplay?
    private var light: HDRContentLight?
    private var count: Int64 = 0, lastPTS: Int64 = -1
    private let progress: (@Sendable (Int64, Double) -> Void)?
    private let duration: Double
    private var nextUpdate: UInt64 = 0
    init(stream: MediaProbe.Stream, expectedRate: HDRFraction? = nil, duration: Double = 0, progress: (@Sendable (Int64, Double) -> Void)? = nil) throws {
        self.duration = duration; self.progress = progress
        try HDR10Audit.validate(stream)
        self.stream = stream
        var md: HDRMasteringDisplay?, cl: HDRContentLight?
        for item in stream.side_data_list ?? [] {
            if item.side_data_type == "Mastering display metadata" {
                guard md == nil else { throw HDR10Audit.failure("Duplicate stream mastering metadata.") }
                md = try HDRMasteringDisplay(item.fields())
            } else if item.side_data_type == "Content light level metadata" {
                guard cl == nil else { throw HDR10Audit.failure("Duplicate stream content-light metadata.") }
                cl = try HDRContentLight(item.fields())
            }
        }
        declaredMastering = md; declaredLight = cl
        let declared = try HDRFraction(stream.avg_frame_rate)
        guard declared.numerator > 0, (1...240).contains(declared.value), declared == (try HDRFraction(stream.r_frame_rate)) else {
            throw HDR10Audit.failure("A stable declared frame rate from 1 to 240 fps is required.")
        }
        if let expectedRate, declared != expectedRate { throw HDR10Audit.failure("Output frame rate changed.") }
        rate = declared; timeBase = try HDRFraction(stream.time_base)
        guard timeBase.numerator > 0, timeBase.value <= 1 / (declared.value * 2) else { throw HDR10Audit.failure("Timestamp time base is missing or too coarse to verify cadence.") }
    }
    func consume(_ f: [String: Any]) throws {
        guard f["pix_fmt"] as? String == "yuv420p10le", f["color_range"] as? String == "tv",
              f["color_space"] as? String == "bt2020nc", f["color_primaries"] as? String == "bt2020",
              f["color_transfer"] as? String == "smpte2084", f["chroma_location"] as? String == "left",
              f["sample_aspect_ratio"] as? String == "1:1",
              try HDR10Audit.integer(f["width"], range: 2...16384) == Int64(stream.width!),
              try HDR10Audit.integer(f["height"], range: 2...16384) == Int64(stream.height!),
              try HDR10Audit.integer(f["interlaced_frame"], range: 0...1) == 0 else {
            throw HDR10Audit.failure("Frame \(count + 1) has unsupported or changing picture/color properties.")
        }
        let pts = try HDR10Audit.integer(f["pts"], range: 0...1_000_000_000_000)
        let lhs = Decimal(pts) * Decimal(timeBase.numerator) * Decimal(rate.numerator)
        let rhs = Decimal(count) * Decimal(timeBase.denominator) * Decimal(rate.denominator)
        let tick = Decimal(timeBase.numerator) * Decimal(rate.numerator)
        guard count < 1_000_000_000, pts > lastPTS, (count != 0 || pts == 0), abs(lhs - rhs) <= tick else {
            throw HDR10Audit.failure("Frame \(count + 1) is not on the supported zero-start fixed cadence (one container tick tolerance).")
        }
        guard let side = f["side_data_list"] as? [[String: Any]], side.count <= 64 else { throw HDR10Audit.failure("Missing or excessive static metadata.") }
        var md: HDRMasteringDisplay?, cl: HDRContentLight?
        for item in side {
            switch item["side_data_type"] as? String {
            case "Mastering display metadata":
                guard md == nil else { throw HDR10Audit.failure("Duplicate mastering metadata.") }
                md = try HDRMasteringDisplay(item)
            case "Content light level metadata":
                guard cl == nil else { throw HDR10Audit.failure("Duplicate content-light metadata.") }
                cl = try HDRContentLight(item)
            case "H.26[45] User Data Unregistered SEI message": break
            default: throw HDR10Audit.failure("Unsupported frame side data: \(String(describing: item["side_data_type"])). Dynamic HDR is not supported.")
            }
        }
        guard let md else { throw HDR10Audit.failure("Every decoded frame must declare mastering display metadata.") }
        if let declaredMastering, declaredMastering != md { throw HDR10Audit.failure("Container and decoded mastering metadata disagree.") }
        if let declaredLight, declaredLight != cl { throw HDR10Audit.failure("Container and decoded content-light metadata disagree.") }
        if count == 0 { mastering = md; light = cl }
        else if md != mastering || cl != light { throw HDR10Audit.failure("Static HDR metadata changes at frame \(count + 1).") }
        count += 1; lastPTS = pts
        let now = DispatchTime.now().uptimeNanoseconds
        if now >= nextUpdate {
            nextUpdate = now + 250_000_000
            progress?(count, duration > 0 && duration.isFinite ? min(0.99, Double(pts) * timeBase.value / duration) : 0)
        }
    }
    func finish() throws -> HDR10Contract {
        guard let mastering, count > 0 else { throw HDR10Audit.failure("No complete HDR frames were decoded.") }
        if let declared = stream.nb_frames, declared != "N/A", Int64(declared) != count { throw HDR10Audit.failure("Decoded frame count differs from the container count.") }
        return HDR10Contract(width: stream.width!, height: stream.height!, rate: rate, timeBase: timeBase, mastering: mastering, light: light, frames: count, lastPTS: lastPTS)
    }
}

enum HDR10Audit {
    static func failure(_ text: String) -> NativeExportError { .invalid("HDR10: " + text) }
    static func integer(_ raw: Any?, range: ClosedRange<Int64>) throws -> Int64 {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let value = Int64(number.stringValue), range.contains(value) else { throw failure("Missing or invalid integer metadata.") }
        return value
    }
    static func validate(_ s: MediaProbe.Stream) throws {
        try HDRInspection.requireQualifiedTranscode(s)
        guard s.codec_name == "hevc", s.profile == "Main 10", s.pix_fmt == "yuv420p10le",
              s.color_transfer == "smpte2084", s.color_primaries == "bt2020", s.color_space == "bt2020nc",
              s.color_range == "tv", s.chroma_location == "left", s.field_order == "progressive",
              s.sample_aspect_ratio == "1:1", s.start_pts == 0,
              (s.tags?["rotate"] ?? "0") == "0", (s.width ?? 0) % 2 == 0, (s.height ?? 0) % 2 == 0,
              (2...16384).contains(s.width ?? 0), (2...16384).contains(s.height ?? 0) else {
            throw failure("Requires HEVC Main 10, 10-bit 4:2:0, limited PQ / BT.2020, left chroma, progressive square pixels, no rotation and zero start.")
        }
        // Stream-level side data can signal Dolby Vision before decoding frames.
        // Only static declarations are accepted, and compared with decoded frames.
        guard (s.side_data_list ?? []).count <= 2,
              (s.side_data_list ?? []).allSatisfy({ ["Mastering display metadata", "Content light level metadata"].contains($0.side_data_type ?? "") && ($0.rotation ?? 0) == 0 }) else { throw failure("Stream side data is outside this initial HDR10 contract (including dynamic HDR and display matrices).") }
    }
    static func checkTools(_ tools: FFmpegTools) async throws {
        for executable in [tools.ffmpeg, tools.ffprobe] {
            let r = try await ToolRunner().run(executable: executable, arguments: ["-version"])
            let words = String(decoding: r.stdout, as: UTF8.self).split(whereSeparator: \.isWhitespace)
            guard r.status == 0, !r.truncated, words.count >= 3,
                  words[2] == "9.0" || words[2].hasPrefix("9.0.") else {
                throw failure("This initial metadata audit is qualified for FFmpeg/ffprobe 9.0.x. Other versions need separate validation.")
            }
        }
    }
    static func read(_ source: URL, tools: FFmpegTools, probe: MediaProbe, expectedRate: HDRFraction? = nil, progress: (@Sendable (Int64, Double) -> Void)? = nil, metrics: (@Sendable (Int) -> Void)? = nil) async throws -> HDR10Contract {
        guard let stream = probe.video else { throw failure("No selected video stream.") }
        let accumulator = try HDRFrameAccumulator(stream: stream, expectedRate: expectedRate, duration: probe.seconds, progress: progress)
        let parser = HDRFrameJSON { try accumulator.consume($0) }
        let runner = ToolRunner()
        let result: ToolResult
        do {
            result = try await runner.run(executable: tools.ffprobe, arguments: [
                "-v", "error", "-threads", "2", "-protocol_whitelist", "file,pipe", "-select_streams", String(stream.index), "-show_frames",
                "-show_entries", "frame=pts,width,height,pix_fmt,color_range,color_space,color_primaries,color_transfer,chroma_location,sample_aspect_ratio,interlaced_frame:frame_side_data",
                "-of", "json", source.path
            ], stdoutLimit: 0) { data in
                // Request cancellation once; a pipe may still drain several chunks.
                guard parser.error == nil else { return }
                parser.accept(data)
                if parser.error != nil { runner.cancel() }
            }
        } catch {
            if let parsingError = parser.error { throw parsingError }
            throw error
        }
        try Task.checkCancellation()
        guard result.status == 0, result.stderr.isEmpty else { throw failure("Full decode failed. " + String(decoding: result.stderr, as: UTF8.self)) }
        // stdoutLimit=0 deliberately retains no transcript. Only the streaming
        // parser's complete-document check certifies receipt of all records.
        try parser.finish()
        let contract = try accumulator.finish()
        metrics?(parser.peakRecordBytes)
        return contract
    }
}
