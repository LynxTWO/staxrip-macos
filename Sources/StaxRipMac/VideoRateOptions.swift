import SwiftUI

struct VideoRateOptions: Codable, Equatable {
    var backend = "Software"
    var mode = "Constant quality"
    var bitrate = 4000
}

struct VideoRateOptionsView: View {
    @Binding var configuration: EncodeConfiguration
    @EnvironmentObject private var dolby: DolbyInspectionController
    @State private var acknowledgementError: String?
    var source: URL? = nil
    private var p81: Bool { configuration.colorMode == DolbyConversionIntent.p81Copy }
    private var dolbyCopy: Bool { p81 || configuration.colorMode == DolbyConversionIntent.hdr10Copy }
    private var hdrIssue: String? {
        do { try EncodePlan.validateHDRSettings(configuration); return nil }
        catch { return error.localizedDescription }
    }
    private var copyIssue: String? {
        do { try VideoCopyContract.validateSettings(configuration); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingPicker("Color workflow", selection: $configuration.colorMode, values: ["SDR", "Preserve static HDR10", DolbyConversionIntent.hdr10Copy, DolbyConversionIntent.p81Copy])
                .accessibilityHint("Choose standard dynamic range or verified static H D R ten preservation. This does not change your other settings.")
            Text("Dolby Vision P8.1 execution remains unavailable outside the isolated development demonstration. Saved intent does not enable conversion.")
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("dolby.p81.unavailable")
            Text("Tone-mapped SDR — unavailable: a verified pixel tone and gamut transform is required. The SDR setting above does not tone-map HDR.")
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("dolby.sdr.unavailable")
            if dolbyCopy {
                Text(p81 ? "Prepare P8.1 base-layer copy · MKV · no video re-encoding or tone mapping. Reviewed Dolby metadata is converted to P8.1; enhancement-layer data is removed. This does not reconstruct enhancement pixels. The original source is kept." : "Prepare HDR10 base-layer copy · MKV · no video re-encoding or tone mapping. Dolby Vision metadata and the enhancement layer will be removed; static HDR10 remains. The original source is kept.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Text("Initial route: one 4K Main 10 P7 MEL video track at 24000/1001, CM 2.9, MKV. Choose Copy original, No audio and Remove all subtitles; original size and no edits. Every packet and decoded frame must pass before publication. Other profiles, additional tracks and reordered pictures remain unavailable.").font(.caption).foregroundStyle(Color.warning)
                    .accessibilityIdentifier("dolby.hdr10.support")
                Toggle(p81 ? "I acknowledge enhancement-layer loss for this inspected source" : "I acknowledge Dolby Vision loss for this inspected source", isOn: Binding(get: {
                    guard let source, let report = dolby.report(for: source) else { return false }
                    return (p81 ? configuration.p81EnhancementLossAcknowledgement : configuration.dolbyLossAcknowledgement)?.matches(source: source, fingerprint: report.source) == true
                }, set: { acknowledged in
                    acknowledgementError = nil
                    guard acknowledged else { if p81 { configuration.p81EnhancementLossAcknowledgement = nil } else { configuration.dolbyLossAcknowledgement = nil }; return }
                    guard let source, let report = dolby.report(for: source) else { return }
                    do { let value = try DolbyLossAcknowledgement(source: source, fingerprint: report.source); if p81 { configuration.p81EnhancementLossAcknowledgement = value } else { configuration.dolbyLossAcknowledgement = value } }
                    catch { acknowledgementError = error.localizedDescription }
                }))
                .disabled(source.flatMap { dolby.report(for: $0) } == nil)
                .accessibilityIdentifier(p81 ? "dolby.p81.acknowledge" : "dolby.hdr10.acknowledge")
                Text("Inspect the complete Dolby metadata first. Acknowledgement is tied to the inspected source content; it does not qualify conversion. Changing sources clears it. Saved intent must be checked against fresh source content before execution.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let acknowledgementError { Text(acknowledgementError).font(.caption).foregroundStyle(Color.warning) }
            }
            if !configuration.copiesVideo && configuration.colorMode == "Preserve static HDR10" {
                if let hdrIssue { Text(hdrIssue).font(.caption).foregroundStyle(Color.warning).fixedSize(horizontal: false, vertical: true) }
                Text("Requires software HEVC, MKV and original picture settings. Every source and output frame is decoded for verification, adding two full scans plus source identity checks. FFmpeg 9.0.x only.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Static PQ / BT.2020 metadata only. Recognized dynamic or unknown side data is refused. Proprietary data hidden in unregistered SEI cannot be certified; calibrated HDR playback is not verified.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if configuration.copiesVideo {
                Text("Copy the original encoded picture without another video encoding pass. Audio and subtitle choices still apply; AAC and Opus still re-encode audio.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                if !dolbyCopy {
                if let copyIssue { Text(copyIssue).font(.caption).foregroundStyle(Color.warning).fixedSize(horizontal: false, vertical: true) }
                Text("Supports 8-bit SDR H.264/HEVC, 10-bit HEVC Main 10 with declared BT.709 limited-range SDR, or 8/10-bit AV1 Main with declared BT.709 limited-range SDR. First video only: upright, progressive and square-pixel in MP4/QuickTime or Matroska. Requires original size and no picture filters or trim.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Supports eight-bit standard dynamic range H two six four or H E V C, ten-bit H E V C Main ten with declared B T seven zero nine, limited-range standard dynamic range, or eight or ten-bit A V one Main with declared B T seven zero nine, limited-range standard dynamic range. First video only: upright, progressive and square-pixel in M P four, QuickTime or Matroska. Requires original size and no picture filters or trim.")
                Text("Video packets and presentation timing are checked before saving. This adds source/output scans and up to 128 MiB of temporary audit storage, limited to two million video packets. Conversions that cannot preserve packet timing are refused, including some variable-frame-rate Matroska sources. Stored video quality, speed and engine settings are inactive.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                settingPicker("Encoding engine", selection: Binding(get: { configuration.rate.backend }, set: { value in
                    var next = configuration
                    next.selectBackend(value)
                    configuration = next
                }), values: configuration.codec == "AV1" ? ["Software"] : ["Software", "Apple hardware"])
                settingPicker("Rate control", selection: $configuration.rate.mode, values: configuration.rate.backend == "Apple hardware" ? ["Target bitrate"] : ["Constant quality", "Target bitrate"])
                if configuration.rate.mode == "Target bitrate" {
                    HStack {
                        Text("Video bitrate (kb/s)")
                        TextField("Video bitrate", value: $configuration.rate.bitrate, format: .number)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Video bitrate, in kilobits per second")
                            .accessibilityHint("Single-pass target bitrate. Does not guarantee a file size or a constant bitrate.")
                    }
                    Text("Single-pass target, not a guaranteed file size or constant bitrate. Actual bitrate depends on the material and encoder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if configuration.rate.backend == "Apple hardware" {
                    Text("VideoToolbox requires hardware support. Software fallback is disabled. CRF and software speed presets do not apply.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.font(.system(size: 12))
        HEVCBufferLimitsView(configuration: $configuration, source: source)
            .font(.system(size: 12))
    }
}
