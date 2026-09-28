import SwiftUI

struct TrackRoutingView: View {
    let source: URL
    @Binding var configuration: EncodeConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var probe: MediaProbe?
    @State private var error: String?
    @State private var audio: [Int]?
    @State private var subtitles: [Int]?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Choose your tracks", subtitle: source.lastPathComponent)
            Text("Choose the languages and tracks to carry into this encode. Audio codec and subtitle handling settings still apply. Video uses the first non-cover-art track.")
                .font(.caption).foregroundStyle(.secondary)
            if let probe {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        tracks("Audio", type: "audio", probe: probe, selection: $audio)
                        Divider()
                        tracks("Subtitles", type: "subtitle", probe: probe, selection: $subtitles)
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(.orange).textSelection(.enabled)
            } else { ProgressView("Reading source tracks…") }
            Spacer(minLength: 0)
            Text("Importing a new source resets track selection to All. Saved sessions and queue copies preserve it. Missing selected tracks fail preflight.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply selection") {
                    configuration.audioTracks = audio
                    configuration.subtitleTracks = subtitles
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(probe == nil)
            }
        }.padding(26).frame(width: 620, height: 560)
        .task {
            audio = configuration.audioTracks; subtitles = configuration.subtitleTracks
            guard let tools = FFmpegTools.discover() else { error = "Install FFmpeg to inspect and select tracks."; return }
            do { probe = try await MediaProbe.read(source, tools: tools) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func tracks(_ title: String, type: String, probe: MediaProbe, selection: Binding<[Int]?>) -> some View {
        let streams = probe.streams.filter { $0.codec_type == type }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("All") { selection.wrappedValue = nil }.accessibilityLabel("All \(title) tracks")
                Button("None") { selection.wrappedValue = [] }.accessibilityLabel("No \(title) tracks")
            }
            if streams.isEmpty { Text("No \(type) tracks found.").foregroundStyle(.secondary) }
            ForEach(streams) { stream in
                Toggle(isOn: Binding(get: { selection.wrappedValue?.contains(stream.index) ?? true }, set: { selected in
                    var indices = selection.wrappedValue ?? streams.map(\.index)
                    indices.removeAll { $0 == stream.index }
                    if selected { indices.append(stream.index) }
                    selection.wrappedValue = indices.sorted()
                })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("#\(stream.index) · \(stream.tags?["language"] ?? "und") · \(stream.codec_name ?? "unknown")")
                        if let title = stream.tags?["title"] { Text(title).font(.caption).foregroundStyle(.secondary) }
                        if let channels = stream.channels { Text("\(channels) channels · \(stream.channel_layout ?? "unspecified layout")").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if let indices = selection.wrappedValue {
                let missing = indices.filter { index in !streams.contains { $0.index == index } }
                if !missing.isEmpty { Text("Missing selections: \(missing.map(String.init).joined(separator: ", ")). Choose All or None to reset.").foregroundStyle(.orange) }
            }
        }
    }
}
