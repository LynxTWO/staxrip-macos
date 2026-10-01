import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct ExportSourceStabilityTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-stability-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func fixture(_ root: URL, name: String, color: String, tools: FFmpegTools) async throws -> URL {
        let url = root.appendingPathComponent(name)
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "color=c=\(color):s=160x96:r=24:d=0.5", "-c:v", "libx264", "-preset", "ultrafast", url.path])
        try #require(result.status == 0)
        return url
    }
    private func job(_ root: URL, source: URL, name: String) -> QueueJob {
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.container = "MP4"; c.resolution = "Original"
        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"; c.speed = "Fast"
        return QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent(name).path, configuration: c, created: Date())
    }
    private func finish(_ batch: BatchController) async throws {
        do { while batch.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch { batch.cancel(); throw error }
    }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["before", "after"])
    func sameMetadataReplacementCannotPublishAndRetryRecapturesSource(moment: String) async throws {
        let root = try directory(); var active: BatchController?
        defer { if active?.running != true { try? FileManager.default.removeItem(at: root) } else { active?.cancel() } }
        let tools = try #require(FFmpegTools.discover())
        let source = try await fixture(root, name: "source.mp4", color: "blue", tools: tools)
        let replacement = try await fixture(root, name: "replacement.mp4", color: "red", tools: tools)
        let before = try await MediaProbe.read(source, tools: tools), after = try await MediaProbe.read(replacement, tools: tools)
        #expect(before.video?.codec_name == after.video?.codec_name && before.video?.width == after.video?.width && before.video?.height == after.video?.height)
        #expect(before.video?.sample_aspect_ratio == after.video?.sample_aspect_ratio && before.seconds == after.seconds)
        #expect(before.streams.count == after.streams.count)
        #expect(try Data(contentsOf: source) != Data(contentsOf: replacement))
        let expectedSource = try Data(contentsOf: replacement)
        let prior = root.appendingPathComponent("prior.mp4"); try Data("Prior output".utf8).write(to: prior)
        let unrelated = root.appendingPathComponent(".staxrip-batch-unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let sentinel = unrelated.appendingPathComponent("keep"); try Data([1, 2, 3]).write(to: sentinel)
        let script = root.appendingPathComponent("encoder")
        let replace = "/bin/cp " + quote(replacement.path) + " " + quote(source.path) + "\n"
        let body = "#!/bin/zsh\n" + (moment == "before" ? replace : "") + quote(tools.ffmpeg.path) + " \"$@\"\nresult=$?\n" + (moment == "after" ? replace : "") + "exit $result\n"
        try Data(body.utf8).write(to: script); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let first = job(root, source: source, name: "result.mp4"), later = job(root, source: source, name: "later.mp4")
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json")); active = batch
        batch.tools = FFmpegTools(ffmpeg: script, ffprobe: tools.ffprobe); batch.encoders = ["libx264"]
        batch.start([first, later]); try await finish(batch)
        #expect(batch.statuses[first.id]?.phase == "Failed")
        #expect(batch.statuses[first.id]?.detail.contains("Source changed during export: content fingerprint differs") == true)
        #expect(batch.statuses[later.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: first.destination) && !FileManager.default.fileExists(atPath: later.destination))
        #expect(try Data(contentsOf: prior) == Data("Prior output".utf8))
        #expect(try Data(contentsOf: sentinel) == Data([1, 2, 3]))
        #expect(try Data(contentsOf: source) == expectedSource)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".staxrip-batch-") } == [unrelated.lastPathComponent])
        // Explicit retry observes the now-current source; failed attempts retain no old fingerprint.
        batch.tools = tools; batch.start([first]); try await finish(batch)
        #expect(batch.statuses[first.id]?.phase == "Completed")
        #expect(batch.statuses[first.id]?.detail.contains("Source content fingerprint unchanged") == true)
        #expect(FileManager.default.fileExists(atPath: first.destination))
        #expect(try Data(contentsOf: source) == expectedSource)
    }

    private final class Callbacks: @unchecked Sendable {
        let lock = NSLock(); var callbacks: [@Sendable (Int64, Int64) -> Void] = []
        func store(_ callback: @escaping @Sendable (Int64, Int64) -> Void) { lock.lock(); callbacks.append(callback); lock.unlock() }
        func snapshot() -> [@Sendable (Int64, Int64) -> Void] { lock.lock(); defer { lock.unlock() }; return callbacks }
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func lateContentProgressCannotOverwriteCompletedOutput() async throws {
        let root = try directory(); var active: BatchController?
        defer { if active?.running != true { try? FileManager.default.removeItem(at: root) } else { active?.cancel() } }
        let tools = try #require(FFmpegTools.discover())
        let source = try await fixture(root, name: "source.mp4", color: "blue", tools: tools)
        let callbacks = Callbacks()
        let batch = BatchController(readSource: { url, progress in
            callbacks.store(progress)
            return try await ExportSourceFingerprint.read(url, progress: progress)
        }); active = batch
        batch.tools = tools; batch.encoders = ["libx264"]
        let item = job(root, source: source, name: "output.mp4")
        batch.start([item]); try await finish(batch)
        let status = try #require(batch.statuses[item.id]); try #require(status.phase == "Completed", Comment(rawValue: status.detail))
        #expect(callbacks.snapshot().count == 2)
        for callback in callbacks.snapshot() { callback(0, 100) }
        // Drain posted main-actor callbacks before checking the final status.
        for _ in 0..<10 { await Task.yield() }
        #expect(batch.statuses[item.id]?.phase == "Completed")
        #expect(batch.statuses[item.id]?.progress == 1)
        #expect(batch.statuses[item.id]?.detail == status.detail)
    }
    private actor HeldReader {
        var count = 0
        var continuation: CheckedContinuation<Void, Never>?
        var callback: (@Sendable (Int64, Int64) -> Void)?
        var ready: Bool { continuation != nil }
        func pause(_ progress: @escaping @Sendable (Int64, Int64) -> Void, on pass: Int) async {
            count += 1
            guard count == pass else { return }
            callback = progress
            await withCheckedContinuation { continuation = $0 }
        }
        func lateProgress() { callback?(1, 100) }
        func release() { continuation?.resume(); continuation = nil }
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)), arguments: [1, 2])
    func cancelledCheckWaitsAndCannotPublishOrOverwriteStopStatus(pass: Int) async throws {
        let root = try directory(); var active: BatchController?
        defer { if active?.running != true { try? FileManager.default.removeItem(at: root) } else { active?.cancel() } }
        let tools = try #require(FFmpegTools.discover())
        let source = try await fixture(root, name: "source.mp4", color: "blue", tools: tools)
        let original = try Data(contentsOf: source)
        let held = HeldReader()
        let batch = BatchController(readSource: { url, progress in
            await held.pause(progress, on: pass)
            return try await ExportSourceFingerprint.read(url, progress: progress)
        }); active = batch
        batch.tools = tools; batch.encoders = ["libx264"]
        let item = job(root, source: source, name: "output.mp4"), later = job(root, source: source, name: "later.mp4")
        batch.start([item, later])
        do {
            while !(await held.ready) {
                try #require(batch.running, Comment(rawValue: batch.statuses[item.id]?.detail ?? "Batch ended before check"))
                try await Task.sleep(for: .milliseconds(10))
            }
            batch.cancel()
            await held.lateProgress()
            for _ in 0..<10 { await Task.yield() }
            #expect(batch.running)
            #expect(batch.statuses[item.id]?.detail == "Stop requested. Waiting for the source content check to finish.")
            #expect(!FileManager.default.fileExists(atPath: item.destination))
            let staging = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".staxrip-batch-") }
            #expect(staging.count == (pass == 1 ? 0 : 1))
            await held.release()
            try await finish(batch)
            #expect(batch.statuses[item.id]?.phase == "Cancelled")
            #expect(batch.statuses[later.id]?.phase == "Pending")
            #expect(!FileManager.default.fileExists(atPath: item.destination))
            #expect(try Data(contentsOf: source) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
        } catch { await held.release(); batch.cancel(); try? await finish(batch); throw error }
    }

}
