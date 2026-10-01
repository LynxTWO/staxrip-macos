import SwiftUI

struct QueueView: View {
    @EnvironmentObject var model: WorkspaceModel
    @EnvironmentObject var audio: AudioController
    @EnvironmentObject var batch: BatchController
    @EnvironmentObject var exporter: ExportController
    @StateObject private var fileAccess = QueueFileAccess()
    @State private var editingJob: QueueJob?
    private var checks: [UUID: QueueCheck] { batch.reviewMatches(model.jobs) ? batch.queueChecks : [:] }
    private var overview: QueueOverview {
        QueueOverview(jobs: model.jobs, statuses: batch.statuses, running: batch.running, reviewing: batch.reviewing,
                      publicationJobID: batch.publicationJobID, checks: checks)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle(overview.title, subtitle: overview.message)
                .accessibilityElement(children: .combine)
            HStack(spacing: 16) {
                outcomeCount(overview.completed, title: "Completed", symbol: "checkmark.circle", color: .secondary)
                outcomeCount(overview.remaining, title: "Remaining", symbol: "clock", color: .secondary)
                if overview.attention > 0 { outcomeCount(overview.attention, title: overview.attention == 1 ? "Needs attention" : "Need attention", symbol: "exclamationmark.triangle", color: .warning) }
                Spacer()
                if batch.reviewing {
                    Button("Cancel check", role: .cancel) { batch.cancelReview() }
                } else {
                    Button("Check queue") { batch.review(model.jobs) }
                        .disabled(model.jobs.isEmpty || batch.tools == nil || batch.running || exporter.running || audio.running || model.filePanelActive || fileAccess.reviewing)
                        .help("Read source metadata and check settings and destinations without encoding or writing files.")
                }
                if batch.running {
                    Button(batch.publicationJobID == nil ? "Cancel batch" : "Stop after current publication", role: .cancel) { batch.cancel() }
                        .help(batch.publicationJobID == nil ? "Cancel the current job and stop the batch. An active source content check waits for filesystem reads to return before cleanup." : "Wait for this publication to finish, preserve any successful output, and stop before the next job.")
                } else {
                    Button { model.chooseQueueStart(using: batch) { !exporter.running && !audio.running && !fileAccess.reviewing } } label: { Label("Start queue…", systemImage: "play.fill") }
                        .primaryAction().disabled(batch.pendingJobs(in: model.jobs).isEmpty || batch.tools == nil || batch.reviewing || exporter.running || audio.running || model.filePanelActive || fileAccess.reviewing)
                        .help("Review each configured output folder before starting. Cancel starts nothing. Each job then performs independent checks, including reading its source in full before inspection and publication.")
                }
                Button { model.exportQueue() } label: { Label("Export JSON…", systemImage: "square.and.arrow.up") }
                    .disabled(model.jobs.isEmpty || model.filePanelActive || fileAccess.reviewing)
            }
            Text(batch.toolDescription).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
            if !batch.reviewStatus.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(batch.reviewStatus).font(.callout).accessibilityLabel("Queue check status").accessibilityValue(batch.reviewStatus)
                    if let date = batch.reviewDate, batch.reviewMatches(model.jobs) { Text("Checked at " + date.formatted(date: .omitted, time: .standard)).font(.caption) }
                    Text("Read-only snapshot. Files and available resources can change; Start queue performs independent checks. No disk-space, hardware or full HDR guarantee.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let recovery = batch.recovery {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Previous batch available · \(recovery.jobs.count) \(recovery.jobs.count == 1 ? "job" : "jobs")").font(.headline)
                        Text("Restore into an empty queue to review it. Nothing starts automatically. Starting a new batch replaces this recovery record.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore previous queue") {
                        if let jobs = batch.restoreQueue() { model.jobs = jobs }
                    }.disabled(!model.jobs.isEmpty || batch.running || exporter.running || audio.running || model.filePanelActive || fileAccess.reviewing)
                }.padding(16).background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if let error = batch.recoveryError { Text(error).font(.caption).foregroundStyle(Color.warning).textSelection(.enabled) }
            if model.jobs.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Color.accent)
                    Text("A little preparation. A better encode.").font(.title3.weight(.medium))
                    Text("Set up a source in the workspace, then add its configuration here.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Go to workspace") { model.section = "Workspace" }.controlSize(.large)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.jobs) { job in
                            QueueJobRow(job: job, index: (model.jobs.firstIndex(where: { $0.id == job.id }) ?? 0) + 1,
                                        check: checks[job.id], fileAccess: fileAccess, edit: { editingJob = job })
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                Text("This is a GUI prototype. Jobs run sequentially; the batch stops on failure or a temporary-file cleanup warning. Completed outputs are never replaced. The last started batch is saved locally for explicit recovery after a restart. Use Session → Save session to keep and reopen your workspace and queue. Export JSON creates a queue-only reference file. Neither format is a Windows StaxRip project file.")
            }.font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }.padding(28)
        .onAppear { if !batch.reviewMatches(model.jobs) { batch.invalidateReview() } }
        .sheet(item: $editingJob) { job in QueueEditor(job: job).environmentObject(model) }
    }
    private func outcomeCount(_ count: Int, title: String, symbol: String, color: Color) -> some View {
        Label { Text("\(count)").monospacedDigit().fontWeight(.semibold) + Text(" " + title) } icon: { Image(systemName: symbol) }
            .font(.caption).foregroundStyle(color)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isStaticText)
            .accessibilityLabel("\(count) \(title.lowercased())")
    }

}


