import Foundation
import Darwin

/// Current-run permission only. Copies of a configuration share this lifetime;
/// sessions and presets never serialize a security-scoped URL or permission.
final class SubtitleFileAccess: @unchecked Sendable {
    let url: URL
    private let scoped: Bool
    init(_ url: URL) {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

struct ExternalSubtitle: Codable, Equatable, Sendable {
    #if DEBUG
    @TaskLocal static var observeBoundary: (@Sendable (String) -> Void)?
    #endif
    var path: String
    var language = "und"
    var title = "External captions"
    var access: SubtitleFileAccess? = nil

    private enum CodingKeys: String, CodingKey { case path, language, title }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path && lhs.language == rhs.language && lhs.title.utf8.elementsEqual(rhs.title.utf8)
    }
    static let languages = [
        ("und", "Unspecified"), ("eng", "English"), ("fra", "French"),
        ("spa", "Spanish"), ("deu", "German"), ("ita", "Italian"),
        ("por", "Portuguese"), ("jpn", "Japanese"), ("zho", "Chinese"),
        ("kor", "Korean"), ("rus", "Russian"), ("ara", "Arabic"),
        ("hin", "Hindi"), ("heb", "Hebrew")
    ]
    func validate() throws {
        guard path.hasPrefix("/"), path.utf8.count <= 4096,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              Self.languages.contains(where: { $0.0 == language }),
              title.utf8.count <= 1024, title == title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw SubRipDocument.failure("Use an absolute local file path, a listed language, and a plain title of at most 1024 UTF-8 bytes without surrounding spaces or control characters.")
        }
    }

    static func validateWorkflow(_ configuration: EncodeConfiguration) throws {
        guard configuration.colorMode == "SDR" else {
            throw SubRipDocument.failure("External captions require SDR. Remove the external reference or change the color workflow explicitly.")
        }
        _ = try SubRipDocument.trimMilliseconds(configuration.picture.start)
        _ = try SubRipDocument.trimMilliseconds(configuration.picture.end)
    }

    func read() async throws -> SubRipDocument {
        #if DEBUG
        let observe = Self.observeBoundary
        observe?("body entered")
        #endif
        try validate()
        try Task.checkCancellation()
        let reference = self
        let priority = Task.currentPriority
        let workerQoS: DispatchQoS.QoSClass = priority >= .high ? .userInitiated :
            priority >= .medium ? .default : priority >= .low ? .utility : .background
        let document: SubRipDocument = try await withCheckedThrowingContinuation { continuation in
            #if DEBUG
            observe?("submitting worker")
            #endif
            // A caption read owns its dispatch domain and retains the request's
            // priority. Descriptor/access lifetime and cancellation settlement
            // stay inside the original awaited read.
            let worker = DispatchQueue(label: "StaxRip.external-subtitle",
                qos: DispatchQoS(qosClass: workerQoS, relativePriority: 0))
            worker.async {
                #if DEBUG
                observe?("worker entered")
                #endif
                do {
                    let document = try withExtendedLifetime(reference.access) {
                        let url = reference.access?.url ?? URL(fileURLWithPath: reference.path)
                        guard url.standardizedFileURL.path == URL(fileURLWithPath: reference.path).standardizedFileURL.path else {
                            throw SubRipDocument.failure("The selected file access does not match the configured caption path. Select the file again.")
                        }
                        return try SubRipDocument(data: Self.readRegularFile(url))
                    }
                    continuation.resume(returning: document)
                } catch { continuation.resume(throwing: error) }
            }
        }
        // A dispatched read keeps its descriptor and permission until it returns.
        // Cancellation never closes an in-flight descriptor from another thread.
        try Task.checkCancellation()
        return document
    }

    private static func readRegularFile(_ url: URL) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SubRipDocument.failure("Cannot open the caption file. Select an accessible regular UTF-8 SRT file; symbolic links are not accepted.") }
        defer { Darwin.close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= SubRipDocument.inputLimit else {
            throw SubRipDocument.failure("The caption file must be a nonempty regular file no larger than 1 MiB.")
        }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        while bytes.count <= SubRipDocument.inputLimit {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, min($0.count, SubRipDocument.inputLimit + 1 - bytes.count)) }
            if count < 0 {
                if errno == EINTR { continue }
                throw SubRipDocument.failure("Reading the caption file failed. Check the file and its volume, then select it again.")
            }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard bytes.count <= SubRipDocument.inputLimit, fstat(fd, &after) == 0,
              before.st_size == after.st_size, bytes.count == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw SubRipDocument.failure("The caption file changed while being read or exceeded 1 MiB. Retry with a stable file.")
        }
        return bytes
    }
}

struct SubRipCue: Equatable, Sendable {
    let start: Int64
    let end: Int64
    let text: String
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end && lhs.text.utf8.elementsEqual(rhs.text.utf8)
    }
}

