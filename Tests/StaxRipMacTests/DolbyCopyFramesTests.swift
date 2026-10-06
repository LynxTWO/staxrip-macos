import Foundation
import CryptoKit
import Testing
@testable import StaxRipMac

struct DolbyCopyFramesTests {
    private var md: [String: Any] { ["side_data_type":"Mastering display metadata", "red_x":"34000/50000", "red_y":"16000/50000", "green_x":"13250/50000", "green_y":"34500/50000", "blue_x":"7500/50000", "blue_y":"3000/50000", "white_point_x":"15635/50000", "white_point_y":"16450/50000", "min_luminance":"1/10000", "max_luminance":"10000000/10000"] }
    private var light: [String: Any] { ["side_data_type":"Content light level metadata", "max_content":1000, "max_average":400] }
    private func stream(_ side: [[String:Any]] = []) throws -> MediaProbe.Stream {
        var value: [String:Any] = ["index":0, "codec_type":"video", "codec_name":"hevc", "profile":"Main 10", "pix_fmt":"yuv420p10le", "width":3840, "height":2160, "chroma_location":"topleft", "color_range":"tv", "color_space":"bt2020nc", "color_primaries":"bt2020", "color_transfer":"smpte2084", "sample_aspect_ratio":"1:1", "time_base":"1/1000", "avg_frame_rate":"24000/1001", "r_frame_rate":"24000/1001"]
        value["side_data_list"] = side
        return try JSONDecoder().decode(MediaProbe.Stream.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func frame(_ pts: Int64 = 0) -> [String:Any] {
        ["width":3840, "height":2160, "interlaced_frame":0, "pix_fmt":"yuv420p10le", "color_range":"tv", "color_space":"bt2020nc", "color_primaries":"bt2020", "color_transfer":"smpte2084", "chroma_location":"topleft", "sample_aspect_ratio":"1:1", "pts":pts, "side_data_list":[md,light]]
    }
    @Test func allFrameMetadataAndDeclaredValuesMustAgree() throws {
        let good = try DolbyCopyFrames.Frames(stream([md,light]), source: false)
        try good.consume(frame(-42)); try good.consume(frame(0)); #expect(good.count == 2)
        var wrongMD = md; wrongMD["max_luminance"] = "9000000/10000"
        let wrongDeclared = try DolbyCopyFrames.Frames(stream([wrongMD]), source: false)
        #expect(throws: (any Error).self) { try wrongDeclared.consume(frame()) }
        #expect(throws: (any Error).self) { _ = try DolbyCopyFrames.Frames(stream([md,md]), source: false) }
        for key in ["pts", "side_data_list", "chroma_location", "color_transfer", "interlaced_frame"] {
            var missing = frame(); missing.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try DolbyCopyFrames.Frames(stream(), source: false).consume(missing) }
        }
        for sides in [[md,md], [md,light,["side_data_type":"Dolby Vision RPU Data"]], [md,["side_data_type":"unknown"]], [light]] {
            var f = frame(); f["side_data_list"] = sides
            #expect(throws: (any Error).self) { try DolbyCopyFrames.Frames(stream(), source: false).consume(f) }
        }
        let changed = try DolbyCopyFrames.Frames(stream(), source: false); try changed.consume(frame())
        var later = frame(42); later["side_data_list"] = [wrongMD,light]
        #expect(throws: (any Error).self) { try changed.consume(later) }
        #expect(throws: (any Error).self) { try good.consume(frame(0)) }
    }
    @Test func decodedSequencePreservesFrameBoundariesAndRefusesPartialOrSurplus() throws {
        let input = Data(0..<24), pixels = DolbyCopyFrames.Pixels(frameBytes: 12)
        for start in stride(from: 0, to: input.count, by: 5) { pixels.accept(input.subdata(in: start..<min(start+5,input.count))) }
        var expected = SHA256(); expected.update(data: Data("DOLBY-COPY-DECODED-1\0".utf8))
        for index in 0..<2 {
            var ordinal = Int64(index).littleEndian, size = Int64(12).littleEndian
            withUnsafeBytes(of: &ordinal) { expected.update(data: Data($0)) }
            withUnsafeBytes(of: &size) { expected.update(data: Data($0)) }
            expected.update(data: Data(SHA256.hash(data: input.subdata(in: index*12..<(index+1)*12))))
        }
        #expect(try pixels.finish(expected: 2) == Data(expected.finalize()))
        #expect(throws: (any Error).self) { _ = try pixels.finish(expected: 1) }
        let partial = DolbyCopyFrames.Pixels(frameBytes: 12); partial.accept(input.dropLast())
        #expect(throws: (any Error).self) { _ = try partial.finish(expected: 2) }
        let reversed = DolbyCopyFrames.Pixels(frameBytes: 12); reversed.accept(input.suffix(12) + input.prefix(12))
        #expect(try reversed.finish(expected: 2) != pixels.finish(expected: 2))
    }
    @Test func malformedNativeReadStillChecksCloseAndPreservesBodyCause() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dolby-copy-file-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("malformed.mkv"); try Data("generated malformed container".utf8).write(to: source)
        do {
            _ = try await ExportSourceFingerprint.$reportCopyClose.withValue(true) {
                try await ExportSourceFingerprint.readCopy(source, role: .source, timeBase: HDRFraction("1/1000"))
            }
            Issue.record("Expected checked close report")
        } catch let error as ExportSourceFingerprint.CopyCloseFailure {
            #expect(error.status == 0 && error.code == 0 && error.cause != nil)
        }
        // A reported ownership outcome grants no fixture cleanup.
        #expect(try Data(contentsOf: source) == Data("generated malformed container".utf8))
    }
    private final class Witness { weak var owner: ToolRunner? }
    @Test func checkedLaunchRefusalRetainsSamePipesAfterErrorAndTaskDrop() async throws {
        let witness = Witness()
        var task: Task<Void, Never>? = Task {
            let runner = ToolRunner(checkedReaders: true); witness.owner = runner
            do { _ = try await runner.run(executable: URL(fileURLWithPath: "/generated-missing-" + UUID().uuidString), arguments: []); Issue.record("Expected launch refusal") }
            catch let error as ToolRunner.AdmissionFailure { #expect(error.owner === runner && runner.retainsUncertainty) }
            catch { Issue.record("Expected typed admission uncertainty") }
        }
        await task?.value; task = nil
        let retained = try #require(witness.owner); #expect(retained.retainsUncertainty)
        await #expect(throws: (any Error).self) { _ = try await retained.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: []) }
        #expect(retained.retainsUncertainty)
    }
    @Test @MainActor func queueDefersQualificationAndKeepsGenericGuardAndResultDetail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dolby-copy-queue-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("generated.mkv"); try Data("generated not admitted media".utf8).write(to: source)
        var c = EncodeConfiguration(); c.selectCodec("Copy original"); c.colorMode = DolbyConversionIntent.hdr10Copy
        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"
        c.dolbyLossAcknowledgement = try DolbyLossAcknowledgement(source: source, fingerprint: await ExportSourceFingerprint.read(source))
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent("output.mkv").path, configuration: c, created: Date())
        let missing = URL(fileURLWithPath: "/generated-missing-tool")
        let check = try await QueuePreflight.inspect(job, tools: FFmpegTools(ffmpeg: missing, ffprobe: missing), encoders: [])
        #expect(check.kind == .deferred && check.detail.contains("every encoded packet"))
        #expect(!FileManager.default.fileExists(atPath: job.destination))
        #expect(throws: (any Error).self) { try DolbyConversionIntent.requireRunnable(c) }
        let result = BatchStatus(phase: "Completed", progress: 1, detail: "Verified generated result", destination: URL(fileURLWithPath: job.destination))
        #expect(QueueJobPresentation(job: job, status: result, publishing: false, check: nil).showStatusDetail)
        var bad = c; bad.audio = "AAC"
        #expect(throws: (any Error).self) { try DolbyConversionIntent.validateCopySettings(bad) }
        try FileManager.default.removeItem(at: root) // No helper or writer was admitted.
    }

}
