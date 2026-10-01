import SwiftUI

// Presentation of requested settings, never a substitute for EncodePlan's source checks.
struct WorkspaceRecipe {
    struct Entry: Identifiable, Equatable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }
    let entries: [Entry]

    init(_ c: EncodeConfiguration) {
        let p = c.picture
        let trimmed = p.start > 0 || p.end > 0
        let range = trimmed
            ? "From \(Self.seconds(p.start)) to \(p.end > 0 ? Self.seconds(p.end) : "source end"). " + (c.chapterEdits?.mode == .custom ? "Custom chapters clipped and shifted to output time." : "Chapters omitted.")
            : "Full source duration."
        let picture = Entry(id: "Picture", symbol: "crop", title: c.resolution == "Original" ? "Keep original scale" : "Fit within \(c.resolution)",
                            detail: PicturePlan(c).summary + ". " + range)
        let engine = c.rate.backend == "Software" ? "\(c.activeEncoder) · \(c.speed.lowercased()) speed" : "Apple hardware · no software fallback"
        let rate = c.rate.mode == "Constant quality" ? c.rateSummary : "Target \(c.rate.bitrate) kb/s"
        let video = c.copiesVideo
            ? Entry(id: "Video", symbol: "film", title: "Copy original video", detail: "No video re-encoding. Original size and no picture filters or trim required. Audio and subtitle choices still apply.")
            : Entry(id: "Video", symbol: "film", title: "\(c.codec) · \(rate)",
                          detail: "\(engine). \(c.colorMode == "SDR" ? "8-bit SDR requested" : "Static HDR10 preservation requested").")
        let audio: Entry
        if c.audio == "No audio" || c.audioTracks == [] {
            audio = Entry(id: "Audio", symbol: "speaker.slash", title: "No audio", detail: c.audio == "No audio" ? "Audio is omitted from this output." : "No source audio tracks selected.")
        } else {
            let encoding = c.audio == "Copy original" ? "Copy original audio" : "\(c.audio) · \(c.audioBitrate) per track"
            audio = Entry(id: "Audio", symbol: "waveform", title: encoding,
                          detail: Self.tracks(c.audioTracks, kind: "audio") + (c.audio == "Copy original" ? ". No re-encoding requested." : ". Re-encode available selected tracks."))
        }
        let embedded = c.subtitleMode == "Keep embedded tracks" && c.subtitleTracks != []
        let subtitles = Entry(id: "Subtitles", symbol: "captions.bubble",
                              title: embedded ? "Keep embedded captions" : (c.externalSubtitle == nil ? "No subtitles" : "External captions only"),
                              detail: (embedded ? Self.tracks(c.subtitleTracks, kind: "subtitle") + "." : "Embedded subtitles omitted.")
                                + (c.externalSubtitle.map { " Add \(URL(fileURLWithPath: $0.path).lastPathComponent) (\($0.language))." } ?? ""))
        let chapterTitle: String
        let chapterDetail: String
        switch c.chapterEdits?.mode {
        case .custom:
            chapterTitle = "\(c.chapterEdits?.entries.count ?? 0) custom chapters"
            chapterDetail = "Source-timeline ranges. Trim clips and shifts the list; output titles and times are verified."
        case .remove:
            chapterTitle = "No chapters"; chapterDetail = "Omit chapters from the output. Source media stays unchanged."
        case nil:
            chapterTitle = trimmed ? "Source chapters omitted" : "Preserve source chapters"
            chapterDetail = trimmed ? "Create a custom list to retain chapters through a trim." : "Retain supported source titles and ranges. Source compatibility is checked before encoding."
        }
        let chapters = Entry(id: "Chapters", symbol: "list.number", title: chapterTitle, detail: chapterDetail)
        entries = [picture, video, audio, subtitles, chapters]
    }

    private static func tracks(_ indices: [Int]?, kind: String) -> String {
        guard let indices else { return "All available source \(kind) tracks" }
        return "Source \(kind) stream\(indices.count == 1 ? "" : "s") " + indices.map(String.init).joined(separator: ", ")
    }

    private static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3))) + " s"
    }
}

struct WorkspaceRecipeView: View {
    let configuration: EncodeConfiguration
    let selectedTab: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your recipe").font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "slider.horizontal.3").foregroundStyle(Color.accent).accessibilityHidden(true)
            }
            Text("Shape the next version.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 4)
            Text("Jump to a section: ⌥⌘1–5")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 6).padding(.bottom, 18)
            ForEach(Array(WorkspaceRecipe(configuration).entries.enumerated()), id: \.element.id) { index, entry in
                recipeRow(entry, number: index + 1)
                    .padding(.bottom, 8)
            }
            Label("Settings only", systemImage: "info.circle")
                .font(.system(size: 11, weight: .medium)).padding(.top, 7)
            Text("Review source compatibility in Queue before encoding.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
    }

    private func recipeRow(_ entry: WorkspaceRecipe.Entry, number: Int) -> some View {
        let selected = selectedTab == entry.id
        return Button { onSelect(entry.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .frame(width: 25, height: 25)
                    .background(selected ? Color.accent.opacity(0.24) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(entry.id.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1)
                        Spacer(minLength: 2)
                        Image(systemName: selected ? "pencil" : entry.symbol).font(.system(size: 10))
                    }.foregroundStyle(.secondary)
                    Text(entry.title).font(.system(size: 12, weight: .semibold))
                    Text(entry.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2)
                }.fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accent.opacity(0.09) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Color.accent.opacity(0.6) : Color.primary.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [.command, .option])
        .accessibilityLabel("\(entry.id) recipe: \(AccessibilityLanguage.spokenCodecs(entry.title))")
        .accessibilityValue(selected ? "Editing" : "Not selected")
        .accessibilityHint(AccessibilityLanguage.spokenCodecs(entry.detail) + " Opens \(entry.id.lowercased()) settings. Shortcut: Option Command \(number).")
        .accessibilityInputLabels([Text(entry.id), Text(entry.title)])
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
