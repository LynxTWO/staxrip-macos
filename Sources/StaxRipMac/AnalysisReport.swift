import Foundation
import CryptoKit

struct SpeechRegion: Codable, Equatable, Sendable {
    let startFrame: Int64
    let endFrame: Int64
}
struct RegionMeasurement: Codable, Equatable, Sendable {
    let region: SpeechRegion
    let result: MeterSummary
}
struct SourceFingerprint: Codable, Equatable, Sendable {
    let sha256: String
    let byteCount: Int64
    static func read(_ url: URL) async throws -> SourceFingerprint {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256(), count: Int64 = 0
        while true {
            try Task.checkCancellation()
            let hadData = try autoreleasepool {
                let chunk = try handle.read(upToCount: 1024*1024) ?? Data()
                guard !chunk.isEmpty else { return false }
                hash.update(data: chunk); count += Int64(chunk.count)
                return true
            }
            if !hadData { break }
        }
        return SourceFingerprint(sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), byteCount: count)
    }
}
struct AnalysisReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let source: SourceFingerprint
    let track: Int
    let sampleRate: Int
    let channelLabels: [String]
    let decoder: String
    let decodingPolicy: String
    let algorithm: String
    let programme: MeterSummary
    let channels: [MeterSummary]
    let speech: [RegionMeasurement]
    let warnings: [String]

    func validate() throws {
        func require(_ condition: Bool) throws {
            if !condition { throw NativeExportError.invalid("Invalid or unsupported analysis report. Reanalyze the source.") }
        }
        try require(schemaVersion == 1 && (0...1024).contains(track))
        try require([44100,48000,88200,96000,192000].contains(sampleRate))
        try require(channelLabels == ["FC"] || channelLabels == ["FL", "FR"])
        try require(source.sha256.count == 64 && source.sha256.allSatisfy { "0123456789abcdef".contains($0) } && source.byteCount > 0)
        try require(!algorithm.isEmpty && algorithm.count <= 512 && !decoder.isEmpty && decoder.count <= 1024)
        try require(decodingPolicy.count <= 2048 && warnings.count <= 32 && warnings.allSatisfy { $0.count <= 2048 })
        try require(channels.count == channelLabels.count && speech.count <= 16)
        func checkValue(_ m: MeterValue, range: ClosedRange<Double>) throws {
            if let v = m.value { try require(v.isFinite && range.contains(v) && m.unavailable == nil) }
            else { try require(m.unavailable?.isEmpty == false && (m.unavailable?.count ?? 0) <= 512) }
        }
        func check(_ m: MeterSummary, traceAllowed: Bool) throws {
            try require(m.frames > 0 && m.frames <= Int64(sampleRate)*14400)
            try checkValue(m.integrated, range: -200...150); try checkValue(m.range, range: 0...200)
            try checkValue(m.samplePeak, range: -1000...150); try checkValue(m.truePeak, range: -1000...150)
            try require(m.trace.count <= Int(m.frames/Int64(sampleRate/50)))
            if !traceAllowed { try require(m.trace.isEmpty) }
            var previous: Int64 = 0
            for point in m.trace {
                try require(point.frame > previous && point.frame <= m.frames)
                for value in [point.momentary, point.shortTerm].compactMap({ $0 }) { try require(value.isFinite && (-1000...150).contains(value)) }
                if point.frame < Int64(sampleRate)*4/10 { try require(point.momentary == nil) }
                if point.frame < Int64(sampleRate)*3 { try require(point.shortTerm == nil) }
                previous = point.frame
            }
        }
        try check(programme, traceAllowed: true)
        for channel in channels { try check(channel, traceAllowed: false); try require(channel.frames == programme.frames) }
        var end: Int64 = 0
        for passage in speech {
            try require(passage.region.startFrame >= end && passage.region.endFrame > passage.region.startFrame && passage.region.endFrame <= programme.frames)
            try check(passage.result, traceAllowed: false)
            try require(passage.result.frames == passage.region.endFrame-passage.region.startFrame)
            end = passage.region.endFrame
        }
    }
    func save(to destination: URL) throws {
        try Task.checkCancellation()
        try validate()
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".staxrip-report-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 32*1024*1024 else { throw NativeExportError.invalid("Report exceeds the 32 MiB file limit.") }
        try data.write(to: staging, options: .withoutOverwriting)
        try Task.checkCancellation()
        try ExportPublication.publish(staged: staging, destination: destination)
    }
    static func read(_ url: URL) throws -> AnalysisReport {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 32*1024*1024+1) ?? Data()
        guard data.count <= 32*1024*1024 else { throw NativeExportError.invalid("Report exceeds the 32 MiB file limit.") }
        let report = try JSONDecoder().decode(Self.self, from: data)
        try report.validate()
        try Task.checkCancellation()
        return report
    }
}

