import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct OutputGeometryTests {
    @Test func exactOriginalAndBoundedProportionalFit() throws {
        let original = try OutputGeometry(width: 160, height: 96, resolution: "Original")
        #expect(try original.verify(width: 160, height: 96).contains("160 × 96"))
        #expect(throws: (any Error).self) { try original.verify(width: 158, height: 96) }
        let landscape = try OutputGeometry(width: 160, height: 96, resolution: "1280 × 720")
        #expect(try landscape.verify(width: 1200, height: 720).contains("1200 × 720"))
        let portrait = try OutputGeometry(width: 98, height: 160, resolution: "1280 × 720")
        // Both nearby even values are legitimate filter rounding; ideal width is 441.
        for width in [440, 442] { _ = try portrait.verify(width: width, height: 720) }
        for (w, h) in [(438, 720), (444, 720), (1200, 718), (160, 96), (1280, 720), (1202, 720), (1200, 722), (1282, 720), (1201, 720), (0, 720)] {
            #expect(throws: (any Error).self) { try landscape.verify(width: w, height: h) }
        }
        #expect(throws: (any Error).self) { try landscape.verify(width: nil, height: 720) }
        #expect(throws: (any Error).self) { try landscape.verify(width: 1200, height: nil) }
        for (w, h) in [(0, 96), (-2, 96), (161, 96), (Int.max, 96), (Int(Int32.max) - 1, 2)] {
            #expect(throws: (any Error).self) { try OutputGeometry(width: w, height: h, resolution: "1280 × 720") }
        }
        #expect(throws: (any Error).self) { try OutputGeometry(width: 160, height: 96, resolution: "unknown") }
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("output-geometry-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func configuration(_ resolution: String) -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.codec = "H.264"; c.encoder = "x264"; c.container = "MKV"
        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"; c.picture.deinterlace = "Off"; c.resolution = resolution; c.speed = "Fast"
        return c
    }
    private func fixture(_ root: URL, size: String, tools: FFmpegTools) async throws -> URL {
        let source = root.appendingPathComponent(size + ".mkv")
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=\(size):rate=24:duration=0.25", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        try #require(result.status == 0)
        return source
    }
    private func finish(_ batch: BatchController) async throws {
        do {
            while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        } catch {
            batch.cancel()
            throw error
        }
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func generatedPortraitLandscapeAndCropExportsHaveVerifiedRasterSize() async throws {
        let root = try directory()
        var activeBatch: BatchController?
        defer {
            // A timed-out test must not delete staging while its operation is alive.
            if activeBatch?.running == true { activeBatch?.cancel() }
            else { try? FileManager.default.removeItem(at: root) }
        }
        let tools = try #require(FFmpegTools.discover())
        let landscape = try await fixture(root, size: "160x96", tools: tools)
        let portrait = try await fixture(root, size: "98x160", tools: tools)
        let landscapeBytes = try Data(contentsOf: landscape), portraitBytes = try Data(contentsOf: portrait)
        var jobs: [QueueJob] = []
        for (index, tuple) in [(landscape, "1280 × 720", false), (portrait, "1280 × 720", false), (landscape, "1920 × 1080", true)].enumerated() {
            var c = configuration(tuple.1)
            if tuple.2 { c.picture.cropLeft = 4; c.cropTop = 2 }
            jobs.append(QueueJob(id: UUID(), source: tuple.0.path, isDemo: false, destination: root.appendingPathComponent("result\(index).mkv").path, configuration: c, created: Date()))
        }
        // Reproduce the former 20-second helper limit without relying on runner load.
        var delayedPublication = false
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"), publishOutput: { staged, output in
            if !delayedPublication {
                delayedPublication = true
                try await Task.sleep(for: .seconds(21))
            }
            try await ExportPublication.publishAsync(staged: staged, destination: output)
        })
        activeBatch = batch
        batch.tools = tools; batch.encoders = ["libx264"]; batch.start(jobs); try await finish(batch)
        for (index, job) in jobs.enumerated() {
            let status = try #require(batch.statuses[job.id]); try #require(status.phase == "Completed", Comment(rawValue: status.detail))
            let output = try await MediaProbe.read(URL(fileURLWithPath: job.destination), tools: tools)
            let w = try #require(output.video?.width), h = try #require(output.video?.height)
            if index == 0 { #expect(w == 1200 && h == 720) }
            if index == 1 { #expect([440, 442].contains(w) && h == 720) }
            if index == 2 { #expect(w == 1792 && h == 1080) }
            #expect(status.detail.contains("Verified frame size \(w) × \(h) pixels"))
        }
        #expect(try Data(contentsOf: landscape) == landscapeBytes); #expect(try Data(contentsOf: portrait) == portraitBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func droppedResizeCannotPublishEvenWhenEncoderSucceeds() async throws {
        let root = try directory()
        var activeBatch: BatchController?
        defer {
            // A timed-out test must not delete staging while its operation is alive.
            if activeBatch?.running == true { activeBatch?.cancel() }
            else { try? FileManager.default.removeItem(at: root) }
        }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, size: "160x96", tools: tools)
        let original = try Data(contentsOf: source), prior = root.appendingPathComponent("prior.mkv")
        try Data("Keep prior output".utf8).write(to: prior)
        let script = root.appendingPathComponent("encoder")
        let executable = "'" + tools.ffmpeg.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // zsh arrays preserve literal arguments while dropping precisely the -vf pair.
        let body = "#!/bin/zsh\nargs=()\nwhile (( $# )); do\n if [[ $1 == -vf ]]; then shift 2; else args+=(\"$1\"); shift; fi\ndone\nexec " + executable + " \"${args[@]}\"\n"
        try Data(body.utf8).write(to: script); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent("result.mkv").path, configuration: configuration("1280 × 720"), created: Date())
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        activeBatch = batch
        batch.tools = FFmpegTools(ffmpeg: script, ffprobe: tools.ffprobe); batch.encoders = ["libx264"]; batch.start([job]); try await finish(batch)
        #expect(batch.statuses[job.id]?.phase == "Failed")
        #expect(batch.statuses[job.id]?.detail.contains("Frame size verification:") == true)
        #expect(!FileManager.default.fileExists(atPath: job.destination))
        #expect(try Data(contentsOf: source) == original); #expect(try Data(contentsOf: prior) == Data("Keep prior output".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
}