struct SubRipDocument: Equatable, Sendable {
    #if DEBUG
    @TaskLocal static var observeSnapshotBoundary: (@Sendable (String) -> Void)?
    #endif
    static let inputLimit = 1_048_576
    static let outputLimit = 2_097_152
    static let maximumTime: Int64 = 48 * 60 * 60 * 1000
    let cues: [SubRipCue]

    private init(cues: [SubRipCue]) { self.cues = cues }

    static func trimMilliseconds(_ seconds: Double) throws -> Int64 {
        let scaled = seconds * 1000
        guard seconds.isFinite, seconds >= 0, scaled <= Double(maximumTime),
              abs(scaled - scaled.rounded()) <= 0.000001 else {
            throw failure("With external captions, use trim times within 48 hours and at most three decimal places, such as 12.345 seconds.")
        }
        return Int64(scaled.rounded())
    }

    func clipped(start: Int64, end: Int64) throws -> Self {
        guard start >= 0, end > start, end <= Self.maximumTime else {
            throw Self.failure("Choose a nonempty trim interval within the source duration.")
        }
        let selected = cues.compactMap { cue -> SubRipCue? in
            let a = max(cue.start, start), b = min(cue.end, end)
            guard b > a else { return nil }
            return SubRipCue(start: a - start, end: b - start, text: cue.text)
        }
        guard !selected.isEmpty else {
            throw Self.failure("No external caption cues overlap this trim. Adjust the range or remove the external reference explicitly.")
        }
        return Self(cues: selected)
    }

    func forExport(probe: MediaProbe, configuration: EncodeConfiguration) throws -> Self {
        try validateTimeline(probe: probe, configuration: configuration)
        let p = configuration.picture
        guard p.start > 0 || p.end > 0 else { return self }
        guard p.start < probe.seconds, p.end == 0 || p.end <= probe.seconds else {
            throw Self.failure("The trim range must lie within the source duration.")
        }
        let start = try Self.trimMilliseconds(p.start)
        // Captions are millisecond-based and already bounded by this floor.
        let end = p.end == 0 ? Int64(floor(probe.seconds * 1000)) : try Self.trimMilliseconds(p.end)
        return try clipped(start: start, end: end)
    }

    static func failure(_ message: String) -> NativeExportError {
        .invalid("External subtitles: " + message)
    }

