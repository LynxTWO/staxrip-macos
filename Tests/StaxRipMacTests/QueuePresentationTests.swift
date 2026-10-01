import Foundation
import Testing
@testable import StaxRipMac

struct QueuePresentationTests {
    private func job() -> QueueJob {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return QueueJob(id: UUID(), source: root.appendingPathComponent("source.mkv").path, isDemo: false,
                        destination: root.appendingPathComponent("output.mkv").path, configuration: EncodeConfiguration(), created: Date())
    }
    @Test func emptyAndUnreviewedNeverClaimCompletedOrCompatible() {
        let empty = QueueOverview(jobs: [], statuses: [UUID(): BatchStatus(phase: "Completed")], running: false, reviewing: false, publicationJobID: nil)
        #expect(empty.completed == 0 && empty.remaining == 0 && empty.attention == 0)
        #expect(empty.title == "Your queue is empty")
        let first = job(), second = job()
        let unreviewed = QueueOverview(jobs: [first, second], statuses: [UUID(): BatchStatus(phase: "Failed")], running: false, reviewing: false, publicationJobID: nil)
        #expect(unreviewed.completed == 0 && unreviewed.remaining == 2 && unreviewed.attention == 0)
        #expect(unreviewed.title == "Ready for your review")
        #expect(unreviewed.message.contains("checks still apply"))
    }
    @Test func completedCleanupIsBothSavedAndNeedsAttention() throws {
        let first = job(), second = job()
        let clean = BatchStatus(phase: "Completed", progress: 1, detail: "Verified", destination: URL(fileURLWithPath: first.destination))
        // A legacy Codable record has no structured cleanup field.
        let data = try JSONEncoder().encode(BatchStatus(phase: "Completed", progress: 1, detail: "Verified\nCleanup warning: fixture removal refused", destination: URL(fileURLWithPath: second.destination)))
        let warning = try JSONDecoder().decode(BatchStatus.self, from: data)
        let overview = QueueOverview(jobs: [first, second], statuses: [first.id: clean, second.id: warning], running: false, reviewing: false, publicationJobID: nil)
        #expect(overview.completed == 2 && overview.remaining == 0 && overview.attention == 1)
        #expect(overview.title != "Queue complete")
        let row = QueueJobPresentation(job: second, status: warning, publishing: false, check: nil)
        #expect(row.completed && row.needsAttention && row.showStatusDetail)
        #expect(row.label == "Saved · cleanup warning")
        let allClean = QueueOverview(jobs: [first], statuses: [first.id: clean], running: false, reviewing: false, publicationJobID: nil)
        #expect(allClean.title == "Queue complete")
        #expect(!QueueJobPresentation(job: first, status: clean, publishing: false, check: nil).showStatusDetail)
        #expect(!BatchStatus(detail: "File named Cleanup warning: example.mkv").hasCleanupWarning)
    }
    @Test(arguments: ["Failed", "Cancelled", "Interrupted"])
    func stoppedOutcomesStayVisibleAndRetriable(phase: String) {
        let first = job(), second = job()
        let failed = BatchStatus(phase: phase, detail: "Review destination before retrying")
        let states = [first.id: BatchStatus(phase: "Completed", destination: URL(fileURLWithPath: first.destination)), second.id: failed]
        let overview = QueueOverview(jobs: [first, second], statuses: states, running: false, reviewing: false, publicationJobID: nil)
        #expect(overview.completed == 1 && overview.remaining == 1 && overview.attention == 1)
        #expect(overview.title == "Review before continuing")
        let row = QueueJobPresentation(job: second, status: failed, publishing: false, check: nil)
        #expect(!row.completed && row.needsAttention && row.showStatusDetail)
        #expect(row.label == phase)
    }
    @Test(arguments: ["Inspecting", "Encoding", "Verifying"])
    func activeAndPublicationOverrideEarlierOutcomes(phase: String) {
        let first = job(), second = job()
        let states = [first.id: BatchStatus(phase: "Failed"), second.id: BatchStatus(phase: phase, detail: "Working")]
        let active = QueueOverview(jobs: [first, second], statuses: states, running: true, reviewing: false, publicationJobID: nil)
        #expect(active.title == "Queue in progress")
        #expect(QueueJobPresentation(job: second, status: states[second.id], publishing: false, check: nil).showStatusDetail)
        let finishing = QueueOverview(jobs: [first, second], statuses: states, running: true, reviewing: false, publicationJobID: second.id)
        #expect(finishing.title == "Finishing the current output")
        #expect(finishing.completed == 0)
        #expect(QueueJobPresentation(job: second, status: states[second.id], publishing: true, check: nil).label == "Finishing")
        let orphan = QueueOverview(jobs: [first], statuses: states, running: true, reviewing: false, publicationJobID: second.id)
        #expect(orphan.title == "Queue in progress")
    }
    @Test func preliminaryIssuesAreVisibleWithoutTurningChecksIntoSuccess() {
        let first = job()
        let issue = QueueCheck(id: first.id, kind: .issue, detail: "Destination already exists")
        let overview = QueueOverview(jobs: [first], statuses: [:], running: false, reviewing: false, publicationJobID: nil, checks: [first.id: issue])
        #expect(overview.attention == 1 && overview.completed == 0 && overview.remaining == 1)
        #expect(QueueJobPresentation(job: first, status: nil, publishing: false, check: issue).needsAttention)
        let checking = QueueOverview(jobs: [first], statuses: [:], running: false, reviewing: true, publicationJobID: nil, checks: [first.id: issue])
        #expect(checking.title == "Checking your queue")
        let passed = QueueCheck(id: first.id, kind: .checked, detail: "Snapshot passed")
        let preliminary = QueueOverview(jobs: [first], statuses: [:], running: false, reviewing: false, publicationJobID: nil, checks: [first.id: passed])
        #expect(preliminary.completed == 0 && preliminary.remaining == 1)
        #expect(preliminary.title == "Ready for your review")
    }
}
