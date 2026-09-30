import Foundation
import CoreGraphics

struct PreviewStamp: Equatable, Sendable {
    let pts: Int64
    let base: HDRFraction
    var seconds: Double { Double(pts) * base.value }
    func matches(_ other: Self) -> Bool {
        Decimal(pts) * Decimal(base.numerator) * Decimal(other.base.denominator) ==
        Decimal(other.pts) * Decimal(other.base.numerator) * Decimal(base.denominator)
    }
}

struct PictureFrame: Sendable {
    let rgb: Data
    let width, height: Int
    let aspect: HDRFraction
    let stamp: PreviewStamp
    var image: CGImage? {
        guard let provider = CGDataProvider(data: rgb as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .relativeColorimetric)
    }
}

struct PictureComparison: Sendable {
    let original, filtered: PictureFrame
    let requested: Double
    let sourceIdentity: SourceFingerprint
    let operations: String
}

// Only the stdout-draining callback mutates this buffer. ToolRunner joins that
// callback before returning, so the result is read after all writes finish.
private final class PreviewBytes: @unchecked Sendable {
    static let limit = 3840 * 2160 * 3
    var data = Data()
    var exceeded = false
    func append(_ chunk: Data, runner: ToolRunner) {
        guard !exceeded else { return }
        guard chunk.count <= Self.limit - data.count else { exceeded = true; runner.cancel(); return }
        data.append(chunk)
    }
}

enum PicturePreview {
    static func failure(_ text: String) -> Error { NativeExportError.invalid("Picture preview: " + text) }

    static func validate(_ c: EncodeConfiguration, probe: MediaProbe, time: Double) throws -> MediaProbe.Stream {
        try SessionDocument.validate(c)
        guard c.colorMode == "SDR", let v = probe.video,
              ["yuv420p", "nv12"].contains(v.pix_fmt ?? ""), v.color_primaries == "bt709",
              v.color_transfer == "bt709", v.color_space == "bt709", ["tv", "pc"].contains(v.color_range ?? ""),
              v.sample_aspect_ratio == "1:1", v.start_pts == 0,
              let width = v.width, let height = v.height, (2...3840).contains(width), (2...3840).contains(height), width * height <= 3840 * 2160 else {
            throw failure("Use a square-pixel, zero-start 8-bit SDR BT.709 source up to 3840 × 2160 (either orientation) with explicit color range. HDR and missing color metadata are not supported by this preview. Queue support is separate.")
        }
        guard let base = try? HDRFraction(v.time_base), base.numerator > 0 else { throw failure("The source has no valid time base.") }
        let orientation = try SourceOrientation.read(v)
        try orientation.validateTranscode(v, configuration: c)
        let uprightWidth = orientation.swapsAxes ? height : width
        let uprightHeight = orientation.swapsAxes ? width : height
        let p = c.picture
        guard uprightWidth > p.cropLeft + p.cropRight, uprightHeight > c.cropTop + c.cropBottom,
              (uprightWidth - p.cropLeft - p.cropRight) % 2 == 0, (uprightHeight - c.cropTop - c.cropBottom) % 2 == 0 else {
            throw failure("The crop must leave positive, even picture dimensions. Adjust the picture settings.")
        }
        let end = p.end > 0 ? p.end : probe.seconds
        guard probe.seconds.isFinite, probe.seconds > 0, end <= probe.seconds,
              time.isFinite, time >= p.start, time < end else {
            throw failure("Choose a source time inside the trim interval and before the end of the source.")
        }
        return v
    }

    enum StepResult: Sendable {
        case comparison(PictureComparison)
        case boundary
    }

