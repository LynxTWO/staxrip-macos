import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct AV1CopyTests {
    private struct Frame: Decodable {
        let best_effort_timestamp_time: String
        let width, height: Int
        let pix_fmt: String
    }
    private struct Frames: Decodable { let frames: [Frame] }
    private func run(_ tool: URL, _ args: [String]) async throws -> Data {
        let result = try await ToolRunner().run(executable: tool, arguments: args, stdoutLimit: 1_048_576)
        try #require(result.status == 0 && !result.truncated, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
        return result.stdout
    }
    private func encode(_ args: [String], tools: FFmpegTools) async throws -> Data {
        try await run(tools.ffmpeg, ["-v", "error", "-nostdin", "-n"] + args)
    }
    private func frames(_ file: URL, pixel: String, tools: FFmpegTools) async throws -> [Double] {
        let data = try await run(tools.ffprobe, ["-v", "error", "-select_streams", "v:0", "-show_frames",
            "-show_entries", "frame=best_effort_timestamp_time,width,height,pix_fmt:frame_side_data=", "-of", "json=compact=1", file.path])
        let frames = try JSONDecoder().decode(Frames.self, from: data).frames
        try #require(frames.count == 72)
        var previous = -1.0
        return try frames.map { frame in
            let time = try #require(Double(frame.best_effort_timestamp_time))
            try #require(time.isFinite && time > previous && frame.width == 160 && frame.height == 96 && frame.pix_fmt == pixel)
            previous = time; return time
        }
    }
    private func pictureHash(_ file: URL, pixel: String, tools: FFmpegTools) async throws -> Data {
        try await encode(["-i", file.path, "-map", "0:v:0", "-fps_mode", "passthrough", "-c:v", "rawvideo",
            "-pix_fmt", pixel, "-f", "hash", "-hash", "sha256", "pipe:1"], tools: tools)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func actualQueuePreservesEightAndTenBitAV1AcrossMP4AndMatroska() async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("av1-copy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        var passed = false
        defer { if passed && !batch.running { try? FileManager.default.removeItem(at: root) } }
        do {
            let caption = root.appendingPathComponent("captions.srt"), prior = root.appendingPathComponent("prior.mkv")
            let text = Data("1\n00:00:00,250 --> 00:00:02,750\nGenerated caption\n\n".utf8)
            let sentinel = Data("Preserve existing output".utf8)
            try text.write(to: caption, options: .withoutOverwriting)
            try sentinel.write(to: prior, options: .withoutOverwriting)
            batch.tools = tools; batch.encoders = []
            for bits in [8, 10] {
                let pixel = bits == 8 ? "yuv420p" : "yuv420p10le"
                let mp4 = root.appendingPathComponent("source-\(bits).mp4"), mkv = root.appendingPathComponent("source-\(bits).mkv")
                let pattern = bits == 8 ? "testsrc2=size=160x96:rate=24:duration=3" :
                    "nullsrc=size=160x96:rate=24:duration=3,format=yuv420p10le,geq=lum='64+mod(X*5+Y*7+N*3,877)':cb='512+mod(X,17)':cr='512-mod(Y,19)'"
                _ = try await encode(["-f", "lavfi", "-i", pattern, "-c:v", "libsvtav1", "-preset", "10", "-crf", "20",
                    "-pix_fmt", pixel, "-threads", "2", "-svtav1-params",
                    "lp=2:color-primaries=1:transfer-characteristics=1:matrix-coefficients=1:color-range=0", mp4.path], tools: tools)
                _ = try await encode(["-i", mp4.path, "-map", "0:v:0", "-c:v", "copy", mkv.path], tools: tools)
                let originals = try [Data(contentsOf: mp4), Data(contentsOf: mkv)]
                for source in [mp4, mkv] {
                    let before = try await MediaProbe.read(source, tools: tools)
                    let video = try #require(before.video)
                    try #require(video.codec_name == "av1" && video.profile == "Main" && video.pix_fmt == pixel)
                    try #require(video.color_primaries == "bt709" && video.color_transfer == "bt709" && video.color_space == "bt709" && video.color_range == "tv")
                    let referenceFrames = try await frames(source, pixel: pixel, tools: tools)
                    let referenceHash = try await pictureHash(source, pixel: pixel, tools: tools)
                    if bits == 10 {
                        let raw = try await encode(["-i", source.path, "-map", "0:v:0", "-frames:v", "1", "-c:v", "rawvideo",
                            "-pix_fmt", pixel, "-f", "rawvideo", "pipe:1"], tools: tools)
                        try #require(raw.count == 160 * 96 * 3)
                        let samples: [UInt16] = raw.withUnsafeBytes { bytes in
                            stride(from: 0, to: bytes.count, by: 2).map { UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt16.self)) }
                        }
                        try #require(samples.allSatisfy { $0 < 1024 } && samples.contains { $0 & 3 != 0 })
                    }
                    for container in ["MP4", "MKV"] {
                        var c = EncodeConfiguration(); c.selectCodec("Copy original"); c.container = container
                        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"
                        c.externalSubtitle = ExternalSubtitle(path: caption.path, language: "eng", title: "Generated AV1 captions")
                        c.chapterEdits = ChapterEdits(mode: .custom, entries: [
                            ChapterEntry(startMilliseconds: 0, endMilliseconds: 1500, title: "First"),
                            ChapterEntry(startMilliseconds: 1500, endMilliseconds: 3000, title: "Second")])
                        let output = root.appendingPathComponent("\(bits)-\(source.pathExtension)-to-\(container.lowercased()).\(container.lowercased())")
                        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: c, created: Date())
                        let preflight = try await QueuePreflight.inspect(job, tools: tools, encoders: [])
                        try #require(preflight.kind == .deferred && preflight.detail.contains("packet verification"))
                        batch.start([job])
                        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
                        let status = try #require(batch.statuses[job.id])
                        try #require(status.phase == "Completed", Comment(rawValue: status.detail))
                        #expect(status.detail.contains("Verified copied video: 72 encoded packets"))
                        #expect(try await pictureHash(output, pixel: pixel, tools: tools) == referenceHash)
                        let actualFrames = try await frames(output, pixel: pixel, tools: tools)
                        for (a, b) in zip(referenceFrames, actualFrames) { #expect(abs(a - b) <= 0.001001) }
                        let after = try await MediaProbe.read(output, tools: tools)
                        _ = try VideoCopyContract.make(probe: before, configuration: c).verifyMetadata(after)
                        #expect(after.streams.filter { $0.codec_type == "video" }.count == 1)
                        #expect(after.streams.filter { $0.codec_type == "audio" }.isEmpty)
                        let subtitle = try #require(after.streams.first { $0.codec_type == "subtitle" })
                        #expect(try await encode(["-i", output.path, "-map", "0:\(subtitle.index)", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: tools) == text)
                        let chapters = try ContainerPreservation.readChapters(after)
                        try #require(chapters.count == 2)
                        #expect(chapters.map(\.title) == ["First", "Second"])
                        for (index, chapter) in chapters.enumerated() {
                            #expect(abs(chapter.start - Double(index) * 1.5) < 0.001)
                            #expect(abs(chapter.end - Double(index + 1) * 1.5) < 0.001)
                        }
                        #expect(try Data(contentsOf: mp4) == originals[0] && Data(contentsOf: mkv) == originals[1])
                        #expect(try Data(contentsOf: caption) == text && Data(contentsOf: prior) == sentinel)
                        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
                    }
                }
            }
            passed = true
        } catch {
            if batch.running { batch.cancel() }
            await Task { @MainActor in
                while batch.running { try? await Task.sleep(for: .milliseconds(10)) }
            }.value
            throw error
        }
    }
}
