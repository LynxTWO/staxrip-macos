import AppKit
import UniformTypeIdentifiers

enum WorkspaceFileRequest: Equatable {
    case source
    case reviewSource(URL)
    case destination(URL)
    case openSession
    case saveSession
    case exportQueue
    case nativeExport(URL)
    case reviewQueueDestination(URL, position: Int, total: Int)
}

@MainActor
protocol WorkspacePanelPresenting: AnyObject {
    @discardableResult
    func select(_ request: WorkspaceFileRequest, completion: @escaping @MainActor (URL?) -> Void) -> Bool
    @discardableResult
    func confirmReplacement(completion: @escaping @MainActor (Bool) -> Void) -> Bool
}

/// A single attached workspace dialog. Completion is delivered after AppKit has
/// finished dismissing the sheet, so a following confirmation can attach normally.
@MainActor
final class WorkspaceFilePanels: WorkspacePanelPresenting {
    private var active = false
    private var nativeNameDelegate: NativeOutputNameDelegate?
    private func window() -> NSWindow? {
        guard !active, let window = NSApp.mainWindow ?? NSApp.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && !($0 is NSPanel)
        }), window.attachedSheet == nil else { return nil }
        return window
    }

    func select(_ request: WorkspaceFileRequest, completion: @escaping @MainActor (URL?) -> Void) -> Bool {
        guard let window = window() else { return false }
        let panel: NSSavePanel
        switch request {
        case .source, .reviewSource:
            let picker = NSOpenPanel()
            picker.title = "Open a source video"
            picker.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "mkv") ?? .movie]
            picker.allowsMultipleSelection = false
            if case .reviewSource(let source) = request {
                picker.title = "Review saved source"
                picker.message = "Select \(source.lastPathComponent) at its saved location. Your saved settings and output name will be kept."
                picker.directoryURL = source.deletingLastPathComponent()
            }
            panel = picker
        case .destination(let folder):
            let picker = NSOpenPanel()
            picker.title = "Choose an output folder"
            picker.canChooseFiles = false; picker.canChooseDirectories = true
            picker.canCreateDirectories = true; picker.allowsMultipleSelection = false
            picker.directoryURL = folder
            panel = picker
        case .reviewQueueDestination(let folder, let position, let total):
            let picker = NSOpenPanel()
            picker.title = "Review output folder \(position) of \(total)"
            picker.message = "Select the configured folder: \(folder.path)\nThe queue starts after the last folder review. Cancel starts nothing. Selection does not guarantee filesystem access."
            picker.prompt = position == total ? "Start queue" : "Continue"
            picker.canChooseFiles = false; picker.canChooseDirectories = true
            picker.canCreateDirectories = false; picker.allowsMultipleSelection = false
            picker.directoryURL = folder.deletingLastPathComponent()
            panel = picker
        case .openSession:
            let picker = NSOpenPanel()
            picker.title = "Open StaxRip Mac session"
            picker.allowedContentTypes = [.json]; picker.allowsMultipleSelection = false
            panel = picker
        case .saveSession:
            panel = NSSavePanel()
            panel.title = "Save StaxRip Mac session"
            panel.nameFieldStringValue = "StaxRip session.json"
            panel.allowedContentTypes = [.json]
        case .nativeExport(let source):
            panel = NSSavePanel()
            panel.title = "Export MP4 with Apple media tools"
            panel.prompt = "Export"
            panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "_native.mp4"
            panel.allowedContentTypes = [.mpeg4Movie]
            panel.message = "Choose a new output name. Existing files will not be replaced."
            let delegate = NativeOutputNameDelegate()
            nativeNameDelegate = delegate
            panel.delegate = delegate
        case .exportQueue:
            panel = NSSavePanel()
            panel.title = "Export prototype queue"
            panel.nameFieldStringValue = "staxrip-prototype-queue.json"
            panel.allowedContentTypes = [.json]
        }
        active = true
        panel.beginSheetModal(for: window) { [weak self] response in
            let selected = response == .OK ? panel.url : nil
            panel.orderOut(nil)
            DispatchQueue.main.async {
                self?.nativeNameDelegate = nil
                self?.active = false
                completion(selected)
            }
        }
        return true
    }

    func confirmReplacement(completion: @escaping @MainActor (Bool) -> Void) -> Bool {
        guard let window = window() else { return false }
        let alert = NSAlert()
        alert.messageText = "Replace the current workspace?"
        alert.informativeText = "Open this saved session in place of the current source, settings and queue. Cancel to save your current session first."
        alert.addButton(withTitle: "Open session")
        alert.addButton(withTitle: "Cancel")
        active = true
        alert.beginSheetModal(for: window) { [weak self] response in
            DispatchQueue.main.async {
                self?.active = false
                completion(response == .alertFirstButtonReturn)
            }
        }
        return true
    }
}
