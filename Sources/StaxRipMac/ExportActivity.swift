import Foundation

enum ExportActivity {
    typealias Factory = (String) -> (() -> Void)

    static let explanation = "Automatic system sleep is prevented until this export and its cleanup finish. Your screen can still turn off or lock."

    static func begin(reason: String) -> () -> Void {
        let process = ProcessInfo.processInfo
        let token = process.beginActivity(options: .idleSystemSleepDisabled, reason: reason)
        // The export owner calls this once from its settled-operation defer.
        return { process.endActivity(token) }
    }
}
