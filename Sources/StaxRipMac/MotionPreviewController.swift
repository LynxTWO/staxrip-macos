import SwiftUI
import AVKit

@MainActor
final class MotionPreviewController: ObservableObject {
    typealias Renderer = @Sendable (URL, EncodeConfiguration, Double, FFmpegTools, MotionWorkspace, @escaping @Sendable (String) -> Void) async throws -> MotionComparison
    typealias Cleanup = @Sendable (MotionWorkspace) async throws -> Void
    @Published private(set) var result: MotionComparison?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var playhead = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var seeking = false
    private var seekGeneration = UUID()
    private(set) var timeObserver: Any?
    @Published private(set) var running = false
    @Published private(set) var cleanupFailed = false
    @Published private(set) var status = "Render a silent three-second original and filtered comparison."
    private(set) var workspace: MotionWorkspace?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var cleaning = false
    private let renderer: Renderer
    private let cleanup: Cleanup

    init(renderer: @escaping Renderer = { source, configuration, time, tools, workspace, progress in
        try await MotionPreview.render(source: source, configuration: configuration, time: time, tools: tools, workspace: workspace, progress: progress)
    }, cleanup: @escaping Cleanup = { try await $0.remove() }) {
        self.renderer = renderer; self.cleanup = cleanup
    }
    private func detach() {
        seekGeneration = UUID(); seeking = false
        if let player, let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil; result = nil
        playhead = 0; isPlaying = false
    }
    var frameTimes: [Double] {
        guard let frames = result?.frames, let first = frames.first else { return [] }
        return frames.map { Double($0.stamp.pts - first.stamp.pts) * $0.stamp.base.value }
    }
    var lastTime: Double { frameTimes.last ?? 0 }
    var currentFrame: Int { frameTimes.lastIndex(where: { $0 <= playhead + 1e-9 }) ?? 0 }
    var canStepBack: Bool { result != nil && !seeking && currentFrame > 0 }
    var canStepForward: Bool { result != nil && !seeking && currentFrame + 1 < frameTimes.count }
    func step(_ direction: PreviewStepDirection) {
        guard direction == .previous ? canStepBack : canStepForward else { return }
        seekFrame(currentFrame + (direction == .previous ? -1 : 1))
    }
    func seek(seconds: Double) {
        guard seconds.isFinite, !frameTimes.isEmpty else { return }
        let target = min(lastTime, max(0, seconds)), times = frameTimes
        guard let index = times.indices.min(by: { abs(times[$0] - target) < abs(times[$1] - target) }) else { return }
        seekFrame(index)
    }
    func togglePlayback() {
        guard let player, !seeking, result != nil else { return }
        if isPlaying { player.pause(); isPlaying = false }
        else if playhead >= lastTime { seekFrame(0, resume: true) }
        else { player.play(); isPlaying = true }
    }
    private func seekFrame(_ index: Int, resume: Bool = false) {
        guard let player, let frames = result?.frames, frames.indices.contains(index), let first = frames.first else { return }
        let stamp = frames[index].stamp
        let (ticks, overflow) = (stamp.pts - first.stamp.pts).multipliedReportingOverflow(by: stamp.base.numerator)
        guard !overflow, ticks >= 0, stamp.base.denominator <= Int32.max else { return }
        let target = CMTime(value: ticks, timescale: Int32(stamp.base.denominator))
        let ticket = UUID(); seekGeneration = ticket
        player.pause(); isPlaying = false; seeking = true; playhead = frameTimes[index]
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] completed in
            Task { @MainActor in
                guard let self, let player, self.player === player, self.seekGeneration == ticket else { return }
                self.seeking = false
                if completed, resume { player.play(); self.isPlaying = true }
                if !completed { self.status = "The native player could not complete that seek. Try another frame or render again." }
            }
        }
    }
    private func observePlayback(_ playback: AVPlayer, generation id: UUID) {
        timeObserver = playback.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self, weak playback] time in
            Task { @MainActor in
                guard let self, let playback, self.player === playback, self.generation == id, !self.seeking else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.playhead = min(self.lastTime, max(0, seconds)) }
                self.isPlaying = playback.rate != 0
            }
        }
    }
    private func removeOwned() async -> Bool {
        guard let workspace else { return true }
        cleaning = true
        defer { cleaning = false }
        do {
            try await cleanup(workspace)
            self.workspace = nil; cleanupFailed = false
            return true
        } catch {
            cleanupFailed = true
            status = "Motion preview stopped, but its temporary movie could not be removed. Retry cleanup before rendering again. " + error.localizedDescription
            return false
        }
    }
    func close() {
        generation = UUID(); detach()
        if running {
            if !cleaning { task?.cancel(); status = "Stopping motion preview and waiting for its encoder…" }
            return
        }
        guard workspace != nil else { return }
        running = true; status = "Removing the temporary motion movie…"
        task = Task { [self] in
            if await removeOwned() { status = "Motion preview closed. Temporary movie removed." }
            running = false; task = nil
        }
    }
    func invalidate() { close() }
    func cancel() { close() }
    func retryCleanup() { guard !running, cleanupFailed else { return }; close() }
    func finishClosing() async -> Bool {
        close()
        let pending = task
        await pending?.value
        return workspace == nil
    }
    func render(source: URL, configuration: EncodeConfiguration, time: Double, tools: FFmpegTools?) {
        guard !running, !cleanupFailed else { return }
        guard let tools else { status = "FFmpeg and ffprobe are required for motion comparison."; return }
        let id = UUID(); generation = id; detach(); running = true
        status = "Preparing motion comparison…"
        task = Task { [self] in
            defer {
                running = false; task = nil
                if generation != id && !cleanupFailed { status = "Motion preview cancelled. Temporary movie removed." }
            }
            guard await removeOwned(), generation == id, !Task.isCancelled else { return }
            do {
                let owned = try MotionWorkspace.create(); workspace = owned
                let rendered = try await renderer(source, configuration, time, tools, owned) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == id, self.running, !self.cleaning else { return }
                        self.status = message
                    }
                }
                guard generation == id, !Task.isCancelled else {
                    if await removeOwned() { status = "Motion preview cancelled. Temporary movie removed." }
                    return
                }
                let playback = AVPlayer(url: owned.movie); playback.isMuted = true; playback.allowsExternalPlayback = false
                player = playback; result = rendered
                observePlayback(playback, generation: id)
                status = "Motion comparison ready. One shared timeline; no audio."
            } catch {
                let message = error is CancellationError || generation != id ? "Motion preview cancelled." : error.localizedDescription
                if await removeOwned() { status = message }
            }
        }
    }
}

