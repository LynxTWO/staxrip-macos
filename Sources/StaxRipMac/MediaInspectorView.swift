import SwiftUI

struct MediaInspectorView: View {
    @EnvironmentObject var batch: BatchController
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    let source: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("Inside the source", subtitle: source.lastPathComponent)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if batch.inspecting { ProgressView("Reading media contents…").frame(maxWidth: .infinity, minHeight: 180) }
            if let error = batch.inspectionError { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if let probe = batch.inspection {
                HStack(spacing: 24) {
                    stat("CONTAINER", ContainerInspection.text(probe.format?.format_name, fallback: "Unknown"))
                    stat("DURATION", ContainerInspection.timestamp(probe.format?.duration))
                    stat("STREAMS", String(probe.streams.count))
                }
                Picker("Media content section", selection: $section) {
                    Text("Tracks (\(ContainerInspection.tracks(probe).count))").tag(0)
                    Text("Chapters (\(probe.chapters?.count ?? 0))").tag(1)
                    Text("Attachments (\(ContainerInspection.attachmentStreams(probe).count))").tag(2)
                }.pickerStyle(.segmented).labelsHidden()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if section == 0 {
                            let streams = ContainerInspection.tracks(probe)
                            if streams.isEmpty { empty("No media tracks reported.") }
                            limitNotice(streams.count)
                            ForEach(Array(streams.prefix(ContainerInspection.rowLimit).enumerated()), id: \.offset) { item in track(item.element) }
                        } else if section == 1 {
                            if (probe.chapters ?? []).isEmpty { empty("No chapters reported by the source.") }
                            limitNotice(probe.chapters?.count ?? 0)
                            ForEach(ContainerInspection.chapters(probe)) { chapter in
                                card {
                                    Text("Chapter \(chapter.id + 1) · \(chapter.title)").font(.headline).accessibilityAddTraits(.isHeader)
                                    field("Reported start", value: chapter.start, help: "Chapter start reported by the container, shown as hours, minutes, seconds and milliseconds. This is not a verified frame position.")
                                    field("Reported end", value: chapter.end, help: "Chapter end reported by the container. No timing correction is applied.")
                                    field("Source identifier", value: chapter.identifier, help: "The reported chapter identifier, which may differ from its position in this list.")
                                    field("Time base", value: chapter.timeBase, help: "The reported seconds per chapter timestamp tick.")
                                    if let note = chapter.note { Text(note).foregroundStyle(.orange).textSelection(.enabled) }
                                }
                            }
                        } else {
                            let attachments = ContainerInspection.attachmentStreams(probe)
                            if attachments.isEmpty { empty("No embedded files or cover artwork reported.") }
                            limitNotice(attachments.count)
                            ForEach(ContainerInspection.attachments(probe)) { item in
                                card {
                                    Label("\(item.kind) · stream \(item.streamIndex)", systemImage: item.kind == "Cover artwork" ? "photo" : "paperclip")
                                        .font(.headline).accessibilityAddTraits(.isHeader)
                                    field("Reported filename", value: item.filename, help: "A label from the source metadata, not a local file path. This inspector does not extract or open attachments.")
                                    field("Declared file type", value: item.mimeType, help: "The source's MIME type label. The embedded payload has not been verified.")
                                    field("Reported codec", value: item.codec, help: "Codec reported by the probe, when available. Cover artwork is not selected as the main movie video.")
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 340).id(section)
                Text("Reported metadata only. Chapter positions and attachment contents are not verified. Long labels are shortened and control characters are replaced for display. Nothing is extracted or opened.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if section == 0 {
                    Text("Source tags do not verify HDR preservation or frame-by-frame timing. Missing color tags do not prove SDR. Preserve static HDR10 requires its separate full-frame source and output audits; HLG remains unsupported.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("The advanced plan encodes the first non-cover-art video. Choose tracks selects audio and subtitles. Inspecting chapters and attachments does not guarantee their preservation in an output.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(26).frame(width: 690).task(id: source) { await batch.inspect(source) }
    }
    private func track(_ stream: MediaProbe.Stream) -> some View {
        card {
            HStack {
                Image(systemName: stream.codec_type == "video" ? "film" : stream.codec_type == "audio" ? "waveform" : "text.bubble").foregroundStyle(Color.accent)
                Text("Track \(stream.index) · \(ContainerInspection.text(stream.codec_type, fallback: "unknown"))").font(.headline)
                Spacer()
                Text(ContainerInspection.text(stream.codec_name, fallback: "unknown")).monospaced()
            }
            if let width = stream.width, let height = stream.height { Text("\(width) × \(height) · \(ContainerInspection.text(stream.pix_fmt, fallback: "unknown pixel format"))") }
            if let channels = stream.channels { Text("\(channels) channels · \(ContainerInspection.text(stream.channel_layout, fallback: "layout unspecified")) · \(ContainerInspection.text(stream.sample_rate, fallback: "?")) Hz") }
            if stream.codec_type == "video" {
                details("Picture format", rows: VideoInspection.picture(stream))
                details("Declared color", rows: VideoInspection.color(stream))
                details("Timing and geometry", rows: VideoInspection.timing(stream))
            }
            if let language = stream.tags?["language"] { Text("Language: \(ContainerInspection.text(language))") }
        }
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).font(.system(size: 12)).padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
    private func empty(_ message: String) -> some View { Text(message).foregroundStyle(.secondary).padding(.vertical, 24) }
    @ViewBuilder private func limitNotice(_ total: Int) -> some View {
        if let notice = ContainerInspection.limitNotice(total) { Text(notice).font(.caption).foregroundStyle(.secondary) }
    }
    private func field(_ label: String, value: String, help: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 165, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value).accessibilityHint(help).help(help)
    }
    private func details(_ title: String, rows: [VideoInspection.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in field(row.label, value: ContainerInspection.text(row.value), help: row.help) }
        }.padding(.top, 6)
    }
    private func stat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { eyebrow(name); Text(value).font(.system(size: 12, weight: .medium)) }
    }
}