    init(data: Data, maximumBytes: Int = inputLimit) throws {
        guard !data.isEmpty, data.count <= min(maximumBytes, Self.outputLimit),
              var text = String(data: data, encoding: .utf8) else {
            throw Self.failure("Use a bounded, nonempty UTF-8 SubRip (.srt) file.")
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !text.contains("\r") else { throw Self.failure("Use LF or CRLF line endings.") }
        let lines = text.components(separatedBy: "\n")
        var cursor = 0, result: [SubRipCue] = []
        while cursor < lines.count {
            if lines[cursor].isEmpty { cursor += 1; continue }
            guard result.count < 10000, lines[cursor] == String(result.count + 1), cursor + 1 < lines.count else {
                throw Self.failure("Use at most 10000 cues numbered sequentially from 1.")
            }
            let number = result.count + 1
            let interval = lines[cursor + 1].components(separatedBy: " --> ")
            guard interval.count == 2 else { throw Self.failure("Cue \(number) needs a plain start --> end interval without positioning attributes.") }
            let start = try Self.timestamp(interval[0]), end = try Self.timestamp(interval[1])
            guard end > start, start >= (result.last?.end ?? 0) else {
                throw Self.failure("Cue \(number) has an empty, reversed or overlapping interval. Retiming is not supported yet.")
            }
            cursor += 2
            var content: [String] = []
            while cursor < lines.count, !lines[cursor].isEmpty {
                let line = lines[cursor]
                guard line == line.trimmingCharacters(in: .whitespaces),
                      !line.contains(where: { "<>\\{}".contains($0) }),
                      !line.unicodeScalars.contains(where: {
                          $0.value < 32 || (127...159).contains($0.value) || $0.value == 0x2028 || $0.value == 0x2029
                      }) else {
                    throw Self.failure("Cue \(number) must contain plain text without styling, backslash escapes, control characters or surrounding line spaces.")
                }
                content.append(line); cursor += 1
            }
            let body = content.joined(separator: "\n")
            guard !body.isEmpty, body.utf8.count <= 4096 else {
                throw Self.failure("Cue \(number) needs 1 to 4096 UTF-8 text bytes.")
            }
            result.append(SubRipCue(start: start, end: end, text: body))
        }
        guard !result.isEmpty else { throw Self.failure("The caption file contains no cues.") }
        cues = result
    }

    private static func timestamp(_ text: String) throws -> Int64 {
        let b = Array(text.utf8)
        guard b.count == 12, b[2] == 58, b[5] == 58, b[8] == 44,
              [0, 1, 3, 4, 6, 7, 9, 10, 11].allSatisfy({ (48...57).contains(b[$0]) }) else {
            throw failure("Cue times must use HH:MM:SS,mmm with millisecond precision.")
        }
        func pair(_ i: Int) -> Int64 { Int64(b[i] - 48) * 10 + Int64(b[i + 1] - 48) }
        let hours = pair(0), minutes = pair(3), seconds = pair(6)
        let millis = Int64(b[9] - 48) * 100 + Int64(b[10] - 48) * 10 + Int64(b[11] - 48)
        let total = ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis
        guard minutes < 60, seconds < 60, total <= maximumTime else {
            throw failure("Cue times must have valid fields and remain within 48 hours.")
        }
        return total
    }

    private static func timestamp(_ millis: Int64) -> String {
        String(format: "%02lld:%02lld:%02lld,%03lld", millis / 3600000, millis / 60000 % 60, millis / 1000 % 60, millis % 1000)
    }

    var canonicalData: Data {
        Data(cues.enumerated().map { index, cue in
            "\(index + 1)\n\(Self.timestamp(cue.start)) --> \(Self.timestamp(cue.end))\n\(cue.text)\n\n"
        }.joined().utf8)
    }

    func validateTimeline(probe: MediaProbe, configuration: EncodeConfiguration) throws {
        try ExternalSubtitle.validateWorkflow(configuration)
        guard let start = Double(probe.format?.start_time ?? ""), start == 0,
              probe.video?.start_pts == 0, probe.seconds.isFinite,
              probe.seconds > 0, probe.seconds <= 48 * 60 * 60 else {
            throw Self.failure("External captions require a known zero-start video timeline with a duration of at most 48 hours.")
        }
        guard let last = cues.last, last.end <= Int64(floor(probe.seconds * 1000)) else {
            throw Self.failure("A caption ends after the source duration. Correct the caption file before exporting.")
        }
    }

    func writeSnapshot(to url: URL) async throws {
        #if DEBUG
        let observe = Self.observeSnapshotBoundary
        observe?("body entered")
        #endif
        try Task.checkCancellation()
        let bytes = canonicalData
        let priority = Task.currentPriority
        let qos: DispatchQoS.QoSClass = priority >= .high ? .userInitiated :
            priority >= .medium ? .default : priority >= .low ? .utility : .background
        let worker = DispatchQueue(label: "StaxRip.caption-snapshot", qos: DispatchQoS(qosClass: qos, relativePriority: 0))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            #if DEBUG
            observe?("submitting worker")
            #endif
            worker.async {
                #if DEBUG
                observe?("worker entered")
                #endif
                do {
                    try bytes.write(to: url, options: .withoutOverwriting)
                    #if DEBUG
                    observe?("worker finished")
                    #endif
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        try Task.checkCancellation()
    }
}

struct ExternalSubtitleExport: Sendable {
    let reference: ExternalSubtitle
    let document: SubRipDocument
    let ordinal: Int
    let codec: String

    func verify(_ staged: URL, probe: MediaProbe, tools: FFmpegTools, timeout: Double = 120) async throws -> String {
        try Task.checkCancellation()
        let streams = probe.streams.filter { $0.codec_type == "subtitle" }
        guard streams.indices.contains(ordinal), streams[ordinal].codec_name == codec else {
            throw SubRipDocument.failure("The added output track is missing or has the wrong codec. Nothing published.")
        }
        let stream = streams[ordinal]
        let language = try tag("language", stream: stream) ?? "und"
        let title = try tag(codec == "mov_text" ? "name" : "title", stream: stream) ?? ""
        guard language == reference.language, title.utf8.elementsEqual(reference.title.utf8) else {
            throw SubRipDocument.failure("The added track's language or title changed. Nothing published.")
        }
        let result = try await withThrowingTaskGroup(of: ToolResult.self) { group in
            group.addTask {
                try await ToolRunner().run(executable: tools.ffmpeg, arguments: [
                    "-v", "error", "-nostdin", "-protocol_whitelist", "file,pipe", "-i", staged.path,
                    "-map", "0:\(stream.index)", "-c:s", "srt", "-f", "srt", "pipe:1"
                ], stdoutLimit: SubRipDocument.outputLimit)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.001, min(120, timeout)) * 1_000_000_000))
                throw SubRipDocument.failure("Output caption verification reached its time limit. Nothing published.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        try Task.checkCancellation()
        guard result.status == 0, !result.truncated else {
            throw SubRipDocument.failure("Cannot decode the added caption track within its output bounds. Nothing published.")
        }
        let decoded = try SubRipDocument(data: result.stdout, maximumBytes: SubRipDocument.outputLimit)
        guard decoded == document else {
            throw SubRipDocument.failure("The added caption text or cue timing changed in the encoded output. Nothing published.")
        }
        return "Verified \(document.cues.count) external caption cues, text and millisecond timing"
    }

    private func tag(_ key: String, stream: MediaProbe.Stream) throws -> String? {
        let matches = (stream.tags ?? [:]).filter { $0.key.lowercased() == key }
        guard matches.count <= 1 else { throw SubRipDocument.failure("The added track contains ambiguous \(key) metadata. Nothing published.") }
        return matches.first?.value
    }
}
