import Foundation
import Darwin
import Testing
@testable import StaxRipMac

struct ExternalSubtitleTests {
    private let plain = "1\n00:00:00,000 --> 00:00:00,500\nCafé — 起点\nمرحبا — שלום 🎬 👩‍💻 e\u{301}\n\n2\n00:00:00,500 --> 00:00:00,999\nSecond & final\n\n"
    private func cue(_ body: String) -> Data {
        Data("1\n00:00:00,000 --> 00:00:00,999\n\(body)\n\n".utf8)
    }

    @Test func plainCuesPreserveUnicodeBytesAndAdjacentIntervals() throws {
        let document = try SubRipDocument(data: Data(plain.utf8))
        #expect(document.cues.count == 2)
        #expect(document.cues[0].start == 0 && document.cues[0].end == 500)
        #expect(document.cues[1].start == 500 && document.cues[1].end == 999)
        #expect(document.canonicalData == Data(plain.utf8))
        let windows = "\u{FEFF}" + plain.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(try SubRipDocument(data: Data(windows.utf8)) == document)
        let composed = try SubRipDocument(data: cue("é"))
        let decomposed = try SubRipDocument(data: cue("e\u{301}"))
        #expect(composed != decomposed, "Exact caption text compares UTF-8, not canonical-equivalent Swift strings")
    }

    @Test func malformedUnsupportedAndAmbiguousCaptionsRefuse() throws {
        let header = "1\n00:00:00,000 --> 00:00:00,999\nText\n\n"
        let invalid = ["", "\n\n", header.replacingOccurrences(of: "1\n", with: "0\n"),
                       header.replacingOccurrences(of: "1\n", with: "01\n"),
                       "1\n00:00:00,000 --> 00:00:00,999\n\n",
                       header + "3\n00:00:01,000 --> 00:00:02,000\nSkipped number\n",
                       header + "2\n00:00:00,500 --> 00:00:02,000\nOverlap\n",
                       header.replacingOccurrences(of: "00:00:00,999", with: "00:00:00,000"),
                       header.replacingOccurrences(of: "00:00:00,999", with: "00:60:00,999"),
                       header.replacingOccurrences(of: "00:00:00,999", with: "00:00:60,999"),
                       header.replacingOccurrences(of: "00:00:00,999", with: "48:00:00,001"),
                       header.replacingOccurrences(of: "00:00:00,999", with: "0:00:00,999"),
                       header.replacingOccurrences(of: "00:00:00,999", with: "00:00:00.999"),
                       header.replacingOccurrences(of: "00:00:00,999", with: "00:00:00,999 X1:10"),
                       header.replacingOccurrences(of: "\n", with: "\r")]
        for text in invalid { #expect(throws: (any Error).self) { try SubRipDocument(data: Data(text.utf8)) } }
        for text in ["<i>Styled</i>", "{position}", "a\\Nb", " space", "space ", "tab\ttext", "nul\0text", "control\u{85}", "line\u{2028}break"] {
            #expect(throws: (any Error).self) { try SubRipDocument(data: cue(text)) }
        }
        #expect(throws: (any Error).self) { try SubRipDocument(data: Data([0xff, 0xfe, 0x00])) }
        #expect(throws: (any Error).self) { try SubRipDocument(data: Data(plain.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })) }
        _ = try SubRipDocument(data: Data("1\n47:59:59,999 --> 48:00:00,000\nLast millisecond\n".utf8))
    }

    @Test func byteCueAndTextBoundsAreEnforced() throws {
        _ = try SubRipDocument(data: cue(String(repeating: "x", count: 4096)))
        #expect(throws: (any Error).self) { try SubRipDocument(data: cue(String(repeating: "x", count: 4097))) }
        _ = try SubRipDocument(data: cue(String(repeating: "界", count: 1365) + "x"))
        #expect(throws: (any Error).self) { try SubRipDocument(data: cue(String(repeating: "界", count: 1366))) }
        var exact = cue("x")
        exact.append(Data(repeating: 10, count: SubRipDocument.inputLimit - exact.count))
        #expect(try SubRipDocument(data: exact).cues.count == 1)
        exact.append(10)
        #expect(throws: (any Error).self) { try SubRipDocument(data: exact) }
        func stamp(_ milliseconds: Int) -> String {
            String(format: "00:00:%02d,%03d", milliseconds / 1000, milliseconds % 1000)
        }
        let maximum = (0..<10000).map { "\($0 + 1)\n\(stamp($0 * 2)) --> \(stamp($0 * 2 + 1))\nx\n\n" }.joined()
        #expect(try SubRipDocument(data: Data(maximum.utf8)).cues.count == 10000)
        #expect(throws: (any Error).self) {
            try SubRipDocument(data: Data((maximum + "10001\n00:00:20,000 --> 00:00:20,001\nx\n").utf8))
        }
    }

