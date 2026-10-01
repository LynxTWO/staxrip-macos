import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct OutputDurationTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("duration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func source(_ root: URL, tools: FFmpegTools, seconds: Int = 180, rate: Int = 24) async throws -> URL {
        let url = root.appendingPathComponent("source.mp4")
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "color=c=blue:s=160x96:r=\(rate):d=\(seconds)", "-c:v", "libx264", "-preset", "ultrafast", url.path])
        try #require(result.status == 0)
        return url
    }
    private func job(_ root: URL, source: URL, name: String, start: Double = 0, end: Double = 0) -> QueueJob {
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.container = "MP4"; c.resolution = "Original"
        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"; c.speed = "Fast"
        c.picture.start = start; c.picture.end = end
        return QueueJob(id: UUID(), source: source.path, isDemo: false,
                        destination: root.appendingPathComponent(name).path, configuration: c, created: Date())
    }
    private func finish(_ batch: BatchController) async throws {
        do { while batch.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch { batch.cancel(); throw error }
    }

    @Test func knownDurationHasFixedStrictAllowanceAndUnknownOrInvalidIsExplicit() throws {
        for expected in [1.0, 180, 7200, 86_400] {
            #expect(try OutputDurationCheck.verify(expected: expected, actual: expected).contains("within 250 ms"))
            #expect(try OutputDurationCheck.verify(expected: expected, actual: expected + 0.249).contains("within 250 ms"))
            #expect(try OutputDurationCheck.verify(expected: expected, actual: expected - 0.249).contains("within 250 ms"))
            for difference in [-1.0, -0.25, 0.25, 1] where expected + difference > 0 {
                #expect(throws: (any Error).self) { try OutputDurationCheck.verify(expected: expected, actual: expected + difference) }
            }
        }
        for expected in [0.0, -1] {
            #expect(try OutputDurationCheck.verify(expected: expected, actual: 180) == "Duration unverified: source duration unavailable")
        }
        for actual in [0.0, -1, .nan, .infinity, -.infinity] {
            #expect(throws: (any Error).self) { try OutputDurationCheck.verify(expected: 180, actual: actual) }
        }
        for expected in [Double.nan, .infinity, -.infinity] {
            #expect(throws: (any Error).self) { try OutputDurationCheck.verify(expected: expected, actual: 180) }
        }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(3)))
    func twoHourLowRateSourceAndPreciseTrimHaveBoundedVerifiedDuration() async throws {
        let root = try directory(); var active: BatchController?
        defer { if active?.running != true { try? FileManager.default.removeItem(at: root) } else { active?.cancel() } }
        let tools = try #require(FFmpegTools.discover())
        let long = try await source(root, tools: tools, seconds: 7200, rate: 1)
        let original = try Data(contentsOf: long)
        let whole = job(root, source: long, name: "whole.mp4")
        // Whole-second endpoints suit this deliberately low-frame-rate long fixture.
        let trim = job(root, source: long, name: "trim.mp4", start: 7195, end: 7198)
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json")); active = batch
        batch.tools = tools; batch.encoders = ["libx264"]
        batch.start([whole, trim]); try await finish(batch)
        for (item, expected) in [(whole, 7200.0), (trim, 3.0)] {
            let status = try #require(batch.statuses[item.id])
            #expect(status.phase == "Completed", Comment(rawValue: status.detail))
            #expect(status.detail.contains("Container duration within 250 ms of plan"))
            let actual = try await MediaProbe.read(URL(fileURLWithPath: item.destination), tools: tools)
            #expect(abs(actual.seconds - expected) < 0.25)
        }
        #expect(try Data(contentsOf: long) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(3)), arguments: [false, true])
    func oneSecondChangeOnMultiMinuteOutputCannotPublishAndRetryWorks(extended: Bool) async throws {
        let root = try directory(); var active: BatchController?
        defer { if active?.running != true { try? FileManager.default.removeItem(at: root) } else { active?.cancel() } }
        let tools = try #require(FFmpegTools.discover())
        let source = try await source(root, tools: tools), original = try Data(contentsOf: source)
        let prior = root.appendingPathComponent("prior.mp4"); try Data("keep prior output".utf8).write(to: prior)
        let unrelated = root.appendingPathComponent(".staxrip-batch-unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let sentinel = unrelated.appendingPathComponent("keep"); try Data([1, 2, 3]).write(to: sentinel)
        let script = root.appendingPathComponent("encoder")
        let change = extended ? "-vf 'tpad=stop_mode=clone:stop_duration=1'" : "-t 179"
        let text = "#!/bin/zsh\nargs=(\"$@\")\noutput=${args[-1]}\nargs[-1]=()\nexec " + quote(tools.ffmpeg.path) + " \"${args[@]}\" " + change + " \"$output\"\n"
        try Data(text.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let first = job(root, source: source, name: "result.mp4"), later = job(root, source: source, name: "later.mp4")
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json")); active = batch
        batch.tools = FFmpegTools(ffmpeg: script, ffprobe: tools.ffprobe); batch.encoders = ["libx264"]
        batch.start([first, later]); try await finish(batch)
        #expect(batch.statuses[first.id]?.phase == "Failed")
        #expect(batch.statuses[first.id]?.detail.contains("Output duration differs") == true)
        #expect(batch.statuses[later.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: first.destination) && !FileManager.default.fileExists(atPath: later.destination))
        // When run against the original policy, record the actual accepted duration.
        if FileManager.default.fileExists(atPath: first.destination) {
            let accepted = try await MediaProbe.read(URL(fileURLWithPath: first.destination), tools: tools)
            #expect(accepted.seconds == 180, "Original policy accepted changed duration")
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: prior) == Data("keep prior output".utf8))
        #expect(try Data(contentsOf: sentinel) == Data([1, 2, 3]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".staxrip-batch-") } == [unrelated.lastPathComponent])
        batch.tools = tools; batch.start([first]); try await finish(batch)
        #expect(batch.statuses[first.id]?.phase == "Completed")
        #expect(batch.statuses[first.id]?.detail.contains("Container duration within 250 ms of plan") == true)
        let result = try await MediaProbe.read(URL(fileURLWithPath: first.destination), tools: tools)
        #expect(abs(result.seconds - 180) < 0.25)
        if !extended {
            let trim = job(root, source: source, name: "fractional-trim.mp4", start: 60.125, end: 62.375)
            batch.start([trim]); try await finish(batch)
            #expect(batch.statuses[trim.id]?.phase == "Completed")
            let trimmed = try await MediaProbe.read(URL(fileURLWithPath: trim.destination), tools: tools)
            #expect(abs(trimmed.seconds - 2.25) < 0.001)
        }
        #expect(try Data(contentsOf: source) == original)
    }
}
