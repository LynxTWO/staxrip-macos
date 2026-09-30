import SwiftUI

struct MediaInspectorView: View {
    @EnvironmentObject var batch: BatchController
    @Environment(\.dismiss) private var dismiss
    let source: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                sectionTitle("Inside the source", subtitle: source.lastPathComponent)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if batch.inspecting { ProgressView("Reading media tracks…").frame(maxWidth: .infinity, minHeight: 180) }
            if let error = batch.inspectionError { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if let probe = batch.inspection {
                HStack(spacing: 24) {
                    stat("CONTAINER", probe.format?.format_name ?? "Unknown")
                    stat("DURATION", String(format: "%.2f seconds", probe.seconds))
                    stat("TRACKS", String(probe.streams.count))
                }
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(probe.streams) { stream in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: stream.codec_type == "video" ? "film" : stream.codec_type == "audio" ? "waveform" : "text.bubble")
                                        .foregroundStyle(Color.accent)
                                    Text("Track \(stream.index) · \(stream.codec_type ?? "unknown")").font(.headline)
                                    Spacer()
                                    Text(stream.codec_name ?? "unknown").monospaced()
                                }
                                if let width = stream.width, let height = stream.height {
                                    Text("\(width) × \(height) · \(stream.pix_fmt ?? "unknown pixel format")")
                                }
                                if let channels = stream.channels {
                                    Text("\(channels) channels · \(stream.channel_layout ?? "layout unspecified") · \(stream.sample_rate ?? "?") Hz")
                                }
                                if stream.codec_type == "video" {
                                    details("Picture format", rows: VideoInspection.picture(stream))
                                    details("Declared color", rows: VideoInspection.color(stream))
                                    details("Timing and geometry", rows: VideoInspection.timing(stream))
                                }
                                if let language = stream.tags?["language"] { Text("Language: \(language)") }
                            }.font(.system(size: 12)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.frame(height: 340)
                Text("Source tags do not verify HDR preservation or frame-by-frame timing. Missing color tags do not prove SDR. Advanced encoding defaults to 8-bit SDR. Preserve static HDR10 requires its separate full-frame source and output audits; HLG remains unsupported. Quick Export follows Apple’s presets.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("The advanced plan encodes the first non-cover-art video. Use Choose tracks in Workspace or the queue editor to select audio and subtitle streams.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(26).frame(width: 690).task { await batch.inspect(source) }
    }
    private func details(_ title: String, rows: [VideoInspection.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 12) {
                    Text(row.label).foregroundStyle(.secondary).frame(width: 165, alignment: .leading)
                    Text(row.value).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.label)
                .accessibilityValue(row.value)
                .accessibilityHint(row.help)
                .help(row.help)
            }
        }.padding(.top, 6)
    }
    private func stat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { eyebrow(name); Text(value).font(.system(size: 12, weight: .medium)) }
    }
}
