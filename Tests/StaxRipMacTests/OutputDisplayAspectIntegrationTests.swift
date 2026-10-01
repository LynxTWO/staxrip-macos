import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct OutputDisplayAspectIntegrationTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("display-aspect-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func configuration(_ codec: String = "H.264", container: String = "MKV", crop: Bool = true) -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.selectCodec(codec); c.container = container
        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"; c.picture.deinterlace = "Off"
        c.resolution = "1280 × 720"; c.speed = "Fast"
        if crop { c.picture.cropLeft = 6; c.picture.cropRight = 10; c.cropTop = 4; c.cropBottom = 6 }
        return c
    }
    private func fixture(_ root: URL, tools: FFmpegTools, unknown: Bool = false) async throws -> URL {
        let source = root.appendingPathComponent("source.mkv")
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=722x480:rate=24:duration=0.25", "-vf", unknown ? "setsar=0" : "setsar=32/27", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        try #require(result.status == 0)
        return source
    }
    private func finish(_ batch: BatchController) async throws {
        do { while batch.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch { batch.cancel(); throw error }
    }
    private func job(_ root: URL, source: URL, name: String, configuration: EncodeConfiguration) -> QueueJob {
        QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent(name).path, configuration: configuration, created: Date())
    }
    private func clean(_ root: URL, batch: BatchController?) {
        if batch?.running == true { batch?.cancel() }
        else { try? FileManager.default.removeItem(at: root) }
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func softwareCodecsAndContainersPreserveAnamorphicDisplayShape() async throws {
        let root = try directory(); var active: BatchController?
        defer { clean(root, batch: active) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools)
        let sourceBytes = try Data(contentsOf: source)
        var jobs: [QueueJob] = []
        for codec in ["H.264", "HEVC", "AV1"] {
            for container in ["MKV", "MP4"] {
                for crop in [false, true] {
                    jobs.append(job(root, source: source, name: "\(codec)-\(crop).\(container.lowercased())", configuration: configuration(codec, container: container, crop: crop)))
                }
            }
        }
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json")); active = batch
        batch.tools = tools; batch.encoders = ["libx264", "libx265", "libsvtav1"]
        batch.start(jobs)
        let began = Date()
        var lastPhases = "", phaseRecords = 0
        do {
            while batch.running {
                let phases = jobs.enumerated().map { "\($0.offset + 1):\(batch.statuses[$0.element.id]?.phase ?? "Pending")" }.joined(separator: " ")
                if phases != lastPhases, phaseRecords < 96 {
                    print("Display matrix \(String(format: "%.3f", Date().timeIntervalSince(began)))s \(phases)")
                    lastPhases = phases; phaseRecords += 1
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch { batch.cancel(); throw error }
        print("Display matrix finished after \(String(format: "%.3f", Date().timeIntervalSince(began)))s; inspecting 12 outputs")
        for item in jobs {
            let status = try #require(batch.statuses[item.id])
            try #require(status.phase == "Completed", Comment(rawValue: status.detail))
            let result = try await MediaProbe.read(URL(fileURLWithPath: item.destination), tools: tools)
            let video = try #require(result.video)
            #expect(video.height == 720)
            if item.configuration.picture.cropLeft == 6 {
                #expect(video.width == 1082)
                #expect(video.sample_aspect_ratio == "90368:76281")
                #expect(status.detail.contains("Verified display proportions 11296:6345"))
            } else {
                #expect(video.width == 1084)
                #expect(video.sample_aspect_ratio == "2888:2439")
                #expect(status.detail.contains("Verified display proportions 722:405"))
            }
        }
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["1", "0"])
    func changedOrMissingPixelShapeCannotPublish(pixelShape: String) async throws {
        let root = try directory(); var active: BatchController?
        defer { clean(root, batch: active) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools)
        let sourceBytes = try Data(contentsOf: source), prior = root.appendingPathComponent("prior.mkv")
        try Data("Prior output remains intact".utf8).write(to: prior)
        let unrelated = root.appendingPathComponent(".staxrip-batch-unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let sentinel = unrelated.appendingPathComponent("keep"); try Data([1, 2, 3]).write(to: sentinel)
        let script = root.appendingPathComponent("encoder")
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        // Real encode with unchanged crop/resize followed by a deliberately wrong SAR.
        // Save probe evidence before the queue removes its owned failed staging.
        let body = "#!/bin/zsh\nargs=()\nwhile (( $# )); do\n if [[ $1 == -vf ]]; then args+=(\"$1\" \"$2,setsar=\(pixelShape)\"); shift 2; else args+=(\"$1\"); shift; fi\ndone\n" + quote(tools.ffmpeg.path) + " \"${args[@]}\"\nresult=$?\nif (( result == 0 )); then " + quote(tools.ffprobe.path) + " -v error -show_streams -show_format -of json \"${args[-1]}\" > " + quote(root.appendingPathComponent("encoded.json").path) + "; fi\nexit $result\n"
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let first = job(root, source: source, name: "result.mkv", configuration: configuration())
        let later = job(root, source: source, name: "later.mkv", configuration: configuration())
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json")); active = batch
        batch.tools = FFmpegTools(ffmpeg: script, ffprobe: tools.ffprobe); batch.encoders = ["libx264"]
        batch.start([first, later]); try await finish(batch)
        #expect(batch.statuses[first.id]?.phase == "Failed")
        #expect(batch.statuses[first.id]?.detail.contains("Display proportion verification:") == true)
        #expect(batch.statuses[later.id]?.phase == "Pending")
        for item in [first, later] { #expect(!FileManager.default.fileExists(atPath: item.destination)) }
        let encoded = try JSONDecoder().decode(MediaProbe.self, from: Data(contentsOf: root.appendingPathComponent("encoded.json")))
        #expect(encoded.video?.width == 1082 && encoded.video?.height == 720)
        if pixelShape == "1" { #expect(encoded.video?.sample_aspect_ratio == "1:1") }
        else { #expect(encoded.video?.sample_aspect_ratio == nil) }
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: prior) == Data("Prior output remains intact".utf8))
        #expect(try Data(contentsOf: sentinel) == Data([1, 2, 3]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".staxrip-batch-") } == [unrelated.lastPathComponent])
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func nearSquareMatroskaRoundingIsNotReportedAsExact() async throws {
        let root = try directory(); var active: BatchController?
        defer { clean(root, batch: active) }
        let tools = try #require(FFmpegTools.discover())
        let source = root.appendingPathComponent("source.mkv")
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=0.25", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        try #require(generated.status == 0)
        let original = try Data(contentsOf: source)
        var c = configuration(crop: false)
        c.picture.cropLeft = 4; c.cropTop = 2; c.resolution = "1920 × 1080"
        let item = job(root, source: source, name: "result.mkv", configuration: c)
        // Independently encode the same plan to retain evidence of the real muxer result.
        let probe = try await MediaProbe.read(source, tools: tools)
        let reference = root.appendingPathComponent("reference.mkv")
        let plan = try EncodePlan.make(job: item, probe: probe, encoders: ["libx264"], staged: reference)
        let encoded = try await ToolRunner().run(executable: tools.ffmpeg, arguments: plan.arguments)
        try #require(encoded.status == 0)
        let result = try await MediaProbe.read(reference, tools: tools)
        #expect(result.video?.width == 1792 && result.video?.height == 1080)
        let referenceBytes = try Data(contentsOf: reference)
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json")); active = batch
        batch.tools = tools; batch.encoders = ["libx264"]; batch.start([item]); try await finish(batch)
        let status = try #require(batch.statuses[item.id])
        // A future tool version may preserve this ratio. Require truthful behavior
        // for either observed result rather than forcing an upstream bug forever.
        if result.video?.sample_aspect_ratio == "5265:5264" {
            #expect(status.phase == "Completed")
            #expect(status.detail.contains("Verified display proportions 78:47"))
        } else {
            #expect(status.phase == "Failed")
            #expect(status.detail.contains("Display proportion verification:"))
            #expect(status.detail.contains("rounded pixel shape"))
            #expect(!FileManager.default.fileExists(atPath: item.destination))
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: reference) == referenceBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func unknownSourceRemainsExplicitlyUnverified() async throws {
        let root = try directory(); var active: BatchController?
        defer { clean(root, batch: active) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools, unknown: true)
        let original = try Data(contentsOf: source)
        let probe = try await MediaProbe.read(source, tools: tools)
        #expect(probe.video?.sample_aspect_ratio == nil)
        let item = job(root, source: source, name: "unknown.mkv", configuration: configuration())
        let plan = try EncodePlan.make(job: item, probe: probe, encoders: ["libx264"], staged: root.appendingPathComponent("stage.mkv"))
        #expect(plan.summary.contains(OutputDisplayAspect.unavailable))
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json")); active = batch
        batch.tools = tools; batch.encoders = ["libx264"]; batch.start([item]); try await finish(batch)
        let status = try #require(batch.statuses[item.id])
        try #require(status.phase == "Completed", Comment(rawValue: status.detail))
        #expect(status.detail.contains(OutputDisplayAspect.unavailable))
        #expect(!status.detail.contains("Verified display proportions"))
        let result = try await MediaProbe.read(URL(fileURLWithPath: item.destination), tools: tools)
        #expect(result.video?.width == 1082 && result.video?.height == 720)
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
}
