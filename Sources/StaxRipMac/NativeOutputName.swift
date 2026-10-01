import AppKit
import Darwin

/// A naming aid only. Exclusive publication remains the final race protection.
enum NativeOutputName {
    static func candidate(_ proposed: URL?) throws -> URL {
        guard let proposed, proposed.isFileURL, !proposed.hasDirectoryPath,
              !proposed.path.utf8.contains(0), !proposed.lastPathComponent.isEmpty else {
            throw NativeExportError.invalid("Choose a local MP4 file name.")
        }
        let candidate = proposed.pathExtension.isEmpty ? proposed.appendingPathExtension("mp4") : proposed
        guard candidate.pathExtension.lowercased() == "mp4" else {
            throw NativeExportError.invalid("Use a file name ending in .mp4.")
        }
        return candidate
    }

    static func validate(_ proposed: URL?) throws {
        let candidate = try candidate(proposed)
        var entry = stat()
        if lstat(candidate.path, &entry) == 0 {
            throw NativeExportError.invalid("An item already uses this name. Choose a new MP4 name; nothing was replaced.")
        }
        let code = errno
        guard code == ENOENT else {
            throw NativeExportError.invalid("This name could not be checked (system error \(code)). Choose another local folder or name.")
        }
    }
}

@MainActor
final class NativeOutputNameDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? {
        guard okFlag, let panel = sender as? NSSavePanel else { return filename }
        do {
            try NativeOutputName.validate(panel.url)
            return filename // AppKit appends its required extension; never silently rename.
        } catch {
            let message = error.localizedDescription
            panel.message = message
            NSAccessibility.post(element: panel, notification: .announcementRequested,
                                 userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            return nil // Keep the sheet open before AppKit offers Replace.
        }
    }
}