// Only the stdout reader touches this consumer. Results are read after ToolRunner joins that reader.
private final class PCMAnalysisConsumer: @unchecked Sendable {
    let programme: StreamingLoudness
    let channels: [StreamingLoudness]
    let regions: [SpeechRegion]
    let passages: [StreamingLoudness]
    var pending = Data()
    var failure: Error?
    var frames: Int64 = 0
    var lastProgressFrame: Int64 = 0
    var lastProgressTime = 0.0
    var regionIndex = 0
    init(rate: Int, channels: Int, regions: [SpeechRegion]) throws {
        programme = try StreamingLoudness(rate: rate, channels: channels)
        self.channels = try (0..<channels).map { _ in try StreamingLoudness(rate: rate, channels: 1, captureTrace: false) }
        self.regions = regions
        passages = try regions.map { _ in try StreamingLoudness(rate: rate, channels: channels, captureTrace: false) }
    }
    func consume(_ data: Data) throws {
        pending.append(data)
        let bytesPerFrame = programme.channels*8
        let usable = pending.count/bytesPerFrame*bytesPerFrame
        guard usable > 0 else { return }
        var samples = [Double](repeating: 0, count: usable/8)
        pending.withUnsafeBytes { bytes in
            for i in samples.indices { samples[i] = Double(bitPattern: UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: i*8, as: UInt64.self))) }
        }
        for i in stride(from: 0, to: samples.count, by: programme.channels) {
            try programme.pushFrame(samples, offset: i)
            for channel in channels.indices { try channels[channel].pushFrame(samples, offset: i+channel) }
            while regionIndex < regions.count && frames >= regions[regionIndex].endFrame { regionIndex += 1 }
            if regionIndex < regions.count && frames >= regions[regionIndex].startFrame { try passages[regionIndex].pushFrame(samples, offset: i) }
            frames += 1
        }
        // Reset Data's backing storage, not just its visible start index. At most
        // one partial interleaved frame survives a decoder callback.
        pending = Data(Array(pending.suffix(pending.count-usable)))
    }
}

struct FreshAnalysis: Sendable {
    let report: AnalysisReport
    let speechReference: MeterValue
    let planningEnergies: [Double]
}

