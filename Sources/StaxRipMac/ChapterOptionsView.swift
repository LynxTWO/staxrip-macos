import SwiftUI

struct ChapterOptionsView: View {
    @Binding var configuration: EncodeConfiguration
    let source: URL?
    @EnvironmentObject private var editor: ChapterEditorController
    @State private var showingEditor = false
    private var selection: Binding<String> {
        Binding(get: {
            switch configuration.chapterEdits?.mode {
            case .custom: return "Custom chapter list"
            case .remove: return "Remove all chapters"
            case nil: return "Preserve source chapters"
            }
        }, set: { value in
            if value == "Custom chapter list" { openEditor() }
            else { configuration.chapterEdits = value == "Remove all chapters" ? .init(mode: .remove) : nil }
        })
    }
    private func openEditor() {
        if editor.begin(configuration: configuration, source: source) { showingEditor = true }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingPicker("Chapter handling", selection: selection,
                          values: ["Preserve source chapters", "Remove all chapters", "Custom chapter list"])
                .disabled(editor.running)
            if let edits = configuration.chapterEdits, edits.mode == .custom {
                ChapterTimeline(entries: edits.entries)
                Text("\(edits.entries.count) authored chapters on the source timeline.").font(.callout)
            }
            Button(configuration.chapterEdits?.mode == .custom ? "Edit chapter list…" : "Create chapter list…") { openEditor() }
                .disabled(editor.running)
                .help("Edit an isolated draft, or copy source chapter titles and times into it. Cancel keeps the current recipe.")
            Text(configuration.chapterEdits?.mode == .custom
                 ? "Custom times refer to the source. Trim keeps only overlapping chapter ranges and moves them to output time. MP4 requires chapters to start at output zero with no gaps; MKV can retain gaps."
                 : configuration.chapterEdits?.mode == .remove
                 ? "The output will contain no chapters. Source media is unchanged."
                 : "Untrimmed exports retain supported source chapters. Trimming omits them. Create a custom list to edit titles or keep chapters through a trim.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("New source imports reset chapter choices. Sessions and queued configurations retain them; reusable presets do not copy them.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if editor.running { Text("A source chapter read is settling…").font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $showingEditor) {
            ChapterEditorView(configuration: $configuration, source: source).environmentObject(editor)
        }
    }
}

struct ChapterTimeline: View {
    let entries: [ChapterEntry]
    var body: some View {
        let end = Double(entries.last?.endMilliseconds ?? 0)
        VStack(spacing: 6) {
            Canvas { context, size in
                guard end > 0 else { return }
                for (index, entry) in entries.enumerated() {
                    let x = size.width * Double(entry.startMilliseconds) / end
                    let width = size.width * Double(entry.endMilliseconds - entry.startMilliseconds) / end
                    let rect = CGRect(x: x, y: 0, width: max(1, width - 2), height: size.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.accent.opacity(index.isMultiple(of: 2) ? 0.8 : 0.45)))
                }
            }.frame(height: 16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            HStack {
                Text("0 s")
                Spacer()
                Text(ChapterEdits.secondsText(entries.last?.endMilliseconds ?? 0) + " s")
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Source chapter timeline")
        .accessibilityValue("\(entries.count) chapters, displayed from zero to \(ChapterEdits.secondsText(entries.last?.endMilliseconds ?? 0)) seconds")
    }
}

private struct ChapterEditorView: View {
    @Binding var configuration: EncodeConfiguration
    let source: URL?
    @EnvironmentObject private var editor: ChapterEditorController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let issue = editor.issue
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Give your film a chapter map").font(.title2.weight(.semibold))
                    Text("Source times in seconds · up to three decimal places").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("DRAFT").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Color.accent.opacity(0.12), in: Capsule())
            }
            Text("Set titles and nonoverlapping ranges in time order. Custom ranges are clipped and shifted by your trim. Source files are never edited.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Replace draft with source chapters") { editor.importSource() }
                    .disabled(!editor.canImport)
                Spacer()
                Button("Sort by start time") { editor.sortByTime() }.disabled(editor.running || editor.rows.isEmpty)
                Button("Add chapter") { editor.add() }.disabled(editor.running || editor.rows.count >= 1000)
            }
            if editor.running { ProgressView("Reading source chapters…").controlSize(.small) }
            if issue == nil, let edits = try? editor.edits() { ChapterTimeline(entries: edits.entries) }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach($editor.rows) { $row in
                        let number = (editor.rows.firstIndex(where: { $0.id == row.id }) ?? 0) + 1
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", number)).font(.system(.headline, design: .monospaced)).foregroundStyle(Color.accent)
                                TextField("Chapter title", text: $row.title).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Chapter \(number) title")
                                Button { editor.remove(row.id) } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Remove chapter \(number)")
                                    .help("Remove this chapter from the draft. Source media is unchanged.")
                            }
                            HStack(spacing: 10) {
                                Text("Start").font(.caption)
                                TextField("Seconds", text: $row.start).frame(width: 125).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Chapter \(number) start, source seconds")
                                Text("End").font(.caption)
                                TextField("Seconds", text: $row.end).frame(width: 125).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Chapter \(number) end, source seconds")
                                Spacer()
                                Button("Split in half") { editor.split(row.id) }.disabled(editor.rows.count >= 1000)
                                    .accessibilityLabel("Split chapter \(number) into two ranges")
                            }
                        }.padding(13).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            .disabled(editor.running)
                    }
                    if editor.rows.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "list.number").font(.system(size: 28)).foregroundStyle(Color.accent)
                            Text("A place for every part of the story.").font(.headline)
                            Text("Add a chapter or copy the source list to begin.").font(.callout).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 34)
                    }
                }
            }
            Text(editor.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Chapter editor status").accessibilityValue(editor.status)
            if let issue { Text(issue).font(.caption).foregroundStyle(Color.warning).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button("Cancel") { editor.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("Changes apply only after you choose Apply.").font(.caption).foregroundStyle(.secondary)
                Button("Apply chapter list") {
                    do { configuration = try editor.applying(to: configuration, source: source); dismiss() }
                    catch { editor.report(error) }
                }.primaryAction().keyboardShortcut(.defaultAction)
                    .disabled(editor.running || issue != nil)
            }
        }.padding(24).frame(width: 780, height: 680)
            .onDisappear { editor.cancel() }
    }
}
