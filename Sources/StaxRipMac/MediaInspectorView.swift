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
                                if let transfer = stream.color_transfer { Text("Transfer: \(transfer)") }
                                if let language = stream.tags?["language"] { Text("Language: \(language)") }
                            }.font(.system(size: 12)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.frame(maxHeight: 380)
                Text("The current advanced plan encodes the first non-cover-art video and all selected audio/subtitle categories. Track-by-track routing is a future extension.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(26).frame(width: 610).task { await batch.inspect(source) }
    }
    private func stat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { eyebrow(name); Text(value).font(.system(size: 12, weight: .medium)) }
    }
}
