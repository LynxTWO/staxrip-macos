import Foundation

/// Checks declared stream display geometry, not decoded picture content or
/// frame-varying metadata. Missing source pixel shape is never inferred as 1:1.
struct OutputDisplayAspect: Sendable {
    private struct Fraction: Equatable, Sendable, CustomStringConvertible {
        let numerator: Int64
        let denominator: Int64
        init(_ numerator: Int64, _ denominator: Int64) {
            var a = numerator, b = denominator
            while b != 0 { let remainder = a % b; a = b; b = remainder }
            self.numerator = numerator / a
            self.denominator = denominator / a
        }
        var description: String { "\(numerator):\(denominator)" }
    }
    private let expected: Fraction?
    static let unavailable = "Display proportions unverified: source pixel shape unavailable"
    var summary: String {
        expected.map { "Expected display proportions \($0)" } ?? Self.unavailable
    }

    init(width: Int, height: Int, sampleAspectRatio: String?) throws {
        try Self.validateDimensions(width: width, height: height)
        expected = try Self.parse(sampleAspectRatio, location: "Source").map {
            // Each factor is positive Int32. Each product fits signed Int64.
            Fraction(Int64(width) * $0.numerator, Int64(height) * $0.denominator)
        }
    }

    func verify(width: Int?, height: Int?, sampleAspectRatio: String?) throws -> String {
        guard let width, let height else { throw Self.failure("Output raster dimensions are unavailable. Nothing published.") }
        try Self.validateDimensions(width: width, height: height)
        let pixelShape = try Self.parse(sampleAspectRatio, location: "Output")
        guard let expected else { return Self.unavailable }
        guard let pixelShape else {
            throw Self.failure("Output pixel shape is missing, so the source's declared display proportions cannot be verified. Nothing published.")
        }
        let actual = Fraction(Int64(width) * pixelShape.numerator, Int64(height) * pixelShape.denominator)
        guard actual == expected else {
            throw Self.failure("Output display proportions \(actual) do not match the planned \(expected). The encoder or container may have rounded pixel shape. Try a different container or Original size. Nothing published.")
        }
        return "Verified display proportions \(expected)"
    }

    private static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= Int32.max, height <= Int32.max else {
            throw failure("Raster dimensions must be positive and within supported bounds.")
        }
    }
    private static func parse(_ value: String?, location: String) throws -> Fraction? {
        guard let value else { return nil }
        if value == "N/A" || value == "0:1" { return nil }
        guard value.utf8.count <= 32 else { throw failure("\(location) pixel shape exceeds its text bounds.") }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let numerator = Int64(parts[0]), let denominator = Int64(parts[1]),
              numerator > 0, denominator > 0, numerator <= Int32.max, denominator <= Int32.max else {
            throw failure("\(location) pixel shape is malformed or exceeds supported positive rational bounds.")
        }
        return Fraction(numerator, denominator)
    }
    private static func failure(_ detail: String) -> NativeExportError {
        .invalid("Display proportion verification: " + detail)
    }
}
