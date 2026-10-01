import SwiftUI

struct VideoRateOptions: Codable, Equatable {
    var backend = "Software"
    var mode = "Constant quality"
    var bitrate = 4000
}

struct VideoRateOptionsView: View {
    @Binding var configuration: EncodeConfiguration
    private var hdrIssue: String? {
        do { try EncodePlan.validateHDRSettings(configuration); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingPicker("Color workflow", selection: $configuration.colorMode, values: ["SDR", "Preserve static HDR10"])
                .accessibilityHint("Choose standard dynamic range or verified static H D R ten preservation. This does not change your other settings.")
            if configuration.colorMode == "Preserve static HDR10" {
                if let hdrIssue { Text(hdrIssue).font(.caption).foregroundStyle(Color.warning).fixedSize(horizontal: false, vertical: true) }
                Text("Requires software HEVC, MKV and original picture settings. Every source and output frame is decoded for verification, adding two full scans plus source identity checks. FFmpeg 9.0.x only.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Static PQ / BT.2020 metadata only. Recognized dynamic or unknown side data is refused. Proprietary data hidden in unregistered SEI cannot be certified; calibrated HDR playback is not verified.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
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
        }.font(.system(size: 12))
    }
}
