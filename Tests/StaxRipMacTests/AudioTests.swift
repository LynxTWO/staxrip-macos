import Foundation
import Testing
@testable import StaxRipMac

struct AudioTests {
    private func fixture(_ tools: FFmpegTools) async throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("audio-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let source = dir.appendingPathComponent("two-tracks.mka")
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=4", "-filter_complex", "[0:a]asplit=2[a][b];[b]volume=0.5[quiet]", "-map", "[a]", "-map", "[quiet]", "-c:a", "pcm_s16le", source.path])
        #expect(result.status == 0)
        return (dir, source)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["FLAC", "WAV", "AAC", "Opus"])
    func selectedTrackExportsWithVerifiedFormat(format: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let (dir, source) = try await fixture(tools)
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = try Data(contentsOf: source)
        var settings = AudioSettings(); settings.format = format; settings.channels = 2
        let destination = dir.appendingPathComponent("result." + settings.fileExtension)
        try await AudioEngine.export(source: source, track: 1, destination: destination, settings: settings, tools: tools) { _ in }
        let actual = try await MediaProbe.read(destination, tools: tools)
        #expect(actual.streams.count == 1)
        #expect(actual.streams.first?.codec_name == settings.codec)
        #expect(actual.streams.first?.channels == 2)
        #expect(actual.streams.first?.sample_rate == "48000")
        #expect(abs(actual.seconds - 4) < 0.15)
        #expect(try Data(contentsOf: source) == original)
        let measured = try await AudioEngine.analyze(source: destination, track: 0, tools: tools)
        let sourceMeasured = try await AudioEngine.analyze(source: source, track: 1, tools: tools)
        #expect(abs(try #require(Double(measured.input_i)) - #require(Double(sourceMeasured.input_i))) < 0.5)
        let resultBytes = try Data(contentsOf: destination)
        await #expect(throws: (any Error).self) {
            try await AudioEngine.export(source: source, track: 1, destination: destination, settings: settings, tools: tools) { _ in }
        }
        #expect(try Data(contentsOf: destination) == resultBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-audio-") })
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil)) func loudnessMeasuresSelectedTrack() async throws {
        let tools = try #require(FFmpegTools.discover())
        let (dir, source) = try await fixture(tools)
        defer { try? FileManager.default.removeItem(at: dir) }
        let loud = try await AudioEngine.analyze(source: source, track: 0, tools: tools)
        let quiet = try await AudioEngine.analyze(source: source, track: 1, tools: tools)
        let difference = try #require(Double(loud.input_i)) - #require(Double(quiet.input_i))
        #expect(abs(difference - 6.02) < 0.2)
        #expect(try #require(Double(quiet.input_tp)) < -20)
        await #expect(throws: (any Error).self) { try await AudioEngine.analyze(source: source, track: 99, tools: tools) }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["FLAC", "WAV", "AAC", "Opus"])
    func normalizedExportMeetsMeasuredTarget(format: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let (dir, source) = try await fixture(tools)
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = AudioSettings(); settings.format = format; settings.channels = 2; settings.normalize = true; settings.targetLUFS = -16
        let destination = dir.appendingPathComponent("normalized." + settings.fileExtension)
        let before = try Data(contentsOf: source)
        try await AudioEngine.export(source: source, track: 1, destination: destination, settings: settings, tools: tools) { _ in }
        let measured = try await AudioEngine.analyze(source: destination, track: 0, tools: tools)
        #expect(abs(try #require(Double(measured.input_i)) + 16) <= 0.5)
        #expect(try #require(Double(measured.input_tp)) <= -1)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil)) func silentNormalizationFailsWithoutOutput() async throws {
        let tools = try #require(FFmpegTools.discover())
        let (dir, _) = try await fixture(tools)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("silence.wav")
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", "2", source.path])
        #expect(result.status == 0)
        var settings = AudioSettings(); settings.normalize = true
        let destination = dir.appendingPathComponent("result.flac")
        await #expect(throws: (any Error).self) { try await AudioEngine.export(source: source, track: 0, destination: destination, settings: settings, tools: tools) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-audio-") })
    }

    @Test func loudnessVerificationRejectsOvershootAndNonFiniteMeasurements() {
        for (level, peak) in [("-12", "-2"), ("-16", "0.1"), ("-inf", "-inf"), ("nan", "-2")] {
            let report = LoudnessReport(input_i: level, input_tp: peak, input_lra: "0", input_thresh: "-26", target_offset: "0")
            #expect(throws: (any Error).self) { try AudioEngine.verifyNormalized(report, target: -16) }
        }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func nightMasterControlsMeasuredRange() async throws {
        let tools = try #require(FFmpegTools.discover())
        let (dir, _) = try await fixture(tools)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("wide-range.wav")
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "aevalsrc=0.3*sin(2*PI*440*t)*if(lt(mod(t\\,20)\\,10)\\,0.15\\,1):s=48000:d=60", "-c:a", "pcm_s24le", source.path])
        #expect(generated.status == 0, Comment(rawValue: String(decoding: generated.stderr, as: UTF8.self)))
        let before = try await AudioEngine.analyze(source: source, track: 0, tools: tools)
        #expect(try #require(Double(before.input_lra)) > 10)
        var settings = AudioSettings(); settings.normalize = true; settings.targetLUFS = -18.5; settings.targetLRA = 3; settings.loudnessMode = "Night / Venue"
        let destination = dir.appendingPathComponent("night.flac")
        try await AudioEngine.export(source: source, track: 0, destination: destination, settings: settings, tools: tools) { _ in }
        let after = try await AudioEngine.analyze(source: destination, track: 0, tools: tools)
        #expect(abs(try #require(Double(after.input_i)) + 18.5) <= 0.5)
        #expect(try #require(Double(after.input_lra)) <= 4)
        #expect(try #require(Double(after.input_tp)) <= -1)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func gatedMeasurementIgnoresQuietBookendsAndAuditsChannels() async throws {
        let tools = try #require(FFmpegTools.discover())
        let (dir, _) = try await fixture(tools)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("gating.wav")
        // EBU Tech 3341-style sequence: 10 s at -36 dBFS, 60 s at -23, 10 s at -36.
        let expression = "sin(2*PI*1000*t)*if(between(t\\,10\\,70)\\,0.070794578\\,0.015848932)"
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "aevalsrc=\(expression)|\(expression):s=48000:d=80:c=stereo", "-c:a", "pcm_s24le", source.path])
        #expect(generated.status == 0)
        let report = try await AudioEngine.analyze(source: source, track: 0, tools: tools)
        #expect(abs(try #require(Double(report.input_i)) + 23) <= 0.15)
        let channels = try await AudioAudit.channels(source: source, track: 0, tools: tools)
        #expect(channels.map(\.label) == ["FL", "FR"])
        #expect(abs(try #require(Double(channels[0].report.input_i)) + 26.01) < 0.2)
        #expect(channels[0].report.input_i == channels[1].report.input_i)
        let passage = try await AudioAudit.dialogue(source: source, track: 0, selection: DialogueSelection(start: 20, end: 50), tools: tools)
        #expect(abs(try #require(Double(passage.input_i)) + 23) <= 0.15)
        await #expect(throws: (any Error).self) {
            try await AudioAudit.dialogue(source: source, track: 0, selection: DialogueSelection(start: 79, end: 90), tools: tools)
        }
    }

    @Test func excessiveRangeCannotBePublishedAsVerified() {
        let report = LoudnessReport(input_i: "-18", input_tp: "-2", input_lra: "8", input_thresh: "-28", target_offset: "0")
        #expect(throws: (any Error).self) { try AudioEngine.verifyNormalized(report, target: -18, maximumLRA: 3) }
    }

    @Test func malformedLoudnessReportIsRejected() {
        #expect(throws: (any Error).self) { try LoudnessReport.parse(Data("not a report".utf8)) }
    }
}