private struct QueueJobRow: View {
    @EnvironmentObject var model: WorkspaceModel
    @EnvironmentObject var audio: AudioController
    @EnvironmentObject var batch: BatchController
    let job: QueueJob
    let index: Int
    let check: QueueCheck?
    @ObservedObject var fileAccess: QueueFileAccess
    let edit: () -> Void
    @State private var expanded = false
    private var state: BatchStatus? { batch.statuses[job.id] }
    private var publishing: Bool { batch.publicationJobID == job.id }
    private var presentation: QueueJobPresentation { QueueJobPresentation(job: job, status: state, publishing: publishing, check: check) }
    private var locked: Bool { batch.running || audio.running || model.filePanelActive || fileAccess.reviewing }
    private var sourceName: String { URL(fileURLWithPath: job.source).lastPathComponent }
    private var outputName: String { URL(fileURLWithPath: job.destination).lastPathComponent }
    private var recipe: String { "\(job.configuration.codec) · \(job.configuration.rateSummary) · \(job.configuration.container) · \(job.configuration.colorMode) · \(job.configuration.audio)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(index)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 26, height: 26).background(Color.accent.opacity(0.08), in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(outputName).font(.headline).textSelection(.enabled)
                    Text("From " + sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(job.source)
                    Text(recipe).font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel(AccessibilityLanguage.spokenCodecs(recipe))
                    ForEach(Array(job.configuration.externalCaptions.enumerated()), id: \.offset) { captionIndex, captions in
                        Text("Caption \(captionIndex + 1) (\(captions.language)): " + URL(fileURLWithPath: captions.path).lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Additional SubRip subtitle track \(captionIndex + 1), \(captions.language), " + URL(fileURLWithPath: captions.path).lastPathComponent)
                    }
                }
                Spacer(minLength: 8)
                Label(presentation.label, systemImage: presentation.symbol).font(.caption.weight(.medium))
                    .foregroundStyle(presentation.needsAttention ? Color.warning : (presentation.completed ? Color.accent : Color.secondary))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background((presentation.needsAttention ? Color.warning : Color.accent).opacity(0.08), in: Capsule())
                    .accessibilityLabel("Job \(index), \(presentation.label)")
            }
            if let state, presentation.showStatusDetail, !state.detail.isEmpty {
                statusDetail(state)
            }
            if let state, !publishing && (state.phase == "Encoding" || (job.configuration.colorMode == "Preserve static HDR10" && ["Inspecting", "Verifying"].contains(state.phase))) {
                ProgressView(value: state.progress)
                    .accessibilityLabel(state.phase == "Encoding" ? "Encoding progress" : "H D R ten full frame audit progress")
            }
            if let check, check.kind == .issue { checkDetail(check) }
            HStack(spacing: 14) {
                if let destination = state?.destination {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([destination]) } label: { Label("Reveal output", systemImage: "arrow.up.forward.square") }
                        .help("Reveal the recorded output in Finder.").accessibilityLabel("Reveal output \(outputName)")
                }
                Button(action: edit) { Label("Edit", systemImage: "slider.horizontal.3") }.disabled(locked)
                    .accessibilityLabel("Edit settings for \(outputName)")
                Button { model.duplicateJob(job) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.disabled(locked)
                    .accessibilityLabel("Duplicate configuration for \(outputName)")
                Spacer()
                Button { model.moveJob(job.id, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(locked || model.jobs.first?.id == job.id).help("Move up")
                    .accessibilityLabel("Move \(outputName) earlier in the queue")
                Button { model.moveJob(job.id, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(locked || model.jobs.last?.id == job.id).help("Move down")
                    .accessibilityLabel("Move \(outputName) later in the queue")
                Button { batch.reset(job.id); model.jobs.removeAll { $0.id == job.id } } label: { Image(systemName: "trash") }
                    .disabled(locked).help("Remove configuration")
                    .accessibilityLabel("Remove queued configuration for \(outputName)")
                    .accessibilityHint("Removes this queue entry. Does not delete source media or saved outputs.")
            }.buttonStyle(.borderless).font(.caption)
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 9) {
                    if let state, !presentation.showStatusDetail, !state.detail.isEmpty { statusDetail(state) }
                    if let check, check.kind != .issue { checkDetail(check) }
                    filePath("Source", path: job.source)
                    filePath("Destination", path: job.destination)
                    HStack {
                        Button("Review source access…") { fileAccess.review(job, destination: false) }
                            .accessibilityLabel("Review source access for \(outputName)")
                        Button("Review destination access…") { fileAccess.review(job, destination: true) }
                            .accessibilityLabel("Review destination access for \(outputName)")
                    }.disabled(fileAccess.reviewing || model.filePanelActive || job.isDemo)
                        .help("Select the configured location using the native file picker. Queue paths stay unchanged and no encode starts.")
                }.padding(.top, 7)
            } label: {
                Text(presentation.completed ? "Verification and file details" : "Checks and file details")
                    .accessibilityLabel("\(presentation.completed ? "Verification" : "Checks") and file details for \(outputName)")
            }.font(.caption)
            if let result = fileAccess.result, result.jobID == job.id {
                Text(result.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
    private func statusDetail(_ state: BatchStatus) -> some View {
        Text(state.detail).font(.caption).foregroundStyle(presentation.needsAttention ? Color.warning : Color.secondary)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(AccessibilityLanguage.spokenCodecs(state.detail))
    }
    private func checkDetail(_ check: QueueCheck) -> some View {
        Text(check.kind.rawValue + ": " + check.detail).font(.caption)
            .foregroundStyle(check.kind == .issue ? Color.warning : Color.secondary)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Queue check: " + AccessibilityLanguage.spokenCodecs(check.kind.rawValue + ". " + check.detail))
    }
    private func filePath(_ label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).fontWeight(.medium)
            Text(path).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
