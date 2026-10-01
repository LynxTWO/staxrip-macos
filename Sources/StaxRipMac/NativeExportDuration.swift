import Foundation

/// Aggregate asset timing, not decoded frame completeness or A/V synchronization.
struct NativeExportDuration {
    let sourceSeconds: Double

    init(sourceSeconds: Double) throws {
        guard sourceSeconds.isFinite, sourceSeconds > 0 else {
            throw NativeExportError.invalid("Quick Export could not read a finite, positive source duration. Choose a source with readable timing. Nothing published.")
        }
        self.sourceSeconds = sourceSeconds
    }

    func verify(actual: Double) throws {
        _ = try OutputDurationCheck.verify(expected: sourceSeconds, actual: actual)
    }
}
