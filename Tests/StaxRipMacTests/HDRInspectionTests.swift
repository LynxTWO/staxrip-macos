import Foundation
import Testing
@testable import StaxRipMac

struct HDRInspectionTests {
    private func stream(_ fields: [String: Any]) throws -> MediaProbe.Stream {
        var object = fields; object["index"] = 0
        return try JSONDecoder().decode(MediaProbe.Stream.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private var dolby: [String: Any] {
        ["side_data_type": HDRInspection.dolbyType, "dv_version_major": 1, "dv_version_minor": 0,
         "dv_profile": 7, "dv_level": 6, "rpu_present_flag": 1, "el_present_flag": 1,
         "bl_present_flag": 1, "dv_bl_signal_compatibility_id": 6, "dv_md_compression": "none"]
    }
    @Test func dolbyConfigurationSurvivesTypedProbeAndIsExplainedWithoutGuessingEnhancementType() throws {
        let s = try stream(["codec_type": "video", "chroma_location": "topleft", "side_data_list": [dolby]])
        let record = try #require(s.side_data_list?.first)
        let fields = try record.fields()
        for (key, expected) in dolby { #expect(String(describing: fields[key]!) == String(describing: expected)) }
        let rows = HDRInspection.rows(s)
        #expect(rows.first?.value == "Top left (topleft)")
        #expect(rows.first { $0.label == "Dolby Vision profile" }?.value == "7")
        #expect(rows.first { $0.label == "Dolby Vision version" }?.value == "1.0")
        #expect(rows.first { $0.label == "Enhancement layer" }?.value == "Present")
        #expect(rows.first { $0.label == "Dynamic metadata (RPU)" }?.value == "Present")
        #expect(!rows.contains { $0.value.contains("FEL") || $0.value.contains("MEL") })
        #expect(throws: (any Error).self) { try HDRInspection.requireQualifiedTranscode(s) }
    }
    @Test func incompleteInvalidRepeatedAndAbsentDeclarationsStayExplicit() throws {
        let missing = try stream([:])
        #expect(HDRInspection.dynamicFormats(missing).isEmpty)
        #expect(HDRInspection.rows(missing)[1].value == "Not reported at stream level")
        let incomplete = try stream(["side_data_list": [["side_data_type": HDRInspection.dolbyType, "rpu_present_flag": 0, "el_present_flag": 2, "dv_profile": -1]]])
        let rows = HDRInspection.rows(incomplete)
        #expect(rows.first { $0.label == "Base layer" }?.value == "Not reported")
        #expect(rows.first { $0.label == "Enhancement layer" }?.value == "Invalid value (2)")
        #expect(rows.first { $0.label == "Dynamic metadata (RPU)" }?.value == "Not present")
        #expect(rows.first { $0.label == "Dolby Vision profile" }?.value == "Invalid value (-1)")
        #expect(rows.first { $0.label == "Dolby Vision version" }?.value == "Incomplete or not reported")
        let repeated = try stream(["side_data_list": [dolby, dolby]])
        #expect(!HDRInspection.rows(repeated).contains { $0.label == "Dolby Vision profile" })
        #expect(HDRInspection.rows(repeated).last?.value == "Multiple records; ambiguous")
    }
    @Test(arguments: ["DOVI configuration record", "HEVC enhancement-layer decoder configuration",
                     "HDR10+ Dynamic Metadata (SMPTE 2094-40)", "HDR Dynamic Metadata SMPTE2094-40 (HDR10+)"])
    func dynamicHDRCannotEnterSDRTranscodeThroughMissingOrMisleadingColorTags(type: String) throws {
        let s = try stream(["codec_type": "video", "codec_name": "hevc", "pix_fmt": "yuv420p",
                            "width": 160, "height": 96, "side_data_list": [["side_data_type": type]]])
        let probe = MediaProbe(streams: [s], format: nil)
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.audio = "No audio"
        let job = QueueJob(id: UUID(), source: "/generated/source.mkv", isDemo: false,
                           destination: "/generated/output.mkv", configuration: c, created: Date())
        do {
            _ = try EncodePlan.make(job: job, probe: probe, encoders: ["libx264"], staged: URL(fileURLWithPath: "/generated/staged.mkv"))
            Issue.record("A dynamic-HDR declaration was silently discarded")
        } catch { #expect(error.localizedDescription.contains("Dynamic HDR:")) }
        do { try HDR10Audit.validate(s); Issue.record("Dynamic HDR entered static HDR10 audit") }
        catch { #expect(error.localizedDescription.contains("Dynamic HDR:")) }
    }
    @Test func spatialAudioComesFromCodecProfileAndOnlySelectedReencodedTracksEnterSummary() throws {
        let atmos = try stream(["codec_type": "audio", "codec_name": "truehd", "profile": "Dolby TrueHD + Dolby Atmos", "channels": 8])
        let plain = try stream(["codec_type": "audio", "codec_name": "truehd", "channels": 8, "tags": ["title": "Atmos"]])
        #expect(TrackInspection.declaredSpatialAudio(atmos) == "Dolby Atmos")
        #expect(TrackInspection.declaredSpatialAudio(plain) == nil)
        #expect(TrackInspection.audioProfile(plain) == "Not reported")
        #expect(TrackInspection.conversionSummary([atmos], audio: "Opus").contains("without object metadata"))
        for choice in ["Copy original", "No audio"] { #expect(TrackInspection.conversionSummary([atmos], audio: choice).isEmpty) }
        #expect(TrackInspection.conversionSummary([plain], audio: "AAC").isEmpty)
    }
}
