import Testing
import Foundation
@testable import StaxRipMac

@MainActor
struct HEVCBufferTests {
    private func video(_ width: Int = 3840, _ height: Int = 2160, rate: String = "24000/1001", average: String? = nil) throws -> MediaProbe.Stream {
        let data = try JSONSerialization.data(withJSONObject: ["index": 0, "codec_type": "video", "codec_name": "h264", "width": width, "height": height,
            "pix_fmt": "yuv420p", "field_order": "progressive", "sample_aspect_ratio": "1:1", "r_frame_rate": rate, "avg_frame_rate": average ?? rate])
        return try JSONDecoder().decode(MediaProbe.Stream.self, from: data)
    }
    @Test func recommendationsRespectRasterCadenceTierAndTarget() throws {
        let high = try HEVCBufferPlanner.recommend(width: 3840, height: 2160, fps: 24000.0 / 1001, limits: HEVCBufferLimits())
        #expect(high.level == "5" && high.tier == "High" && high.maxrate == 100000 && high.bufsize == 100000)
        var main = HEVCBufferLimits(); main.tier = "Main"
        let compatible = try HEVCBufferPlanner.recommend(width: 3840, height: 2160, fps: 24, limits: main)
        #expect(compatible.level == "5" && compatible.maxrate == 25000 && compatible.bufsize == 25000)
        let sixty = try HEVCBufferPlanner.recommend(width: 3840, height: 2160, fps: 60, limits: main)
        #expect(sixty.level == "5.1" && sixty.maxrate == 40000)
        let target = try HEVCBufferPlanner.recommend(width: 1920, height: 1080, fps: 24, limits: main, target: 15000)
        #expect(target.level == "4.1" && target.maxrate >= 15000)
        let tiny = try HEVCBufferPlanner.recommend(width: 128, height: 128, fps: 24, limits: HEVCBufferLimits())
        #expect(tiny.tier == "Main") // High is unavailable below level 4.
        #expect(throws: (any Error).self) { try HEVCBufferPlanner.recommend(width: 16384, height: 16384, fps: 240, limits: main) }
        #expect(throws: (any Error).self) { try HEVCBufferPlanner.recommend(width: Int.max, height: 2, fps: .nan, limits: main) }
    }
    @Test func manualValuesRemainFixedAndInvalidOrInapplicableChoicesRefuse() throws {
        var c = EncodeConfiguration(); c.selectCodec("HEVC")
        c.hevcBufferLimits = HEVCBufferLimits(mode: "Custom", tier: "High", maxrate: 70000, bufsize: 80000)
        let resolved = try #require(try HEVCBufferPlanner.resolve(c, video: video()))
        #expect(resolved.maxrate == 70000 && resolved.bufsize == 80000 && resolved.level == "5")
        c.resolution = "1280 × 720"
        let smaller = try #require(try HEVCBufferPlanner.resolve(c, video: video()))
        #expect(smaller.maxrate == 70000 && smaller.bufsize == 80000) // Selects a larger level rather than clamping.
        c.rate.mode = "Target bitrate"; c.rate.bitrate = 80000
        #expect(throws: (any Error).self) { try SessionDocument.validate(c) }
        c.rate.bitrate = 60000; c.hevcBufferLimits?.bufsize = 0
        #expect(throws: (any Error).self) { try SessionDocument.validate(c) }
        c.hevcBufferLimits = HEVCBufferLimits(); c.selectCodec("AV1")
        #expect(throws: (any Error).self) { try SessionDocument.validate(c) }
        c.selectCodec("HEVC"); c.rate.backend = "Apple hardware"
        #expect(throws: (any Error).self) { try SessionDocument.validate(c) }
        c.rate.backend = "Software"
        let s = try video(average: "25/1")
        #expect(throws: (any Error).self) { try HEVCBufferPlanner.resolve(c, video: s) }
    }
    @Test func versionsPreserveLimitsAndLegacyIntentCannotBeMislabelled() throws {
        let legacy = try JSONDecoder().decode(EncodeConfiguration.self, from: JSONEncoder().encode(EncodeConfiguration()))
        #expect(legacy.hevcBufferLimits == nil)
        var c = legacy; c.selectCodec("HEVC"); c.hevcBufferLimits = HEVCBufferLimits(mode: "Custom", tier: "Main", maxrate: 18000, bufsize: 22000)
        let job = QueueJob(id: UUID(), source: "/generated/source.mkv", isDemo: false, destination: "/generated/result.mkv", configuration: c, created: Date())
        var doc = SessionDocument(configuration: c, outputFolder: "/generated", outputStem: "result", jobs: [job])
        let decoded = try JSONDecoder().decode(SessionDocument.self, from: JSONEncoder().encode(doc)).validated()
        #expect(decoded.configuration == c && decoded.jobs[0].configuration == c)
        doc.version = 9
        #expect(throws: (any Error).self) { try doc.validated() }
        var journal = BatchJournal(jobs: [job], statuses: [:]); _ = try journal.validated(); journal.version = 8
        #expect(throws: (any Error).self) { try journal.validated() }
        var presets = PresetDocument(presets: [CustomPreset(name: "Limited HEVC", configuration: c)])
        #expect(try PresetDocument.decode(presets.encoded()).presets[0].configuration == c)
        presets.version = 1
        #expect(throws: (any Error).self) { try presets.validated() }
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["Suggested", "Custom"])
    func actualQueueAppliesPeakBufferAndHRDWithoutChangingSource(mode: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hevc-buffer-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("generated.mkv"), output = dir.appendingPathComponent("limited.mkv")
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=1", "-c:v", "libx264", source.path])
        #expect(fixture.status == 0)
        let sourceBytes = try Data(contentsOf: source)
        var c = EncodeConfiguration(); c.selectCodec("HEVC"); c.speed = "Fast"; c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"
        c.hevcBufferLimits = HEVCBufferLimits(mode: mode, tier: "Main", maxrate: 4000, bufsize: 6000)
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: c, created: Date())
        let batch = BatchController(); await batch.discover(); batch.start([job])
        while batch.running { try await Task.sleep(for: .milliseconds(20)) }
        let state = try #require(batch.statuses[job.id]); #expect(state.phase == "Completed", Comment(rawValue: state.detail))
        #expect(try Data(contentsOf: source) == sourceBytes)
        let raw = dir.appendingPathComponent("result.hevc")
        let demux = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-i", output.path, "-map", "0:v:0", "-c", "copy", "-f", "hevc", raw.path])
        #expect(demux.status == 0)
        let bytes = try Data(contentsOf: raw)
        let text = String(decoding: bytes, as: UTF8.self)
        let peak = mode == "Suggested" ? 1500 : 4000, buffer = mode == "Suggested" ? 1500 : 6000
        #expect(text.contains("vbv-maxrate=\(peak)") && text.contains("vbv-bufsize=\(buffer)"))
        let signaling = HEVCSignalingLines()
        let headers = try await ToolRunner().runWithStreams(executable: tools.ffmpeg, arguments: ["-v", "info", "-i", raw.path, "-map", "0:v:0", "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"], onErrorOutput: { signaling.feed($0) })
        #expect(headers.status == 0)
        #expect(signaling.hasNALHRD && signaling.hasBufferingPeriod && !signaling.overlong)
        let probe = try await MediaProbe.read(output, tools: tools)
        #expect(probe.video?.codec_name == "hevc" && probe.video?.width == 320 && probe.video?.height == 180)
        #expect(try !FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix(".staxrip-batch-") })
    }
}

// Observe streamed syntax instead of relying on the runner's 64 KiB stderr tail.
private final class HEVCSignalingLines: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var nal = false, period = false, excessive = false
    var hasNALHRD: Bool { lock.lock(); defer { lock.unlock() }; return nal }
    var hasBufferingPeriod: Bool { lock.lock(); defer { lock.unlock() }; return period }
    var overlong: Bool { lock.lock(); defer { lock.unlock() }; return excessive }
    func feed(_ bytes: Data) {
        lock.lock(); defer { lock.unlock() }
        for byte in bytes {
            if byte == 10 {
                let line = String(decoding: pending, as: UTF8.self)
                if line.contains("nal_hrd_parameters_present_flag") && line.hasSuffix(" = 1") { nal = true }
                if line.contains("Buffering Period") { period = true }
                pending.removeAll(keepingCapacity: true)
            } else if pending.count < 4096 { pending.append(byte) }
            else { excessive = true }
        }
    }
}
