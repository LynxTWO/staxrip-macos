import SwiftUI

@MainActor
final class PicturePreviewController: ObservableObject {
    @Published private(set) var result: PictureComparison?
    @Published private(set) var running = false
    @Published private(set) var stale = false
    @Published private(set) var status = "Choose a source time, then render a comparison."
    @Published private(set) var atFirstFrame = false
    @Published private(set) var atLastFrame = false
    private var renderedSource: URL?
    private var renderedConfiguration: EncodeConfiguration?
    var canStepPrevious: Bool { result != nil && !running && !stale && !atFirstFrame }
    var canStepNext: Bool { result != nil && !running && !stale && !atLastFrame }
    private var generation = UUID()
    private var task: Task<Void, Never>?

    func invalidate() {
        generation = UUID()
        task?.cancel()
        stale = result != nil
        renderedSource = nil; renderedConfiguration = nil; atFirstFrame = false; atLastFrame = false
        status = running ? "Settings changed. Cancelling the old request…" : "Settings changed. Render again to see the current picture."
    }
    func cancel() {
        generation = UUID()
        task?.cancel()
        if running { stale = result != nil; renderedSource = nil; renderedConfiguration = nil }
        status = running ? "Cancelling preview…" : "Choose a source time, then render a comparison."
    }
    func close() { cancel(); result = nil; stale = false; renderedSource = nil; renderedConfiguration = nil; atFirstFrame = false; atLastFrame = false }

    func render(source: URL, configuration: EncodeConfiguration, time: Double, tools: FFmpegTools?) {
        guard !running else { return }
        guard let tools else { status = "FFmpeg and ffprobe are required. Configure the existing local tools, then retry."; return }
        let id = UUID(); generation = id
        result = nil; stale = false; running = true
        renderedSource = nil; renderedConfiguration = nil; atFirstFrame = false; atLastFrame = false
        status = "Starting picture preview…"
        task = Task { [self] in
            defer { finishRequest(id) }
            do {
                let rendered = try await PicturePreview.render(source: source, configuration: configuration, time: time, tools: tools) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == id, self.running, self.result == nil else { return }
                        self.status = message
                    }
                }
                guard generation == id, !Task.isCancelled else { return }
                result = rendered; renderedSource = source; renderedConfiguration = configuration
                status = "Comparison ready. Picture filters only; final compression quality is not shown."
            } catch {
                guard generation == id else {
                    status = stale ? "Preview stopped. Previous images are out of date." : "Preview cancelled. Render again when ready."
                    return
                }
                status = error is CancellationError ? "Preview cancelled." : error.localizedDescription
            }
        }
    }

    private func finishRequest(_ id: UUID) {
        running = false; task = nil
        // A request can finish between cancellation and the awaiting actor's
        // resumption. Clear transient cancellation text on that path as well.
        if generation != id {
            status = stale ? "Preview stopped. Previous images are out of date." : "Preview cancelled. Render again when ready."
        }
    }

    func step(source: URL, configuration: EncodeConfiguration, direction: PreviewStepDirection, tools: FFmpegTools?) {
        guard !running else { return }
        guard !stale, let current = result, renderedSource == source, renderedConfiguration == configuration else {
            invalidate(); status = "Render a current comparison before stepping through frames."; return
        }
        guard direction == .previous ? !atFirstFrame : !atLastFrame else { return }
        guard let tools else { status = "FFmpeg and ffprobe are required for frame stepping."; return }
        let anchor = current.original.stamp, identity = current.sourceIdentity
        let id = UUID(); generation = id; running = true; status = "Finding the adjacent decoded frame…"
        task = Task { [self] in
            defer { finishRequest(id) }
            do {
                let outcome = try await PicturePreview.step(source: source, configuration: configuration, anchor: anchor,
                    expectedSource: identity, direction: direction, tools: tools) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == id, self.running else { return }
                        self.status = message
                    }
                }
                guard generation == id, !Task.isCancelled else { return }
                switch outcome {
                case .comparison(let rendered):
                    result = rendered; atFirstFrame = false; atLastFrame = false
                    status = "Adjacent frame ready. Original and filtered timestamps match the selected decoded frame."
                case .boundary:
                    if direction == .previous { atFirstFrame = true } else { atLastFrame = true }
                    status = "\(direction == .previous ? "First" : "Last") frame inside the trim interval. Current comparison retained."
                }
            } catch {
                guard generation == id else {
                    status = stale ? "Preview stopped. Previous images are out of date." : "Preview cancelled. Render again when ready."
                    return
                }
                stale = result != nil; renderedSource = nil; renderedConfiguration = nil
                status = error is CancellationError ? "Frame step cancelled. Render again before stepping." : error.localizedDescription
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
                Text("Jump to source time (seconds)")
                TextField("Seconds", value: $time, format: .number).frame(width: 110)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Preview jump time in seconds")
                    .accessibilityHint("Render comparison jumps to this source time inside the trim interval. Frame stepping uses the displayed frame instead.")
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
            HStack {
                Button("Previous frame") { step(.previous) }
                    .disabled(!controller.canStepPrevious)
                    .accessibilityHint("Show the preceding decoded source frame inside the trim interval, with the same picture filters.")
                Button("Next frame") { step(.next) }
                    .disabled(!controller.canStepNext)
                    .accessibilityHint("Show the following decoded source frame using its actual timestamp, including variable frame rates.")
                Text("Steps use decoded timestamps, not an assumed frame rate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if controller.stale {
                Label("Out of date. Render again for the current source and settings.", systemImage: "exclamationmark.triangle.fill")
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
        .padding(24).frame(width: 900, height: 680)
        .onAppear { time = model.config.picture.start }
        .onChange(of: time) { _, _ in controller.invalidate() }
        .onChange(of: model.config) { _, _ in controller.invalidate() }
        .onChange(of: model.sourceURL) { _, _ in controller.invalidate() }
        .onDisappear { controller.close() }
    }

    private func step(_ direction: PreviewStepDirection) {
        guard let source = model.sourceURL else { return }
        controller.step(source: source, configuration: model.config, direction: direction, tools: FFmpegTools.discover())
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
