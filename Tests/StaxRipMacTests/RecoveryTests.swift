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

    @Test func demonstrationJournalSelectionRefusesAdoptionAndAliases() throws {
        let parent = try directory().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("staxrip-demo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let journal = root.appendingPathComponent("demo-batch.json")
        #expect(BatchJournal.demoSelection(root: nil) == .notRequested)
        for invalid in ["", "relative", parent.path, root.path + "/missing", root.path + "\n"] {
            #expect(BatchJournal.demoSelection(root: invalid) == .refused)
        }
        #expect(BatchJournal.demoSelection(root: root.path) == .isolated(journal))
        let alias = parent.appendingPathComponent("staxrip-demo-" + UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        #expect(BatchJournal.demoSelection(root: alias.path) == .refused)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        #expect(BatchJournal.demoSelection(root: root.path) == .refused)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let sentinel = Data("existing generated recovery must be retained".utf8)
        try sentinel.write(to: journal, options: .withoutOverwriting)
        #expect(BatchJournal.demoSelection(root: root.path) == .refused)
        #expect(try Data(contentsOf: journal) == sentinel)
        try FileManager.default.removeItem(at: journal)
        try sentinel.write(to: journal.appendingPathExtension("lock"), options: .withoutOverwriting)
        #expect(BatchJournal.demoSelection(root: root.path) == .refused)
        #expect(try Data(contentsOf: journal.appendingPathExtension("lock")) == sentinel)
    }

    @Test func refusedDemonstrationCannotStartOrCheckpoint() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent("untouched.json")
        let controller = BatchController(journalURL: journal)
        controller.configureDemoJournal(refused: true)
        controller.tools = FFmpegTools(ffmpeg: URL(fileURLWithPath: "/usr/bin/false"), ffprobe: URL(fileURLWithPath: "/usr/bin/false"))
        controller.start([job(in: root)])
        #expect(!controller.running)
        #expect(controller.statuses.isEmpty)
        #expect(controller.recovery == nil)
        #expect(controller.recoveryError?.contains("Queue execution is disabled") == true)
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        #expect(!FileManager.default.fileExists(atPath: journal.appendingPathExtension("lock").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func validDemonstrationCheckpointsOnlyItsGeneratedJournal() async throws {
        let parent = try directory().resolvingSymlinksInPath()
        var settled = false
        defer { if settled { try? FileManager.default.removeItem(at: parent) } }
        let root = parent.appendingPathComponent("staxrip-demo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        guard case .isolated(let journal) = BatchJournal.demoSelection(root: root.path) else {
            Issue.record("Fresh generated journal selection refused"); return
        }
        let controller = BatchController(journalURL: journal)
        controller.configureDemoJournal(refused: false)
        controller.tools = FFmpegTools(ffmpeg: URL(fileURLWithPath: "/usr/bin/false"), ffprobe: URL(fileURLWithPath: "/usr/bin/false"))
        let item = QueueJob(id: UUID(), source: root.appendingPathComponent("source.mkv").path,
                            isDemo: true, destination: root.appendingPathComponent("result.mkv").path,
                            configuration: EncodeConfiguration(), created: Date(timeIntervalSince1970: 0))
        controller.start([item])
        let deadline = Date().addingTimeInterval(5)
        while controller.running && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!controller.running)
        settled = true
        #expect(controller.isolatedDemoJournal)
        #expect(controller.statuses[item.id]?.phase == "Failed")
        let saved = try BatchJournal.read(from: journal)
        #expect(saved.jobs == [item])
        #expect(saved.statuses[item.id]?.phase == "Failed")
        #expect(!FileManager.default.fileExists(atPath: item.destination))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) == ["demo-batch.json", "demo-batch.json.lock"])
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
