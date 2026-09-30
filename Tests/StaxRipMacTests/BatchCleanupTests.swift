import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@MainActor
struct BatchCleanupTests {
    private func fixture() async throws -> (URL, FFmpegTools, QueueJob) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("batch-cleanup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let tools = try #require(FFmpegTools.discover())
        let source = root.appendingPathComponent("source.mkv")
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=0.25", "-c:v", "ffv1", source.path])
        #expect(result.status == 0)
        let unrelated = root.appendingPathComponent(".staxrip-batch-unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        try Data("keep sibling".utf8).write(to: unrelated.appendingPathComponent("keep"))
        var config = EncodeConfiguration()
        config.codec = "H.264"; config.encoder = "x264"; config.container = "MKV"
        config.audio = "No audio"; config.subtitleMode = "Remove all subtitles"; config.speed = "Fast"
        config.picture.deinterlace = "Off"
        return (root, tools, QueueJob(id: UUID(), source: source.path, isDemo: false,
                                     destination: root.appendingPathComponent("result.mkv").path, configuration: config, created: Date()))
    }
    private func finish(_ controller: BatchController) async throws {
        let deadline = Date().addingTimeInterval(15)
        while controller.running && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        if controller.running { controller.cancel() }
        #expect(!controller.running, "Batch should settle within the fixture deadline")
    }
    private func second(_ job: QueueJob) -> QueueJob {
        QueueJob(id: UUID(), source: job.source, isDemo: job.isDemo,
                 destination: URL(fileURLWithPath: job.destination).deletingLastPathComponent().appendingPathComponent("second.mkv").path,
                 configuration: job.configuration, created: job.created)
    }
    private func protectedFiles(_ root: URL, job: QueueJob, source: Data) throws {
        #expect(try Data(contentsOf: URL(fileURLWithPath: job.source)) == source)
        #expect(try Data(contentsOf: root.appendingPathComponent(".staxrip-batch-unrelated/keep")) == Data("keep sibling".utf8))
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func publishedCleanupFailureKeepsOutputAndStopsBeforeNextJob() async throws {
        let (root, tools, job) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Data(contentsOf: URL(fileURLWithPath: job.source))
        let next = second(job), journal = root.appendingPathComponent("journal.json")
        var attempted: [URL] = []
        let batch = BatchController(journalURL: journal, removeStaging: { directory in
            attempted.append(directory)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        })
        batch.tools = tools; batch.encoders = ["libx264"]; batch.start([job, next])
        try await finish(batch)
        let status = try #require(batch.statuses[job.id])
        #expect(status.phase == "Completed"); #expect(status.progress == 1)
        #expect(status.destination == URL(fileURLWithPath: job.destination))
        #expect(status.detail.contains("Cleanup warning")); #expect(status.detail.contains("saved successfully"))
        #expect(attempted.count == 1)
        let retained = try #require(attempted.first)
        #expect(retained.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        #expect(retained.lastPathComponent.hasPrefix(".staxrip-batch-"))
        #expect(retained.lastPathComponent != ".staxrip-batch-unrelated")
        #expect(status.detail.contains(retained.path))
        #expect(FileManager.default.fileExists(atPath: retained.path))
        #expect(batch.statuses[next.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: next.destination))
        let probe = try await MediaProbe.read(URL(fileURLWithPath: job.destination), tools: tools)
        #expect(probe.video?.codec_name == "h264"); #expect(probe.seconds > 0)
        let output = try Data(contentsOf: URL(fileURLWithPath: job.destination))
        #expect(try Data(contentsOf: retained.appendingPathComponent("encoded.mkv")) == output)
        let restarted = BatchController(journalURL: journal)
        _ = try #require(restarted.restoreQueue())
        #expect(restarted.statuses[job.id]?.phase == "Completed")
        #expect(restarted.statuses[job.id]?.detail == status.detail)
        restarted.tools = tools; restarted.encoders = ["libx264"]; restarted.start([job])
        #expect(!restarted.running)
        #expect(try Data(contentsOf: URL(fileURLWithPath: job.destination)) == output)
        try protectedFiles(root, job: job, source: source)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: [false, true])
    func failedOrCancelledWriterPreservesPrimaryOutcomeWhenCleanupFails(cancel: Bool) async throws {
        let (root, tools, job) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Data(contentsOf: URL(fileURLWithPath: job.source))
        let script = root.appendingPathComponent("encoder")
        let body = "#!/bin/sh\nfor target do :; done\nprintf partial > \"$target\"\nprintf '%s' \"$$\" > \"${target%/*}/writer.pid\"\nprintf 'deliberate encoder failure' >&2\n" + (cancel ? "exec /bin/sleep 30\n" : "exit 42\n")
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let next = second(job), journal = root.appendingPathComponent("journal.json")
        var attempted: [URL] = []
        let batch = BatchController(journalURL: journal, removeStaging: { directory in
            attempted.append(directory)
            let pidText = try String(contentsOf: directory.appendingPathComponent("writer.pid"), encoding: .utf8)
            let pid = try #require(Int32(pidText))
            let alive = Darwin.kill(pid, 0), code = errno
            #expect(alive == -1, "Writer must settle before cleanup")
            #expect(code == ESRCH)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        })
        batch.tools = FFmpegTools(ffmpeg: script, ffprobe: tools.ffprobe); batch.encoders = ["libx264"]
        batch.start([job, next])
        if cancel {
            let deadline = Date().addingTimeInterval(5)
            var started = false
            while batch.running && Date() < deadline {
                let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                started = directories.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("writer.pid").path) }
                if started { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(started, "Cancel an actually started writer")
            batch.cancel()
        }
        try await finish(batch)
        let status = try #require(batch.statuses[job.id])
        #expect(status.phase == (cancel ? "Cancelled" : "Failed"))
        #expect(status.destination == nil); #expect(status.detail.contains("No output was published"))
        #expect(status.detail.contains("Cleanup warning"))
        if cancel { #expect(status.detail.contains("Operation was cancelled")) }
        else { #expect(status.detail.contains("FFmpeg exited 42")); #expect(status.detail.contains("deliberate encoder failure")) }
        #expect(attempted.count == 1)
        let retained = try #require(attempted.first)
        #expect(status.detail.contains(retained.path))
        #expect(try Data(contentsOf: retained.appendingPathComponent("encoded.mkv")) == Data("partial".utf8))
        #expect(batch.statuses[next.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: job.destination))
        #expect(!FileManager.default.fileExists(atPath: next.destination))
        let restored = try BatchJournal.read(from: journal).restoredStatuses()
        #expect(restored[job.id]?.phase == status.phase); #expect(restored[job.id]?.detail == status.detail)
        try protectedFiles(root, job: job, source: source)
    }
}
