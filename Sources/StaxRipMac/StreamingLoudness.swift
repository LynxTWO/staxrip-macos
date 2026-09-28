import Foundation

// Adapted from SignalForge 93d82e2, MIT; see THIRD-PARTY-NOTICES.md.
// Internal mono/stereo measurement, not a certification or a dialogue detector.
struct MeterValue: Codable, Equatable, Sendable {
    let value: Double?
    let unavailable: String?
    static func measured(_ value: Double?) -> MeterValue {
        if let value, value.isFinite { return MeterValue(value: value, unavailable: nil) }
        return MeterValue(value: nil, unavailable: "Silence, below gate, or insufficient duration")
    }
    var display: String { value.map { String(format: "%.2f", $0) } ?? "Unavailable" }
}
struct LoudnessPoint: Codable, Equatable, Sendable {
    let frame: Int64
    let momentary: Double?
    let shortTerm: Double?
}
struct MeterSummary: Equatable, Sendable {
    let frames: Int64
    let integrated: MeterValue
    let range: MeterValue
    let samplePeak: MeterValue
    let truePeak: MeterValue
    let trace: [LoudnessPoint]
}

private struct MeterBiquad {
    let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    mutating func process(_ x: Double) -> Double {
        let y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}
private struct MeterWeighting {
    var shelf: MeterBiquad
    var highpass: MeterBiquad
    init(rate: Int) {
        let k = tan(.pi * 1681.974450955533 / Double(rate))
        let vh = pow(10.0, 3.999843853973347 / 20), vb = pow(vh, 0.4996667741545416)
        let kq = k / 0.7071752369554196, kk = k*k, a0 = 1+kq+kk
        shelf = MeterBiquad(b0: (vh+vb*kq+kk)/a0, b1: 2*(kk-vh)/a0, b2: (vh-vb*kq+kk)/a0,
                           a1: 2*(kk-1)/a0, a2: (1-kq+kk)/a0)
        let h = tan(.pi * 38.13547087602444 / Double(rate)), hh = h*h, hq = h/0.5003270373238773
        highpass = MeterBiquad(b0: 1, b1: -2, b2: 1, a1: 2*(hh-1)/(1+hq+hh), a2: (1-hq+hh)/(1+hq+hh))
    }
    mutating func process(_ x: Double) -> Double { highpass.process(shelf.process(x)) }
}
private struct PeakInterpolator {
    static let coefficients: [[Double]] = [
        [0.0017089844,0.0109863280,-0.0196533200,0.0332031250,-0.0594482420,0.1373291000,0.9721679700,-0.1022949200,0.0476074220,-0.0266113280,0.0148925780,-0.0083007813],
        [-0.0291748050,0.0292968750,-0.0517578120,0.0891113280,-0.1665039100,0.4650878900,0.7797851600,-0.2003173800,0.1015625000,-0.0582275400,0.0330810550,-0.0189208980],
        [-0.0189208980,0.0330810550,-0.0582275400,0.1015625000,-0.2003173800,0.7797851600,0.4650878900,-0.1665039100,0.0891113280,-0.0517578120,0.0292968750,-0.0291748050],
        [-0.0083007813,0.0148925780,-0.0266113280,0.0476074220,-0.1022949200,0.9721679700,0.1373291000,-0.0594482420,0.0332031250,-0.0196533200,0.0109863280,0.0017089844]
    ]
    var delay = [Double](repeating: 0, count: 24)
    var cursor = 0
    var maximum = 0.0
    mutating func push(_ x: Double) {
        delay[cursor] = x; delay[cursor+12] = x
        let end = cursor+12
        maximum = max(maximum, abs(x))
        for phase in Self.coefficients {
            var sum = 0.0
            for tap in 0..<12 { sum += phase[tap] * delay[end-tap] }
            maximum = max(maximum, abs(sum))
        }
        cursor = (cursor+1)%12
    }
}

// Owned by one serial decoder consumer. PCM is never retained beyond a chunk.
final class StreamingLoudness {
    static let algorithm = "SignalForge-derived Swift meter 1; K-weighted BS.1770 gates; EBU LRA; 4x/12-tap peak estimate"
    let rate: Int, channels: Int
    private var filters: [MeterWeighting]
    private var peaks: [PeakInterpolator]
    private var ring: [Double]
    private var cursor = 0
    private var sum400 = 0.0, sum3 = 0.0, samplePeak = 0.0
    private var blocks: [Double] = [], shortBlocks: [Double] = []
    private var trace: [LoudnessPoint] = []
    private(set) var frames: Int64 = 0
    private let w400: Int, w3: Int, hop: Int, traceHop: Int
    private let captureTrace: Bool
    private var completed: MeterSummary?
    init(rate: Int, channels: Int, captureTrace: Bool = true) throws {
        guard [44100,48000,88200,96000,192000].contains(rate), (1...2).contains(channels) else {
            throw NativeExportError.invalid("Measured analysis supports explicit mono/stereo at 44.1, 48, 88.2, 96 or 192 kHz.")
        }
        self.rate = rate; self.channels = channels; self.captureTrace = captureTrace
        w400 = rate*4/10; w3 = rate*3; hop = rate/10; traceHop = rate/50
        filters = (0..<channels).map { _ in MeterWeighting(rate: rate) }
        peaks = (0..<channels).map { _ in PeakInterpolator() }
        ring = [Double](repeating: 0, count: rate*3)
    }
    func push(_ samples: [Double]) throws {
        guard samples.count % channels == 0 else { throw NativeExportError.invalid("Incomplete PCM frame.") }
        for offset in stride(from: 0, to: samples.count, by: channels) { try pushFrame(samples, offset: offset) }
    }
    func pushFrame(_ samples: [Double], offset: Int) throws {
        guard completed == nil, frames < Int64(rate)*14400 else { throw NativeExportError.invalid("Analysis is finished or exceeds the four-hour analysis limit.") }
        var energy = 0.0
        for channel in 0..<channels {
            let x = samples[offset+channel]
            guard x.isFinite, abs(x) <= 1e6 else { throw NativeExportError.invalid("Invalid or excessive decoded sample level.") }
            samplePeak = max(samplePeak, abs(x)); peaks[channel].push(x)
            let y = filters[channel].process(x); energy += y*y
        }
        addEnergy(energy, record: true)
    }
    private func addEnergy(_ energy: Double, record: Bool) {
        let old400 = ring[(cursor+w3-w400)%w3], old3 = ring[cursor]
        sum400 += energy-old400; sum3 += energy-old3
        ring[cursor] = energy; cursor = (cursor+1)%w3; frames += 1
        if frames >= w400, frames % Int64(hop) == 0, record { blocks.append(max(0,sum400/Double(w400))) }
        if frames >= w3, frames % Int64(hop) == 0 { shortBlocks.append(max(0,sum3/Double(w3))) }
        if record, captureTrace, frames % Int64(traceHop) == 0 {
            trace.append(LoudnessPoint(frame: frames, momentary: frames >= w400 ? Self.lufs(max(0,sum400/Double(w400))) : nil,
                                       shortTerm: frames >= w3 ? Self.lufs(max(0,sum3/Double(w3))) : nil))
        }
    }
    // Finishes once; tail affects LRA and interpolated peak only, never media duration or integrated LUFS.
    func finish() -> MeterSummary {
        if let completed { return completed }
        let actualFrames = frames
        for c in 0..<channels { for _ in 0..<12 { peaks[c].push(0) } }
        if actualFrames >= w3 { for _ in 0..<(rate*3/2) { addEnergy(0, record: false) } }
        let range: Double?
        let gated = Self.gate(shortBlocks, relativeLU: -20).compactMap(Self.lufs).sorted()
        if actualFrames >= w3, gated.count >= 2 {
            range = gated[Int((Double(gated.count-1)*0.95).rounded())] - gated[Int((Double(gated.count-1)*0.10).rounded())]
        } else { range = nil }
        let integrated = Self.gate(blocks, relativeLU: -10)
        let result = MeterSummary(frames: actualFrames, integrated: .measured(integrated.isEmpty ? nil : Self.lufs(integrated.reduce(0,+)/Double(integrated.count))),
                            range: .measured(range), samplePeak: .measured(Self.db(samplePeak)),
                            truePeak: .measured(Self.db(peaks.map(\.maximum).max() ?? 0)), trace: trace)
        completed = result
        return result
    }
    private static func db(_ x: Double) -> Double? { x > 0 ? 20*log10(x) : nil }
    private static func lufs(_ energy: Double) -> Double? { energy > 0 ? -0.691+10*log10(energy) : nil }
    private static func gate(_ energies: [Double], relativeLU: Double) -> [Double] {
        let absolute = energies.filter { (lufs($0) ?? -.infinity) > -70 }
        guard !absolute.isEmpty else { return [] }
        let threshold = absolute.reduce(0,+)/Double(absolute.count)*pow(10,relativeLU/10)
        return absolute.filter { $0 > threshold }
    }
}

// Fixed-width, lossless timeline encoding avoids one Foundation JSON object per point.
// Each record: LE Int64 frame, UInt8 presence flags, LE Float64 M, LE Float64 S.
// Absent values have a zero payload; no NaN sentinel is used.
extension MeterSummary: Codable {
    private enum CodingKeys: String, CodingKey { case frames, integrated, range, samplePeak, truePeak, traceEncoding, traceData }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(frames, forKey: .frames); try c.encode(integrated, forKey: .integrated)
        try c.encode(range, forKey: .range); try c.encode(samplePeak, forKey: .samplePeak); try c.encode(truePeak, forKey: .truePeak)
        try c.encode("frame-i64-flags-u8-ms-f64le-v1", forKey: .traceEncoding)
        var data = Data(); data.reserveCapacity(trace.count*25)
        for p in trace {
            var frame = p.frame.littleEndian
            withUnsafeBytes(of: &frame) { data.append(contentsOf: $0) }
            data.append((p.momentary == nil ? 0 : 1) | (p.shortTerm == nil ? 0 : 2))
            for value in [p.momentary, p.shortTerm] {
                var bits = (value ?? 0).bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        try c.encode(data, forKey: .traceData)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frames = try c.decode(Int64.self, forKey: .frames)
        integrated = try c.decode(MeterValue.self, forKey: .integrated)
        range = try c.decode(MeterValue.self, forKey: .range)
        samplePeak = try c.decode(MeterValue.self, forKey: .samplePeak)
        truePeak = try c.decode(MeterValue.self, forKey: .truePeak)
        guard try c.decode(String.self, forKey: .traceEncoding) == "frame-i64-flags-u8-ms-f64le-v1" else { throw NativeExportError.invalid("Unsupported timeline encoding.") }
        let data = try c.decode(Data.self, forKey: .traceData)
        guard data.count % 25 == 0, data.count <= 720000*25 else { throw NativeExportError.invalid("Invalid or oversized report timeline.") }
        var points: [LoudnessPoint] = []; points.reserveCapacity(data.count/25)
        try data.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: data.count, by: 25) {
                let frame = Int64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int64.self))
                let flags = bytes[offset+8]
                let m = Double(bitPattern: UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset+9, as: UInt64.self)))
                let s = Double(bitPattern: UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset+17, as: UInt64.self)))
                guard flags <= 3, m.isFinite, s.isFinite, flags & 1 != 0 || m == 0, flags & 2 != 0 || s == 0 else { throw NativeExportError.invalid("Invalid timeline values.") }
                points.append(LoudnessPoint(frame: frame, momentary: flags & 1 != 0 ? m : nil, shortTerm: flags & 2 != 0 ? s : nil))
            }
        }
        trace = points
    }
}
