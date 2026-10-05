import Foundation

struct ChapterEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var startMilliseconds: Int64
    var endMilliseconds: Int64
    var title: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.startMilliseconds == rhs.startMilliseconds &&
        lhs.endMilliseconds == rhs.endMilliseconds && lhs.title.utf8.elementsEqual(rhs.title.utf8)
    }
}

/// Nil in EncodeConfiguration retains the legacy source-chapter policy.
struct ChapterEdits: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable { case remove, custom }
    var mode: Mode
    var entries: [ChapterEntry] = []
    static let maximumMilliseconds: Int64 = 604_800_000

    static func failure(_ message: String) -> NativeExportError { .invalid("Chapters: " + message) }
    func validate() throws {
        if mode == .remove {
            guard entries.isEmpty else { throw Self.failure("Remove chapters cannot contain an authored list.") }
            return
        }
        guard !entries.isEmpty, entries.count <= 1000, Set(entries.map(\.id)).count == entries.count else {
            throw Self.failure("Use 1 to 1000 chapters with unique identifiers.")
        }
        var previousEnd: Int64 = 0
        for (index, entry) in entries.enumerated() {
            guard entry.startMilliseconds >= previousEnd, entry.endMilliseconds > entry.startMilliseconds,
                  entry.endMilliseconds <= Self.maximumMilliseconds else {
                throw Self.failure("Chapter \(index + 1) needs an ordered, nonoverlapping positive range between zero and seven days.")
            }
            guard !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.title.utf8.count <= 4096,
                  !entry.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw Self.failure("Chapter \(index + 1) needs a title of up to 4096 UTF-8 bytes without control characters.")
            }
            previousEnd = entry.endMilliseconds
        }
    }

    static func milliseconds(_ text: String) throws -> Int64 {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]{1,6}(\.[0-9]{1,3})?$"#, options: .regularExpression) != nil else {
            throw failure("Enter seconds using a decimal point and at most three decimal places, for example 92.125.")
        }
        let parts = value.split(separator: ".")
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard let whole = Int64(parts[0]), let partial = Int64(fraction + String(repeating: "0", count: 3 - fraction.count)) else {
            throw failure("The chapter time is invalid.")
        }
        let result = whole * 1000 + partial
        guard result <= maximumMilliseconds else { throw failure("Chapter times must be within seven days.") }
        return result
    }
    static func secondsText(_ milliseconds: Int64) -> String {
        "\(milliseconds / 1000)." + String(format: "%03lld", milliseconds % 1000)
    }
}

struct ChapterPlan: Sendable {
    #if DEBUG
    enum WriteEvent: String, Sendable { case bodyEntered, noMetadata, submitting, workerEntered, writeReturned, writeRefused, bodyResumed }
    @TaskLocal static var observeMetadataWrite: (@Sendable (WriteEvent) -> Void)?
    #endif

    enum MetadataTimeline { case source, output }
    let expected: [ContainerPreservation.Chapter]
    let metadata: Data?
    let preservesSource: Bool
    let summary: String

