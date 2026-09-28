import SwiftUI
import AppKit

struct AudioSettings: Equatable {
    var format = "FLAC"
    var bitrate = 192
    var sampleRate = 48000
    var channels = 0
    var normalize = false
    var targetLUFS = -16
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

    static func export(source: URL, track: Int, destination: URL, settings: AudioSettings, tools: FFmpegTools, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard ["AAC", "Opus", "FLAC", "WAV"].contains(settings.format), [128, 192, 256, 320].contains(settings.bitrate),
              [44100, 48000, 96000].contains(settings.sampleRate), [0, 1, 2].contains(settings.channels),
              [-23, -16, -14].contains(settings.targetLUFS),
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
            let target = "I=\(settings.targetLUFS):TP=-1.5:LRA=11"
            let measured = try await analyze(source: source, track: track, tools: tools, filter: conversion + ",loudnorm=" + target + ":print_format=json")
            let fields = [measured.input_i, measured.input_tp, measured.input_lra, measured.input_thresh, measured.target_offset]
            guard fields.allSatisfy({ Double($0)?.isFinite == true }) else {
                throw NativeExportError.invalid("This track is silent or too short to measure reliably. Export without normalization or select measurable audio.")
            }
            // Only validated numbers enter the filter string; no metadata or user text is interpreted.
            let values = fields.map { String(Double($0)!) }
            normalization = conversion + ",loudnorm=" + target + ":measured_I=\(values[0]):measured_TP=\(values[1]):measured_LRA=\(values[2]):measured_thresh=\(values[3]):offset=\(values[4]):linear=true"
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
        if settings.normalize {
            let measured = try await analyze(source: staged, track: 0, tools: tools)
            try verifyNormalized(measured, target: settings.targetLUFS)
        }
        try Task.checkCancellation()
        try ExportPublication.publish(staged: staged, destination: destination)
    }

    static func verifyNormalized(_ report: LoudnessReport, target: Int) throws {
        guard let integrated = Double(report.input_i), integrated.isFinite,
              let peak = Double(report.input_tp), peak.isFinite,
              abs(integrated - Double(target)) <= 0.5, peak <= -1.0 else {
            throw NativeExportError.invalid("Normalized output did not meet the target within ±0.5 LU or exceeded the −1 dBTP verification ceiling. No output was published. Try a lower target or a lossless format.")
        }
    }
}

@MainActor
final class AudioController: ObservableObject {
    @Published var source: URL?
    @Published var probe: MediaProbe?
    @Published var track = -1
    @Published var settings = AudioSettings()
    @Published var running = false
    @Published var status = "Open an audio file or a video containing audio."
    @Published var progress = 0.0
    @Published var report: LoudnessReport?
    @Published var output: URL?
    private var task: Task<Void, Never>?
    var tracks: [MediaProbe.Stream] { probe?.streams.filter { $0.codec_type == "audio" } ?? [] }

    func load(_ url: URL, tools: FFmpegTools) {
        guard !running else { return }
        source = nil; probe = nil; track = -1; report = nil; output = nil
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
    func export(to destination: URL, tools: FFmpegTools) {
        guard let source, track >= 0, !running else { return }
        let selected = track, settings = settings
        output = nil
        perform(settings.normalize ? "Measuring, normalizing and verifying audio…" : "Encoding audio…") {
            try await AudioEngine.export(source: source, track: selected, destination: destination, settings: settings, tools: tools) { value in
                Task { @MainActor in self.progress = value }
            }
            self.output = destination; self.progress = 1; self.status = settings.normalize ? "Verified audio export complete · \(settings.targetLUFS) LUFS ±0.5 · true peak ≤ −1 dBTP" : "Verified audio export complete"
        }
    }
    func cancel() { task?.cancel() }
    private func perform(_ message: String, operation: @escaping @MainActor () async throws -> Void) {
        running = true; status = message; progress = 0
        task = Task {
            defer { running = false; task = nil }
            do { try await operation() }
            catch is CancellationError { status = "Cancelled · no output published" }
            catch { status = error.localizedDescription }
        }
    }
}
