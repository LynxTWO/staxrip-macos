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
        if let window = NSApp.keyWindow { picker.beginSheetModal(for: window, completionHandler: completion) }
        else { picker.begin(completionHandler: completion) }
    }
}
