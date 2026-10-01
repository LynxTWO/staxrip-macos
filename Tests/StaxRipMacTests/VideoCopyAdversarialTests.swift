import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@MainActor
struct VideoCopyAdversarialTests {
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func run(_ args: [String], tools: FFmpegTools) async throws {
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n"] + args)
        try #require(result.status == 0, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["missing", "different", "shifted"])
    func alteredRealPacketsCannotPublishOrAdvanceQueue(change: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-copy-refusal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        defer { if batch.running { batch.cancel() } else { try? FileManager.default.removeItem(at: root) } }
        let source = root.appendingPathComponent("source.mp4"), replacement = root.appendingPathComponent("replacement.mkv")
        try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=3", "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p", source.path], tools: tools)
        if change == "shifted" {
            try await run(["-itsoffset", "0.125", "-i", source.path, "-map", "0:v:0", "-c:v", "copy", replacement.path], tools: tools)
        } else if change == "missing" {
            // B-frame ordering leaves the container duration unchanged while a packet is lost.
            try await run(["-i", source.path, "-map", "0:v:0", "-c:v", "copy", "-frames:v", "71", replacement.path], tools: tools)
        } else {
            let alternate = root.appendingPathComponent("alternate.mp4")
            try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=3", "-vf", "negate", "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p", alternate.path], tools: tools)
            try await run(["-i", alternate.path, "-c", "copy", replacement.path], tools: tools)
        }
        let sourceBytes = try Data(contentsOf: source)
        let prior = root.appendingPathComponent("prior.mkv"), sentinel = Data("Prior output remains".utf8)
        try sentinel.write(to: prior)
        let sibling = root.appendingPathComponent(".staxrip-batch-unrelated")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        try sentinel.write(to: sibling.appendingPathComponent("keep"))
        let wrapper = root.appendingPathComponent("encoder-wrapper")
        let body = "#!/bin/sh\nset -e\nfor target do :; done\ncase \"$target\" in */encoded.mkv)\n"
            + quote(tools.ffmpeg.path) + " \"$@\"\n/bin/cp " + quote(replacement.path) + " \"$target\"\nexit 0;; esac\nexec " + quote(tools.ffmpeg.path) + " \"$@\"\n"
        try Data(body.utf8).write(to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        var c = EncodeConfiguration(); c.selectCodec("Copy original"); c.container = "MKV"; c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent("output.mkv").path, configuration: c, created: Date())
        let next = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent("next.mkv").path, configuration: c, created: Date())
        batch.tools = FFmpegTools(ffmpeg: wrapper, ffprobe: tools.ffprobe); batch.encoders = []
        batch.start([job, next])
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        let status = try #require(batch.statuses[job.id])
        #expect(status.phase == "Failed", Comment(rawValue: status.detail))
        #expect(status.detail.contains("Video copy:") && (change == "shifted" ? status.detail.contains("metadata changed") : status.detail.contains("packet")), Comment(rawValue: status.detail))
        #expect(batch.statuses[next.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: job.destination))
        #expect(!FileManager.default.fileExists(atPath: next.destination))
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: prior) == sentinel)
        #expect(try Data(contentsOf: sibling.appendingPathComponent("keep")) == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".staxrip-batch-") } == [".staxrip-batch-unrelated"])
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func malformedAuditAndPrivateManifestChangesAreRejected() async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-copy-audit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mp4")
        try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=1", "-c:v", "libx264", "-pix_fmt", "yuv420p", source.path], tools: tools)
        let probe = try await MediaProbe.read(source, tools: tools)
        var c = EncodeConfiguration(); c.selectCodec("Copy original")
        let contract = try VideoCopyContract.make(probe: probe, configuration: c)
        let manifest = try await VideoCopyManifest.capture(source, contract: contract, directory: root, tools: tools)
        #expect(manifest.count == 24)
        #expect(try await manifest.verify(source, probe: probe, tools: tools).contains("24 encoded packets"))
        let original = try Data(contentsOf: manifest.url)
        #expect(original.count == 24 * VideoCopyPacket.recordBytes)
        let permissions = try FileManager.default.attributesOfItem(atPath: manifest.url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        for bytes in [Data(original.dropLast()), original + Data([0]), Data(repeating: 0, count: original.count)] {
            try bytes.write(to: manifest.url)
            do { _ = try await manifest.verify(source, probe: probe, tools: tools); Issue.record("Changed manifest accepted") }
            catch { #expect(!(error is CancellationError)) }
        }
        try original.write(to: manifest.url)
        // Capture uses exclusive creation: it must never replace an existing manifest.
        do { _ = try await VideoCopyManifest.capture(source, contract: contract, directory: root, tools: tools); Issue.record("Existing manifest replaced") }
        catch { #expect(try Data(contentsOf: manifest.url) == original) }
        try FileManager.default.removeItem(at: manifest.url)
        try FileManager.default.createSymbolicLink(at: manifest.url, withDestinationURL: source)
        do { _ = try await manifest.verify(source, probe: probe, tools: tools); Issue.record("Manifest symlink followed") }
        catch { #expect(!(error is CancellationError)) }
        try FileManager.default.removeItem(at: manifest.url)
        let wrapper = root.appendingPathComponent("probe-wrapper")
        for body in ["printf 'malformed\\n'", "printf 'pts=0'; exit 0", "exit 9"] {
            try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: wrapper)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
            do {
                _ = try await VideoCopyManifest.capture(source, contract: contract, directory: root,
                    tools: FFmpegTools(ffmpeg: tools.ffmpeg, ffprobe: wrapper))
                Issue.record("Malformed or failed packet probe accepted")
            } catch { #expect(!(error is CancellationError), Comment(rawValue: error.localizedDescription)) }
            try FileManager.default.removeItem(at: manifest.url)
        }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: [false, true])
    func cancellationSettlesPacketToolBeforeCleanup(verifying: Bool) async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-copy-cancel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mp4")
        try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=1", "-c:v", "libx264", "-pix_fmt", "yuv420p", source.path], tools: tools)
        let bytes = try Data(contentsOf: source), probe = try await MediaProbe.read(source, tools: tools)
        var c = EncodeConfiguration(); c.selectCodec("Copy original")
        let contract = try VideoCopyContract.make(probe: probe, configuration: c)
        let manifest = verifying ? try await VideoCopyManifest.capture(source, contract: contract, directory: root, tools: tools) : nil
        let pidFile = root.appendingPathComponent("tool.pid"), wrapper = root.appendingPathComponent("probe-wrapper")
        try Data(("#!/bin/sh\nprintf '%s' \"$$\" > " + quote(pidFile.path) + "\nexec /bin/sleep 30\n").utf8).write(to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let wrapped = FFmpegTools(ffmpeg: tools.ffmpeg, ffprobe: wrapper)
        let task = Task {
            if let manifest { _ = try await manifest.verify(source, probe: probe, tools: wrapped) }
            else { _ = try await VideoCopyManifest.capture(source, contract: contract, directory: root, tools: wrapped) }
        }
        let until = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: pidFile.path) && Date() < until { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        do { try await task.value; Issue.record("Cancelled audit completed") }
        catch { #expect(error is CancellationError) }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH)
        #expect(try Data(contentsOf: source) == bytes)
        // Settlement has returned: owned staging may now be removed.
        try FileManager.default.removeItem(at: root.appendingPathComponent("video-packets.bin"))
    }

}
