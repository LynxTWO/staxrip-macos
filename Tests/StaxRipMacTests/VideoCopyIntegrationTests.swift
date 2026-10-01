import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct VideoCopyIntegrationTests {
    private func run(_ args: [String], tools: FFmpegTools, limit: Int = 2_000_000) async throws -> Data {
        let result = try await ToolRunner().run(executable: tools.ffmpeg,
            arguments: ["-v", "error", "-nostdin", "-n"] + args, stdoutLimit: limit)
        try #require(result.status == 0 && !result.truncated, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
        return result.stdout
    }
    private struct FrameList: Decodable {
        struct Frame: Decodable { let best_effort_timestamp_time: String }
        let frames: [Frame]
    }
    private func frames(_ url: URL, tools: FFmpegTools) async throws -> [Double] {
        let result = try await ToolRunner().run(executable: tools.ffprobe,
            arguments: ["-v", "error", "-select_streams", "v:0", "-show_frames", "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", url.path])
        try #require(result.status == 0 && !result.truncated)
        return try JSONDecoder().decode(FrameList.self, from: result.stdout).frames.map { try #require(Double($0.best_effort_timestamp_time)) }
    }
    private func pictureHash(_ url: URL, tools: FFmpegTools) async throws -> Data {
        try await run(["-i", url.path, "-map", "0:v:0", "-fps_mode", "passthrough", "-c:v", "rawvideo", "-pix_fmt", "yuv420p", "-f", "hash", "-hash", "sha256", "pipe:1"], tools: tools)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)),
          arguments: ["h264 MKV Copy original", "h264 MP4 AAC", "hevc MKV Opus", "hevc MP4 Copy original", "h264 MP4 AAC Matroska", "hevc MP4 AAC Matroska", "h264 MP4 AAC Matroska CFR", "hevc MP4 AAC Matroska CFR"])
    func realCopiesKeepPicturesTimingAndTrackRecipe(mode: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-copy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        defer { if batch.running { batch.cancel() } else { try? FileManager.default.removeItem(at: root) } }
        let source = root.appendingPathComponent(mode.contains("Matroska") ? "source.mkv" : "source.mp4"), captions = root.appendingPathComponent("captions.srt")
        let hevc = mode.hasPrefix("hevc")
        var arguments = ["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=3",
            "-f", "lavfi", "-i", "sine=frequency=500:sample_rate=48000:duration=2",
            "-filter_complex", (mode.contains("CFR") ? "[0:v]settb=1/1000,setpts=N*1000/24[v];[1:a]asetpts=PTS+0.5/TB[a]" : "[0:v]settb=1/1000,setpts='(N+0.45*mod(N,2))*1000/24'[v];[1:a]asetpts=PTS+0.5/TB[a]"),
            "-map", "[a]", "-map", "[v]", "-c:a", "aac", "-c:v", hevc ? "libx265" : "libx264",
            "-preset", "fast", "-pix_fmt", "yuv420p", "-fps_mode:v", "passthrough", "-enc_time_base:v", "filter"]
        if hevc { arguments += ["-x265-params", "pools=2:frame-threads=2:log-level=error"] }
        _ = try await run(arguments + [source.path], tools: tools)
        let captionBytes = Data("1\n00:00:00,000 --> 00:00:01,000\nCafé e\u{301}\n\n2\n00:00:01,500 --> 00:00:02,500\nOriginal picture\n\n".utf8)
        try captionBytes.write(to: captions)
        let sourceBytes = try Data(contentsOf: source)
        let prior = root.appendingPathComponent("prior.mkv"), sentinel = Data("Existing output".utf8)
        try sentinel.write(to: prior)
        var c = EncodeConfiguration(); c.selectCodec("Copy original")
        c.container = mode.contains("MP4") ? "MP4" : "MKV"
        c.audio = mode.contains("AAC") ? "AAC" : mode.contains("Opus") ? "Opus" : "Copy original"
        c.subtitleMode = "Remove all subtitles"
        c.externalSubtitle = ExternalSubtitle(path: captions.path, language: "eng", title: "Original captions")
        c.chapterEdits = ChapterEdits(mode: .custom, entries: [
            ChapterEntry(startMilliseconds: 0, endMilliseconds: 1500, title: "First = literal"),
            ChapterEntry(startMilliseconds: 1500, endMilliseconds: 3000, title: "Second")])
        let output = root.appendingPathComponent("copied." + c.container.lowercased())
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: c, created: Date())
        let encoders: Set<String> = ["aac", "libopus"] // No video encoder is advertised to this plan.
        let check = try await QueuePreflight.inspect(job, tools: tools, encoders: encoders)
        #expect(check.kind == .deferred && check.detail.contains("packet verification"))
        batch.tools = tools; batch.encoders = encoders; batch.start([job])
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        let status = try #require(batch.statuses[job.id])
        if mode.contains("Matroska") && !mode.contains("CFR") {
            // Matroska nominal packet durations cannot reproduce this VFR MP4
            // timeline within the contract. Never silently relax the tolerance.
            #expect(status.phase == "Failed" && status.detail.contains("presentation timing changed"), Comment(rawValue: status.detail))
            #expect(!FileManager.default.fileExists(atPath: output.path))
            #expect(try Data(contentsOf: source) == sourceBytes)
            #expect(try Data(contentsOf: captions) == captionBytes)
            #expect(try Data(contentsOf: prior) == sentinel)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
            return
        }
        try #require(status.phase == "Completed", Comment(rawValue: status.detail))
        #expect(status.detail.contains("Verified copied video: 72 encoded packets"))
        #expect(status.detail.contains("Verified 2 external caption cues"))
        #expect(try await pictureHash(source, tools: tools) == pictureHash(output, tools: tools))
        let before = try await frames(source, tools: tools), after = try await frames(output, tools: tools)
        try #require(before.count == 72 && after.count == before.count)
        for (a, b) in zip(before, after) { #expect(abs(a - b) <= 0.001001) }
        let actual = try await MediaProbe.read(output, tools: tools)
        let chapters = try ContainerPreservation.readChapters(actual)
        #expect(chapters.map(\.title) == ["First = literal", "Second"])
        try #require(chapters.count == 2)
        #expect(chapters[0].start == 0 && abs(chapters[0].end - 1.5) < 0.001)
        #expect(abs(chapters[1].start - 1.5) < 0.001 && abs(chapters[1].end - 3) < 0.001)
        let decoded = try await run(["-i", output.path, "-map", "0:s:0", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: tools)
        #expect(decoded == captionBytes)
        let pcm = try await run(["-copyts", "-i", output.path, "-map", "0:a:0", "-af", "aresample=async=1:first_pts=0", "-ac", "1", "-ar", "48000", "-f", "f32le", "pipe:1"], tools: tools)
        let samples: [Float] = pcm.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count - 3, by: 4).map { Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) }
        }
        try #require(samples.count >= 119000 && samples.count <= 124000)
        #expect(samples.prefix(21600).allSatisfy { abs($0) < 0.0001 })
        let onset = try #require(samples.firstIndex { abs($0) > 0.02 })
        #expect(abs(Double(onset) / 48000 - 0.5) <= 0.025)
        #expect(samples[30000..<110000].reduce(0.0) { $0 + Double($1 * $1) } / 80000 > 0.003)
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: captions) == captionBytes)
        #expect(try Data(contentsOf: prior) == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
}
