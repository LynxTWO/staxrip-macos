import AVFoundation

import SwiftUI
import AppKit

struct AudioSettings: Equatable {
    var format = "FLAC"
    var bitrate = 192
    var sampleRate = 48000
    var channels = 0
    var normalize = false
    var targetLUFS = -16.0
    var targetLRA = 11.0
    var loudnessMode = "Smart master"
    var fileExtension: String { ["AAC": "m4a", "Opus": "opus", "FLAC": "flac", "WAV": "wav"][format] ?? "" }
    var codec: String { ["AAC": "aac", "Opus": "opus", "FLAC": "flac", "WAV": "pcm_s24le"][format] ?? "" }
}

struct LoudnessReport: Decodable {
    let input_i: String
    let input_tp: String
    let input_lra: String
    let input_thresh: String
    let target_offset: String
    static func parse(_ data: Data) throws -> LoudnessReport {
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.range(of: "{", options: .backwards), let end = text.range(of: "}", options: .backwards), start.lowerBound < end.upperBound else {
            throw NativeExportError.invalid("The audio tool did not return a loudness report.")
        }
        return try JSONDecoder().decode(Self.self, from: Data(text[start.lowerBound..<end.upperBound].utf8))
    }
}

struct AudioEngine {
    static func analyze(source: URL, track: Int, tools: FFmpegTools, filter: String = "loudnorm=print_format=json") async throws -> LoudnessReport {
        let probe = try await MediaProbe.read(source, tools: tools)
        guard probe.streams.contains(where: { $0.index == track && $0.codec_type == "audio" }) else { throw NativeExportError.invalid("Select an available audio track.") }
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-hide_banner", "-nostdin", "-nostats", "-protocol_whitelist", "file,pipe", "-i", source.path, "-map", "0:\(track)", "-vn", "-sn", "-dn", "-af", filter, "-f", "null", "-"])
        guard result.status == 0 else { throw NativeExportError.invalid(String(decoding: result.stderr, as: UTF8.self)) }
        return try LoudnessReport.parse(result.stderr)
    }

