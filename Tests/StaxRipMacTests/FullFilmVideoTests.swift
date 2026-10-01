import Foundation
import Testing
@testable import StaxRipMac

/// Explicit local qualification of one licensed source; ordinary CI stays synthetic.
@MainActor
struct FullFilmVideoTests {
    private let sourceHash = "f12c070e295b38cfc94ebd61ac3357c3bac82d1015985f1e8da93a4c6496c46d"
    private struct Frame: Decodable {
        let best_effort_timestamp_time: String
        let width, height: Int
        let pix_fmt: String
    }
    private struct Frames: Decodable { let frames: [Frame] }
    private struct Receipt: Encodable {
        let sourceSHA256: String
        let codec: String
        let decodedFrames: Int
        let maximumFrameDifferenceSeconds: Double
        let subtitleTracks: Int
        let outputBytes: Int64
        let pipelineSeconds: Double
        let copiedPicturesSHA256: String?
        let ffmpegVersion: String
        let system: String
    }
    private func run(_ executable: URL, _ args: [String], limit: Int = 4 * 1024 * 1024) async throws -> Data {
        let result = try await ToolRunner().run(executable: executable, arguments: args, stdoutLimit: limit)
        try #require(result.status == 0 && !result.truncated, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
        return result.stdout
    }
    private func frames(_ file: URL, tools: FFmpegTools) async throws -> [Frame] {
        let data = try await run(tools.ffprobe, ["-v", "error", "-select_streams", "v:0", "-show_frames",
            "-show_entries", "frame=best_effort_timestamp_time,width,height,pix_fmt:frame_side_data=", "-of", "json", file.path])
        let result = try JSONDecoder().decode(Frames.self, from: data).frames
        try #require(result.count == 21_312)
        var previous = -1.0
        for frame in result {
            let time = try #require(Double(frame.best_effort_timestamp_time))
            try #require(time.isFinite && time >= 0 && time > previous)
            try #require(frame.width == 1280 && frame.height == 544 && frame.pix_fmt == "yuv420p")
            previous = time
        }
        return result
    }
    private func pictureHash(_ file: URL, tools: FFmpegTools) async throws -> String {
        let data = try await run(tools.ffmpeg, ["-v", "error", "-nostdin", "-i", file.path, "-map", "0:v:0",
            "-fps_mode", "passthrough", "-c:v", "rawvideo", "-pix_fmt", "yuv420p", "-f", "hash", "-hash", "sha256", "pipe:1"], limit: 1024)
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(text.hasPrefix("SHA256=") && text.utf8.count == 71)
        return text
    }
    private func captions(_ file: URL, index: Int, tools: FFmpegTools) async throws -> Data {
        try await run(tools.ffmpeg, ["-v", "error", "-nostdin", "-i", file.path, "-map", "0:\(index)",
            "-c:s", "srt", "-f", "srt", "pipe:1"], limit: 1_048_576)
    }
    private func tag(_ track: MediaProbe.Stream, _ name: String) -> String? {
        track.tags?.first { $0.key.lowercased() == name }?.value
    }
    private func join(_ batch: BatchController) async {
        if batch.running { batch.cancel() }
        await Task { @MainActor in
            while batch.running { try? await Task.sleep(for: .milliseconds(20)) }
        }.value
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_FULL_FILM_VIDEO"] == "1"), .timeLimit(.minutes(15)))
    func licensedFilmKeepsCompleteVideoTimelineAndCaptionPayloads() async throws {
        let env = ProcessInfo.processInfo.environment
        let sourcePath = try #require(env["STAXRIP_FILM_SOURCE"])
        let parentPath = try #require(env["STAXRIP_FILM_OUTPUT"])
        try #require(sourcePath.hasPrefix("/") && parentPath.hasPrefix("/"))
        let source = URL(fileURLWithPath: sourcePath), parent = URL(fileURLWithPath: parentPath)
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .volumeAvailableCapacityKey])
        try #require(values.isDirectory == true && (values.volumeAvailableCapacity ?? 0) >= 8 * 1024 * 1024 * 1024)
        let original = try await ExportSourceFingerprint.read(source)
        try #require(original.sha256 == sourceHash && original.byteCount == 681_285_280)
        let tools = try #require(FFmpegTools.discover())
        let version = String(decoding: try await run(tools.ffmpeg, ["-version"], limit: 16_384), as: UTF8.self).split(separator: "\n").first.map(String.init) ?? "unknown"
        let root = parent.appendingPathComponent("sintel-video-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        print("FULL_FILM_VIDEO owned local results: \(root.path)")
        let attribution = "Sintel (2010), © Blender Foundation / sintel.org. Source: https://download.blender.org/durian/movies/Sintel.2010.720p.mkv.zip\nCC BY 3.0: https://creativecommons.org/licenses/by/3.0/ ; https://durian.blender.org/sharing/\nThese local derivatives are modified: audio removed, video copied or re-encoded, two generated test caption tracks added. Original film credits retained. Generated captions are validation markers, not translations. No endorsement implied.\n"
        try Data(attribution.utf8).write(to: root.appendingPathComponent("ATTRIBUTION.txt"), options: .withoutOverwriting)
        let a = root.appendingPathComponent("generated-a.srt"), b = root.appendingPathComponent("generated-b.srt")
        let textA = Data("1\n00:00:10,000 --> 00:00:12,000\nGenerated validation A — early\n\n2\n00:07:20,000 --> 00:07:22,000\nGenerated validation A — middle\n\n3\n00:14:40,000 --> 00:14:42,000\nGenerated validation A — late\n\n".utf8)
        let textB = Data("1\n00:00:11,125 --> 00:00:12,875\nGenerated validation B — e\u{301}\n\n2\n00:07:21,125 --> 00:07:22,875\nGenerated validation B — 起点\n\n3\n00:14:41,125 --> 00:14:42,875\nGenerated validation B — end\n\n".utf8)
        try textA.write(to: a, options: .withoutOverwriting); try textB.write(to: b, options: .withoutOverwriting)
        let protected = root.appendingPathComponent("prior-output.mkv"), protectedBytes = Data("Existing output sentinel".utf8)
        try protectedBytes.write(to: protected, options: .withoutOverwriting)
        let probe = try await MediaProbe.read(source, tools: tools)
        let tracks = probe.streams.filter { $0.codec_type == "subtitle" }
        try #require(tracks.count == 10 && tracks.allSatisfy { $0.codec_name == "subrip" })
        let referenceFrames = try await frames(source, tools: tools)
        let referenceHash = try await pictureHash(source, tools: tools)
        var referenceCaptions: [Data] = []
        for track in tracks { referenceCaptions.append(try await captions(source, index: track.index, tools: tools)) }
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        batch.tools = tools; batch.encoders = ["libx264", "libx265"]
        do {
            for (codec, name) in [("Copy original", "copy"), ("H.264", "h264"), ("HEVC", "hevc")] {
                var c = EncodeConfiguration(); c.selectCodec(codec); c.audio = "No audio"; c.container = "MKV"
                c.speed = "Fast"; c.quality = codec == "H.264" ? 20 : 22
                c.externalCaptions = [ExternalSubtitle(path: a.path, language: "und", title: "Generated validation A"),
                                      ExternalSubtitle(path: b.path, language: "und", title: "Generated validation B")]
                let output = root.appendingPathComponent("Sintel-silent-\(name)-modified.mkv")
                let item = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: c, created: Date())
                _ = try await QueuePreflight.inspect(item, tools: tools, encoders: batch.encoders)
                let start = ContinuousClock.now
                batch.start([item])
                while batch.running { try await Task.sleep(for: .milliseconds(20)) }
                let status = try #require(batch.statuses[item.id])
                try #require(status.phase == "Completed", Comment(rawValue: status.detail))
                let elapsed = start.duration(to: .now).components
                let after = try await MediaProbe.read(output, tools: tools)
                try #require(after.streams.filter { $0.codec_type == "video" }.count == 1)
                try #require(after.streams.filter { $0.codec_type == "audio" }.isEmpty)
                try #require(after.video?.codec_name == (codec == "HEVC" ? "hevc" : "h264"))
                let actualFrames = try await frames(output, tools: tools)
                var maximumError = 0.0
                for (expected, actual) in zip(referenceFrames, actualFrames) {
                    let difference = abs(try #require(Double(expected.best_effort_timestamp_time)) - #require(Double(actual.best_effort_timestamp_time)))
                    try #require(difference <= 0.001001)
                    maximumError = max(maximumError, difference)
                }
                let actualTracks = after.streams.filter { $0.codec_type == "subtitle" }
                try #require(actualTracks.count == 12)
                for (index, track) in actualTracks.enumerated() {
                    let expected = index < 10 ? referenceCaptions[index] : (index == 10 ? textA : textB)
                    try #require(try await captions(output, index: track.index, tools: tools) == expected)
                    if index < 10 {
                        try #require(tag(track, "language") == tag(tracks[index], "language"))
                        try #require(tag(track, "title") == tag(tracks[index], "title"))
                    } else {
                        // Matroska may omit its default und language tag.
                        try #require((tag(track, "language") ?? "und") == "und")
                        try #require(tag(track, "title") == c.externalCaptions[index - 10].title)
                    }
                }
                let copiedHash = codec == "Copy original" ? try await pictureHash(output, tools: tools) : nil
                if let copiedHash { try #require(copiedHash == referenceHash) }
                let bytes = try #require((FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value)
                try #require(bytes > 0 && bytes < 2 * 1024 * 1024 * 1024)
                try #require(try Data(contentsOf: protected) == protectedBytes)
                try #require(try Data(contentsOf: a) == textA && Data(contentsOf: b) == textB)
                try #require(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
                let receipt = Receipt(sourceSHA256: original.sha256, codec: codec, decodedFrames: actualFrames.count,
                    maximumFrameDifferenceSeconds: maximumError, subtitleTracks: actualTracks.count, outputBytes: bytes,
                    pipelineSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, copiedPicturesSHA256: copiedHash,
                    ffmpegVersion: version, system: ProcessInfo.processInfo.operatingSystemVersionString)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(receipt).write(to: root.appendingPathComponent(name + "-receipt.json"), options: .withoutOverwriting)
                print("FULL_FILM_VIDEO \(name): verified \(actualFrames.count) frames and \(actualTracks.count) subtitle tracks; \(bytes) bytes")
            }
        } catch {
            await join(batch)
            try #require(try await ExportSourceFingerprint.read(source) == original)
            throw error
        }
        try #require(try await ExportSourceFingerprint.read(source) == original)
    }
}
