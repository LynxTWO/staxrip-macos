import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct RecoveryTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func job(in folder: URL, name: String = "result") -> QueueJob {
        QueueJob(id: UUID(), source: folder.appendingPathComponent("source.mkv").path, isDemo: false, destination: folder.appendingPathComponent(name + ".mkv").path, configuration: EncodeConfiguration(), created: Date())
    }

    @Test func interruptedJobsRestoreWithoutStartingOrRemovingFiles() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = job(in: dir), second = job(in: dir, name: "second")
        let partial = dir.appendingPathComponent(".staxrip-batch-owned-by-other-operation")
        try Data("keep".utf8).write(to: partial)
        let journalURL = dir.appendingPathComponent("journal.json")
        try BatchJournal(jobs: [first, second], statuses: [first.id: BatchStatus(phase: "Encoding", progress: 0.5), second.id: BatchStatus()]).write(to: journalURL)
        let controller = BatchController(journalURL: journalURL)
        #expect(!controller.running)
        #expect(controller.statuses.isEmpty)
        #expect(controller.recovery?.jobs.count == 2)
        let restored = try #require(controller.restoreQueue())
        #expect(restored.map(\.id) == [first.id, second.id])
        #expect(controller.statuses[first.id]?.phase == "Interrupted")
        #expect(controller.statuses[second.id]?.phase == "Pending")
        #expect(!controller.running)
        #expect(try Data(contentsOf: partial) == Data("keep".utf8))
        #expect(!FileManager.default.fileExists(atPath: first.destination))
        #expect(controller.restoreQueue() == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: journalURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func missingCompletedOutputBecomesReviewableFailure() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let item = job(in: dir)
        let journal = BatchJournal(jobs: [item], statuses: [item.id: BatchStatus(phase: "Completed", progress: 1, destination: URL(fileURLWithPath: item.destination))])
        #expect(try journal.validated().restoredStatuses()[item.id]?.phase == "Failed")
    }

    @Test func publicationBeforeCrashIsNotTreatedAsSafeToOverwrite() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let item = job(in: dir)
        let destination = URL(fileURLWithPath: item.destination)
        try Data("published but completion not checkpointed".utf8).write(to: destination)
        let journal = BatchJournal(jobs: [item], statuses: [item.id: BatchStatus(phase: "Verifying")])
        #expect(try journal.validated().restoredStatuses()[item.id]?.phase == "Interrupted")
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func journalLeasePreventsConcurrentWritersAndReleases() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("journal.json")
        var first: BatchJournalLease? = try BatchJournalLease(journalURL: url)
        #expect(first != nil)
        #expect(throws: (any Error).self) { try BatchJournalLease(journalURL: url) }
        first = nil
        let next = try BatchJournalLease(journalURL: url)
        withExtendedLifetime(next) { }
    }

    @Test func untrustedRecoveryIsRejected() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let item = job(in: dir)
        var journal = BatchJournal(jobs: [item], statuses: [UUID(): BatchStatus()])
        #expect(throws: (any Error).self) { try journal.validated() }
        journal.statuses = [item.id: BatchStatus(phase: "Completed", progress: 1, destination: URL(fileURLWithPath: "/unrelated/output.mkv"))]
        #expect(throws: (any Error).self) { try journal.validated() }
        journal.statuses = [:]; journal.version = 99
        #expect(throws: (any Error).self) { try journal.validated() }
        let url = dir.appendingPathComponent("broken.json")
        try Data("{not json".utf8).write(to: url)
        let controller = BatchController(journalURL: url)
        #expect(controller.recoveryError != nil)
        #expect(controller.restoreQueue() == nil)
        #expect(!controller.running)
        try Data(repeating: 32, count: 5_000_001).write(to: url)
        #expect(throws: (any Error).self) { try BatchJournal.read(from: url) }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil)) func completedBatchSurvivesControllerRestart() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let item = job(in: dir), tools = try #require(FFmpegTools.discover())
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24:duration=1", "-c:v", "libx264", item.source])
        #expect(fixture.status == 0)
        let journalURL = dir.appendingPathComponent("journal.json")
        let controller = BatchController(journalURL: journalURL)
        await controller.discover(); controller.start([item])
        while controller.running { try await Task.sleep(for: .milliseconds(20)) }
        #expect(controller.statuses[item.id]?.phase == "Completed")
        let restarted = BatchController(journalURL: journalURL)
        let restored = try #require(restarted.restoreQueue())
        #expect(restarted.statuses[item.id]?.phase == "Completed")
        let original = try Data(contentsOf: URL(fileURLWithPath: item.destination))
        await restarted.discover(); restarted.start(restored)
        #expect(!restarted.running)
        #expect(try Data(contentsOf: URL(fileURLWithPath: item.destination)) == original)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil)) func journalWriteFailurePreventsBatchStart() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let blocker = dir.appendingPathComponent("file-not-directory")
        try Data("existing".utf8).write(to: blocker)
        let item = job(in: dir)
        let controller = BatchController(journalURL: blocker.appendingPathComponent("journal.json"))
        await controller.discover(); controller.start([item])
        #expect(!controller.running)
        #expect(controller.recoveryError != nil)
        #expect(!FileManager.default.fileExists(atPath: item.destination))
        #expect(try Data(contentsOf: blocker) == Data("existing".utf8))
    }
}
