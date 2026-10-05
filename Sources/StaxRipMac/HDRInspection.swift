import Foundation

/// Stream declarations, not a decoded-frame assessment or a conversion contract.
enum HDRInspection {
    static let dolbyType = "DOVI configuration record"
    static let enhancementType = "HEVC enhancement-layer decoder configuration"
    static let hdr10PlusType = "HDR10+ Dynamic Metadata (SMPTE 2094-40)"
    static let hdr10PlusFrameType = "HDR Dynamic Metadata SMPTE2094-40 (HDR10+)"

    static func dynamicFormats(_ stream: MediaProbe.Stream) -> [String] {
        let types = Set((stream.side_data_list ?? []).compactMap(\.side_data_type))
        var result: [String] = []
        if types.contains(dolbyType) || types.contains(enhancementType) { result.append("Dolby Vision") }
        if types.contains(hdr10PlusType) || types.contains(hdr10PlusFrameType) { result.append("HDR10+") }
        return result
    }

    static func requireQualifiedTranscode(_ stream: MediaProbe.Stream) throws {
        let formats = dynamicFormats(stream)
        guard formats.isEmpty else {
            throw NativeExportError.invalid("Dynamic HDR: this source declares " + formats.joined(separator: " and ") + ". Re-encoding requires a qualified metadata conversion workflow. The current SDR and static HDR10 encoders cannot preserve this information. Inspect the source HDR details; changing color tags does not convert dynamic metadata.")
        }
    }

    private static func integer(_ value: Int?, range: ClosedRange<Int>) -> String {
        guard let value else { return "Not reported" }
        return range.contains(value) ? String(value) : "Invalid value (\(value))"
    }
    private static func flag(_ value: Int?) -> String {
        switch value {
        case 1: return "Present"
        case 0: return "Not present"
        case nil: return "Not reported"
        default: return "Invalid value (\(value!))"
        }
    }
    static func rows(_ stream: MediaProbe.Stream) -> [VideoInspection.Row] {
        let data = stream.side_data_list ?? []
        let records = data.filter { $0.side_data_type == dolbyType }
        var result = [VideoInspection.Row(label: "Chroma placement", value: VideoInspection.reported(stream.chroma_location,
            names: ["left": "Left", "topleft": "Top left", "center": "Center", "top": "Top", "bottomleft": "Bottom left", "bottom": "Bottom"]),
            help: "Where color samples sit relative to brightness samples. Changing this label alone does not resample the picture."),
            VideoInspection.Row(label: "Dynamic HDR declaration", value: dynamicFormats(stream).isEmpty ? "Not reported at stream level" : dynamicFormats(stream).joined(separator: ", "),
            help: "Reported stream configuration. Missing declarations do not prove that frame-level or proprietary metadata is absent.")]
        guard records.count == 1, let dv = records.first else {
            if records.count > 1 {
                result.append(VideoInspection.Row(label: "Dolby Vision configuration", value: "Multiple records; ambiguous",
                    help: "Conflicting or repeated declarations require investigation. No profile was selected automatically."))
            }
            return result
        }
        result += [
            VideoInspection.Row(label: "Dolby Vision profile", value: integer(dv.dv_profile, range: 0...15), help: "The declared Dolby Vision profile. Profile seven can contain a minimal or full enhancement layer; this record does not distinguish them."),
            VideoInspection.Row(label: "Dolby Vision level", value: integer(dv.dv_level, range: 0...63), help: "The declared Dolby Vision level; this is separate from the profile."),
            VideoInspection.Row(label: "Dolby Vision version", value: dv.dv_version_major == nil || dv.dv_version_minor == nil ? "Incomplete or not reported" : integer(dv.dv_version_major, range: 0...255) + "." + integer(dv.dv_version_minor, range: 0...255), help: "Version declared by the Dolby Vision configuration record."),
            VideoInspection.Row(label: "Base layer", value: flag(dv.bl_present_flag), help: "Whether the configuration declares a base picture layer."),
            VideoInspection.Row(label: "Enhancement layer", value: flag(dv.el_present_flag), help: "Whether the configuration declares an enhancement layer. This does not establish minimal or full enhancement, or prove decoder support."),
            VideoInspection.Row(label: "Dynamic metadata (RPU)", value: flag(dv.rpu_present_flag), help: "Whether Reference Processing Unit metadata is declared. Complete per-frame metadata and picture alignment have not been verified."),
            VideoInspection.Row(label: "Base compatibility ID", value: integer(dv.dv_bl_signal_compatibility_id, range: 0...15), help: "Raw base-layer signal compatibility identifier. This inspector does not infer a supported conversion from it."),
            VideoInspection.Row(label: "Metadata compression", value: VideoInspection.reported(dv.dv_md_compression), help: "Reported Dolby Vision metadata compression mode.")
        ]
        return result
    }
}


// Saved user intent, never an admission or output-verification receipt. Execution
// must independently bind this content identity and qualify the complete route.
struct DolbyLossAcknowledgement: Codable, Equatable, Sendable {
    let sourcePath: String
    let sha256: String
    let bytes: Int64

    init(source: URL, fingerprint: SourceFingerprint) throws {
        sourcePath = source.standardizedFileURL.path
        sha256 = fingerprint.sha256; bytes = fingerprint.byteCount
        try validate()
    }
    func validate() throws {
        guard sourcePath.hasPrefix("/"), sourcePath.utf8.count <= 16384,
              !sourcePath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              URL(fileURLWithPath: sourcePath).standardizedFileURL.path == sourcePath,
              bytes > 0, bytes <= DolbyInspection.maximumFileBytes,
              sha256.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SessionError.invalid("Invalid source identity for Dolby Vision loss acknowledgement.")
        }
    }
    func matches(source: URL, fingerprint: SourceFingerprint) -> Bool {
        source.standardizedFileURL.path == sourcePath && sha256 == fingerprint.sha256 && bytes == fingerprint.byteCount
    }
}

enum DolbyConversionIntent {
    static let hdr10Copy = "HDR10 base-layer copy"
    static let unavailable = "HDR10 base-layer copy is not available for execution yet. Complete source and output verification must be qualified before this route can run. No output was created."
    static func validate(_ configuration: EncodeConfiguration) throws {
        if let acknowledgement = configuration.dolbyLossAcknowledgement {
            try acknowledgement.validate()
            guard configuration.colorMode == hdr10Copy else {
                throw SessionError.invalid("Dolby Vision loss acknowledgement belongs only to HDR10 base-layer copy.")
            }
        }
    }
    static func requireRunnable(_ configuration: EncodeConfiguration) throws {
        if configuration.colorMode == hdr10Copy { throw NativeExportError.invalid(unavailable) }
    }
}
