import Foundation
import Testing
@testable import StaxRipMac

struct DockPresentationTests {
    @Test func progressNeverClaimsSettlement() {
        for value in [Double.nan, .infinity, -.infinity, -1, 0, 1, 2] {
            let state = DockPresentation(activities: [.init(title: "Quick Export · working", progress: value)], attention: [])
            #expect(state.badge == "…")
            #expect(!state.summary.contains("%"))
        }
        let measured = DockPresentation(activities: [.init(title: "Quick Export · encoding", progress: 0.437)], attention: [])
        #expect(measured.badge == "43%")
        #expect(measured.summary.contains("43%"))
        let almost = DockPresentation(activities: [.init(title: "Quick Export · encoding", progress: 0.9999)], attention: [])
        #expect(almost.badge == "99%")
    }
    @Test func independentWorkDoesNotInventAnAggregateAndAttentionSurvives() {
        let operations: [DockPresentation.Activity] = [.init(title: "Queue", progress: 0.5), .init(title: "Audio Lab")]
        let active = DockPresentation(activities: operations, attention: ["Cleanup needed"])
        #expect(active.badge == "…" && !active.summary.contains("%"))
        #expect(active.details == ["Queue · 50%", "Audio Lab", "Cleanup needed"])
        let settled = DockPresentation(activities: [], attention: ["Cleanup needed"])
        #expect(settled.badge == "!")
        let clear = DockPresentation(activities: [], attention: [])
        #expect(clear.badge == nil && clear.summary == "No operations running")
    }
    @Test func queueUsesCurrentIDsAndOnlyEncodingProgress() {
        let id = UUID(), stale = UUID()
        var statuses = [id: BatchStatus(phase: "Pending"), stale: BatchStatus(phase: "Failed")]
        let pending = DockPresentation.queue(jobs: [id], statuses: statuses, running: false, reviewing: false, publishing: nil, checks: [:])
        #expect(pending.0 == nil && pending.1.isEmpty)
        for phase in ["Inspecting", "Encoding", "Verifying"] {
            statuses[id] = BatchStatus(phase: phase, progress: 0.5)
            let work = DockPresentation.queue(jobs: [id], statuses: statuses, running: true, reviewing: false, publishing: nil, checks: [:])
            #expect(work.0?.percent == (phase == "Encoding" ? 50 : nil))
            #expect(work.1.isEmpty)
        }
        let finishing = DockPresentation.queue(jobs: [id], statuses: statuses, running: true, reviewing: false, publishing: id, checks: [:])
        #expect(finishing.0?.title.contains("finishing") == true && finishing.0?.percent == nil)
        statuses[id] = BatchStatus(phase: "Completed", progress: 1)
        let done = DockPresentation.queue(jobs: [id], statuses: statuses, running: false, reviewing: false, publishing: nil, checks: [:])
        #expect(done.0 == nil && done.1.isEmpty)
        statuses[id] = BatchStatus(phase: "Cancelled")
        let cancelled = DockPresentation.queue(jobs: [id], statuses: statuses, running: false, reviewing: false, publishing: nil, checks: [:])
        #expect(cancelled.0 == nil && cancelled.1.isEmpty)
        statuses[id] = BatchStatus(phase: "Completed", progress: 1, detail: "Verified\nCleanup warning: generated fixture")
        let cleanup = DockPresentation.queue(jobs: [id], statuses: statuses, running: false, reviewing: false, publishing: nil, checks: [:])
        #expect(cleanup.0 == nil && cleanup.1.count == 1)
        let removed = DockPresentation.queue(jobs: [], statuses: statuses, running: false, reviewing: false, publishing: nil, checks: [:])
        #expect(removed.0 == nil && removed.1.isEmpty)
    }
    @Test func reviewIsWorkWithoutEncodingAndIssuesAreNotSuccess() {
        let id = UUID()
        let issue = QueueCheck(id: id, kind: .issue, detail: "generated issue")
        let result = DockPresentation.queue(jobs: [id], statuses: [:], running: false, reviewing: true, publishing: nil, checks: [id: issue])
        #expect(result.0?.title == "Queue · checking recipes")
        #expect(result.0?.percent == nil && result.1.count == 1)
    }
}
