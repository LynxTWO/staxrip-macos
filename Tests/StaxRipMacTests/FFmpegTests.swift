import Testing
import Foundation
@testable import StaxRipMac

@MainActor
struct FFmpegTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("media-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["H.264", "HEVC", "AV1"])
    func realBatchAppliesVideoAudioAndCrop(codec: String) async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tools = try #require(FFmpegTools.discover())
        let source = dir.appendingPathComponent("source ' quoted ; $(literal).mkv")
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=1", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", source.path])
        #expect(fixture.status == 0)
        let sourceBytes = try Data(contentsOf: source)
        let model = WorkspaceModel()
        model.sourceURL = source; model.sourceName = source.lastPathComponent
        model.outputFolder = dir; model.outputStem = "result"
        model.config.codec = codec
        model.config.encoder = codec == "AV1" ? "SVT-AV1" : codec == "HEVC" ? "x265" : "x264"
        model.config.speed = "Fast"
        model.config.cropTop = 2; model.config.cropBottom = 2
        model.config.audio = "Opus"
        model.addToQueue()
        let batch = BatchController()
        await batch.discover()
        #expect(batch.tools != nil)
        batch.start(model.jobs)
        while batch.running { try await Task.sleep(for: .milliseconds(20)) }
        let state = try #require(batch.statuses[model.jobs[0].id])
        #expect(state.phase == "Completed", Comment(rawValue: state.detail))
        let output = try #require(state.destination)
        let probe = try await MediaProbe.read(output, tools: tools)
        #expect(probe.video?.height == 176)
        #expect(probe.video?.codec_name == (codec == "AV1" ? "av1" : codec == "HEVC" ? "hevc" : "h264"))
        #expect(probe.streams.first(where: { $0.codec_type == "audio" })?.codec_name == "opus")
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func cancellingRealEncodeLeavesNoOutputAndCanRetry() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tools = try #require(FFmpegTools.discover())
        let source = dir.appendingPathComponent("long.mkv")
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24:duration=8", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        #expect(fixture.status == 0)
        var config = EncodeConfiguration(); config.speed = "Thorough"
        let output = dir.appendingPathComponent("cancelled.mkv")
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: config, created: Date())
        let batch = BatchController(); await batch.discover(); batch.start([job])
        let deadline = Date().addingTimeInterval(15)
        while batch.running && batch.statuses[job.id]?.phase != "Encoding" && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(batch.statuses[job.id]?.phase == "Encoding")
        try await Task.sleep(for: .milliseconds(100))
        batch.cancel()
        while batch.running { try await Task.sleep(for: .milliseconds(20)) }
        #expect(batch.statuses[job.id]?.phase == "Cancelled")
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [source.lastPathComponent])
        var retry = job; retry.configuration.codec = "H.264"; retry.configuration.encoder = "x264"; retry.configuration.speed = "Fast"
        batch.start([retry])
        while batch.running { try await Task.sleep(for: .milliseconds(20)) }
        #expect(batch.statuses[job.id]?.phase == "Completed")
    }

    @Test func planRejectsHDR() throws {
        let probe = try JSONDecoder().decode(MediaProbe.self, from: Data("""
        {"streams":[{"index":0,"codec_type":"video","codec_name":"h264","width":320,"height":180,"pix_fmt":"yuv420p","color_transfer":"smpte2084"}],"format":{"duration":"1"}}
        """.utf8))
        let job = QueueJob(id: UUID(), source: "/synthetic/$(literal).mkv", isDemo: false, destination: "/synthetic/out.mkv", configuration: EncodeConfiguration(), created: Date())
        #expect(throws: (any Error).self) { try EncodePlan.make(job: job, probe: probe, encoders: ["libsvtav1", "aac"], staged: URL(fileURLWithPath: job.destination)) }
    }

    @Test func runnerKeepsArgumentsLiteralAndCancels() async throws {
        let result = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["$(literal); quote ' stays data"])
        #expect(String(decoding: result.stdout, as: UTF8.self).contains("$(literal); quote ' stays data"))
        let runner = ToolRunner()
        let task = Task { try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled process returned success") }
        catch is CancellationError { }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil)) func batchStopsBeforeLaterJobsOnFailure() async throws {
        let config = EncodeConfiguration()
        let first = QueueJob(id: UUID(), source: "demo", isDemo: true, destination: "/synthetic/a.mkv", configuration: config, created: Date())
        let second = QueueJob(id: UUID(), source: "demo", isDemo: true, destination: "/synthetic/b.mkv", configuration: config, created: Date())
        let batch = BatchController(); await batch.discover(); batch.start([first, second])
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        #expect(batch.statuses[first.id]?.phase == "Failed")
        #expect(batch.statuses[second.id]?.phase == "Pending")
    }
}
