import Foundation

/// The flat chapter and embedded-file subset promised by the existing queue mapping.
/// Cover artwork, editions and arbitrary tags are outside this contract.
struct ContainerPreservation: Sendable {
    struct Chapter: Sendable {
        let start, end, tick: Double
        let title: String
    }
    struct Attachment: Equatable, Sendable {
        let filename, mime, hash: String
        let size: Int
    }
    let chapters: [Chapter]
    let attachments: [Attachment]

    static func failure(_ reason: String) -> NativeExportError {
        .invalid("Container preservation: \(reason)")
    }

    static func tag(_ tags: [String: String]?, _ key: String, limit: Int) throws -> String {
        let values = (tags ?? [:]).filter { $0.key.lowercased() == key }.map(\.value)
        guard Set(values.map { Data($0.utf8) }).count <= 1, values.allSatisfy({ $0.utf8.count <= limit }) else {
            throw failure("Ambiguous or excessive chapter/attachment text cannot be verified.")
        }
        return values.first ?? ""
    }

    static func readChapters(_ probe: MediaProbe) throws -> [Chapter] {
        let entries = probe.chapters ?? []
        guard entries.count <= 10_000 else { throw failure("At most 10000 flat chapters are supported.") }
        var result: [Chapter] = []
        for entry in entries {
            let parts = (entry.time_base ?? "").split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let numerator = Int64(parts[0]), let denominator = Int64(parts[1]),
                  numerator > 0, denominator > 0, let start = entry.start, let end = entry.end,
                  start >= 0, end > start else {
                throw failure("Chapter timing is missing or invalid; it cannot be preserved reliably.")
            }
            let tick = Double(numerator) / Double(denominator)
            let a = Double(start) * tick, b = Double(end) * tick
            guard tick.isFinite, tick > 0, a.isFinite, b.isFinite, b > a, b <= 1_000_000_000,
                  result.last.map({ a >= $0.end - 0.0000001 }) ?? true else {
                throw failure("Chapter ranges must be ordered, nonoverlapping and within the supported timing bounds.")
            }
            result.append(Chapter(start: a, end: b, tick: tick, title: try tag(entry.tags, "title", limit: 4096)))
        }
        return result
    }

    static func readAttachments(_ probe: MediaProbe) throws -> [Attachment] {
        let entries = probe.streams.filter { $0.codec_type == "attachment" }
        guard entries.count <= 1000 else { throw failure("At most 1000 retained attachments are supported.") }
        return try entries.map { entry in
            let hash = entry.extradata_hash ?? ""
            let hex = hash.hasPrefix("SHA256:") ? String(hash.dropFirst(7)) : ""
            guard hex.utf8.count == 64, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  let size = entry.extradata_size, size >= 0, size <= Int(Int32.max) else {
                throw failure("An attachment has no valid SHA-256 payload hash or supported byte size.")
            }
            return Attachment(filename: try tag(entry.tags, "filename", limit: 4096),
                              mime: try tag(entry.tags, "mimetype", limit: 1024),
                              hash: hex.lowercased(), size: size)
        }
    }

    static func make(probe: MediaProbe, configuration: EncodeConfiguration, chapterPlan: ChapterPlan? = nil) throws -> Self {
        let chapters = try (chapterPlan ?? ChapterPlan.make(probe: probe, configuration: configuration)).expected
        let attachments = configuration.container == "MKV" && configuration.subtitleMode == "Keep embedded tracks"
            ? try readAttachments(probe) : []
        return Self(chapters: chapters, attachments: attachments)
    }

    func verify(_ output: MediaProbe) throws -> String {
        let actualChapters = try Self.readChapters(output)
        let actualAttachments = try Self.readAttachments(output)
        guard actualChapters.count == chapters.count else { throw Self.failure("Output chapter count changed. Nothing published.") }
        for (expected, actual) in zip(chapters, actualChapters) {
            let tolerance = actual.tick + 0.0000001
            guard actual.tick <= 0.001, expected.title.utf8.elementsEqual(actual.title.utf8),
                  abs(expected.start - actual.start) <= tolerance,
                  abs(expected.end - actual.end) <= tolerance else {
                throw Self.failure("Output chapter titles or times changed beyond the supported precision. Nothing published.")
            }
        }
        guard actualAttachments == attachments else {
            throw Self.failure("Output attachment names, types, sizes or payload hashes changed. Nothing published.")
        }
        return "Verified \(chapters.count) chapter titles/times · \(attachments.count) attachment payloads/names/types"
    }
}
