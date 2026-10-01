import SwiftUI

struct QueueEditor: View {
    @EnvironmentObject private var model: WorkspaceModel
    @EnvironmentObject private var batch: BatchController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: QueueJob
    @State private var showingTracks = false
    @State private var stem: String

    init(job: QueueJob) {
        _draft = State(initialValue: job)
        _stem = State(initialValue: URL(fileURLWithPath: job.destination).deletingPathExtension().lastPathComponent)
    }

    private var destination: String {
        URL(fileURLWithPath: draft.destination).deletingLastPathComponent()
            .appendingPathComponent(stem.trimmingCharacters(in: .whitespacesAndNewlines) + "." + draft.configuration.container.lowercased()).path
    }
    private var issue: String? {
        do { try SessionDocument.validate(draft.configuration) }
        catch { return error.localizedDescription }
        return WorkspaceModel.filenameIssue(stem) ?? model.destinationIssue(destination, source: draft.isDemo ? nil : draft.source, excluding: draft.id)
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Edit configuration", subtitle: URL(fileURLWithPath: draft.source).lastPathComponent)
            if !draft.isDemo { Button("Choose source tracks…") { showingTracks = true } }
            Divider()
            HStack(spacing: 16) {
                settingPicker("Codec", selection: Binding(get: { draft.configuration.codec }, set: { value in
                    var next = draft.configuration
                    next.selectCodec(value)
                    draft.configuration = next
                }), values: ["AV1", "HEVC", "H.264", "Copy original"])
                settingPicker("Container", selection: $draft.configuration.container, values: ["MKV", "MP4"])
            }
            VideoRateOptionsView(configuration: $draft.configuration)
            if !draft.configuration.copiesVideo && draft.configuration.rate.mode == "Constant quality" {
            HStack {
                Text("Constant quality")
                Slider(value: $draft.configuration.quality, in: 0...51, step: 1)
                    .accessibilityLabel("Queue constant rate factor")
                Text("CRF \(Int(draft.configuration.quality))").monospacedDigit().frame(width: 60)
            }.font(.system(size: 12))
            }
            HStack(spacing: 16) {
                if !draft.configuration.copiesVideo {
                    settingPicker("Speed preference", selection: $draft.configuration.speed, values: ["Thorough", "Balanced", "Fast"]).disabled(draft.configuration.rate.backend != "Software")
                }
                settingPicker("Output size", selection: $draft.configuration.resolution, values: ["Original", "1920 × 1080", "1280 × 720"])
            }
            HStack(spacing: 16) {
                Stepper("Top crop: \(draft.configuration.cropTop) px", value: $draft.configuration.cropTop, in: 0...240, step: 2)
                Stepper("Bottom: \(draft.configuration.cropBottom) px", value: $draft.configuration.cropBottom, in: 0...240, step: 2)
            }.font(.system(size: 12))
            PictureOptionsView(options: $draft.configuration.picture)
            HStack(spacing: 16) {
                settingPicker("Audio", selection: $draft.configuration.audio, values: ["AAC", "Opus", "Copy original", "No audio"])
                settingPicker("Bitrate", selection: $draft.configuration.audioBitrate, values: ["128 kb/s", "192 kb/s", "256 kb/s", "320 kb/s"])
                    .disabled(!["AAC", "Opus"].contains(draft.configuration.audio))
            }
            SubtitleOptionsView(configuration: $draft.configuration, sourceAvailable: !draft.isDemo)
            Divider()
            ChapterOptionsView(configuration: $draft.configuration, source: draft.isDemo ? nil : URL(fileURLWithPath: draft.source))
            VStack(alignment: .leading, spacing: 8) {
                eyebrow("Output name")
                HStack {
                    TextField("File name", text: $stem).textFieldStyle(.roundedBorder).accessibilityLabel("Queue output name")
                    Text("." + draft.configuration.container.lowercased()).foregroundStyle(.secondary)
                }
                Text(URL(fileURLWithPath: draft.destination).deletingLastPathComponent().path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let issue { Text(issue).font(.caption).foregroundStyle(Color.warning) }
            }
            Divider()
            HStack {
                Text("Changes apply only to this queue item.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save changes") {
                    draft.destination = destination
                    model.updateJob(draft)
                    batch.reset(draft.id)
                    dismiss()
                }.keyboardShortcut(.defaultAction).primaryAction().disabled(issue != nil)
            }
        }.padding(28)
        }.frame(width: 600, height: 720)
        .sheet(isPresented: $showingTracks) {
            TrackRoutingView(source: URL(fileURLWithPath: draft.source), configuration: $draft.configuration)
        }
    }
}
