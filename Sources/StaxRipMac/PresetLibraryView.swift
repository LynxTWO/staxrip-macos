import SwiftUI
import UniformTypeIdentifiers

struct PresetLibraryView: View {
    @EnvironmentObject var model: WorkspaceModel
    @EnvironmentObject var library: CustomPresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selection: UUID?
    @State private var message = ""
    private var selected: CustomPreset? { library.presets.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My encoding presets").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Save reusable codec, quality, color, size and deinterlace settings, plus audio and subtitle encoding defaults. Crop, trim, source track selections, paths and queue entries stay with your current workspace.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Preset name", text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Custom preset name")
                Button("Save current settings") {
                    action {
                        try library.save(name: name, configuration: model.config)
                        selection = library.presets.last?.id
                        message = "Preset saved. Source-specific settings were excluded."
                    }
                }.disabled(library.problem != nil)
            }
            if let problem = library.problem {
                Text(problem).foregroundStyle(Color.warning).textSelection(.enabled)
            }
            List(selection: $selection) {
                ForEach(library.presets) { preset in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(preset.name).font(.headline)
                        Text(preset.summary).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).tag(preset.id)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(preset.name)
                        .accessibilityValue(AccessibilityLanguage.spokenCodecs(preset.summary))
                }
            }.overlay {
                if library.presets.isEmpty { Text("No custom presets yet. Save your current settings above.").foregroundStyle(.secondary) }
            }
            if let selected {
                Text("Selected: \(selected.name)").font(.headline)
                HStack {
                    Button("Apply to workspace") {
                        action {
                            try model.applyCustomPreset(selected)
                            message = "Applied \(selected.name). Crop, trim and selected source tracks were retained. Use Undo settings in the workspace to reverse it."
                        }
                    }
                    Button("Rename") { action { try library.rename(selected.id, to: name); message = "Preset renamed." } }
                    Button("Remove") { action { try library.remove(selected.id); selection = nil; message = "Preset removed. Undo library change can restore it during this app run." } }
                    Button("Export recipe…") { export(selected) }
                }.disabled(library.problem != nil)
            }
            HStack {
                Button("Import recipe…") { importRecipe() }.disabled(library.problem != nil)
                Button("Undo library change") { action { try library.undo(); selection = nil; message = "Library change undone." } }
                    .disabled(!library.canUndo || library.problem != nil)
                Spacer()
                Button("Reload library") { library.reload(); selection = nil; message = library.problem == nil ? "Library reloaded. Library undo history cleared." : "" }
            }
            Text(message.isEmpty ? "Applying a recipe never starts encoding. HDR source requirements still apply." : message)
                .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Preset library status").accessibilityValue(message.isEmpty ? "Ready" : message)
        }.padding(24).frame(width: 780, height: 570)
        .onChange(of: selection) { _, _ in if let selected { name = selected.name } }
    }
    private func action(_ operation: () throws -> Void) {
        do { try operation() } catch { message = error.localizedDescription }
    }
    private func importRecipe() {
        let panel = NSOpenPanel(); panel.title = "Import one StaxRip recipe"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action { try library.importRecipe(from: url); selection = library.presets.last?.id; message = "Recipe imported. Review it before applying." }
    }
    private func export(_ preset: CustomPreset) {
        let panel = NSSavePanel(); panel.title = "Export StaxRip recipe"
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "StaxRip recipe.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action { try library.exportRecipe(preset.id, to: url); message = "Recipe exported without source paths or track selections." }
    }
}
