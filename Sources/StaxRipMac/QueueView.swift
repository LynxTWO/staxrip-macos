import SwiftUI

struct QueueView: View {
    @EnvironmentObject var model: WorkspaceModel
    @EnvironmentObject var audio: AudioController
    @EnvironmentObject var batch: BatchController
    @EnvironmentObject var exporter: ExportController
    @StateObject private var fileAccess = QueueFileAccess()
    @State private var editingJob: QueueJob?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                sectionTitle("Ready when you are", subtitle: "Saved configurations for this session.")
                Spacer()
                if batch.reviewing {
                    Button("Cancel check", role: .cancel) { batch.cancelReview() }
                } else {
                    Button("Check queue") { batch.review(model.jobs) }
                        .disabled(model.jobs.isEmpty || batch.tools == nil || batch.running || exporter.running || audio.running)
                        .help("Read source metadata and check settings and destinations without encoding or writing files.")
                }
                if batch.running {
                    Button(batch.publicationJobID == nil ? "Cancel batch" : "Stop after current publication", role: .cancel) { batch.cancel() }
                        .help(batch.publicationJobID == nil ? "Cancel the current job and stop the batch." : "Wait for this publication to finish, preserve any successful output, and stop before the next job.")
                } else {
                    Button { batch.start(model.jobs) } label: { Label("Start queue", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).disabled(model.jobs.isEmpty || batch.tools == nil || batch.reviewing || exporter.running || audio.running)
                }
                Button { model.exportQueue() } label: { Label("Export JSON…", systemImage: "square.and.arrow.up") }
                    .disabled(model.jobs.isEmpty)
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
                        Text("Previous batch available · \(recovery.jobs.count) jobs").font(.headline)
                        Text("Restore into an empty queue to review it. Nothing starts automatically. Starting a new batch replaces this recovery record.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore previous queue") {
                        if let jobs = batch.restoreQueue() { model.jobs = jobs }
                    }.disabled(!model.jobs.isEmpty || batch.running || exporter.running || audio.running)
                }.padding(16).background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if let error = batch.recoveryError { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
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
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    Text(String((model.jobs.firstIndex(where: { $0.id == job.id }) ?? 0) + 1))
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.accent).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(URL(fileURLWithPath: job.source).lastPathComponent).font(.system(size: 14, weight: .semibold))
                                        if let captions = job.configuration.externalSubtitle {
                                            Text("Additional captions: " + URL(fileURLWithPath: captions.path).lastPathComponent)
                                                .font(.caption).foregroundStyle(.secondary)
                                                .accessibilityLabel("Additional SubRip subtitle file, " + URL(fileURLWithPath: captions.path).lastPathComponent)
                                        }
                                        Text("\(job.configuration.codec) · \(job.configuration.rateSummary) · \(job.configuration.container) · \(job.configuration.colorMode) · \(job.configuration.audio)")
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(job.isDemo ? "DEMO" : (batch.publicationJobID == job.id ? "Finishing" : (batch.statuses[job.id]?.phase ?? "Ready")).uppercased())
                                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                    Button { batch.reset(job.id); model.jobs.removeAll { $0.id == job.id } } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless).disabled(batch.running || audio.running).help("Remove configuration").accessibilityLabel("Remove queued configuration for \(URL(fileURLWithPath: job.source).lastPathComponent)")
                                        .accessibilityHint("Removes this queue entry. Does not delete the source file.")
                                }
                                HStack(spacing: 14) {
                                    Button { editingJob = job } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                                    Button { model.duplicateJob(job) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                    Spacer()
                                    Button { model.moveJob(job.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                        .disabled(model.jobs.first?.id == job.id).help("Move up").accessibilityLabel("Move \(URL(fileURLWithPath: job.source).lastPathComponent) earlier in the queue")
                                    Button { model.moveJob(job.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                        .disabled(model.jobs.last?.id == job.id).help("Move down").accessibilityLabel("Move \(URL(fileURLWithPath: job.source).lastPathComponent) later in the queue")
                                }.buttonStyle(.borderless).font(.system(size: 11)).disabled(batch.running || audio.running)
                                HStack {
                                    Button("Review source access…") { fileAccess.review(job, destination: false) }
                                    Button("Review destination access…") { fileAccess.review(job, destination: true) }
                                }.font(.caption).disabled(fileAccess.reviewing || job.isDemo)
                                    .help("Select the configured location using the native file picker. Queue paths stay unchanged and no encode starts.")
                                if let result = fileAccess.result, result.jobID == job.id {
                                    Text(result.message).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if batch.reviewMatches(model.jobs), let check = batch.queueChecks[job.id] {
                                    Text(check.kind.rawValue + ": " + check.detail)
                                        .font(.caption).foregroundStyle(check.kind == .issue ? .orange : .secondary)
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                        .accessibilityLabel("Queue check: " + AccessibilityLanguage.spokenCodecs(check.kind.rawValue + ". " + check.detail))
                                }
                                if let state = batch.statuses[job.id] {
                                    if batch.publicationJobID != job.id && (state.phase == "Encoding" || (job.configuration.colorMode == "Preserve static HDR10" && ["Inspecting", "Verifying"].contains(state.phase))) {
                                        ProgressView(value: state.progress)
                                            .accessibilityLabel(state.phase == "Encoding" ? "Encoding progress" : "H D R ten full frame audit progress")
                                    }
                                    Text(state.detail).accessibilityLabel(AccessibilityLanguage.spokenCodecs(state.detail)).font(.system(size: 10)).foregroundStyle(state.phase == "Failed" ? .orange : .secondary).textSelection(.enabled)
                                    if let result = state.destination {
                                        Button("Reveal output") { NSWorkspace.shared.activateFileViewerSelecting([result]) }.font(.caption)
                                    }
                                }
                                Divider()
                                Label(job.destination, systemImage: "folder").font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                            }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
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
}
