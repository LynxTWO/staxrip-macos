import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct TrimmedCaptionTests {
    private func run(_ args: [String], tools: FFmpegTools, limit: Int = 2_000_000) async throws -> Data {
        let result = try await ToolRunner().run(executable: tools.ffmpeg,
            arguments: ["-v", "error", "-nostdin", "-n"] + args, stdoutLimit: limit)
        try #require(result.status == 0 && !result.truncated,
                     Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
        return result.stdout
    }
    private struct FrameList: Decodable {
        struct Frame: Decodable { let best_effort_timestamp_time: String }
        let frames: [Frame]
    }
    private func frames(_ url: URL, tools: FFmpegTools) async throws -> [Double] {
        let result = try await ToolRunner().run(executable: tools.ffprobe, arguments: [
            "-v", "error", "-select_streams", "v:0", "-show_frames", "-show_entries",
            "frame=best_effort_timestamp_time", "-of", "json", url.path])
        try #require(result.status == 0 && !result.truncated)
        return try JSONDecoder().decode(FrameList.self, from: result.stdout).frames.map {
            try #require(Double($0.best_effort_timestamp_time))
        }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)),
          arguments: ["MKV AAC", "MP4 AAC", "MKV Opus"])
    func actualTrimPreservesCuesFramesAudioDelayAndChapters(mode: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caption-trim-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        defer {
            if batch.running { batch.cancel() }
            else { try? FileManager.default.removeItem(at: root) }
        }
        let source = root.appendingPathComponent("source.mkv"), captions = root.appendingPathComponent("captions.srt")
        _ = try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=8",
            "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=4",
            "-filter_complex", "[0:v]settb=1/1000,setpts='(N+0.45*mod(N,2))*1000/24'[v];[1:a]asetpts=PTS+3/TB[a]",
            "-map", "[v]", "-map", "[a]", "-fps_mode:v", "passthrough", "-enc_time_base:v", "filter",
            "-c:v", "ffv1", "-c:a", "pcm_s16le", source.path], tools: tools)
        let original = Data("1\n00:00:00,000 --> 00:00:01,000\nBefore\n\n2\n00:00:01,500 --> 00:00:03,000\nCafé e\u{301}\n\n3\n00:00:03,500 --> 00:00:04,000\nInside\n\n4\n00:00:04,500 --> 00:00:06,000\nCross end\n\n".utf8)
        let expected = Data("1\n00:00:00,000 --> 00:00:01,000\nCafé e\u{301}\n\n2\n00:00:01,500 --> 00:00:02,000\nInside\n\n3\n00:00:02,500 --> 00:00:03,000\nCross end\n\n".utf8)
        try original.write(to: captions)
        let sourceBytes = try Data(contentsOf: source)
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.speed = "Fast"
        c.container = mode.hasPrefix("MP4") ? "MP4" : "MKV"
        c.audio = mode.hasSuffix("Opus") ? "Opus" : "AAC"; c.subtitleMode = "Remove all subtitles"
        c.picture.start = 2; c.picture.end = 5
        c.externalSubtitle = ExternalSubtitle(path: captions.path, language: "eng", title: "Clipped captions")
        c.chapterEdits = ChapterEdits(mode: .custom, entries: [
            ChapterEntry(startMilliseconds: 1000, endMilliseconds: 3500, title: "First = literal"),
            ChapterEntry(startMilliseconds: 3500, endMilliseconds: 6000, title: "Second")])
        let output = root.appendingPathComponent("output." + c.container.lowercased())
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path,
                           configuration: c, created: Date())
        let encoders: Set<String> = ["libx264", "aac", "libopus"]
        let review = try await QueuePreflight.inspect(job, tools: tools, encoders: encoders)
        #expect(review.kind == .checked && review.detail.contains("3 captured cues, clipped to trim"))
        batch.tools = tools; batch.encoders = encoders; batch.start([job])
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        let status = try #require(batch.statuses[job.id])
        try #require(status.phase == "Completed", Comment(rawValue: status.detail))
        #expect(status.detail.contains("Verified 3 external caption cues"))
        let decoded = try await run(["-i", output.path, "-map", "0:s:0", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: tools)
        #expect(decoded == expected)
        let inputTimes = try await frames(source, tools: tools)
        let expectedTimes = inputTimes.filter { $0 >= 2 && $0 < 5 }.map { $0 - 2 }
        let outputTimes = try await frames(output, tools: tools)
        try #require(outputTimes.count == expectedTimes.count)
        for (a, b) in zip(outputTimes, expectedTimes) { #expect(abs(a - b) <= 0.001001) }
        let probe = try await MediaProbe.read(output, tools: tools)
        let chapters = try ContainerPreservation.readChapters(probe)
        try #require(chapters.count == 2)
        #expect(chapters[0].start == 0 && abs(chapters[0].end - 1.5) < 0.001)
        #expect(abs(chapters[1].start - 1.5) < 0.001 && abs(chapters[1].end - 3) < 0.001)
        #expect(chapters.map(\.title) == ["First = literal", "Second"])
        // Decode against container timestamps, padding the delayed track to time zero.
        // A one-second displacement would otherwise be invisible in raw sample order.
        let pcm = try await run(["-copyts", "-i", output.path, "-map", "0:a:0", "-af",
            "aresample=async=1:first_pts=0", "-ac", "1", "-ar", "48000", "-f", "f32le", "pipe:1"], tools: tools)
        let samples: [Float] = pcm.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count - 3, by: 4).map {
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
            }
        }
        try #require(samples.count >= 140_000 && samples.count <= 147_000)
        #expect(samples.prefix(43_200).allSatisfy { abs($0) < 0.0001 }, "The first 0.9 seconds stay silent")
        let onset = try #require(samples.firstIndex { abs($0) > 0.02 })
        #expect(abs(Double(onset) / 48000 - 1) < 0.025, "Tone onset remains at one second, within one AAC frame plus rounding")
        let energy = samples[50_400..<139_200].reduce(0.0) { $0 + Double($1) * Double($1) } / 88_800
        #expect(energy > 0.003)
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: captions) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
}