    private func probe(start: String? = "0.000000", videoStart: Int64? = 0, duration: String = "1.000000") throws -> MediaProbe {
        var format: [String: Any] = ["duration": duration]
        if let start { format["start_time"] = start }
        var video: [String: Any] = ["index": 0, "codec_type": "video"]
        if let videoStart { video["start_pts"] = videoStart }
        return try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: ["streams": [video], "format": format]))
    }
    @Test func timelineRequiresKnownZeroStartAndNoRetiming() throws {
        let document = try SubRipDocument(data: cue("x"))
        let config = EncodeConfiguration()
        try document.validateTimeline(probe: probe(), configuration: config)
        try document.validateTimeline(probe: probe(duration: "0.999"), configuration: config)
        for source in [try probe(start: nil), try probe(start: "nan"), try probe(start: "0.001"), try probe(videoStart: nil), try probe(videoStart: 1), try probe(duration: "0.998"), try probe(duration: "0.998999"), try probe(duration: "nan"), try probe(duration: "0"), try probe(duration: "172801")] {
            #expect(throws: (any Error).self) { try document.validateTimeline(probe: source, configuration: config) }
        }
        var trimmed = config; trimmed.picture.start = 0.1
        #expect(throws: (any Error).self) { try document.validateTimeline(probe: probe(), configuration: trimmed) }
        var hdr = config; hdr.colorMode = "Preserve static HDR10"
        #expect(throws: (any Error).self) { try document.validateTimeline(probe: probe(), configuration: hdr) }
    }

    @Test(.timeLimit(.minutes(1))) func boundedRegularReadCapturesFreshContentsAndRefusesSpecialFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("external-srt-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("captions.srt")
        try Data(plain.utf8).write(to: file)
        let reference = ExternalSubtitle(path: file.path, access: SubtitleFileAccess(file))
        let captured = try await reference.read()
        let changed = cue("New captured text")
        try changed.write(to: file)
        #expect(captured.canonicalData == Data(plain.utf8))
        #expect(try await reference.read().canonicalData == changed)
        let link = root.appendingPathComponent("link.srt"), fifo = root.appendingPathComponent("pipe.srt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try #require(mkfifo(fifo.path, 0o600) == 0)
        for url in [link, fifo, root, root.appendingPathComponent("missing.srt"), URL(fileURLWithPath: "/dev/null")] {
            await #expect(throws: (any Error).self) { try await ExternalSubtitle(path: url.path).read() }
        }
        try Data(repeating: 120, count: SubRipDocument.inputLimit + 1).write(to: file)
        await #expect(throws: (any Error).self) { try await reference.read() }
        var mismatch = reference; mismatch.path = root.appendingPathComponent("different.srt").path
        await #expect(throws: (any Error).self) { try await mismatch.read() }
        let encoded = try JSONEncoder().encode(reference)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("access"))
        let restored = try JSONDecoder().decode(ExternalSubtitle.self, from: encoded)
        #expect(restored == reference && restored.access == nil)
    }

    @Test func externalMetadataIsBounded() throws {
        let reference = ExternalSubtitle(path: "/generated/captions.srt")
        try reference.validate()
        var bad = reference; bad.language = "zzz"
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = reference; bad.path = "relative.srt"
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = reference; bad.path = "/" + String(repeating: "x", count: 4096)
        #expect(throws: (any Error).self) { try bad.validate() }
        for title in [" leading", "trailing ", "line\nbreak", String(repeating: "x", count: 1025)] {
            bad = reference; bad.title = title
            #expect(throws: (any Error).self) { try bad.validate() }
        }
    }
}
