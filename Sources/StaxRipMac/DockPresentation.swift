import Foundation

// A read-only snapshot. Nothing here starts work, estimates time or reads media.
struct DockPresentation: Equatable {
    struct Activity: Equatable {
        let title: String
        var progress: Double? = nil
        var line: String {
            percent.map { "\(title) · \($0)%" } ?? title
        }
        var percent: Int? {
            guard let progress, progress.isFinite, progress > 0, progress < 1 else { return nil }
            return min(99, Int(progress * 100))
        }
    }
    let badge: String?
    let summary: String
    let details: [String]

    init(activities: [Activity], attention: [String]) {
        details = activities.map(\.line) + attention
        if activities.count == 1, let activity = activities.first {
            badge = activity.percent.map { "\($0)%" } ?? "…"
            summary = activity.line
        } else if !activities.isEmpty {
            badge = "…"
            summary = "\(activities.count) operations in progress"
        } else if !attention.isEmpty {
            badge = "!"
            summary = "Attention needed"
        } else {
            badge = nil
            summary = "No operations running"
        }
    }

    // Limit interpretation to current queue IDs and known phases. Historical
    // status records and unstarted jobs cannot imply active or completed work.
    static func queue(jobs: [UUID], statuses: [UUID: BatchStatus], running: Bool,
                      reviewing: Bool, publishing: UUID?, checks: [UUID: QueueCheck]) -> (Activity?, [String]) {
        let current = jobs.compactMap { statuses[$0] }
        var attention: [String] = []
        if current.contains(where: { $0.hasCleanupWarning }) { attention.append("Queue · temporary files need attention") }
        if current.contains(where: { ["Failed", "Interrupted"].contains($0.phase) }) { attention.append("Queue · review stopped jobs") }
        if jobs.contains(where: { checks[$0]?.kind == .issue }) { attention.append("Queue · review preflight issues") }
        if running {
            if let publishing, jobs.contains(publishing) { return (Activity(title: "Queue · finishing output"), attention) }
            let active = current.filter { ["Inspecting", "Encoding", "Verifying"].contains($0.phase) }
            if active.count == 1, let status = active.first {
                switch status.phase {
                case "Encoding": return (Activity(title: "Queue · encoding current job", progress: status.progress), attention)
                case "Verifying": return (Activity(title: "Queue · verifying output"), attention)
                default: return (Activity(title: "Queue · preparing current job"), attention)
                }
            }
            return (Activity(title: "Queue · working"), attention)
        }
        if reviewing { return (Activity(title: "Queue · checking recipes"), attention) }
        return (nil, attention)
    }
}