    static func step(source: URL, configuration: EncodeConfiguration, anchor: PreviewStamp,
                     expectedSource: SourceFingerprint, direction: PreviewStepDirection, tools: FFmpegTools,
                     timeout: Double = 120, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> StepResult {
        try await withThrowingTaskGroup(of: StepResult.self) { group in
            group.addTask {
                progress("Checking the current comparison's source identity…")
                guard try await SourceFingerprint.read(source) == expectedSource else {
                    throw failure("The source changed since this comparison. Render again before stepping.")
                }
                let probe = try await MediaProbe.read(source, tools: tools)
                let video = try validate(configuration, probe: probe, time: anchor.seconds)
                let end = configuration.picture.end > 0 ? configuration.picture.end : probe.seconds
                progress("Reading decoded frame timestamps from the beginning…")
                let neighbor = try await PreviewFrameNeighbor.read(source: source, stream: video, anchor: anchor,
                    direction: direction, start: configuration.picture.start, end: end, tools: tools)
                guard let neighbor else {
                    guard try await SourceFingerprint.read(source) == expectedSource else {
                        throw failure("The source changed during frame discovery. Render again before stepping.")
                    }
                    try Task.checkCancellation()
                    return .boundary
                }
                // Request just before the selected timestamp to avoid decimal text
                // rounding up. Exact rational checks below decide acceptance.
                let time = max(configuration.picture.start, neighbor.seconds.nextDown)
                let comparison = try await render(source: source, configuration: configuration, time: time, tools: tools,
                    expectedSource: expectedSource, requiredStamp: neighbor, progress: progress)
                return .comparison(comparison)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.001, min(120, timeout)) * 1_000_000_000))
                throw failure("Frame stepping reached its time limit. Render a new comparison at an earlier source time.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func render(source: URL, configuration: EncodeConfiguration, time: Double, tools: FFmpegTools,
                       timeout: Double = 120, expectedSource: SourceFingerprint? = nil, requiredStamp: PreviewStamp? = nil,
                       progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> PictureComparison {
        try await withThrowingTaskGroup(of: PictureComparison.self) { group in
            group.addTask {
                progress("Checking source identity…")
                let identity = try await SourceFingerprint.read(source)
                if let expectedSource, identity != expectedSource {
                    throw failure("The source changed during frame discovery. Render again before stepping.")
                }
                let probe = try await MediaProbe.read(source, tools: tools)
                let video = try validate(configuration, probe: probe, time: time)
                let orientation = try SourceOrientation.read(video)
                let end = configuration.picture.end > 0 ? configuration.picture.end : probe.seconds
                progress("Reading the original frame from the beginning…")
                let original = try await frame(source: source, stream: video, filters: orientation.filters, time: time, end: end, tools: tools)
                progress("Applying picture filters from the beginning…")
                let plan = PicturePlan(configuration)
                let filtered = try await frame(source: source, stream: video, filters: orientation.filters + plan.filters, time: time, end: end, tools: tools)
                guard original.stamp.matches(filtered.stamp) else { throw failure("The original and filtered timestamps do not match. No comparison is shown.") }
                if let requiredStamp {
                    guard original.stamp.matches(requiredStamp), filtered.stamp.matches(requiredStamp) else {
                        throw failure("The rendered pictures did not match the selected decoded frame. No frame step was accepted.")
                    }
                }
                progress("Rechecking source identity…")
                guard try await SourceFingerprint.read(source) == identity else { throw failure("The source changed during rendering. Refresh after the source is stable.") }
                try Task.checkCancellation()
                return PictureComparison(original: original, filtered: filtered, requested: requiredStamp?.seconds ?? time, sourceIdentity: identity,
                                         operations: (orientation.degrees == 0 ? "" : orientation.summary + " · ") + plan.summary)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.001, min(120, timeout)) * 1_000_000_000))
                throw failure("Rendering reached its time limit. Choose an earlier source time or cancel and try another source.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func frame(source: URL, stream: MediaProbe.Stream, filters: [String], time: Double, end: Double, tools: FFmpegTools) async throws -> PictureFrame {
        // No input seek: temporal filters receive the same history as the queue.
        let select = "select=gte(t\\,\(time))*lt(t\\,\(end))"
        let display = "colorspace=all=bt709:trc=iec61966-2-1:range=pc:format=yuv444p,format=rgb24"
        let expression = (filters + [select, "showinfo@identity=checksum=0", display, "showinfo@display=checksum=0"]).joined(separator: ",")
        let runner = ToolRunner(), bytes = PreviewBytes()
        let orientation = try SourceOrientation.read(stream)
        let result: ToolResult
        do {
            result = try await runner.run(executable: tools.ffmpeg, arguments: [
                "-hide_banner", "-nostdin", "-xerror", "-loglevel", "info", "-threads", "2", "-protocol_whitelist", "file,pipe"] + orientation.inputArguments(stream: stream.index) + ["-i", source.path,
                "-map", "0:\(stream.index)", "-an", "-sn", "-dn", "-vf", expression, "-frames:v", "1", "-fps_mode", "passthrough",
                "-threads", "1", "-f", "rawvideo", "pipe:1"
            ], stdoutLimit: 0) { bytes.append($0, runner: runner) }
        } catch {
            if bytes.exceeded { throw failure("Rendered image exceeded the bounded preview size.") }
            throw error
        }
        guard result.status == 0 else { throw failure("The decoder or picture filter failed. Check the source and installed FFmpeg. No comparison was retained.") }
        return try parse(data: bytes.data, log: String(decoding: result.stderr, as: UTF8.self), expectedRange: stream.color_range!, time: time, end: end)
    }

    static func parse(data: Data, log: String, expectedRange: String, time: Double, end: Double) throws -> PictureFrame {
        func match(_ pattern: String, _ text: String) throws -> [String] {
            let re = try NSRegularExpression(pattern: pattern)
            guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { throw failure("Missing or malformed frame metadata; no comparison is shown.") }
            return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
        func record(_ name: String) throws -> (PreviewStamp, Int, Int, HDRFraction, String) {
            let lines = log.components(separatedBy: .newlines).filter { $0.hasPrefix("[showinfo@\(name) @ ") }
            guard lines.filter({ $0.contains("config in time_base:") }).count == 1,
                  lines.filter({ $0.range(of: #"\bn:\s+0\s+pts:"#, options: .regularExpression) != nil }).count == 1,
                  let config = lines.first(where: { $0.contains("config in time_base:") }),
                  let index = lines.firstIndex(where: { $0.range(of: #"\bn:\s+0\s+pts:"#, options: .regularExpression) != nil }), index + 1 < lines.count else {
                throw failure("No verified frame was found at that time. Choose an earlier time.")
            }
            let baseText = try match(#"time_base: ([0-9]+/[0-9]+),"#, config)[0]
            let base = try HDRFraction(baseText)
            let values = try match(#"\bn:\s+0\s+pts:\s*([0-9]+)\s.*?fmt:(\w+) .*?sar:([0-9]+/[0-9]+) s:([0-9]+)x([0-9]+) "#, lines[index])
            guard let pts = Int64(values[0]), (0...1_000_000_000_000).contains(pts), base.numerator > 0,
                  let w = Int(values[3]), let h = Int(values[4]), (2...3840).contains(w), (2...3840).contains(h), w * h <= 3840 * 2160 else { throw failure("Invalid frame dimensions or timestamp.") }
            let aspect = try HDRFraction(values[2])
            guard aspect.value > 0, aspect.value < 10 else { throw failure("Invalid pixel aspect ratio.") }
            // A decoded frame may log SEI/display side data between its header
            // and color record. Bind one color record to this frame, stopping
            // before the next frame header; never consume another frame's color.
            let frameLines = lines.dropFirst(index + 1).prefix { $0.range(of: #"\bn:\s+[0-9]+\s+pts:"#, options: .regularExpression) == nil }
            let colors = frameLines.filter { $0.range(of: "^\\[showinfo@\(name) @ [^\\]]+\\] color_range:", options: .regularExpression) != nil }
            guard colors.count == 1, let color = colors.first else { throw failure("Missing or ambiguous frame color metadata.") }
            if name == "identity" {
                guard ["yuv420p", "nv12"].contains(values[1]), color.contains("color_range:\(expectedRange) color_space:bt709 color_primaries:bt709 color_trc:bt709") else {
                    throw failure("Decoded frame color differs from the supported source declaration.")
                }
            } else {
                guard values[1] == "rgb24", color.contains("color_range:pc color_space:gbr color_primaries:bt709 color_trc:iec61966-2-1") else { throw failure("The display conversion could not be verified.") }
            }
            return (PreviewStamp(pts: pts, base: base), w, h, aspect, values[1])
        }
        let source = try record("identity"), display = try record("display")
        guard source.0.matches(display.0), source.1 == display.1, source.2 == display.2,
              display.0.seconds + 0.000000001 >= time, display.0.seconds < end,
              data.count == display.1 * display.2 * 3 else { throw failure("Incomplete image data or inconsistent frame timing.") }
        return PictureFrame(rgb: data, width: display.1, height: display.2, aspect: display.3, stamp: display.0)
    }
}
