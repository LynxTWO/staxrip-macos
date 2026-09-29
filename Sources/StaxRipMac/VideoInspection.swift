import Foundation

// Presentation of declared stream metadata only. These fields do not certify
// decoded pictures, output preservation, dynamic HDR, or frame-by-frame timing.
enum VideoInspection {
    struct Row: Identifiable {
        let label: String
        let value: String
        let help: String
        var id: String { label }
    }

    static func reported(_ raw: String?, names: [String: String] = [:]) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !["unknown", "unspecified", "reserved", "N/A"].contains(raw) else { return "Unspecified" }
        if let name = names[raw] { return "\(name) (\(raw))" }
        return raw
    }

    static func ratio(_ raw: String?, frameRate: Bool) -> String {
        guard let raw else { return "Unspecified" }
        let parts = raw.split(separator: frameRate ? "/" : ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]),
              numerator.isFinite, denominator.isFinite, numerator > 0, denominator > 0,
              (numerator / denominator).isFinite, numerator / denominator > 0 else { return "Unspecified (reported: \(raw))" }
        if frameRate {
            return String(format: numerator / denominator < 0.001 ? "%.6g frames/s (%@)" : "%.3f frames/s (%@)", locale: Locale(identifier: "en_US_POSIX"), numerator / denominator, raw)
        }
        return raw
    }

    static func picture(_ stream: MediaProbe.Stream) -> [Row] {
        let depth: String
        if let raw = stream.bits_per_raw_sample, let bits = Int(raw), bits > 0 {
            depth = "\(bits) bits"
        } else { depth = "Unspecified" }
        return [
            Row(label: "Profile", value: reported(stream.profile), help: "Codec profile reported by the source probe."),
            Row(label: "Pixel format", value: reported(stream.pix_fmt), help: "Decoded pixel format reported by the probe. No color conversion is applied by this inspector."),
            Row(label: "Reported bit depth", value: depth, help: "The source's reported raw sample bit depth. An unspecified value does not mean zero bits; consult the pixel format separately.")
        ]
    }

    static func color(_ stream: MediaProbe.Stream) -> [Row] {
        [
            Row(label: "Color primaries", value: reported(stream.color_primaries, names: ["bt709": "Rec. 709", "bt2020": "Rec. 2020", "smpte170m": "SMPTE 170M"]), help: "The declared red, green and blue reference colors. Tags alone do not verify the picture."),
            Row(label: "Transfer function", value: reported(stream.color_transfer, names: ["bt709": "Rec. 709", "smpte2084": "PQ, declared HDR transfer", "arib-std-b67": "HLG, declared HDR transfer", "iec61966-2-1": "sRGB"]), help: "How encoded values relate to light. PQ means Perceptual Quantizer; HLG means Hybrid Log Gamma. Missing tags do not prove standard dynamic range."),
            Row(label: "Color matrix", value: reported(stream.color_space, names: ["bt709": "Rec. 709", "bt2020nc": "Rec. 2020 non-constant luminance", "bt2020c": "Rec. 2020 constant luminance", "gbr": "RGB"]), help: "The declared conversion between color components, often luma and chroma."),
            Row(label: "Signal range", value: reported(stream.color_range, names: ["tv": "Limited range", "pc": "Full range"]), help: "The declared numeric range of the encoded signal. This is separate from HDR brightness range.")
        ]
    }

    static func timing(_ stream: MediaProbe.Stream) -> [Row] {
        let rotations = (stream.side_data_list ?? []).compactMap(\.rotation).map { "\($0)°" }
        return [
            Row(label: "Average frame rate", value: ratio(stream.avg_frame_rate, frameRate: true), help: "Reported average frames per second. This alone does not establish constant or variable frame rate."),
            Row(label: "Reported base frame rate", value: ratio(stream.r_frame_rate, frameRate: true), help: "The probe's reported base rate, which may differ from the average. This is not a frame-by-frame timing analysis."),
            Row(label: "Sample aspect ratio", value: ratio(stream.sample_aspect_ratio, frameRate: false), help: "Pixel width compared with pixel height. One to one indicates square pixels."),
            Row(label: "Display aspect ratio", value: ratio(stream.display_aspect_ratio, frameRate: false), help: "Reported picture width compared with height after accounting for sample aspect ratio."),
            Row(label: "Field order", value: reported(stream.field_order, names: ["progressive": "Progressive", "tt": "Top coded first, top displayed first", "bb": "Bottom coded first, bottom displayed first", "tb": "Top coded first, bottom displayed first", "bt": "Bottom coded first, top displayed first"]), help: "Reported scan and field order. It does not prove that every frame follows this pattern."),
            Row(label: "Display-matrix rotation", value: rotations.isEmpty ? "Unspecified" : rotations.joined(separator: ", "), help: "Rotation reported in display side data, in degrees. Inspection does not rotate the video."),
            Row(label: "Rotation tag", value: reported(stream.tags?["rotate"]), help: "The separate legacy rotation tag, in degrees. Both values are shown if present; conflicts are not resolved automatically.")
        ]
    }
}
