import Foundation

enum PreviewStepDirection: Sendable { case previous, next }

/// Decoded presentation-order evidence only. Retains one partial line and a
/// preceding timestamp, never an index proportional to movie length.
struct PreviewNeighborScanner: Sendable {
    private let anchor: PreviewStamp
    private let base: HDRFraction
    private let direction: PreviewStepDirection
    private let start, end: Double
    private let frameLimit: Int
    private var partial = Data()
    private var previous: Int64?
    private var eligiblePrevious: PreviewStamp?
    private var count = 0
    private var anchorFound = false
    private(set) var finished = false
    private(set) var neighbor: PreviewStamp?

    init(anchor: PreviewStamp, base: HDRFraction, direction: PreviewStepDirection,
         start: Double, end: Double, frameLimit: Int = 2_000_000) throws {
        guard base.numerator > 0, anchor.base.numerator > 0,
              (0...1_000_000_000_000).contains(anchor.pts),
              start.isFinite, end.isFinite, start >= 0, end > start,
              anchor.seconds >= start, anchor.seconds < end, frameLimit > 0 else {
            throw PicturePreview.failure("Frame stepping requires a valid timestamp inside the trim interval.")
        }
        self.anchor = anchor; self.base = base; self.direction = direction
        self.start = start; self.end = end; self.frameLimit = frameLimit
    }
    mutating func accept(_ data: Data) throws {
        guard !finished else { return }
        for byte in data {
            if byte == 10 {
                try line(); partial.removeAll(keepingCapacity: true)
                if finished { return }
            } else {
                guard partial.count < 256 else { throw PicturePreview.failure("Decoded frame timestamp record exceeded its bounds.") }
                partial.append(byte)
            }
        }
    }
    mutating func finish() throws {
        guard !finished else { return }
        if !partial.isEmpty { try line(); partial.removeAll() }
        guard anchorFound else { throw PicturePreview.failure("The current frame timestamp was not found. Render a new comparison.") }
        finished = true
    }
    private mutating func line() throws {
        if partial.isEmpty { return }
        // Suppressed side-data sections may leave empty trailing delimiters.
        guard let text = String(data: partial, encoding: .utf8) else { throw PicturePreview.failure("Invalid decoded timestamp text.") }
        let fields = text.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count >= 2, fields[0] == "frame", fields[1].hasPrefix("pts="),
              fields.dropFirst(2).allSatisfy(\.isEmpty) else { throw PicturePreview.failure("Malformed decoded frame timestamp record.") }
        let number = fields[1].dropFirst(4)
        guard !number.isEmpty, number.utf8.allSatisfy({ (48...57).contains($0) }),
              let pts = Int64(number), (0...1_000_000_000_000).contains(pts),
              previous.map({ pts > $0 }) ?? true else {
            throw PicturePreview.failure("Decoded timestamps are missing, repeated, out of order or unsupported. No frame step was accepted.")
        }
        count += 1
        guard count <= frameLimit else { throw PicturePreview.failure("Frame stepping reached its bounded scan limit. Render a new comparison.") }
        previous = pts
        let stamp = PreviewStamp(pts: pts, base: base)
        if stamp.matches(anchor) {
            anchorFound = true
            if direction == .previous { neighbor = eligiblePrevious; finished = true }
        } else if anchorFound {
            if stamp.seconds < end { neighbor = stamp }
            finished = true
        } else {
            // Rational ordering is exact within the existing timestamp bounds.
            let actual = Decimal(pts) * Decimal(base.numerator) * Decimal(anchor.base.denominator)
            let target = Decimal(anchor.pts) * Decimal(anchor.base.numerator) * Decimal(base.denominator)
            guard actual < target else { throw PicturePreview.failure("The current frame timestamp was not found. Render a new comparison.") }
            if stamp.seconds >= start { eligiblePrevious = stamp }
        }
    }
}

private final class PreviewNeighborBytes: @unchecked Sendable {
    // Only ToolRunner's stdout-draining callback mutates these values. The
    // runner joins its reader before the awaiting task examines the result.
    var scanner: PreviewNeighborScanner
    var failure: Error?
    var stopped = false
    init(_ scanner: PreviewNeighborScanner) { self.scanner = scanner }
    func append(_ data: Data, runner: ToolRunner) {
        guard !stopped else { return }
        do { try scanner.accept(data); stopped = scanner.finished }
        catch { failure = error; stopped = true }
        if stopped { runner.cancel() }
    }
}

enum PreviewFrameNeighbor {
    static func read(source: URL, stream: MediaProbe.Stream, anchor: PreviewStamp,
                     direction: PreviewStepDirection, start: Double, end: Double,
                     tools: FFmpegTools) async throws -> PreviewStamp? {
        let base = try HDRFraction(stream.time_base)
        let bytes = PreviewNeighborBytes(try PreviewNeighborScanner(anchor: anchor, base: base, direction: direction, start: start, end: end))
        let runner = ToolRunner()
        do {
            let result = try await runner.run(executable: tools.ffprobe, arguments: [
                "-v", "error", "-threads", "2", "-protocol_whitelist", "file,pipe", "-select_streams", String(stream.index),
                "-show_frames", "-show_entries", "frame=pts:frame_side_data=", "-of", "compact=p=1:nk=0", source.path
            ], stdoutLimit: 0) { bytes.append($0, runner: runner) }
            guard result.status == 0 else { throw PicturePreview.failure("The decoded-frame scan failed. No frame step was accepted.") }
        } catch is CancellationError {
            // Intentional early stop is accepted only after sufficient evidence;
            // user/task cancellation still wins. ToolRunner has joined the process.
            try Task.checkCancellation()
            guard bytes.stopped else { throw CancellationError() }
        }
        try Task.checkCancellation()
        if let failure = bytes.failure { throw failure }
        try bytes.scanner.finish()
        return bytes.scanner.neighbor
    }
}
