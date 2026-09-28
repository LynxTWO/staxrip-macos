import SwiftUI

struct QueueView: View {
    @EnvironmentObject var model: WorkspaceModel
    @State private var editingJob: QueueJob?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                sectionTitle("Ready when you are", subtitle: "Saved configurations for this session.")
                Spacer()
                Button { model.exportQueue() } label: { Label("Export JSON…", systemImage: "square.and.arrow.up") }
                    .disabled(model.jobs.isEmpty)
            }
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
                                        Text("\(job.configuration.codec) · CRF \(Int(job.configuration.quality)) · \(job.configuration.container) · \(job.configuration.audio)")
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(job.isDemo ? "DEMO CONFIGURATION" : "CONFIGURATION ONLY")
                                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                    Button { model.jobs.removeAll { $0.id == job.id } } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless).help("Remove configuration").accessibilityLabel("Remove \(URL(fileURLWithPath: job.source).lastPathComponent)")
                                }
                                HStack(spacing: 14) {
                                    Button { editingJob = job } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                                    Button { model.duplicateJob(job) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                    Spacer()
                                    Button { model.moveJob(job.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                        .disabled(model.jobs.first?.id == job.id).help("Move up").accessibilityLabel("Move up")
                                    Button { model.moveJob(job.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                        .disabled(model.jobs.last?.id == job.id).help("Move down").accessibilityLabel("Move down")
                                }.buttonStyle(.borderless).font(.system(size: 11))
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
                Text("This is a GUI prototype. Advanced queue jobs do not run yet. Use Session → Save session to keep and reopen your workspace and queue. Export JSON creates a queue-only reference file. Neither format is a Windows StaxRip project file.")
            }.font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }.padding(28)
        .sheet(item: $editingJob) { job in QueueEditor(job: job).environmentObject(model) }
    }
}
