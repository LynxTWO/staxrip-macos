import SwiftUI
import UniformTypeIdentifiers

struct AudioLabView: View {
    @EnvironmentObject var audio: AudioController
    @EnvironmentObject var batch: BatchController
    @EnvironmentObject var exporter: ExportController
    private var busy: Bool { audio.running || batch.running || exporter.running }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        eyebrow("A LITTLE ROOM FOR SOUND")
                        Text("Every track deserves its own stage.").font(.system(size: 27, weight: .semibold, design: .rounded))
                        Text("Extract, measure and encode one track at a time.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "waveform.circle.fill").font(.system(size: 64)).foregroundStyle(Color.accent)
                }
                HStack {
                    Image(systemName: "waveform").foregroundStyle(Color.accent)
                    Text(audio.source?.lastPathComponent ?? "No audio source selected").font(.headline)
                    Spacer()
                    Button("Open audio or video…") { chooseSource() }.disabled(busy || batch.tools == nil)
                }.padding(20).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                if batch.tools == nil { Text(batch.toolDescription).font(.caption).foregroundStyle(.orange) }
                if !audio.tracks.isEmpty {
                    GroupBox("Source track") {
                        Picker("Track", selection: $audio.track) {
                            ForEach(audio.tracks) { track in
                                Text("#\(track.index) · \(track.codec_name ?? "unknown") · \(track.channels ?? 0) ch · \(track.sample_rate ?? "?") Hz · \(track.tags?["language"] ?? "und")").tag(track.index)
                            }
                        }.padding(12).disabled(busy)
                        .onChange(of: audio.track) { _, _ in audio.report = nil }
                    }
                    HStack(alignment: .top, spacing: 20) {
                        GroupBox("Output recipe") {
                            VStack(spacing: 16) {
                                Picker("Format", selection: $audio.settings.format) { ForEach(["FLAC", "WAV", "AAC", "Opus"], id: \.self) { Text($0) } }
                                Picker("Sample rate", selection: $audio.settings.sampleRate) {
                                    if audio.settings.format != "Opus" { Text("44.1 kHz").tag(44100); Text("96 kHz").tag(96000) }
                                    Text("48 kHz").tag(48000)
                                }
                                Picker("Channels", selection: $audio.settings.channels) { Text("Keep source").tag(0); Text("Mono").tag(1); Text("Stereo").tag(2) }
                                if ["AAC", "Opus"].contains(audio.settings.format) {
                                    Picker("Bitrate", selection: $audio.settings.bitrate) { ForEach([128, 192, 256, 320], id: \.self) { Text("\($0) kb/s").tag($0) } }
                                } else { Text("24-bit integer output · resampled to the chosen rate").font(.caption).foregroundStyle(.secondary) }
                            }.padding(14).disabled(busy)
                            .onChange(of: audio.settings.format) { _, format in if format == "Opus" { audio.settings.sampleRate = 48000 } }
                        }.frame(maxWidth: .infinity)
                        GroupBox("Listen with numbers") {
                            VStack(alignment: .leading, spacing: 15) {
                                if let report = audio.report {
                                    metric("Integrated", report.input_i + " LUFS")
                                    metric("True peak", report.input_tp + " dBTP")
                                    metric("Loudness range", report.input_lra + " LU")
                                } else { Text("Measure the complete selected source track. Silent or very short material may have no finite integrated value.").font(.callout).foregroundStyle(.secondary) }
                                Button("Analyze loudness") { if let tools = batch.tools { audio.analyze(tools: tools) } }.disabled(busy)
                                Text("Measurement only; no normalization applied. Mono is measured as mono.").font(.caption).foregroundStyle(.secondary)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxWidth: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    if audio.running { ProgressView(value: audio.progress) }
                    Text(audio.status).font(.callout).textSelection(.enabled)
                    HStack {
                        if audio.running { Button("Cancel audio operation", role: .cancel) { audio.cancel() } }
                        if let output = audio.output { Button("Reveal audio output") { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
                        Spacer()
                        Button("Export audio…") { chooseDestination() }.buttonStyle(.borderedProminent).disabled(busy || audio.source == nil || batch.tools == nil)
                    }
                }.padding(20).background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                Text("Audio Lab has its own source and settings; these are not saved in video sessions. Exports support mono and stereo sources. Channel conversion uses FFmpeg’s default mix; artwork, chapters and source tags are omitted. FLAC/WAV avoid further lossy coding, but cannot restore detail lost in a source. Existing files are never replaced.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(30)
        }
    }
    private func metric(_ name: String, _ value: String) -> some View { HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().fontWeight(.semibold) } }
    private func chooseSource() {
        guard let tools = batch.tools else { return }
        let panel = NSOpenPanel(); panel.title = "Open audio or video for Audio Lab"; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { audio.load(url, tools: tools) }
    }
    private func chooseDestination() {
        guard let tools = batch.tools, let source = audio.source else { return }
        let panel = NSSavePanel(); panel.title = "Export selected audio track"
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "_track\(audio.track)." + audio.settings.fileExtension
        panel.allowedContentTypes = [UTType(filenameExtension: audio.settings.fileExtension) ?? .data]
        if panel.runModal() == .OK, let url = panel.url { audio.export(to: url, tools: tools) }
    }
}