    @discardableResult
    static func export(source: URL, track: Int, destination: URL, settings: AudioSettings, tools: FFmpegTools, progress: @escaping @Sendable (Double) -> Void) async throws -> LoudnessReport? {
        guard ["AAC", "Opus", "FLAC", "WAV"].contains(settings.format), [128, 192, 256, 320].contains(settings.bitrate),
              [44100, 48000, 96000].contains(settings.sampleRate), [0, 1, 2].contains(settings.channels),
              settings.targetLUFS.isFinite, (-36 ... -9).contains(settings.targetLUFS),
              settings.targetLRA.isFinite, (1...20).contains(settings.targetLRA),
              ["Smart master", "Night / Venue"].contains(settings.loudnessMode),
              settings.format != "Opus" || settings.sampleRate == 48000 else { throw NativeExportError.invalid("Unsupported audio configuration. Opus uses 48 kHz output.") }
        guard source.isFileURL, destination.isFileURL, source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath(), !FileManager.default.fileExists(atPath: destination.path) else { throw NativeExportError.invalid("Choose a new output file; existing files are never replaced.") }
        let probe = try await MediaProbe.read(source, tools: tools)
        guard let stream = probe.streams.first(where: { $0.index == track && $0.codec_type == "audio" }), let channelCount = stream.channels, channelCount > 0 else { throw NativeExportError.invalid("The selected audio track is unavailable or has an unknown channel count.") }
        // Multichannel exports need a tested speaker-layout contract, not just a count.
        guard channelCount <= 2 else { throw NativeExportError.invalid("Audio Lab export currently accepts mono or stereo sources. Multichannel routing needs an explicit channel map.") }
        try Task.checkCancellation()
        let outputChannels = settings.channels == 0 ? channelCount : settings.channels
        let conversion = "aresample=\(settings.sampleRate),aformat=channel_layouts=\(outputChannels == 1 ? "mono" : "stereo")"
        var normalization: String?
        if settings.normalize {
            let target = "I=\(settings.targetLUFS):TP=-1.5:LRA=\(settings.targetLRA)"
            let mastering = settings.loudnessMode == "Night / Venue" ? ",acompressor=threshold=0.0630957:ratio=4:attack=20:release=250:knee=4:makeup=1:link=maximum:detection=rms" : ""
            let preprocessing = conversion + mastering
            let measured = try await analyze(source: source, track: track, tools: tools, filter: preprocessing + ",loudnorm=" + target + ":print_format=json")
            let fields = [measured.input_i, measured.input_tp, measured.input_lra, measured.input_thresh, measured.target_offset]
            guard fields.allSatisfy({ Double($0)?.isFinite == true }) else {
                throw NativeExportError.invalid("This track is silent or too short to measure reliably. Export without normalization or select measurable audio.")
            }
            // Only validated numbers enter the filter string; no metadata or user text is interpreted.
            let values = fields.map { String(Double($0)!) }
            normalization = preprocessing + ",loudnorm=" + target + ":measured_I=\(values[0]):measured_TP=\(values[1]):measured_LRA=\(values[2]):measured_thresh=\(values[3]):offset=\(values[4]):linear=\(settings.loudnessMode == "Smart master" ? "true" : "false")"
            try Task.checkCancellation()
        }
        let folder = destination.deletingLastPathComponent().appendingPathComponent(".staxrip-audio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let staged = folder.appendingPathComponent("encoded." + settings.fileExtension)
        var args = ["-hide_banner", "-v", "error", "-nostdin", "-n", "-progress", "pipe:1", "-protocol_whitelist", "file,pipe", "-i", source.path, "-map", "0:\(track)", "-vn", "-sn", "-dn", "-map_metadata", "-1", "-map_chapters", "-1", "-ar", String(settings.sampleRate)]
        if settings.channels > 0 { args += ["-ac", String(settings.channels)] }
        if let normalization { args += ["-af", normalization] }
        switch settings.format {
        case "AAC": args += ["-c:a", "aac", "-b:a", "\(settings.bitrate)k", "-movflags", "+faststart"]
        case "Opus": args += ["-c:a", "libopus", "-b:a", "\(settings.bitrate)k"]
        case "FLAC": args += ["-c:a", "flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24"]
        default: args += ["-c:a", "pcm_s24le"]
        }
        args += [staged.path]
        let parser = ProgressParser(duration: probe.seconds, update: progress)
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: args) { parser.accept($0) }
        guard result.status == 0 else { throw NativeExportError.invalid(String(decoding: result.stderr, as: UTF8.self)) }
        try Task.checkCancellation()
        let actual = try await MediaProbe.read(staged, tools: tools)
        guard actual.streams.count == 1, let audio = actual.streams.first, audio.codec_type == "audio", audio.codec_name == settings.codec,
              audio.channels == (settings.channels == 0 ? channelCount : settings.channels), audio.sample_rate == String(settings.sampleRate), actual.seconds > 0,
              probe.seconds <= 0 || abs(actual.seconds - probe.seconds) < max(0.25, probe.seconds * 0.01) else { throw NativeExportError.invalid("The exported audio did not match its codec, channel count, sample rate or duration contract.") }
        var verifiedReport: LoudnessReport?
        if settings.normalize {
            let measured = try await analyze(source: staged, track: 0, tools: tools)
            try verifyNormalized(measured, target: settings.targetLUFS, maximumLRA: settings.targetLRA)
            verifiedReport = measured
        }
        try Task.checkCancellation()
        try ExportPublication.publish(staged: staged, destination: destination)
        return verifiedReport
    }

