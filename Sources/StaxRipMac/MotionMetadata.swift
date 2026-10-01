import Foundation

struct MotionFrame: Sendable {
    let stamp: PreviewStamp
    let width, height: Int
    let aspect: HDRFraction
    let format: String
    var color: String?
}

// One bounded line and at most 600 records for each of four fixed branches.
// Only the joined stderr callback mutates this value during rendering.
struct MotionMetadata: Sendable {
    static let names = ["original", "filtered", "originalfit", "filteredfit"]
    private var partial = Data()
    private var bases: [String: HDRFraction] = [:]
    private(set) var frames: [String: [MotionFrame]] = [:]
    private let limit: Int
    init(limit: Int = 600) { self.limit = min(600, max(1, limit)) }
    mutating func accept(_ data: Data) throws {
        for byte in data {
            if byte == 10 { try line(); partial.removeAll(keepingCapacity: true) }
            else {
                guard partial.count < 16_384 else { throw PicturePreview.failure("Motion metadata exceeded its line limit.") }
                partial.append(byte)
            }
        }
    }
    mutating func finish() throws {
        // FFmpeg's complete records end with a newline; don't accept a cut trace.
        guard partial.isEmpty else { throw PicturePreview.failure("Motion metadata ended in an incomplete record.") }
        for name in Self.names {
            guard bases[name] != nil, let records = frames[name], !records.isEmpty,
                  records.allSatisfy({ $0.color != nil }) else {
                throw PicturePreview.failure("Motion frame evidence is incomplete.")
            }
        }
    }
    private mutating func line() throws {
        guard let text = String(data: partial, encoding: .utf8) else { throw PicturePreview.failure("Motion metadata is not valid text.") }
        guard let name = Self.names.first(where: { text.hasPrefix("[showinfo@\($0) @ ") }) else { return }
        if text.contains("config in time_base:") {
            guard bases[name] == nil else { throw PicturePreview.failure("Motion time base changed during decoding.") }
            let values = try Self.match(#"config in time_base: ([0-9]+/[0-9]+),"#, text)
            let base = try HDRFraction(values[0]); guard base.numerator > 0 else { throw PicturePreview.failure("Invalid motion time base.") }
            bases[name] = base
        } else if text.range(of: #"\bn:\s*"#, options: .regularExpression) != nil {
            let values = try Self.match(#"\bn:\s*([0-9]+)\s+pts:\s*([0-9]+)\s.*?fmt:(\w+) .*?sar:([0-9]+/[0-9]+) s:([0-9]+)x([0-9]+) "#, text)
            let prior = frames[name] ?? []
            guard let base = bases[name], let n = Int(values[0]), n == prior.count, n < limit,
                  let pts = Int64(values[1]), (0...1_000_000_000_000).contains(pts),
                  prior.last.map({ $0.color != nil && pts > $0.stamp.pts }) ?? true,
                  let w = Int(values[4]), let h = Int(values[5]), (2...3840).contains(w), (2...3840).contains(h), w * h <= 3840 * 2160 else {
                throw PicturePreview.failure("Motion frames exceed their bounds or have missing, repeated or unordered timestamps.")
            }
            let aspect = try HDRFraction(values[3])
            guard aspect.value > 0, aspect.value < 10 else { throw PicturePreview.failure("Invalid motion pixel aspect.") }
            frames[name, default: []].append(MotionFrame(stamp: PreviewStamp(pts: pts, base: base), width: w, height: h, aspect: aspect, format: values[2]))
        } else if text.range(of: #"^\[showinfo@\w+ @ [^\]]+\] color_range:"#, options: .regularExpression) != nil {
            guard let last = frames[name]?.last, last.color == nil else { throw PicturePreview.failure("Motion color evidence is ambiguous.") }
            frames[name]![frames[name]!.count - 1].color = String(text[text.range(of: "color_range:")!.lowerBound...])
        }
    }
    private static func match(_ pattern: String, _ text: String) throws -> [String] {
        let re = try NSRegularExpression(pattern: pattern)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            throw PicturePreview.failure("Malformed motion frame evidence.")
        }
        return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    func verify(time: Double, end: Double, range: String) throws -> [MotionFrame] {
        guard let original = frames["original"], !original.isEmpty else { throw PicturePreview.failure("No motion frames at this source time.") }
        for name in Self.names {
            guard let records = frames[name], records.count == original.count else { throw PicturePreview.failure("Motion branches contain different frame counts.") }
            for (record, reference) in zip(records, original) {
                let fitted = name.hasSuffix("fit")
                let color = "color_range:\(fitted ? "tv" : range) color_space:bt709 color_primaries:bt709 color_trc:bt709"
                guard record.stamp.matches(reference.stamp), record.stamp.seconds + 1e-9 >= time, record.stamp.seconds < end,
                      ["yuv420p", "nv12"].contains(record.format), record.color?.hasPrefix(color) == true,
                      record.width == records[0].width, record.height == records[0].height, record.aspect == records[0].aspect else {
                    throw PicturePreview.failure("Motion branches disagree on timestamps, picture shape or supported color.")
                }
                if fitted {
                    guard record.width <= 640, record.height <= 360, record.aspect.value == 1 else {
                        throw PicturePreview.failure("Motion proxy geometry exceeds its bounds.")
                    }
                    let identity = frames[String(name.dropLast(3))]![0]
                    let dar = Double(identity.width) * identity.aspect.value / Double(identity.height)
                    let fitW = max(2, Int((min(640, 360 * dar) / 2).rounded(.down)) * 2)
                    let fitH = max(2, Int((min(360, 640 / dar) / 2).rounded(.down)) * 2)
                    guard record.width == fitW, record.height == fitH else { throw PicturePreview.failure("Motion proxy display fit could not be verified.") }
                }
            }
        }
        return original
    }
}
