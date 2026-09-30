import Foundation

// Interpret the entire fixed-point display matrix, not just its derived angle:
// reflection, scale and perspective can report the same angle as a pure rotation.
struct SourceOrientation: Equatable, Sendable {
    let degrees: Int
    static let identity = SourceOrientation(degrees: 0)
    var swapsAxes: Bool { degrees == 90 || degrees == 270 }
    var filters: [String] {
        switch degrees {
        case 90: return ["transpose=cclock"]
        case 180: return ["hflip", "vflip"]
        case 270: return ["transpose=clock"]
        default: return []
        }
    }
    var summary: String { degrees == 0 ? "Source orientation unchanged" : "Source orientation: \(degrees) degrees counter-clockwise before crop" }
    static func failure(_ detail: String) -> Error {
        NativeExportError.invalid("Source orientation: \(detail) Use an upright, progressive square-pixel SDR source or a supported right-angle display matrix.")
    }
    static func read(_ stream: MediaProbe.Stream) throws -> Self {
        let matrices = (stream.side_data_list ?? []).filter { $0.side_data_type == "Display Matrix" }
        guard matrices.count <= 1, !(stream.side_data_list ?? []).contains(where: { $0.side_data_type != "Display Matrix" && $0.rotation != nil }) else {
            throw failure("Conflicting orientation metadata.")
        }
        let angle: Int
        if let matrix = matrices.first {
            guard let text = matrix.displaymatrix, text.utf8.count <= 1024, let reported = matrix.rotation else {
                throw failure("The display matrix or its angle is missing.")
            }
            let rows = text.split(whereSeparator: \.isNewline)
            guard rows.count == 3 else { throw failure("Malformed display matrix.") }
            var values: [Int] = []
            for (index, row) in rows.enumerated() {
                let parts = row.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == String(format: "%08d", index) else {
                    throw failure("Malformed display matrix row.")
                }
                let numbers = parts[1].split(whereSeparator: \.isWhitespace)
                guard numbers.count == 3 else { throw failure("Malformed display matrix values.") }
                for number in numbers {
                    guard let value = Int32(number) else { throw failure("Display matrix value is out of range.") }
                    values.append(Int(value))
                }
            }
            let canonical: [(Int, [Int])] = [
                (0, [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824]),
                (90, [0, -65536, 0, 65536, 0, 0, 0, 0, 1073741824]),
                (180, [-65536, 0, 0, 0, -65536, 0, 0, 0, 1073741824]),
                (270, [0, 65536, 0, -65536, 0, 0, 0, 0, 1073741824])
            ]
            guard let match = canonical.first(where: { $0.1 == values }), normalized(reported) == match.0 else {
                throw failure("Mirrored, scaled, translated, arbitrary-angle or inconsistent transforms are not supported.")
            }
            angle = match.0
        } else { angle = 0 }
        if let tag = stream.tags?["rotate"] {
            guard let value = Int(tag), normalized(value) == angle else { throw failure("The legacy rotation tag has no matching verified display matrix.") }
        }
        return Self(degrees: angle)
    }
    private static func normalized(_ angle: Int) -> Int { (angle % 360 + 360) % 360 }

    func validateTranscode(_ stream: MediaProbe.Stream, configuration: EncodeConfiguration) throws {
        guard degrees != 0 else { return }
        guard configuration.colorMode == "SDR", ["yuv420p", "nv12"].contains(stream.pix_fmt ?? ""),
              !["smpte2084", "arib-std-b67"].contains(stream.color_transfer ?? ""),
              stream.sample_aspect_ratio == "1:1", stream.field_order == "progressive", configuration.picture.deinterlace == "Off" else {
            throw Self.failure("Rotated sources require progressive square pixels, 8-bit SDR and deinterlacing Off. Review Picture settings.")
        }
    }
    // Clear the source transform before explicitly transforming pixels. The
    // global stream index handles files whose first stream is not the video.
    func inputArguments(stream: Int) -> [String] {
        ["-noautorotate"] + (degrees == 0 ? [] : ["-display_rotation:\(stream)", "0"])
    }
}
