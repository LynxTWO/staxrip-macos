import Foundation
import Testing
@testable import StaxRipMac

@MainActor
final class ExportActivityRecorder {
    private(set) var reasons: [String] = []
    private(set) var active = 0
    private(set) var ended = 0

    func begin(_ reason: String) -> () -> Void {
        reasons.append(reason); active += 1
        var finished = false
        return { [self] in
            #expect(!finished, "Every export activity must end exactly once")
            finished = true; active -= 1; ended += 1
        }
    }

    func expectSettled(count: Int = 1) {
        #expect(active == 0)
        #expect(reasons.count == count && ended == count)
    }
}

@MainActor
struct ExportActivityTests {
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func oneQueueActivitySpansTwoJobsAndRejectedStartsAcquireNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let tools = try #require(FFmpegTools.discover())
        let source = root.appendingPathComponent("source.mkv")
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=0.25", "-c:v", "ffv1", source.path])
        try #require(generated.status == 0)
        let original = try Data(contentsOf: source)
        let activity = ExportActivityRecorder()
        var cleanupCalls = 0, publicationCalls = 0, sourceCalls = 0
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"), readSource: { url, progress in
            await MainActor.run { #expect(activity.active == 1); sourceCalls += 1 }
            return try await ExportSourceFingerprint.read(url, progress: progress)
        }, publishOutput: { staged, output in
            #expect(activity.active == 1); publicationCalls += 1
            try await ExportPublication.publishAsync(staged: staged, destination: output)
        }, removeStaging: { directory in
            #expect(activity.active == 1); cleanupCalls += 1
            try await ExportStaging.remove(directory)
        }, beginActivity: activity.begin)
        defer { if !batch.running { try? FileManager.default.removeItem(at: root) } }
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.audio = "No audio"
        c.subtitleMode = "Remove all subtitles"; c.speed = "Fast"; c.picture.deinterlace = "Off"
        let jobs = (1...2).map { QueueJob(id: UUID(), source: source.path, isDemo: false,
            destination: root.appendingPathComponent("result-\($0).mkv").path, configuration: c, created: Date()) }
        batch.start(jobs) // Missing tools is a no-op.
        batch.tools = tools; batch.encoders = ["libx264"]
        batch.start([])
        activity.expectSettled(count: 0)
        batch.start(jobs)
        #expect(activity.active == 1)
        batch.start(jobs) // A duplicate start cannot acquire a second token.
        do { while batch.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch {
            batch.cancel()
            await Task { @MainActor in
                while batch.running { try? await Task.sleep(for: .milliseconds(10)) }
            }.value
            throw error
        }
        activity.expectSettled()
        #expect(sourceCalls == 4 && publicationCalls == 2 && cleanupCalls == 2)
        for job in jobs {
            try #require(batch.statuses[job.id]?.phase == "Completed", Comment(rawValue: batch.statuses[job.id]?.detail ?? "Missing status"))
            let probe = try await MediaProbe.read(URL(fileURLWithPath: job.destination), tools: tools)
            #expect(probe.video?.codec_name == "h264" && probe.seconds > 0)
        }
        batch.start(jobs) // Completed-only is a no-op.
        activity.expectSettled()
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })

        let refused = ExportActivityRecorder()
        let blockedJournal = root.appendingPathComponent("missing-parent/journal.json")
        // A preexisting non-directory parent deterministically refuses the recovery write.
        try Data("protected parent".utf8).write(to: blockedJournal.deletingLastPathComponent())
        let rejected = BatchController(journalURL: blockedJournal, beginActivity: refused.begin)
        rejected.tools = tools; rejected.encoders = ["libx264"]; rejected.start(jobs)
        #expect(!rejected.running && rejected.recoveryError != nil)
        refused.expectSettled(count: 0)
        #expect(try Data(contentsOf: blockedJournal.deletingLastPathComponent()) == Data("protected parent".utf8))
    }
}
