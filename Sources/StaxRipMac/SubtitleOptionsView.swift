import SwiftUI
import UniformTypeIdentifiers

struct SubtitleOptionsView: View {
    @Binding var configuration: EncodeConfiguration
    var sourceAvailable = true
    var sourceIdentity: String?
    @State private var choosingFile = false
    @State private var selection: CaptionFileSelection?
    @State private var selectionError: String?

    private var metadataIssue: String? {
        do { try configuration.validateExternalCaptions(); return nil }
        catch { return error.localizedDescription }
    }
    private var embeddedHandling: Binding<String> {
        Binding(get: { configuration.subtitleMode == "Keep embedded tracks" ? "Keep selected embedded tracks" : "Remove embedded tracks" }, set: {
            configuration.subtitleMode = $0 == "Keep selected embedded tracks" ? "Keep embedded tracks" : "Remove all subtitles"
        })
    }
    private func choose(_ index: Int?) {
        selection = CaptionFileSelection(references: configuration.externalCaptions, source: sourceIdentity, replacing: index)
        choosingFile = true
    }
    private func update(_ index: Int, path: String, _ change: (inout ExternalSubtitle) -> Void) {
        var list = configuration.externalCaptions
        guard list.indices.contains(index), list[index].path == path else { return }
        change(&list[index]); configuration.externalCaptions = list
    }
    private func move(_ index: Int, by delta: Int) {
        var list = configuration.externalCaptions
        guard list.indices.contains(index), list.indices.contains(index + delta) else { return }
        list.swapAt(index, index + delta); configuration.externalCaptions = list; selectionError = nil
    }
    @ViewBuilder private func row(_ index: Int, _ reference: ExternalSubtitle) -> some View {
        let name = URL(fileURLWithPath: reference.path).lastPathComponent
        let label = "Caption track \(index + 1), \(name)"
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(String(index + 1)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 24).background(Color.accent.opacity(0.08), in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 12, weight: .semibold))
                        .accessibilityLabel(label + ", external SubRip subtitle file")
                    Text(reference.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(index == 0).accessibilityLabel("Move " + label + " earlier")
                Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(index + 1 == configuration.externalCaptions.count).accessibilityLabel("Move " + label + " later")
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("Language")
                    Picker("Language for " + label, selection: Binding(get: { reference.language }, set: { value in
                        update(index, path: reference.path) { $0.language = value }
                    })) {
                        ForEach(ExternalSubtitle.languages, id: \.0) { item in Text(item.1).tag(item.0) }
                    }.tint(Color.primaryActionFill).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("Track title")
                    TextField("Optional title", text: Binding(get: { reference.title }, set: { value in
                        update(index, path: reference.path) { $0.title = value }
                    })).textFieldStyle(.roundedBorder).accessibilityLabel("Title for " + label)
                }
            }
            Picker("Playback", selection: Binding<CaptionPlayback?>(get: { reference.playback }, set: { value in
                update(index, path: reference.path) { $0.playback = value }
            })) {
                Text("Automatic").tag(Optional<CaptionPlayback>.none)
                ForEach(CaptionPlayback.allCases, id: \.self) { choice in Text(choice.label).tag(Optional(choice)) }
            }.tint(Color.primaryActionFill)
                .accessibilityLabel("Playback for " + label)
                .accessibilityHint("MKV playback hints. Default makes this the preferred caption track. Forced requests display even when captions are off. Player settings can override both.")
            HStack {
                Button("Choose file…") { choose(index) }.disabled(!sourceAvailable)
                    .accessibilityLabel("Choose file for " + label)
                    .help("Replace this reference or select the same saved file again to review access.")
                Button("Remove reference") {
                    var list = configuration.externalCaptions
                    guard list.indices.contains(index), list[index].path == reference.path else { return }
                    list.remove(at: index); configuration.externalCaptions = list; selectionError = nil
                }.accessibilityLabel("Remove " + label + " reference")
                    .help("Omit this added track. The caption file is not deleted.")
            }.font(.caption)
        }.padding(12).background(Color.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingPicker("Embedded tracks", selection: embeddedHandling,
                          values: ["Keep selected embedded tracks", "Remove embedded tracks"])
                .help("Controls tracks already inside the source. Added caption files below are handled separately.")
            Divider()
            HStack {
                Text("Additional caption tracks").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(configuration.externalCaptions.count) / 8").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("\(configuration.externalCaptions.count) of eight external caption tracks selected")
            }
            if configuration.externalCaptions.isEmpty {
                Text("Add the languages your audience needs.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(configuration.externalCaptions.enumerated()), id: \.element.path) { index, reference in row(index, reference) }
            Button("Add SRT file…") { choose(nil) }
                .accessibilityLabel("Add an external SubRip subtitle track")
                .disabled(!sourceAvailable || configuration.externalCaptions.count >= EncodeConfiguration.maximumExternalCaptions)
            Text(sourceAvailable
                 ? "Up to eight plain UTF-8 SRT files, each up to 1 MiB with nonoverlapping cues. Added tracks follow embedded tracks in this order. Every added track's language, title, text and timing is checked before saving. SDR only. Trim clips and shifts each file to the output timeline; use up to three decimal places. A track with no cues in the trim must be removed explicitly. Choose file can also review access to a saved reference."
                 : "Open a source video before choosing additional caption files.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !configuration.externalCaptions.isEmpty {
                Text("Playback choices require MKV. Automatic keeps the usual track defaults. Optional clears default and forced flags. Default makes one added track the sole default caption, including over embedded tracks. Forced asks players to show this track even when captions are off. Players can override these hints; the written flags are checked before saving.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let issue = selectionError ?? metadataIssue { Text(issue).font(.caption).foregroundStyle(Color.warning).fixedSize(horizontal: false, vertical: true) }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText]) { result in
            defer { selection = nil }
            do {
                let url = try result.get()
                guard sourceAvailable, let selection else { throw SubRipDocument.failure("The caption selection is no longer active. Choose a file again.") }
                configuration.externalCaptions = try selection.applying(url, current: configuration, source: sourceIdentity)
                selectionError = nil
            } catch let error as CocoaError where error.code == .userCancelled { selectionError = nil }
            catch { selectionError = error.localizedDescription }
        }
    }
}