struct MotionComparisonView: View {
    @EnvironmentObject var model: WorkspaceModel
    @EnvironmentObject var motion: MotionPreviewController
    @Binding var time: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Source time (seconds)")
                TextField("Seconds", value: $time, format: .number).frame(width: 110)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Motion preview source time in seconds")
                Button("Render motion") {
                    if let source = model.sourceURL { motion.render(source: source, configuration: model.config, time: time, tools: FFmpegTools.discover()) }
                }.disabled(motion.running || motion.cleanupFailed || model.sourceURL == nil)
                if motion.running { Button("Cancel motion") { motion.cancel() } }
                if motion.cleanupFailed { Button("Retry cleanup") { motion.retryCleanup() } }
            }
            if motion.running { ProgressView().controlSize(.small) }
            Text(motion.status).font(.callout).textSelection(.enabled)
                .accessibilityLabel("Motion comparison status").accessibilityValue(motion.status)
            HStack {
                Label("Original", systemImage: "film").frame(maxWidth: .infinity)
                Label("Filtered", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
            }.font(.headline)
            if let player = motion.player, let result = motion.result {
                NativeVideoPreview(player: player, comparisonControls: true).frame(height: 275)
                    .accessibilityLabel("Silent original and filtered motion comparison")
                HStack(spacing: 12) {
                    Button("Previous comparison frame", systemImage: "backward.end") { motion.step(.previous) }
                        .labelStyle(.iconOnly).disabled(!motion.canStepBack)
                        .help("Move to the preceding verified comparison frame.")
                    Button(motion.isPlaying ? "Pause comparison" : "Play comparison", systemImage: motion.isPlaying ? "pause.fill" : "play.fill") { motion.togglePlayback() }
                        .labelStyle(.iconOnly).disabled(motion.seeking).keyboardShortcut(.space, modifiers: [])
                    Button("Next comparison frame", systemImage: "forward.end") { motion.step(.next) }
                        .labelStyle(.iconOnly).disabled(!motion.canStepForward)
                        .help("Move to the next verified comparison frame, including variable frame rates.")
                    Slider(value: Binding(get: { motion.playhead }, set: { motion.seek(seconds: $0) }), in: 0...max(0.001, motion.lastTime))
                        .disabled(result.frames.count < 2).accessibilityLabel("Comparison timeline")
                        .help("Seek both pictures together. Seeking pauses playback and selects the nearest verified frame.")
                    Text("Frame \(motion.currentFrame + 1) of \(result.frames.count)")
                        .font(.caption.monospacedDigit()).frame(minWidth: 100, alignment: .trailing)
                }
                Text(String(format: "%d matching frames · Source %.6f–%.6f s", result.frames.count, result.frames.first!.stamp.seconds, result.frames.last!.stamp.seconds))
                    .font(.caption.monospacedDigit())
                Text(result.operations).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 38))
                    Text("See your picture settings in motion.")
                    Text("A silent sample, two views, one playback timeline.").font(.callout)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 275)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            Label("Silent viewing proxy · Picture filters only, not final encoding quality", systemImage: "speaker.slash")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Preview limits and rendering details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A source interval of up to 3 seconds and 600 frames. Playback may include a final frame tail of up to 250 ms. Both pictures fit into a 1280 × 360 H.264 proxy with even-pixel rounding. Use Still for pixel inspection. Color is not calibrated.")
                    Text("Rendering reads from the beginning to preserve filter history. A two-minute limit requests cancellation; cleanup waits for the encoder and file operations to finish.")
                }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.font(.caption)
        }
    }
}