enum MeasuredAnalysis {
    #if DEBUG
    @TaskLocal static var consumedPCM: (@Sendable (ToolRunner) -> Void)?
    #endif
    static func run(source: URL, track: Int, regions: [SpeechRegion], tools: FFmpegTools, declaredLayout: String? = nil,
                    progress: @escaping @Sendable (Double) -> Void) async throws -> AnalysisReport {
        try await fresh(source: source, track: track, regions: regions, tools: tools, declaredLayout: declaredLayout, progress: progress).report
    }
    static func fresh(source: URL, track: Int, regions: [SpeechRegion], tools: FFmpegTools, declaredLayout: String? = nil,
                      checkedReaders: Bool = false, progress: @escaping @Sendable (Double) -> Void) async throws -> FreshAnalysis {
        let before = try await SourceFingerprint.read(source)
        let probe = try await MediaProbe.read(source, tools: tools, checkedReaders: checkedReaders)
        guard let stream = probe.streams.first(where: { $0.index == track && $0.codec_type == "audio" }),
              let rate = Int(stream.sample_rate ?? ""), let count = stream.channels else {
            throw NativeExportError.invalid("Audio stream format is unavailable.")
        }
        let layout = declaredLayout ?? stream.channel_layout
        guard (count == 1 && layout == "mono") || (count == 2 && layout == "stereo") else {
            throw NativeExportError.invalid("Analysis requires an explicitly identified mono or stereo track. Unknown or surround layouts are not inferred from channel count. Confirm mono/stereo only if you know the source layout.")
        }
        guard probe.seconds.isFinite, probe.seconds > 0, probe.seconds <= 14400, regions.count <= 16 else {
            throw NativeExportError.invalid("Analysis requires a known duration of at most four hours and at most 16 speech intervals.")
        }
        var end: Int64 = 0
        for (index, region) in regions.enumerated() {
            if Double(region.endFrame)/Double(rate) > probe.seconds+0.001 {
                throw NativeExportError.invalid("Speech interval \(index+1) ends beyond the source. Enter an end time of \(String(format: "%.2f", probe.seconds)) seconds or less.")
            }
            guard region.startFrame >= end, region.endFrame > region.startFrame, Double(region.endFrame)/Double(rate) <= probe.seconds+0.001 else {
                throw NativeExportError.invalid("Speech intervals must be ordered, non-overlapping and within the source.")
            }
            end = region.endFrame
        }
        let version = try await ToolRunner(checkedReaders: checkedReaders).run(executable: tools.ffmpeg, arguments: ["-version"])
        guard version.status == 0 else { throw NativeExportError.invalid("Cannot identify the audio decoder.") }
        let decoder = String(decoding: version.stdout, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? "FFmpeg unknown"
        #if DEBUG
        let consumed = Self.consumedPCM
        #endif
        let consumer = try PCMAnalysisConsumer(rate: rate, channels: count, regions: regions)
        let runner = ToolRunner(checkedReaders: checkedReaders)
        let result: ToolResult
        do {
            result = try await runner.run(executable: tools.ffmpeg, arguments: ["-nostdin", "-v", "error", "-xerror", "-protocol_whitelist", "file,pipe", "-i", source.path,
                "-map", "0:\(track)", "-vn", "-sn", "-dn", "-c:a", "pcm_f64le", "-f", "f64le", "pipe:1"], stdoutLimit: 0, onOutput: { data in
                guard consumer.failure == nil else { return }
                do {
                    try consumer.consume(data)
                    #if DEBUG
                    if consumer.frames > 0 { consumed?(runner) }
                    #endif
                    let now = ProcessInfo.processInfo.systemUptime
                    if consumer.frames-consumer.lastProgressFrame >= Int64(rate), now-consumer.lastProgressTime >= 0.25 {
                        consumer.lastProgressTime = now
                        consumer.lastProgressFrame = consumer.frames
                        progress(min(0.95, Double(consumer.frames)/Double(rate)/probe.seconds*0.95))
                    }
                } catch { consumer.failure = error; runner.cancel() }
            })
        } catch {
            if var unsettled = error as? ToolRunner.ReaderCloseFailure {
                unsettled.consumerCause = consumer.failure
                throw unsettled
            }
            if error is CompanionUnsettledOwnership { throw error }
            if let failure = consumer.failure { throw failure }
            throw error
        }
        if let failure = consumer.failure { throw failure }
        guard result.status == 0, consumer.pending.isEmpty, consumer.frames > 0 else {
            throw NativeExportError.invalid("Audio decoding failed or returned incomplete PCM. No report was saved.")
        }
        try Task.checkCancellation()
        guard try await SourceFingerprint.read(source) == before else { throw NativeExportError.invalid("Source changed during analysis. Reanalyze the unchanged file.") }
        let report = AnalysisReport(schemaVersion: 1, source: before, track: track, sampleRate: rate,
            channelLabels: count == 1 ? ["FC"] : ["FL", "FR"], decoder: decoder,
            decodingPolicy: "FFmpeg codec defaults, including codec-specific metadata/DRC behavior; selected stream, native sample rate, Float64 PCM, no downmix or normalization. Layout: \(layout ?? "unknown") (\(declaredLayout == nil ? "stream metadata" : "explicit user declaration")).",
            algorithm: StreamingLoudness.algorithm, programme: consumer.programme.finish(), channels: consumer.channels.map { $0.finish() },
            speech: zip(regions, consumer.passages).map { RegionMeasurement(region: $0, result: $1.finish()) },
            warnings: ["Research meter: official conformance evidence is tracked separately; not certified.",
                "Speech intervals are user-selected mixtures, not detected or isolated dialogue. Each interval resets measurement state.",
                "Channel LUFS are individual mono diagnostics and cannot be added. LRA alone does not constrain sudden spikes.",
                "True peak is a 4x, 12-tap estimate. LRA includes 1.5 seconds terminal silence; traces stop at the source end."])
        try report.validate(); progress(1)
        return FreshAnalysis(report: report, speechReference: StreamingLoudness.pooledIntegrated(consumer.passages.flatMap(\.integratedBlockEnergies)), planningEnergies: consumer.programme.planningEnergies)
    }
}
