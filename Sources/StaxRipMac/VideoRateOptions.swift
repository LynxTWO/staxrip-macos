import SwiftUI

struct VideoRateOptions: Codable, Equatable {
    var backend = "Software"
    var mode = "Constant quality"
    var bitrate = 4000
}

struct VideoRateOptionsView: View {
    @Binding var configuration: EncodeConfiguration
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingPicker("Encoding engine", selection: $configuration.rate.backend, values: configuration.codec == "AV1" ? ["Software"] : ["Software", "Apple hardware"])
                .onChange(of: configuration.rate.backend) { _, backend in
                    if backend == "Apple hardware" { configuration.rate.mode = "Target bitrate" }
                }
                .onChange(of: configuration.codec) { _, codec in
                    if codec == "AV1" { configuration.rate.backend = "Software" }
                }
            settingPicker("Rate control", selection: $configuration.rate.mode, values: configuration.rate.backend == "Apple hardware" ? ["Target bitrate"] : ["Constant quality", "Target bitrate"])
            if configuration.rate.mode == "Target bitrate" {
                HStack {
                    Text("Video bitrate (kb/s)")
                    TextField("Video bitrate", value: $configuration.rate.bitrate, format: .number)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Video bitrate kb/s")
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
