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

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func trimmedDeinterlacedCropHasExpectedDurationAndDimensions() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tools = try #require(FFmpegTools.discover())
        let source = dir.appendingPathComponent("interlaced.mkv")
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=48:duration=4", "-f", "lavfi", "-i", "sine=frequency=880:duration=4", "-vf", "tinterlace=interleave_top", "-c:v", "libx264", "-flags", "+ilme+ildct", "-c:a", "aac", "-shortest", source.path])
        #expect(fixture.status == 0)
        var config = EncodeConfiguration()
        config.codec = "H.264"; config.encoder = "x264"; config.speed = "Fast"
        config.cropTop = 2; config.cropBottom = 4
        config.picture.cropLeft = 6; config.picture.cropRight = 8
        config.picture.start = 1; config.picture.end = 2.5
        config.picture.deinterlace = "All frames"
        config.subtitleMode = "Remove all subtitles"
        let destination = dir.appendingPathComponent("trimmed.mkv")
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: destination.path, configuration: config, created: Date())
        let batch = BatchController(); await batch.discover(); batch.start([job])
        while batch.running { try await Task.sleep(for: .milliseconds(20)) }
        let state = try #require(batch.statuses[job.id])
        #expect(state.phase == "Completed", Comment(rawValue: state.detail))
        let result = try await MediaProbe.read(destination, tools: tools)
        #expect(result.video?.width == 306)
        #expect(result.video?.height == 174)
        #expect(abs(result.seconds - 1.5) < 0.15)
        #expect(result.streams.filter { $0.codec_type == "audio" }.count == 1)
        let details = try await ToolRunner().run(executable: tools.ffprobe, arguments: ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=field_order,r_frame_rate", "-of", "json", destination.path])
        let json = String(decoding: details.stdout, as: UTF8.self)
        #expect(json.contains("progressive"))
        #expect(json.contains("24/1"))
    }

    @Test func pictureSettingsMigrateAndRejectInvalidRanges() throws {
        let original = EncodeConfiguration()
        let encoded = try JSONEncoder().encode(original)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("pictureOptions"))
        let decoded = try JSONDecoder().decode(EncodeConfiguration.self, from: encoded)
        #expect(decoded.picture == PictureOptions())
        var changed = decoded
        changed.picture.start = 2; changed.picture.end = 1
        #expect(throws: (any Error).self) { try SessionDocument.validate(changed) }
        changed.picture.end = 3; changed.picture.cropLeft = 1
        #expect(throws: (any Error).self) { try SessionDocument.validate(changed) }
        changed.picture.cropLeft = 2
        try SessionDocument.validate(changed)
        #expect(try JSONDecoder().decode(EncodeConfiguration.self, from: JSONEncoder().encode(changed)) == changed)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func selectedAudioAndSubtitleStreamsSurviveEncoding() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tools = try #require(FFmpegTools.discover())
        let subtitles = dir.appendingPathComponent("captions.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nSynthetic caption\n".write(to: subtitles, atomically: true, encoding: .utf8)
        let source = dir.appendingPathComponent("multitrack.mkv")
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=1", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-f", "lavfi", "-i", "sine=frequency=880:duration=1", "-i", subtitles.path, "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:s", "-c:v", "libx264", "-c:a", "aac", "-c:s", "srt", "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=fra", "-metadata:s:s:0", "language=fra", source.path])
        #expect(fixture.status == 0)
        var config = EncodeConfiguration()
        config.codec = "H.264"; config.encoder = "x264"; config.speed = "Fast"
        config.audioTracks = [2]; config.subtitleTracks = [3]
        let destination = dir.appendingPathComponent("selected.mkv")
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: destination.path, configuration: config, created: Date())
        let batch = BatchController(); await batch.discover(); batch.start([job])
        while batch.running { try await Task.sleep(for: .milliseconds(20)) }
        let state = try #require(batch.statuses[job.id])
        #expect(state.phase == "Completed", Comment(rawValue: state.detail))
        let result = try await MediaProbe.read(destination, tools: tools)
        #expect(result.streams.filter { $0.codec_type == "audio" }.count == 1)
        #expect(result.streams.first { $0.codec_type == "audio" }?.tags?["language"] == "fra")
        #expect(result.streams.first { $0.codec_type == "subtitle" }?.tags?["language"] == "fra")
        let input = try await MediaProbe.read(source, tools: tools)
        #expect(throws: (any Error).self) { try EncodePlan.selectedStreams(input, type: "audio", indices: [3]) }
        #expect(throws: (any Error).self) { try EncodePlan.selectedStreams(input, type: "audio", indices: [99]) }
        #expect(try EncodePlan.selectedStreams(input, type: "audio", indices: []).isEmpty)
        #expect(try EncodePlan.selectedStreams(input, type: "audio", indices: nil).count == 2)
        #expect(try JSONDecoder().decode(EncodeConfiguration.self, from: JSONEncoder().encode(config)) == config)
        config.audioTracks = [2, 2]
        #expect(throws: (any Error).self) { try SessionDocument.validate(config) }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["H.264", "HEVC", "AV1"])
    func softwareTargetBitrateEncodes(codec: String) async throws {
        try await bitrateEncode(codec: codec, hardware: false)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_TEST_HARDWARE"] == "1"), arguments: ["H.264", "HEVC"])
    func actualHardwareBitrateEncodes(codec: String) async throws {
        try await bitrateEncode(codec: codec, hardware: true)
    }

    private func bitrateEncode(codec: String, hardware: Bool) async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tools = try #require(FFmpegTools.discover())
        let source = dir.appendingPathComponent("bitrate-source.mkv")
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24:duration=2", "-c:v", "libx264", source.path])
        #expect(fixture.status == 0)
        var config = EncodeConfiguration()
        config.codec = codec; config.encoder = codec == "AV1" ? "SVT-AV1" : codec == "HEVC" ? "x265" : "x264"
        config.rate.backend = hardware ? "Apple hardware" : "Software"
        config.rate.mode = "Target bitrate"; config.rate.bitrate = 1200; config.speed = "Fast"
        let destination = dir.appendingPathComponent("bitrate-output.mkv")
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: destination.path, configuration: config, created: Date())
        let batch = BatchController(); await batch.discover()
        let sourceProbe = try await MediaProbe.read(source, tools: tools)
        let plan = try EncodePlan.make(job: job, probe: sourceProbe, encoders: batch.encoders, staged: destination)
        #expect(!plan.arguments.contains("-crf"))
        #expect(plan.arguments.contains("1200k"))
        if hardware {
            #expect(!plan.arguments.contains("-preset"))
            #expect(plan.arguments.contains("-allow_sw"))
        }
        batch.start([job])
        while batch.running { try await Task.sleep(for: .milliseconds(20)) }
        let state = try #require(batch.statuses[job.id])
        #expect(state.phase == "Completed", Comment(rawValue: state.detail))
        let result = try await MediaProbe.read(destination, tools: tools)
        #expect(result.video?.codec_name == (codec == "AV1" ? "av1" : codec == "HEVC" ? "hevc" : "h264"))
        #expect(result.video?.width == 640)
        #expect(abs(result.seconds - 2) < 0.1)
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
