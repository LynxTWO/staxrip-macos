import SwiftUI

@MainActor
final class PicturePreviewController: ObservableObject {
    @Published private(set) var result: PictureComparison?
    @Published private(set) var running = false
    @Published private(set) var stale = false
    @Published private(set) var status = "Choose a source time, then render a comparison."
    private var generation = UUID()
    private var task: Task<Void, Never>?

    func invalidate() {
        generation = UUID()
        task?.cancel()
        stale = result != nil
        status = running ? "Settings changed. Cancelling the old request…" : "Settings changed. Render again to see the current picture."
    }
    func cancel() {
        generation = UUID()
        task?.cancel()
        status = "Cancelling preview…"
    }
    func close() { cancel(); result = nil }

    func render(source: URL, configuration: EncodeConfiguration, time: Double, tools: FFmpegTools?) {
        guard !running else { return }
        guard let tools else { status = "FFmpeg and ffprobe are required. Configure the existing local tools, then retry."; return }
        let id = UUID(); generation = id
        result = nil; stale = false; running = true
        status = "Starting picture preview…"
        task = Task { [self] in
            defer { running = false; task = nil }
            do {
                let rendered = try await PicturePreview.render(source: source, configuration: configuration, time: time, tools: tools) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == id, self.running, self.result == nil else { return }
                        self.status = message
                    }
                }
                guard generation == id, !Task.isCancelled else { return }
                result = rendered
                status = "Comparison ready. Picture filters only; final compression quality is not shown."
            } catch {
                guard generation == id else {
                    if !stale { status = "Preview cancelled. Render again when ready." }
                    return
                }
                status = error is CancellationError ? "Preview cancelled." : error.localizedDescription
            }
        }
    }
}

struct PicturePreviewView: View {
    @EnvironmentObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject var controller: PicturePreviewController
    @State private var time = 0.0
    @State private var actualPixels = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Picture comparison").font(.title2.bold())
                    Text("Inspect crop, size and deinterlacing before encoding.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { controller.close(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Source time (seconds)")
                TextField("Seconds", value: $time, format: .number).frame(width: 110)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Preview source time in seconds")
                    .accessibilityHint("Time in the original source, inside the configured trim interval.")
                Button("Render comparison") {
                    if let source = model.sourceURL { controller.render(source: source, configuration: model.config, time: time, tools: FFmpegTools.discover()) }
                }.disabled(controller.running || model.sourceURL == nil)
                if controller.running { Button("Cancel") { controller.cancel() } }
                Spacer()
                Toggle("100% pixels", isOn: $actualPixels).toggleStyle(.switch)
                    .accessibilityHint("Shows one image pixel per display pixel. Turn off to fit the picture with its display aspect ratio.")
            }
            if controller.running { ProgressView().controlSize(.small) }
            Text(controller.status).font(.callout).textSelection(.enabled)
                .accessibilityLabel("Picture preview status").accessibilityValue(controller.status)
            if controller.stale {
                Label("Out of date. These images use previous settings.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.headline)
            }
            if let result = controller.result {
                HStack(alignment: .top, spacing: 16) {
                    frame(result.original, title: "Original")
                    frame(result.filtered, title: "Filtered")
                }
                Text(String(format: "Requested %.6f s · Actual source time %.6f s", result.requested, result.original.stamp.seconds))
                    .font(.caption.monospacedDigit())
                Text(result.operations).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .accessibilityLabel("Applied picture operations").accessibilityValue(result.operations)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.split.2x1").font(.system(size: 38)).foregroundStyle(.secondary)
                    Text("Original and filtered frames will appear here.")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("SDR BT.709 preview only. Rendering reads from the beginning to preserve deinterlacing context and may take time. Images use an sRGB display conversion; this is not a calibrated color or encoded-quality assessment.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(width: 900, height: 620)
        .onAppear { time = model.config.picture.start }
        .onChange(of: time) { _, _ in controller.invalidate() }
        .onChange(of: model.config) { _, _ in controller.invalidate() }
        .onChange(of: model.sourceURL) { _, _ in controller.invalidate() }
        .onDisappear { controller.close() }
    }

    private func frame(_ frame: PictureFrame, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let image = frame.image {
                GeometryReader { geometry in
                    if actualPixels {
                        ScrollView([.horizontal, .vertical]) {
                            Image(decorative: image, scale: 1)
                                .resizable().interpolation(.none)
                                .frame(width: CGFloat(frame.width) / displayScale, height: CGFloat(frame.height) / displayScale)
                        }
                    } else {
                        Image(decorative: image, scale: 1).resizable()
                            .aspectRatio(Double(frame.width) * frame.aspect.value / Double(frame.height), contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }.frame(height: 285).background(.black, in: RoundedRectangle(cornerRadius: 8))
            }
            Text("\(frame.width) × \(frame.height) pixels").font(.caption.monospacedDigit())
            if frame.aspect.value != 1 {
                Text("Pixel aspect \(frame.aspect.numerator):\(frame.aspect.denominator)").font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("\(title) picture")
        .accessibilityValue("\(frame.width) by \(frame.height) pixels, source time \(String(format: "%.6f", frame.stamp.seconds)) seconds. \(controller.stale ? "Out of date." : "Current comparison.")")
    }
}
