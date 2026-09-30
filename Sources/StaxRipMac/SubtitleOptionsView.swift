import SwiftUI
import UniformTypeIdentifiers

struct SubtitleOptionsView: View {
    @Binding var configuration: EncodeConfiguration
    var sourceAvailable = true
    @State private var choosingFile = false
    @State private var selectionError: String?

    private var metadataIssue: String? {
        do { try configuration.externalSubtitle?.validate(); return nil }
        catch { return error.localizedDescription }
    }
    private var embeddedHandling: Binding<String> {
        Binding(get: { configuration.subtitleMode == "Keep embedded tracks" ? "Keep selected embedded tracks" : "Remove embedded tracks" }, set: {
            configuration.subtitleMode = $0 == "Keep selected embedded tracks" ? "Keep embedded tracks" : "Remove all subtitles"
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingPicker("Embedded tracks", selection: embeddedHandling,
                          values: ["Keep selected embedded tracks", "Remove embedded tracks"])
                .help("Controls tracks already inside the source. An additional caption file below is handled separately.")
            Divider()
            Text("Additional caption file").font(.system(size: 12, weight: .semibold))
            if let reference = configuration.externalSubtitle {
                Text(URL(fileURLWithPath: reference.path).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityLabel("External SubRip subtitle file, " + URL(fileURLWithPath: reference.path).lastPathComponent)
                    .help("File location: " + URL(fileURLWithPath: reference.path).deletingLastPathComponent().path)
                Text(reference.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    .accessibilityHidden(true)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        eyebrow("Language")
                        Picker("External subtitle language", selection: Binding(get: {
                            configuration.externalSubtitle?.language ?? "und"
                        }, set: { configuration.externalSubtitle?.language = $0 })) {
                            ForEach(ExternalSubtitle.languages, id: \.0) { item in Text(item.1).tag(item.0) }
                        }.labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        eyebrow("Track title")
                        TextField("Optional title", text: Binding(get: {
                            configuration.externalSubtitle?.title ?? ""
                        }, set: { configuration.externalSubtitle?.title = $0 }))
                            .textFieldStyle(.roundedBorder).accessibilityLabel("External subtitle track title")
                    }
                }
            } else {
                Text("No external caption file selected.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(configuration.externalSubtitle == nil ? "Add SRT file…" : "Choose SRT file…") { choosingFile = true }
                    .accessibilityLabel("Choose an external SubRip subtitle file")
                    .disabled(!sourceAvailable)
                if configuration.externalSubtitle != nil {
                    Button("Remove reference") { configuration.externalSubtitle = nil; selectionError = nil }
                        .help("Omit this additional track. The caption file is not deleted.")
                        .accessibilityLabel("Remove external subtitle reference")
                }
            }
            Text(sourceAvailable
                 ? "One plain UTF-8 SRT, up to 1 MiB, with nonoverlapping cues. Supports untrimmed SDR video. Check queue validates captions before encoding. A restored session may need the file selected again."
                 : "Open a source video before choosing an additional caption file.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let issue = selectionError ?? metadataIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText]) { result in
            do {
                let url = try result.get()
                guard url.isFileURL else { throw SubRipDocument.failure("Choose a local caption file.") }
                let reference = ExternalSubtitle(path: url.path,
                    language: configuration.externalSubtitle?.language ?? "und",
                    title: configuration.externalSubtitle?.title ?? "External captions",
                    access: SubtitleFileAccess(url))
                try reference.validate()
                configuration.externalSubtitle = reference
                selectionError = nil
            } catch { selectionError = error.localizedDescription }
        }
    }
}
