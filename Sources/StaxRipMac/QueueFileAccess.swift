import AppKit
import SwiftUI

/// Reviews the configured location through a native picker without relinking jobs.
@MainActor
final class QueueFileAccess: ObservableObject {
    @Published private(set) var reviewing = false
    @Published private(set) var result: (jobID: UUID, message: String)?
    private var panel: NSOpenPanel?

    func review(_ job: QueueJob, destination: Bool) {
        guard !reviewing else { return }
        // Accessibility/menu actions need not leave a key window. Keep the panel
        // attached to the workspace instead of falling back to a separate window.
        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && !($0 is NSPanel)
        }), window.attachedSheet == nil else {
            result = (job.id, "Bring the queue window forward and close its current dialog, then review access again.")
            return
        }
        let expected = destination ? URL(fileURLWithPath: job.destination).deletingLastPathComponent() : URL(fileURLWithPath: job.source)
        let picker = NSOpenPanel()
        picker.title = destination ? "Review destination folder access" : "Review source access"
        picker.message = "Select the configured \(destination ? "folder" : "source file"): \(expected.path). This does not change the queue or start an encode."
        picker.prompt = "Review access"
        picker.canChooseFiles = !destination; picker.canChooseDirectories = destination
        picker.allowsMultipleSelection = false; picker.canCreateDirectories = false
        picker.directoryURL = expected.deletingLastPathComponent()
        panel = picker; reviewing = true; result = nil
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak picker] response in
            guard let self else { return }
            picker?.orderOut(nil)
            defer { self.panel = nil; self.reviewing = false }
            let message: String
            if response != .OK {
                message = "Access review cancelled. Queue paths are unchanged."
            } else if picker?.url?.standardizedFileURL.path != expected.standardizedFileURL.path {
                message = "A different location was selected. Queue paths are unchanged; select the configured location to review its access."
            } else {
                message = "\(destination ? "Destination folder" : "Source") selection reviewed. Queue paths are unchanged. Retry Check queue if needed; filesystem access is not guaranteed."
            }
            self.result = (job.id, message)
        }
        picker.beginSheetModal(for: window, completionHandler: completion)
    }
}
