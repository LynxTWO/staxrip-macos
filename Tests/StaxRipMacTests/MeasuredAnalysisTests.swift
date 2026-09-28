import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct MeasuredAnalysisTests {
    private func feed(_ meter: StreamingLoudness, seconds: Double, peakDB: Double?, frequency: Double = 1000, chunk: Int = 2048) throws {
        let length = Int(seconds*Double(meter.rate)), start = meter.frames
        for first in stride(from: 0, to: length, by: chunk) {
            let count = min(chunk, length-first)
            var values = [Double](); values.reserveCapacity(count*meter.channels)
            for frame in first..<(first+count) {
                let x = peakDB.map { pow(10,$0/20)*sin(2 * .pi * frequency * Double(start+Int64(frame))/Double(meter.rate)) } ?? 0
                values.append(contentsOf: repeatElement(x, count: meter.channels))
            }
            try meter.push(values)
        }
    }
    @Test(arguments: [44100,48000,88200,96000,192000])
    func knownStereoToneAndPartitionInvariance(rate: Int) throws {
        let a = try StreamingLoudness(rate: rate, channels: 2), b = try StreamingLoudness(rate: rate, channels: 2)
        try feed(a, seconds: 3.1, peakDB: -23, chunk: 1024)
        try feed(b, seconds: 3.1, peakDB: -23, chunk: 997)
        let first = a.finish(), second = b.finish()
        #expect(abs(try #require(first.integrated.value) + 23) <= 0.1)
        #expect(abs(try #require(first.truePeak.value) + 23) <= 0.2)
        #expect(first == second)
        #expect(a.finish() == first)
        #expect(throws: (any Error).self) { try a.push([0,0]) }
    }
    @Test func gatesSilenceAndQuietPassages() throws {
        let meter = try StreamingLoudness(rate: 48000, channels: 2)
        try feed(meter, seconds: 5, peakDB: nil)
        try feed(meter, seconds: 5, peakDB: -50)
        try feed(meter, seconds: 15, peakDB: -23)
        try feed(meter, seconds: 5, peakDB: -50)
        let result = meter.finish()
        #expect(abs(try #require(result.integrated.value)+23) <= 0.1)
        #expect(try #require(result.range.value) >= 0) // Transitions affect LRA even when quiet passages are gated.
    }
    @Test func loudnessRangeAndIndependentMonoWeight() throws {
        let stereo = try StreamingLoudness(rate: 48000, channels: 2)
        try feed(stereo, seconds: 20, peakDB: -20); try feed(stereo, seconds: 20, peakDB: -30)
        #expect(abs(try #require(stereo.finish().range.value)-10) <= 1)
        let mono = try StreamingLoudness(rate: 48000, channels: 1)
        try feed(mono, seconds: 3, peakDB: -23)
        #expect(abs(try #require(mono.finish().integrated.value) + 26.01) <= 0.1)
    }
    @Test func unavailableAndHostilePCM() throws {
        let silence = try StreamingLoudness(rate: 48000, channels: 1)
        try feed(silence, seconds: 4, peakDB: nil)
        let result = silence.finish()
        #expect(result.integrated.value == nil && result.integrated.unavailable != nil)
        #expect(result.truePeak.value == nil && result.range.value == nil)
        let short = try StreamingLoudness(rate: 48000, channels: 1)
        try feed(short, seconds: 0.2, peakDB: -10)
        #expect(short.finish().integrated.value == nil)
        #expect(throws: (any Error).self) { _ = try StreamingLoudness(rate: 8000, channels: 1) }
        #expect(throws: (any Error).self) { _ = try StreamingLoudness(rate: 48000, channels: 6) }
        let invalid = try StreamingLoudness(rate: 48000, channels: 2)
        #expect(throws: (any Error).self) { try invalid.push([0]) }
        #expect(throws: (any Error).self) { try invalid.push([.nan, 0]) }
    }
    private func fixture(seconds: Int = 6) async throws -> (URL, URL, FFmpegTools) {
        let tools = try #require(FFmpegTools.discover())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("measured-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let source = folder.appendingPathComponent("generated.flac")
        let run = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v","error","-f","lavfi","-i",
            "aevalsrc=0.1*sin(2*PI*1000*t)|0.1*sin(2*PI*1000*t):s=48000:d=\(seconds)","-c:a","flac",source.path])
        #expect(run.status == 0)
        return (folder,source,tools)
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func decoderCrosscheckRegionsAndReportRoundtrip() async throws {
        let (folder,source,tools) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let region = SpeechRegion(startFrame: 48000, endFrame: 48000*5)
        let report = try await MeasuredAnalysis.run(source: source, track: 0, regions: [region], tools: tools) { _ in }
        #expect(report.programme.frames == 48000*6)
        let passageFrames = try #require(report.speech.first?.result.frames)
        #expect(passageFrames == Int64(48000)*4)
        #expect(abs(try #require(report.programme.integrated.value) - #require(report.speech.first?.result.integrated.value)) < 0.01)
        #expect(abs(try #require(report.programme.integrated.value) - #require(report.channels[0].integrated.value)-3.0103) < 0.001)
        let independent = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-hide_banner","-i",source.path,"-af","apad=pad_dur=1.5,ebur128=peak=true","-f","null","-"])
        let log = String(decoding: independent.stderr, as: UTF8.self)
        let summary = try #require(log.components(separatedBy: "Summary:").last)
        func number(_ pattern: String) throws -> Double {
            let regex = try NSRegularExpression(pattern: pattern)
            let match = try #require(regex.firstMatch(in: summary, range: NSRange(summary.startIndex..., in: summary)))
            let range = try #require(Range(match.range(at: 1), in: summary))
            return try #require(Double(summary[range]))
        }
        #expect(abs(try #require(report.programme.integrated.value) - number("I:\\s+(-?[0-9.]+)")) <= 0.15)
        #expect(abs(try #require(report.programme.truePeak.value) - number("Peak:\\s+(-?[0-9.]+)")) <= 0.2)
        #expect(abs(try #require(report.programme.range.value) - number("LRA:\\s+(-?[0-9.]+)")) <= 1)
        let destination = folder.appendingPathComponent("report.json")
        try report.save(to: destination)
        #expect(try AnalysisReport.read(destination) == report)
        #expect(throws: (any Error).self) { try report.save(to: destination) }
        #expect(throws: (any Error).self) { try report.save(to: source) }
        #expect(try await SourceFingerprint.read(source) == report.source)
        let saved = try Data(contentsOf: destination)
        #expect(!String(decoding: saved, as: UTF8.self).contains(folder.path))
        var json = try #require(JSONSerialization.jsonObject(with: saved) as? [String:Any])
        json["schemaVersion"] = 99
        let hostile = folder.appendingPathComponent("hostile.json")
        try JSONSerialization.data(withJSONObject: json).write(to: hostile)
        #expect(throws: (any Error).self) { try AnalysisReport.read(hostile) }
        try Data("replacement".utf8).write(to: source)
        #expect(try await SourceFingerprint.read(source) != report.source)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".staxrip-report-") })
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func cancellationAndDecoderFailuresPreserveSource() async throws {
        let (folder,source,tools) = try await fixture(seconds: 30)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try await SourceFingerprint.read(source)
        let task = Task { try await MeasuredAnalysis.run(source: source, track: 0, regions: [], tools: tools) { _ in } }
        try await Task.sleep(for: .milliseconds(200))
        let start = Date(); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 5)
        let missing = FFmpegTools(ffmpeg: folder.appendingPathComponent("missing"), ffprobe: tools.ffprobe)
        await #expect(throws: (any Error).self) { try await MeasuredAnalysis.run(source: source, track: 0, regions: [], tools: missing) { _ in } }
        await #expect(throws: (any Error).self) { try await MeasuredAnalysis.run(source: source, track: 99, regions: [], tools: tools) { _ in } }
        await #expect(throws: (any Error).self) { try await MeasuredAnalysis.run(source: source, track: 0, regions: [SpeechRegion(startFrame: -1, endFrame: 20)], tools: tools) { _ in } }
        #expect(try await SourceFingerprint.read(source) == original)
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func reportRejectsMalformedTimelineAndLayoutNeedsConsent() async throws {
        let (folder,source,tools) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wave = folder.appendingPathComponent("legacy.wav")
        let decoded = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v","error","-i",source.path,"-c:a","pcm_s16le",wave.path])
        #expect(decoded.status == 0)
        let probe = try await MediaProbe.read(wave, tools: tools)
        #expect(probe.streams.first?.channel_layout == nil)
        await #expect(throws: (any Error).self) { try await MeasuredAnalysis.run(source: wave, track: 0, regions: [], tools: tools) { _ in } }
        let report = try await MeasuredAnalysis.run(source: wave, track: 0, regions: [], tools: tools, declaredLayout: "stereo") { _ in }
        #expect(report.decodingPolicy.contains("explicit user declaration"))
        let encoded = try JSONEncoder().encode(report)
        let original = try #require(JSONSerialization.jsonObject(with: encoded) as? [String:Any])
        for kind in ["flags", "nan", "frames", "channels", "fingerprint"] {
            var json = original
            var programme = try #require(json["programme"] as? [String:Any])
            if kind == "flags" || kind == "nan" {
                let encodedTrace = try #require(programme["traceData"] as? String)
                var trace = try #require(Data(base64Encoded: encodedTrace))
                if kind == "flags" { trace[8] = 255 }
                else { var bits = Double.nan.bitPattern.littleEndian; withUnsafeBytes(of: &bits) { trace.replaceSubrange(9..<17, with: $0) } }
                programme["traceData"] = trace.base64EncodedString()
            }
            if kind == "frames" { programme["frames"] = Int64.max }
            if kind == "channels" { json["channelLabels"] = ["FL","FR","LFE"] }
            if kind == "fingerprint" { json["source"] = ["sha256":"wrong", "byteCount":1] }
            json["programme"] = programme
            let path = folder.appendingPathComponent(kind+".json")
            try JSONSerialization.data(withJSONObject: json).write(to: path)
            #expect(throws: (any Error).self) { try AnalysisReport.read(path) }
        }
        #expect(throws: (any Error).self) { try report.save(to: folder.appendingPathComponent("missing/report.json")) }
        let corrupt = folder.appendingPathComponent("corrupt.flac")
        try Data("not media".utf8).write(to: corrupt)
        await #expect(throws: (any Error).self) { try await MeasuredAnalysis.run(source: corrupt, track: 0, regions: [], tools: tools) { _ in } }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_LONG_ANALYSIS"] == "1"))
    func twoHourStreamingProfile() async throws {
        let duration = 7200
        let (folder,source,tools) = try await fixture(seconds: duration)
        defer { try? FileManager.default.removeItem(at: folder) }
        func memory(_ phase: String) { var info = rusage(); _ = getrusage(RUSAGE_SELF, &info); print("PROFILE \(phase) peakResidentBytes=\(info.ru_maxrss)") }
        memory("fixture ready")
        let start = Date()
        let report = try await MeasuredAnalysis.run(source: source, track: 0, regions: [], tools: tools) { _ in }
        memory("analysis complete")
        #expect(report.programme.frames == Int64(duration)*48000)
        #expect(abs(try #require(report.programme.integrated.value)+20) < 0.1)
        let output = folder.appendingPathComponent("long-report.json")
        try report.save(to: output)
        memory("save complete")
        let reopened = try AnalysisReport.read(output)
        memory("reopen complete")
        let roundtripMatches = reopened == report
        #expect(roundtripMatches)
        var usage = rusage()
        #expect(getrusage(RUSAGE_SELF, &usage) == 0)
        print("TWO_HOUR_PROFILE seconds=\(Date().timeIntervalSince(start)) peakResidentBytes=\(usage.ru_maxrss) frames=\(report.programme.frames) tracePoints=\(report.programme.trace.count)")
        #expect(usage.ru_maxrss < 512*1024*1024)
    }

}
