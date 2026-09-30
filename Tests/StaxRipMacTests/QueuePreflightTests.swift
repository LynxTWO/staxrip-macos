import Foundation
import Testing
@testable import StaxRipMac

@Suite(.serialized)
@MainActor
struct QueuePreflightTests {
    private func folder() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("queue-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false); return u
    }
    private func job(_ source: URL, _ destination: URL) -> QueueJob {
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"
        return QueueJob(id: UUID(), source: source.path, isDemo: false, destination: destination.path, configuration: c, created: Date())
    }
    private func script(_ url: URL, _ body: String) throws {
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    private func probeTool(_ dir: URL, fields: [String: Any]) throws -> FFmpegTools {
        let data = try JSONSerialization.data(withJSONObject: ["streams": [fields], "format": ["duration": "1"]])
        let payload = dir.appendingPathComponent("probe.json"); try data.write(to: payload)
        let probe = dir.appendingPathComponent("probe")
        try script(probe, "/bin/cat '" + payload.path.replacingOccurrences(of: "'", with: "'\\''") + "'")
        return FFmpegTools(ffmpeg: dir.appendingPathComponent("must-not-run"), ffprobe: probe)
    }
    @Test func mixedQueueReportsAllIssuesWithoutWritesOrEncoding() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let real = try #require(FFmpegTools.discover()), source = dir.appendingPathComponent("source.mkv")
        let created = try await ToolRunner().run(executable: real.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=0.2", "-c:v", "ffv1", source.path])
        try #require(created.status == 0)
        let marker = dir.appendingPathComponent("encoder-was-run"), encoder = dir.appendingPathComponent("encoder")
        try script(encoder, "touch '" + marker.path + "'; exit 1")
        let tools = FFmpegTools(ffmpeg: encoder, ffprobe: real.ffprobe)
        let prior = dir.appendingPathComponent("existing.mkv"); try Data("prior output".utf8).write(to: prior)
        let dangling = dir.appendingPathComponent("link.mkv")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: dir.appendingPathComponent("missing-target"))
        let good = job(source, dir.appendingPathComponent("new.mkv"))
        var bad = job(source, dir.appendingPathComponent("invalid.mkv")); bad.configuration.quality = -1
        let jobs = [good, bad, job(dir.appendingPathComponent("missing.mkv"), dir.appendingPathComponent("missing-out.mkv")),
                    job(source, prior), job(source, dangling), job(source, dir.appendingPathComponent("absent/out.mkv")),
                    job(source, dir.appendingPathComponent("wrong.mp4")), job(source, dir.appendingPathComponent("Case.mkv")), job(source, dir.appendingPathComponent("case.mkv"))]
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), hash = try await SourceFingerprint.read(source)
        let results = try await QueuePreflight.review(jobs, completed: [], tools: tools, encoders: ["libx264"])
        #expect(results.count == jobs.count && results.first?.kind == .checked)
        #expect(results.dropFirst().allSatisfy { $0.kind == .issue })
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == before)
        #expect(try await SourceFingerprint.read(source) == hash)
        #expect(try Data(contentsOf: prior) == Data("prior output".utf8))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: dangling.path).hasSuffix("missing-target"))
        let duplicate = [good, good]
        await #expect(throws: (any Error).self) { try await QueuePreflight.review(duplicate, completed: [], tools: tools, encoders: []) }
        var large: [QueueJob] = []; for _ in 0..<1001 { large.append(job(source, dir.appendingPathComponent(UUID().uuidString + ".mkv"))) }
        await #expect(throws: (any Error).self) { try await QueuePreflight.review(large, completed: [], tools: tools, encoders: []) }
    }
    @Test func deferredAndCompletedStatesDoNotClaimUnperformedChecks() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("synthetic-probe-source"); try Data([0]).write(to: source)
        let fields: [String: Any] = ["index": 0, "codec_type": "video", "codec_name": "hevc", "profile": "Main 10", "pix_fmt": "yuv420p10le", "width": 160, "height": 96,
            "color_transfer": "smpte2084", "color_primaries": "bt2020", "color_space": "bt2020nc", "color_range": "tv", "chroma_location": "left",
            "field_order": "progressive", "sample_aspect_ratio": "1:1", "start_pts": 0]
        var tools = try probeTool(dir, fields: fields)
        var hdr = job(source, dir.appendingPathComponent("hdr.mkv")); hdr.configuration.selectCodec("HEVC"); hdr.configuration.colorMode = "Preserve static HDR10"
        let checked = try await QueuePreflight.inspect(hdr, tools: tools, encoders: ["libx265"])
        #expect(checked.kind == .deferred && checked.detail.contains("Full HDR"))
        tools = try probeTool(dir, fields: ["index": 0, "codec_type": "video", "codec_name": "h264", "pix_fmt": "yuv420p", "width": 160, "height": 96])
        var hardware = job(source, dir.appendingPathComponent("hardware.mkv")); hardware.configuration.selectBackend("Apple hardware")
        let hw = try await QueuePreflight.inspect(hardware, tools: tools, encoders: ["h264_videotoolbox"])
        #expect(hw.kind == .deferred && hw.detail.contains("hardware availability"))
        let completed = job(dir.appendingPathComponent("gone"), dir.appendingPathComponent("done.mkv"))
        let done = try await QueuePreflight.review([completed], completed: [completed.id], tools: tools, encoders: [])
        #expect(done.first?.kind == .completed)
        #expect(!FileManager.default.fileExists(atPath: tools.ffmpeg.path))
    }
    @Test func timeoutsCancellationAndIntentChangesCannotRetainStaleResults() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source"); try Data([0]).write(to: source)
        let slow = dir.appendingPathComponent("slow-probe"); try script(slow, "exec /bin/sleep 30")
        let tools = FFmpegTools(ffmpeg: dir.appendingPathComponent("no-encoder"), ffprobe: slow)
        let item = job(source, dir.appendingPathComponent("out.mkv"))
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        let start = Date()
        let result = try await QueuePreflight.review([item], completed: [], tools: tools, encoders: ["libx264"], timeout: 0.05)
        #expect(result.first?.kind == .issue && result.first?.detail.contains("time limit") == true)
        #expect(Date().timeIntervalSince(start) < 6)
        let journal = dir.appendingPathComponent("journal.json")
        let controller = BatchController(journalURL: journal); controller.tools = tools; controller.encoders = ["libx264"]
        controller.statuses[item.id] = BatchStatus(phase: "Pending", detail: "Preserve processing status")
        controller.review([item]); try #require(controller.reviewing)
        controller.start([item]); #expect(!controller.running)
        controller.cancelReview()
        for _ in 0..<300 where controller.reviewing { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!controller.reviewing && controller.queueChecks.isEmpty && !controller.reviewMatches([item]))
        #expect(controller.reviewStatus.contains("cancelled"))
        controller.review([item]); controller.invalidateReview()
        for _ in 0..<300 where controller.reviewing { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!controller.reviewing && controller.queueChecks.isEmpty && controller.reviewDate == nil)
        #expect(controller.statuses[item.id]?.detail == "Preserve processing status")
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == before)
    }
    @Test func completedReviewIsInvalidatedByIntentOrToolChanges() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source"); try Data([0]).write(to: source)
        let tools = try probeTool(dir, fields: ["index": 0, "codec_type": "video", "codec_name": "h264", "pix_fmt": "yuv420p", "width": 160, "height": 96])
        let item = job(source, dir.appendingPathComponent("out.mkv"))
        let controller = BatchController(); controller.tools = tools; controller.encoders = ["libx264"]
        controller.review([item])
        for _ in 0..<300 where controller.reviewing { try await Task.sleep(for: .milliseconds(20)) }
        #expect(controller.reviewMatches([item]) && controller.reviewDate != nil && controller.queueChecks[item.id]?.kind == .checked)
        var edited = item; edited.configuration.quality = 19
        #expect(!controller.reviewMatches([edited]))
        controller.encoders = []; #expect(!controller.reviewMatches([item]) && controller.queueChecks.isEmpty && controller.reviewDate == nil)
        controller.invalidateReview(); #expect(controller.queueChecks.isEmpty && controller.reviewDate == nil)
    }
}