    static func make(probe: MediaProbe, configuration: EncodeConfiguration, includeMetadata: Bool = true,
                     metadataTimeline: MetadataTimeline = .source) throws -> Self {
        let p = configuration.picture
        let trimmed = p.start > 0 || p.end > 0
        guard let edits = configuration.chapterEdits else {
            let chapters = trimmed ? [] : try ContainerPreservation.readChapters(probe)
            try validateContainer(chapters, container: configuration.container)
            return Self(expected: chapters, metadata: nil, preservesSource: !trimmed,
                        summary: trimmed ? "Source chapters omitted for trim" : "Preserve source chapters")
        }
        try edits.validate()
        if edits.mode == .remove {
            return Self(expected: [], metadata: nil, preservesSource: false, summary: "Remove chapters")
        }
        guard probe.video?.start_pts == 0, probe.seconds.isFinite, probe.seconds > 0, probe.seconds <= 604800 else {
            throw ChapterEdits.failure("Custom chapters require a known source duration up to seven days and a video timeline starting at zero.")
        }
        let sourceEnd = Int64((probe.seconds * 1_000_000).rounded())
        let start = try microseconds(p.start)
        let end = p.end > 0 ? try microseconds(p.end) : sourceEnd
        guard start < end, end <= sourceEnd else { throw ChapterEdits.failure("The trim must be inside the source duration.") }
        var selected: [ChapterEntry] = []
        var expected: [ContainerPreservation.Chapter] = []
        for entry in edits.entries {
            let a = entry.startMilliseconds * 1000, b = entry.endMilliseconds * 1000
            guard b <= sourceEnd else { throw ChapterEdits.failure("Chapter \(entry.title) extends beyond the source duration.") }
            let clippedStart = max(a, start), clippedEnd = min(b, end)
            guard clippedEnd > clippedStart else { continue }
            guard clippedEnd - clippedStart >= 1000 else {
                throw ChapterEdits.failure("The trim leaves a chapter shorter than one millisecond. Adjust the chapter or trim boundary.")
            }
            selected.append(entry)
            expected.append(.init(start: Double(clippedStart - start) / 1_000_000,
                                  end: Double(clippedEnd - start) / 1_000_000, tick: 0.000001, title: entry.title))
        }
        try validateContainer(expected, container: configuration.container)
        let data: Data?
        if selected.isEmpty || !includeMetadata { data = nil }
        else {
            // Ordinary output seeking offsets source metadata once. The caption
            // trim path instead filters media and needs output-time metadata here.
            let entries: [(start: Int64, end: Int64, title: String)]
            switch metadataTimeline {
            case .source:
                entries = selected.map { ($0.startMilliseconds * 1000, $0.endMilliseconds * 1000, $0.title) }
            case .output:
                entries = expected.map { (Int64(($0.start * 1_000_000).rounded()),
                                          Int64(($0.end * 1_000_000).rounded()), $0.title) }
            }
            let text = ";FFMETADATA1\n" + entries.map { entry in
                "[CHAPTER]\nTIMEBASE=1/1000000\nSTART=\(entry.start)\nEND=\(entry.end)\ntitle=\(escaped(entry.title))\n"
            }.joined()
            data = Data(text.utf8)
        }
        return Self(expected: expected, metadata: data, preservesSource: false,
                    summary: "Custom chapters: \(expected.count) of \(edits.entries.count) ranges in output")
    }

    private static func microseconds(_ seconds: Double) throws -> Int64 {
        let scaled = seconds * 1_000_000
        guard seconds.isFinite, (0...604800).contains(seconds), abs(scaled - scaled.rounded()) <= 0.0001 else {
            throw ChapterEdits.failure("Use trim times with at most six decimal places for custom chapters.")
        }
        return Int64(scaled.rounded())
    }
    private static func validateContainer(_ chapters: [ContainerPreservation.Chapter], container: String) throws {
        if container == "MP4", !chapters.isEmpty {
            guard chapters[0].start == 0,
                  zip(chapters, chapters.dropFirst()).allSatisfy({ abs($0.end - $1.start) <= 0.0000001 }) else {
                throw ChapterEdits.failure("MP4 chapters must start at zero and be contiguous. Choose MKV to retain chapter gaps.")
            }
        }
    }
    private static func escaped(_ title: String) -> String {
        title.unicodeScalars.reduce(into: "") { result, scalar in
            // Metadata delimiters are scalars even when a combining mark makes
            // them part of a larger grapheme cluster in Swift.
            if [92, 61, 59, 35, 32].contains(scalar.value) { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
    }
    func writeMetadata(to directory: URL) async throws {
        #if DEBUG
        let observe = Self.observeMetadataWrite
        observe?(.bodyEntered)
        #endif
        guard let metadata else {
            #if DEBUG
            observe?(.noMetadata)
            #endif
            return
        }
        try Task.checkCancellation()
        let file = directory.appendingPathComponent("chapters.ffmetadata")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            #if DEBUG
            observe?(.submitting)
            #endif
            DispatchQueue.global(qos: .utility).async {
                #if DEBUG
                observe?(.workerEntered)
                #endif
                do {
                    try metadata.write(to: file, options: .withoutOverwriting)
                    #if DEBUG
                    observe?(.writeReturned)
                    #endif
                    continuation.resume()
                } catch {
                    #if DEBUG
                    observe?(.writeRefused)
                    #endif
                    continuation.resume(throwing: error)
                }
            }
        }
        #if DEBUG
        observe?(.bodyResumed)
        #endif
        try Task.checkCancellation()
    }
}
