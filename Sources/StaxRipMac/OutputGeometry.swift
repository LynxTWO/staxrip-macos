import Foundation

/// Verifies encoded raster size. Sample aspect ratio and picture content are
/// separate contracts; a fit to this box does not promise square pixels.
struct OutputGeometry: Sendable {
    let width: Int
    let height: Int
    let box: (width: Int, height: Int)?

    init(width: Int, height: Int, resolution: String) throws {
        guard width > 0, height > 0, width <= Int32.max, height <= Int32.max,
              width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw Self.failure("The upright cropped frame must have positive even dimensions within supported bounds.")
        }
        self.width = width; self.height = height
        switch resolution {
        case "Original": box = nil
        case "1280 × 720": box = (1280, 720)
        case "1920 × 1080": box = (1920, 1080)
        default: throw Self.failure("The requested output size is unsupported.")
        }
        if let box {
            let widthLimited = Int64(box.width) * Int64(height) <= Int64(box.height) * Int64(width)
            let fitsEvenRaster = widthLimited
                ? Int64(height) * Int64(box.width) >= Int64(width)
                : Int64(width) * Int64(box.height) >= Int64(height)
            guard fitsEvenRaster else {
                throw Self.failure("This frame is too narrow to fit the selected size with positive even dimensions.")
            }
        }
    }

    func verify(width actualWidth: Int?, height actualHeight: Int?) throws -> String {
        guard let w = actualWidth, let h = actualHeight, w > 0, h > 0,
              w.isMultiple(of: 2), h.isMultiple(of: 2) else {
            throw Self.failure("Output frame dimensions are missing or invalid. Nothing published.")
        }
        if let box {
            guard w <= box.width, h <= box.height else {
                throw Self.failure("Output frame exceeds the selected raster box. Nothing published.")
            }
            let widthLimited = Int64(box.width) * Int64(height) <= Int64(box.height) * Int64(width)
            let numerator = Int64(widthLimited ? box.width : box.height)
            let denominator = Int64(widthLimited ? width : height)
            // Cross-products keep the strict rounding bound exact, avoiding
            // floating-point ambiguity at two pixels. All factors are bounded.
            guard w == box.width || h == box.height,
                  abs(Int64(w) * denominator - Int64(width) * numerator) < 2 * denominator,
                  abs(Int64(h) * denominator - Int64(height) * numerator) < 2 * denominator else {
                throw Self.failure("Output \(w) × \(h) does not match the proportional fit within \(box.width) × \(box.height). Nothing published.")
            }
        } else {
            guard w == width, h == height else {
                throw Self.failure("Output \(w) × \(h) does not match the planned \(width) × \(height) frame. Nothing published.")
            }
        }
        return "Verified frame size \(w) × \(h) pixels"
    }

    private static func failure(_ message: String) -> NativeExportError {
        .invalid("Frame size verification: " + message)
    }
}
