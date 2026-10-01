import Foundation
import Testing
@testable import StaxRipMac

struct TrackInspectionTests {
    private func stream(_ fields: [String: Any] = [:]) throws -> MediaProbe.Stream {
        var value = fields; value["index"] = 7
        return try JSONDecoder().decode(MediaProbe.Stream.self, from: JSONSerialization.data(withJSONObject: value))
    }
    @Test func declaredIdentityIsCaseInsensitiveBoundedAndNeverInferred() throws {
        let missing = try stream()
        #expect(TrackInspection.title(missing) == "Unspecified" && TrackInspection.language(missing) == "Unspecified")
        let named = try stream(["tags": ["NAME": "Track é 起点", "LANGUAGE": "fra"]])
        #expect(TrackInspection.title(named) == "Track é 起点" && TrackInspection.language(named) == "fra")
        let title = try stream(["tags": ["title": "Authored title", "name": "Alternate name"]])
        #expect(TrackInspection.title(title) == "Authored title")
        let raw = "a\n\t\u{202E}" + String(repeating: "é", count: 600)
        let hostile = try stream(["tags": ["TITLE": raw, "LANGUAGE": raw]])
        for value in [TrackInspection.title(hostile), TrackInspection.language(hostile)] {
            #expect(value.hasSuffix("[shortened]"))
            #expect(value.unicodeScalars.count < 540)
            #expect(!value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
        }
        let empty = try stream(["tags": ["title": " \n ", "language": ""]])
        #expect(TrackInspection.title(empty) == "Unspecified" && TrackInspection.language(empty) == "Unspecified")
    }
    @Test func allFiveRolesKeepUnknownAndInvalidDistinctFromUnset() throws {
        let keys = ["default", "forced", "hearing_impaired", "visual_impaired", "comment"]
        let absent = TrackInspection.roles(try stream())
        #expect(absent.map(\.id) == keys && Set(absent.map(\.id)).count == 5)
        #expect(absent.allSatisfy { $0.state == .absent })
        for (input, expected) in [(0, TrackInspection.FlagState.unset), (1, .set), (2, .invalid), (-1, .invalid)] {
            let value = try stream(["disposition": Dictionary(uniqueKeysWithValues: keys.map { ($0, input) })])
            let roles = TrackInspection.roles(value)
            #expect(roles.allSatisfy { $0.state == expected && !$0.help.isEmpty })
        }
        let partial = try stream(["disposition": ["default": 1, "forced": 0, "comment": 99, "unknown_future": 1]])
        let roles = TrackInspection.roles(partial)
        #expect(roles.map(\.state) == [.set, .unset, .absent, .absent, .invalid])
        let summary = TrackInspection.summary(partial)
        #expect(summary.contains("Reported flags: Default."))
        #expect(summary.contains("not reported") && summary.contains("invalid"))
        #expect(!summary.contains("unknown_future") && !summary.contains("Forced,"))
        let unknown = TrackInspection.summary(try stream())
        #expect(unknown.contains("none reported as set") && unknown.contains("not reported"))
        let noFlags = try stream(["disposition": Dictionary(uniqueKeysWithValues: keys.map { ($0, 0) })])
        #expect(!TrackInspection.summary(noFlags).contains("not reported"))
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func actualTrackDeclarationsAreReadWithoutMutation() async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("track-roles-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let captions = root.appendingPathComponent("captions.srt"), source = root.appendingPathComponent("source.mkv")
        try Data("1\n00:00:00,000 --> 00:00:01,000\nGenerated captions\n\n".utf8).write(to: captions)
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=1", "-i", captions.path, "-map", "0:v", "-map", "1:s", "-c:v", "libx264", "-preset", "ultrafast", "-threads", "2", "-c:s", "copy", "-metadata:s:s:0", "title=Access captions", "-metadata:s:s:0", "language=eng", "-disposition:s:0", "default+forced+hearing_impaired", source.path])
        try #require(result.status == 0)
        let before = try Data(contentsOf: source), captionBytes = try Data(contentsOf: captions)
        let listing = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let probe = try await MediaProbe.read(source, tools: tools)
        let caption = try #require(probe.streams.first { $0.codec_type == "subtitle" })
        #expect(caption.index == 1)
        #expect(TrackInspection.title(caption) == "Access captions" && TrackInspection.language(caption) == "eng")
        #expect(TrackInspection.roles(caption).map(\.state) == [.set, .set, .set, .unset, .unset])
        #expect(TrackInspection.summary(caption) == "Reported flags: Default, Forced, Hearing accessibility.")
        #expect(try Data(contentsOf: source) == before && Data(contentsOf: captions) == captionBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == listing)
    }
}
