import SwiftUI

struct PictureOptions: Codable, Equatable {
    var cropLeft = 0
    var cropRight = 0
    var deinterlace = "Off"
    var start = 0.0
    var end = 0.0
}

struct PictureOptionsView: View {
    @Binding var options: PictureOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Crop edges follow the upright picture. Supported right-angle source rotation is applied before crop; rotated sources require progressive square-pixel SDR and deinterlacing Off.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Stepper("Left crop: \(options.cropLeft) px", value: $options.cropLeft, in: 0...4096, step: 2)
                Stepper("Right: \(options.cropRight) px", value: $options.cropRight, in: 0...4096, step: 2)
            }
            settingPicker("Deinterlace", selection: $options.deinterlace, values: ["Off", "Flagged frames", "All frames"])
            Text("BWDIF preserves frame rate. Flagged frames uses the source’s interlace flags; choose All frames for incorrectly flagged footage.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading) {
                    Text("Start (seconds)")
                    TextField("Start seconds", value: $options.start, format: .number)
                        .accessibilityLabel("Trim start seconds")
                }
                VStack(alignment: .leading) {
                    Text("End (seconds; 0 = end)")
                    TextField("End seconds", value: $options.end, format: .number)
                        .accessibilityLabel("Trim end seconds")
                }
            }.textFieldStyle(.roundedBorder)
            Text("Trim re-encodes from the selected time. Choose AAC, Opus or No audio and remove subtitles. Chapters are omitted for trimmed outputs. Source preview shows the original.")
                .font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 12))
    }
}
