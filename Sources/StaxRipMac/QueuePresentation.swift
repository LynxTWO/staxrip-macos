import Foundation

extension BatchStatus {
    // Existing journals store this marker in detail; no persistence migration.
    var hasCleanupWarning: Bool {
        detail.hasPrefix("Cleanup warning:") || detail.contains("\nCleanup warning:")
    }
}

struct QueueJobPresentation {
    let completed: Bool
    let needsAttention: Bool
    let showStatusDetail: Bool
    let label: String
    let symbol: String

    init(job: QueueJob, status: BatchStatus?, publishing: Bool, check: QueueCheck?) {
        let dolbyCopy = [DolbyConversionIntent.hdr10Copy,DolbyConversionIntent.p81Copy].contains(job.configuration.colorMode)
        completed = status?.phase == "Completed"
        let cleanup = status?.hasCleanupWarning == true
        let phase = status?.phase ?? "Pending"
        needsAttention = cleanup || ["Failed", "Cancelled", "Interrupted"].contains(phase) || check?.kind == .issue
        showStatusDetail = (completed && dolbyCopy) || needsAttention || publishing || ["Inspecting", "Encoding", "Verifying"].contains(phase)
        if publishing { label = "Finishing"; symbol = "arrow.up.document" }
        else if completed && cleanup { label = "Saved · cleanup warning"; symbol = "exclamationmark.triangle" }
        else if completed { label = "Completed"; symbol = "checkmark.circle.fill" }
        else if phase == "Encoding", dolbyCopy { label = "Copying"; symbol = "doc.on.doc" }
        else if phase == "Failed" { label = "Failed"; symbol = "exclamationmark.triangle" }
        else if phase == "Cancelled" { label = "Cancelled"; symbol = "pause.circle" }
        else if phase == "Interrupted" { label = "Interrupted"; symbol = "exclamationmark.arrow.triangle.2.circlepath" }
        else if job.isDemo { label = "Demo"; symbol = "play.rectangle" }
        else if check?.kind == .issue { label = "Needs correction"; symbol = "exclamationmark.triangle" }
        else if phase == "Pending" { label = "Pending"; symbol = "clock" }
        else { label = phase; symbol = "gearshape.2" }
    }
}

struct QueueOverview {
    let completed: Int
    let remaining: Int
    let attention: Int
    let title: String
    let message: String

    init(jobs: [QueueJob], statuses: [UUID: BatchStatus], running: Bool, reviewing: Bool,
         publicationJobID: UUID?, checks: [UUID: QueueCheck] = [:]) {
        let presentations = jobs.map {
            QueueJobPresentation(job: $0, status: statuses[$0.id], publishing: publicationJobID == $0.id, check: checks[$0.id])
        }
        completed = presentations.filter(\.completed).count
        remaining = jobs.count - completed
        attention = presentations.filter(\.needsAttention).count
        if jobs.isEmpty {
            title = "Your queue is empty"; message = "Build a recipe in Workspace, then bring it here."
        } else if running {
            let finishing = jobs.contains { $0.id == publicationJobID }
            title = finishing ? "Finishing the current output" : "Queue in progress"
            message = finishing ? "Waiting for publication to settle. Later jobs wait their turn." : "Each output is checked before it is saved."
        } else if reviewing {
            title = "Checking your queue"; message = "Reading a preliminary snapshot. Nothing is being encoded."
        } else if completed == jobs.count {
            title = attention > 0 ? "Outputs saved. Attention needed." : "Queue complete"
            message = attention > 0 ? "Recorded outputs stay available. Review the items marked for attention." : "Every job has a recorded completed output."
        } else if attention > 0 {
            title = "Review before continuing"
            message = "Completed jobs are retained. Review the items that need attention before retrying."
        } else {
            title = "Ready for your review"
            message = "These are saved recipes. Source and destination checks still apply."
        }
    }
}
