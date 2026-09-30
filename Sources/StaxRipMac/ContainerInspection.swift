import Foundation

// Reported metadata only. Names are labels, never paths or executable content.
enum ContainerInspection {
    static let rowLimit = 200
    static let textLimit = 512
    struct ChapterEntry: Identifiable {
        let id: Int
        let title, identifier, start, end, timeBase: String
        let note: String?
    }
    struct AttachmentEntry: Identifiable {
        let id: Int
        let streamIndex: Int
        let kind, filename, mimeType, codec: String
    }
    static func text(_ raw: String?, fallback: String = "Unspecified") -> String {
        guard let raw else { return fallback }
        let shortened = raw.unicodeScalars.count > textLimit
        let safe = String(String.UnicodeScalarView(raw.unicodeScalars.prefix(textLimit).map {
            CharacterSet.controlCharacters.contains($0) ? UnicodeScalar(32)! : $0
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty else { return fallback }
        return safe + (shortened ? "… [shortened]" : "")
    }
    static func tag(_ name: String, in tags: [String: String]?) -> String? {
        guard let tags else { return nil }
        if let value = tags[name] { return value }
        return tags.keys.sorted().first(where: { $0.lowercased() == name }).flatMap { tags[$0] }
    }
    static func seconds(_ raw: String?) -> Double? {
        guard let raw, let value = Double(raw), value.isFinite, abs(value) < 9e12 else { return nil }
        return value
    }
    static func timestamp(_ raw: String?) -> String {
        guard let value = seconds(raw) else { return "Unavailable" }
        let ms = Int64((abs(value) * 1000).rounded())
        return (value < 0 ? "−" : "") + String(format: "%02lld:%02lld:%02lld.%03lld", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
    static func isAttachment(_ stream: MediaProbe.Stream) -> Bool {
        stream.codec_type == "attachment" || stream.disposition?["attached_pic"] == 1
    }
    static func tracks(_ probe: MediaProbe) -> [MediaProbe.Stream] { probe.streams.filter { !isAttachment($0) } }
    static func attachmentStreams(_ probe: MediaProbe) -> [MediaProbe.Stream] { probe.streams.filter(isAttachment) }
    static func chapters(_ probe: MediaProbe) -> [ChapterEntry] {
        (probe.chapters ?? []).prefix(rowLimit).enumerated().map { index, chapter in
            var notes: [String] = []
            if let start = seconds(chapter.start_time), let end = seconds(chapter.end_time) {
                if start < 0 { notes.append("Starts before zero.") }
                if end <= start { notes.append("End is not after start.") }
                if let duration = seconds(probe.format?.duration), duration > 0, end > duration + 0.001 {
                    notes.append("Extends beyond the reported container duration.")
                }
            } else { notes.append("Timing is missing or invalid; no position has been inferred.") }
            return ChapterEntry(id: index, title: text(tag("title", in: chapter.tags), fallback: "Untitled chapter"),
                identifier: chapter.id.map(String.init) ?? "Unspecified", start: timestamp(chapter.start_time),
                end: timestamp(chapter.end_time), timeBase: text(chapter.time_base), note: notes.isEmpty ? nil : notes.joined(separator: " "))
        }
    }
    static func attachments(_ probe: MediaProbe) -> [AttachmentEntry] {
        attachmentStreams(probe).prefix(rowLimit).enumerated().map { index, stream in
            AttachmentEntry(id: index, streamIndex: stream.index,
                kind: stream.disposition?["attached_pic"] == 1 ? "Cover artwork" : "Embedded file",
                filename: text(tag("filename", in: stream.tags)), mimeType: text(tag("mimetype", in: stream.tags)),
                codec: text(stream.codec_name))
        }
    }
    static func limitNotice(_ total: Int) -> String? {
        total > rowLimit ? "Showing the first \(rowLimit) of \(total) entries. This inspector limits large metadata lists." : nil
    }
}
