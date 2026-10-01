import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct OriginalMasteringView: View {
    @EnvironmentObject var audio: AudioController
    let busy: Bool
    let tools: FFmpegTools?
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text("ORIGINAL MASTERING · EXPERIMENTAL").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Color.accent)
            Text("Bring the room into balance.").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("A shared gain envelope, measured speech anchors and a verified lossless result. Mono or stereo, at the original sample rate.").foregroundStyle(.secondary)
            HStack(alignment: .top,spacing: 24) {
                VStack(alignment: .leading,spacing: 12) {
                    Picker("Mode",selection: $audio.masterSettings.mode) { ForEach(MasterMode.allCases,id: \.self) { Text($0.rawValue).tag($0) } }.tint(Color.primaryActionFill)
                        .onChange(of: audio.masterSettings.mode) { _,mode in audio.masterSettings.maximumLRA = mode == .night ? 3 : 11 }
                        .accessibilityHint("Smart prefers constant gain when feasible. Night reduces volume differences and checks momentary and short-term excursions.")
                    Picker("Loudness reference",selection: $audio.masterSettings.reference) { ForEach(MasterReference.allCases,id: \.self) { Text($0.rawValue).tag($0) } }.tint(Color.primaryActionFill)
                        .accessibilityHint("Whole programme targets overall loudness. Selected speech targets the combined gated energy of your confirmed intervals; music in those intervals is included.")
                    if audio.masterSettings.reference == .speech {
                        Toggle("I confirm the speech intervals above are representative",isOn: $audio.masterSettings.speechConfirmed)
                            .accessibilityHint("At least one measurable interval is required. Automatic speech detection is not used.")
                    }
                    HStack {
                        Text("Target LUFS"); TextField("Target loudness",value: $audio.masterSettings.target,format: .number)
                            .accessibilityLabel("Original mastering target loudness, in LUFS")
                    }
                    HStack {
                        Text("Maximum LRA"); TextField("Maximum range",value: $audio.masterSettings.maximumLRA,format: .number)
                            .accessibilityLabel("Original mastering maximum programme loudness range, in loudness units")
                    }
                    Button("Build fresh plan") { if let tools { audio.buildMasterPlan(tools: tools) } }.disabled(audio.source == nil || tools == nil)
                        .accessibilityHint("Measures the actual decoded audio and selected speech. Saved reports cannot drive gain.")
                }.textFieldStyle(.roundedBorder).frame(maxWidth: .infinity).disabled(busy)
                VStack(alignment: .leading,spacing: 8) {
                    Text("Processing limits").font(.headline)
                    Text("Target −36 to −9 LUFS; LRA 1–20 LU. Linked envelope −36 to +12 dB. Quiet passages hold adaptive gain. Peak limiting can add attenuation; no limiter makeup gain.")
                    Text("Encoded output must meet the chosen reference within 0.5 LU, LRA within maximum +1 LU, and true peak ≤ −1 dBTP in both meters. Three attempts maximum; failed verification prevents saving.")
                    if audio.masterSettings.mode == .night { Text("Night also limits measured short-term loudness to target +6.5 LU and momentary loudness to target +9.5 LU, including acceptance tolerance.") }
                    Text("Listening quality remains under evaluation. A 3 LU range is not a guarantee against fatigue.").foregroundStyle(.secondary)
                }.font(.caption).frame(maxWidth: .infinity,alignment: .leading)
            }
            if let plan = audio.masterPlan {
                Divider()
                Text(plan.dynamic ? "Plan: linked dynamic gain" : "Plan: constant gain").font(.headline)
                measurement("Programme reference",plan.analysis.report.programme.integrated.display+" LUFS")
                measurement("Pooled selected speech",plan.analysis.speechReference.display+" LUFS")
                measurement("Base gain",String(format: "%.2f dB",plan.baseDB))
                measurement("Applied envelope bounds before limiter",String(format: "%.2f to %.2f dB",plan.minimumDB,plan.maximumDB))
                Text("\(plan.rate) Hz · \(plan.analysis.report.channelLabels.joined(separator: ", ")) · \(plan.frames) frames").font(.caption)
                Text(plan.analysis.report.decoder+" · "+plan.analysis.report.decodingPolicy).font(.caption).foregroundStyle(.secondary)
                if let estimate = try? MasteringEngine.scratchEstimate(rate: plan.rate,channels: plan.analysis.report.channelLabels.count,seconds: Double(plan.frames)/Double(plan.rate)) {
                    Text("Estimated temporary space: \(ByteCountFormatter.string(fromByteCount: estimate,countStyle: .file)). Checked on the destination volume before rendering. Large WAV files use RF64.").font(.caption)
                }
                Button("Render verified candidate…") { chooseDestination() }.disabled(busy || tools == nil)
                    .accessibilityHint("Choose a new FLAC or WAV filename. The full candidate is staged and measured before it can be saved.")
            }
            if let candidate = audio.masterCandidate {
                Divider()
                Text("Verified candidate · \(candidate.verification.attempts) render \(candidate.verification.attempts == 1 ? "attempt" : "attempts")").font(.headline)
                measurement("Programme before / after",candidate.verification.before.integrated.display+" / "+candidate.verification.after.integrated.display+" LUFS")
                measurement("Speech before / after",candidate.verification.speechBefore.display+" / "+candidate.verification.speechAfter.display+" LUFS")
                measurement("Output range",candidate.verification.after.range.display+" LU")
                measurement("Output true peak",candidate.verification.after.truePeak.display+" dBTP")
                measurement("FFmpeg independent check",String(format: "%.1f LUFS · %.1f LU · %.1f dBTP",candidate.verification.independent.integrated,candidate.verification.independent.range,candidate.verification.independent.truePeak))
                HStack {
                    VStack(alignment: .leading) { Text("Start (source seconds)").font(.caption); TextField("Excerpt start seconds",value: $audio.previewStart,format: .number).accessibilityLabel("Comparison excerpt start, in source seconds") }
                    VStack(alignment: .leading) { Text("Duration (seconds)").font(.caption); TextField("Excerpt length seconds",value: $audio.previewLength,format: .number).accessibilityLabel("Comparison excerpt duration, from 5 to 60 seconds") }
                    Button("Build aligned excerpt") { if let tools { audio.buildMasterExcerpt(tools: tools) } }
                }.textFieldStyle(.roundedBorder).disabled(busy)
                    .onChange(of: audio.previewStart) { _,_ in audio.resetMasterPreview() }
                    .onChange(of: audio.previewLength) { _,_ in audio.resetMasterPreview() }
                Text("Excerpt length: 5–60 seconds. Changing source, intervals or settings discards the candidate; changing excerpt times discards only the preview.").font(.caption).foregroundStyle(.secondary)
                if audio.previewReady {
                    MasterAudioPlayerView(player: audio.masterPlayer).frame(height: 0).clipped().hidden().accessibilityHidden(true)
                    Picker("Listen to",selection: Binding(get: { audio.previewProcessed },set: { audio.selectMasterPreview(processed: $0) })) {
                        Text("Original").tag(false); Text("Processed").tag(true)
                    }.pickerStyle(.segmented).tint(Color.primaryActionFill).disabled(busy)
                    Toggle("Level-match this excerpt",isOn: $audio.previewMatched).disabled(busy || audio.previewVolumes.isEmpty)
                        .onChange(of: audio.previewMatched) { _,_ in audio.updateMasterVolume() }
                        .accessibilityHint("Attenuates playback only. Changing the comparison stops playback. Exported audio is unchanged.")
                    Text(audio.previewMatchDescription).font(.caption)
                    Slider(value: Binding(get: { audio.previewPosition },set: { audio.seekMasterPreview($0) }),in: 0...audio.previewLength)
                        .accessibilityLabel("Shared excerpt playback position, in seconds").disabled(busy)
                    HStack {
                        Button(audio.previewPlaying ? "Pause excerpt" : "Play excerpt") { audio.toggleMasterPlayback() }.disabled(busy)
                        Text(String(format: "%.1f / %.1f seconds",audio.previewPosition,audio.previewLength)).monospacedDigit()
                    }
                }
                HStack {
                    Button("Discard candidate") { audio.invalidateMaster() }.disabled(busy)
                    if let saved = audio.masterSaved {
                        Button("Reveal saved audio") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
                        Button("Save processing report…") { chooseReport() }.disabled(busy)
                    } else {
                        Button("Save verified audio") { audio.publishMaster() }.primaryAction().disabled(busy)
                    }
                }
            }
            if audio.running { ProgressView(); Button("Cancel original mastering",role: .cancel) { audio.cancel() }.accessibilityIdentifier("original-mastering-cancel").keyboardShortcut(.cancelAction) }
            Text(audio.status).font(.callout).textSelection(.enabled)
        }.padding(20).background(Color.accent.opacity(0.07),in: RoundedRectangle(cornerRadius: 16))
        .onDisappear { audio.pauseMasterPreview() }
    }
    private func measurement(_ label: String,_ value: String) -> some View {
        VStack(alignment: .leading) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).monospacedDigit() }
            .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value)
    }
    private func chooseDestination() {
        guard let tools,let source = audio.source else { return }
        let panel = NSSavePanel(); panel.title = "Stage original mastering candidate"
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent+"_master.flac"
        panel.allowedContentTypes = [UTType(filenameExtension: "flac") ?? .data,.wav]
        if panel.runModal() == .OK,let url = panel.url { audio.renderMaster(to: url,tools: tools) }
    }
    private func chooseReport() {
        let panel = NSSavePanel(); panel.title = "Save processing report separately"; panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "mastering-report.json"
        if panel.runModal() == .OK,let url = panel.url { audio.saveMasterReport(to: url) }
    }
}
private struct MasterAudioPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { let view = AVPlayerView(); view.controlsStyle = .none; view.player = player; return view }
    func updateNSView(_ view: AVPlayerView,context: Context) { view.player = player }
    static func dismantleNSView(_ view: AVPlayerView,coordinator: ()) { view.player?.pause(); view.player = nil }
}