    static func verifyNormalized(_ report: LoudnessReport, target: Double, maximumLRA: Double? = nil) throws {
        guard let integrated = Double(report.input_i), integrated.isFinite,
              let peak = Double(report.input_tp), peak.isFinite,
              abs(integrated - target) <= 0.5, peak <= -1.0 else {
            throw NativeExportError.invalid("Normalized output did not meet the target within ±0.5 LU or exceeded the −1 dBTP verification ceiling. No output was published. Try a lower target or a lossless format.")
        }
        if let maximumLRA {
            guard let range = Double(report.input_lra), range.isFinite, range <= maximumLRA + 1 else {
                throw NativeExportError.invalid("The encoded loudness range exceeds the requested maximum by more than 1 LU. No output was published. Try Night / Venue mode or a wider range.")
            }
        }
    }
}

@MainActor
final class AudioController: ObservableObject {
    @Published var source: URL? { didSet { if source != oldValue { invalidateMaster(); masterSettings.speechConfirmed = false } } }
    @Published var probe: MediaProbe?
    @Published var track = -1 { didSet { if track != oldValue { invalidateMaster(); masterSettings.speechConfirmed = false } } }
    @Published var settings = AudioSettings()
    @Published var running = false
    @Published var status = "Open an audio file or a video containing audio."
    @Published var progress = 0.0
    @Published var report: LoudnessReport?
    @Published var outputReport: LoudnessReport?
    @Published var channelReports: [ChannelLoudness] = []
    @Published var dialogueSelection = DialogueSelection()
    @Published var dialogueReport: LoudnessReport?
    @Published var analysisReport: AnalysisReport?
    @Published var analysisSourceVerified = false
    @Published var analysisLayout = "metadata" { didSet { if analysisLayout != oldValue { invalidateMaster(); masterSettings.speechConfirmed = false } } }
    @Published var speechInputs: [SpeechIntervalDraft] = [] { didSet { if speechInputs != oldValue { invalidateMaster(); masterSettings.speechConfirmed = false } } }
    @Published var output: URL?
    @Published var masterSettings = MasterSettings() { didSet { if masterSettings != oldValue { invalidateMaster() } } }
    @Published var masterPlan: GainPlan?
    @Published var masterCandidate: MasterCandidate?
    @Published var masterSaved: URL?
    @Published var previewStart = 0.0
    @Published var previewLength = 30.0
    @Published var previewReady = false
    @Published var previewProcessed = false
    @Published var previewMatched = false
    @Published var previewPosition = 0.0
    @Published var previewPlaying = false
    @Published var previewMatchDescription = "Build an excerpt before listening."
    let masterPlayer = AVPlayer()
    var previewURLs: [URL] = []
    var previewVolumes: [Float] = []
    var previewSafeVolume: Float = 1
    var masterGeneration = UUID()
    var previewGeneration = UUID()
    var previewObserver: Any?
    private var task: Task<Void, Never>?
    var tracks: [MediaProbe.Stream] { probe?.streams.filter { $0.codec_type == "audio" } ?? [] }

