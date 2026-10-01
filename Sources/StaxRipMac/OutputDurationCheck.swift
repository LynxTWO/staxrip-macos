import Foundation

/// Declared container duration only; this does not prove decoded A/V alignment.
enum OutputDurationCheck {
    static let tolerance = 0.25

    static func verify(expected: Double, actual: Double) throws -> String {
        guard actual.isFinite, actual > 0, expected.isFinite else {
            throw NativeExportError.invalid("Output duration could not be verified from finite media timing. Nothing published.")
        }
        guard expected > 0 else { return "Duration unverified: source duration unavailable" }
        let difference = abs(actual - expected)
        guard difference < tolerance else {
            throw NativeExportError.invalid(String(format:
                "Output duration differs from the plan: expected %.3f s, measured %.3f s, difference %.3f s. The allowed difference is less than 0.250 s. Nothing published.", expected, actual, difference))
        }
        return "Container duration within 250 ms of plan"
    }
}