    func load(_ url: URL, tools: FFmpegTools) {
        guard !running else { return }
        analysisReport = nil; analysisSourceVerified = false; speechInputs = []; analysisLayout = "metadata"
        source = nil; probe = nil; track = -1; report = nil; output = nil; outputReport = nil; channelReports = []; dialogueReport = nil
        perform("Inspecting audio…") {
            let probe = try await MediaProbe.read(url, tools: tools)
            guard let first = probe.streams.first(where: { $0.codec_type == "audio" }) else { throw NativeExportError.invalid("This file has no audio tracks.") }
            self.source = url; self.probe = probe; self.track = first.index
            self.status = "Ready · \(self.tracks.count) audio tracks"
        }
    }
    func analyze(tools: FFmpegTools) {
        guard let source, track >= 0, !running else { return }
        let selected = track
        report = nil
        perform("Measuring the selected track…") {
            self.report = try await AudioEngine.analyze(source: source, track: selected, tools: tools)
            self.status = "Source loudness measured · no media changed"
        }
    }
    func auditChannels(tools: FFmpegTools) {
        guard let source, track >= 0, !running else { return }
        let selected = track
        channelReports = []
        perform("Measuring each decoded channel; this requires one pass per channel…") {
            self.channelReports = try await AudioAudit.channels(source: source, track: selected, tools: tools)
            self.status = "Channel measurements complete; these are individual mono measurements, not additive programme LUFS."
        }
    }
    func measureDialogue(tools: FFmpegTools) {
        guard let source, track >= 0, !running else { return }
        let selected = track, range = dialogueSelection
        dialogueReport = nil
        perform("Measuring the selected dialogue passage…") {
            self.dialogueReport = try await AudioAudit.dialogue(source: source, track: selected, selection: range, tools: tools)
            self.status = "Selected passage measured. Speech content is user-identified, not automatically detected."
        }
    }
    func export(to destination: URL, tools: FFmpegTools) {
        guard let source, track >= 0, !running else { return }
        let selected = track, settings = settings
        output = nil; outputReport = nil
        perform(settings.normalize ? "Measuring, normalizing and verifying audio…" : "Encoding audio…") {
            self.outputReport = try await AudioEngine.export(source: source, track: selected, destination: destination, settings: settings, tools: tools) { value in
                Task { @MainActor in self.progress = value }
            }
            self.output = destination; self.progress = 1; self.status = settings.normalize ? "Verified audio export complete · \(settings.targetLUFS) LUFS ±0.5 · LRA ≤ \(settings.targetLRA + 1) LU · true peak ≤ −1 dBTP" : "Verified audio export complete"
        }
    }
    func measuredAnalysis(tools: FFmpegTools) {
        guard let source, !running, let rate = Int(tracks.first(where: { $0.index == track })?.sample_rate ?? "") else { return }
        let selected = track, inputs = speechInputs, declaredLayout = analysisLayout == "metadata" ? nil : analysisLayout
        analysisReport = nil; analysisSourceVerified = false
        perform("Hashing source, then measuring decoded audio…") {
            let intervals = try inputs.map { try $0.region(rate: rate) }.sorted { $0.startFrame < $1.startFrame }
            self.analysisReport = try await MeasuredAnalysis.run(source: source, track: selected, regions: intervals, tools: tools, declaredLayout: declaredLayout) { value in
                Task { @MainActor in self.progress = value }
            }
            self.analysisSourceVerified = true
            self.status = "Measured report ready · source fingerprint verified · no gain applied"
        }
    }
    func saveAnalysis(to url: URL) {
        guard let report = analysisReport, !running else { return }
        perform("Saving measured report…") {
            let save = Task.detached { try report.save(to: url) }
            try await withTaskCancellationHandler { try await save.value } onCancel: { save.cancel() }
            self.status = "Report saved locally without source paths · existing files preserved"
        }
    }
    func openAnalysis(_ url: URL) {
        guard !running else { return }
        analysisReport = nil; analysisSourceVerified = false
        perform("Opening measured report…") {
            let opening = Task.detached { try AnalysisReport.read(url) }
            self.analysisReport = try await withTaskCancellationHandler { try await opening.value } onCancel: { opening.cancel() }
            self.status = "Saved report opened · source not yet verified · report cannot drive processing"
        }
    }
    func verifyAnalysisSource() {
        guard let source, let report = analysisReport, !running else { return }
        analysisSourceVerified = false
        perform("Checking source SHA-256…") {
            guard try await SourceFingerprint.read(source) == report.source, self.track == report.track else {
                throw NativeExportError.invalid("Source or selected track differs from this report. Reanalyze before using its measurements.")
            }
            self.analysisSourceVerified = true
            self.status = "Source and selected track match the saved report"
        }
    }
    func cancel() { task?.cancel() }
    func perform(_ message: String, operation: @escaping @MainActor () async throws -> Void) {
        running = true; status = message; progress = 0
        task = Task {
            defer { running = false; task = nil }
            do { try await operation() }
            catch is CancellationError { status = "Cancelled · no output published" }
            catch { status = error.localizedDescription }
        }
    }
}
