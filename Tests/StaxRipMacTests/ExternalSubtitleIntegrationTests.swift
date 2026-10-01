import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
@MainActor
struct ExternalSubtitleIntegrationTests {
    private let plain = "1\n00:00:00,083 --> 00:00:00,417\nCafé — 起点\nPlain & text\n\n2\n00:00:00,625 --> 00:00:00,958\nSecond cue\n\n"
    private struct Fixture {
        let root: URL, source: URL, captions: URL
        let tools: FFmpegTools
        let sourceBytes: Data, captionBytes: Data
        let configuration: EncodeConfiguration
    }
    private func run(_ args: [String], tools: FFmpegTools) async throws -> Data {
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n"] + args)
        try #require(result.status == 0 && !result.truncated, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
        return result.stdout
    }
    private func fixture(container: String = "MKV", embedded: Bool = false) async throws -> Fixture {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("external-mux-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        var ready = false
        defer { if !ready { try? FileManager.default.removeItem(at: root) } }
        let base = root.appendingPathComponent("base.mp4"), captions = root.appendingPathComponent("captions.srt")
        _ = try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=1", "-c:v", "libx264", "-preset", "ultrafast", base.path], tools: tools)
        try Data(plain.utf8).write(to: captions)
        var source = base
        if embedded {
            let first = root.appendingPathComponent("first.srt"), second = root.appendingPathComponent("second.srt")
            try Data("1\n00:00:00,100 --> 00:00:00,800\nEmbedded first\n\n".utf8).write(to: first)
            try Data("1\n00:00:00,200 --> 00:00:00,900\nEmbedded second\n\n".utf8).write(to: second)
            source = root.appendingPathComponent("embedded." + container.lowercased())
            _ = try await run(["-i", base.path, "-f", "srt", "-i", first.path, "-f", "srt", "-i", second.path,
                              "-map", "0:v:0", "-map", "1:0", "-map", "2:0", "-c:v", "copy", "-c:s", container == "MP4" ? "mov_text" : "copy", source.path], tools: tools)
        }
        let sibling = root.appendingPathComponent(".staxrip-batch-unrelated")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        try Data("protected sibling".utf8).write(to: sibling.appendingPathComponent("keep"))
        try Data("prior output".utf8).write(to: root.appendingPathComponent("prior.mkv"))
        var c = EncodeConfiguration()
        c.codec = "H.264"; c.encoder = "x264"; c.container = container; c.speed = "Fast"
        c.audio = "No audio"; c.picture.deinterlace = "Off"
        c.subtitleMode = embedded ? "Keep embedded tracks" : "Remove all subtitles"
        c.subtitleTracks = embedded ? [2] : nil
        c.externalSubtitle = ExternalSubtitle(path: captions.path, language: "fra", title: "Generated captions")
        ready = true
        return Fixture(root: root, source: source, captions: captions, tools: tools,
                       sourceBytes: try Data(contentsOf: source), captionBytes: Data(plain.utf8), configuration: c)
    }
    private func job(_ f: Fixture, name: String = "result") -> QueueJob {
        QueueJob(id: UUID(), source: f.source.path, isDemo: false, destination: f.root.appendingPathComponent(name + "." + f.configuration.container.lowercased()).path, configuration: f.configuration, created: Date())
    }
    private func finish(_ batch: BatchController) async throws {
        do { while batch.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch { batch.cancel(); throw error }
    }
    private func cleanup(_ f: Fixture, batch: BatchController?) {
        if batch?.running == true { batch?.cancel() }
        else { try? FileManager.default.removeItem(at: f.root) }
    }
    private func protected(_ f: Fixture, captionBytes: Data? = nil) throws {
        #expect(try Data(contentsOf: f.source) == f.sourceBytes)
        #expect(try Data(contentsOf: f.captions) == (captionBytes ?? f.captionBytes))
        #expect(try Data(contentsOf: f.root.appendingPathComponent("prior.mkv")) == Data("prior output".utf8))
        #expect(try Data(contentsOf: f.root.appendingPathComponent(".staxrip-batch-unrelated/keep")) == Data("protected sibling".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).filter { $0.hasPrefix(".staxrip-batch-") } == [".staxrip-batch-unrelated"])
    }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func wrapper(_ f: Fixture, body: String) throws -> FFmpegTools {
        let file = f.root.appendingPathComponent("encoder-wrapper")
        try Data(("#!/bin/sh\nset -e\n" + body + "\nexec " + quote(f.tools.ffmpeg.path) + " \"$@\"\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return FFmpegTools(ffmpeg: file, ffprobe: f.tools.ffprobe)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["MKV", "MP4", "MKV embedded", "MP4 embedded", "MKV unspecified", "MP4 unspecified"])
    func multilingualCaptionsAreVerifiedWithIndependentEmbeddedSelection(mode: String) async throws {
        let embedded = mode.contains("embedded")
        let f = try await fixture(container: mode.hasPrefix("MP4") ? "MP4" : "MKV", embedded: embedded)
        var batch: BatchController?
        defer { cleanup(f, batch: batch) }
        var item = job(f)
        if mode.contains("unspecified") { item.configuration.externalSubtitle?.language = "und"; item.configuration.externalSubtitle?.title = "" }
        let journal = f.root.appendingPathComponent("journal.json")
        let before = try Set(FileManager.default.contentsOfDirectory(atPath: f.root.path))
        let check = try await QueuePreflight.inspect(item, tools: f.tools, encoders: ["libx264"])
        #expect(check.kind == .checked && check.detail.contains("2 captured cues"))
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: f.root.path)) == before)
        let controller = BatchController(journalURL: journal); batch = controller
        controller.tools = f.tools; controller.encoders = ["libx264"]; controller.start([item]); try await finish(controller)
        let status = try #require(controller.statuses[item.id])
        try #require(status.phase == "Completed", Comment(rawValue: status.detail))
        #expect(status.detail.contains("Verified 2 external caption cues"))
        let actual = try await MediaProbe.read(URL(fileURLWithPath: item.destination), tools: f.tools)
        #expect(actual.streams.filter { $0.codec_type == "subtitle" }.count == (embedded ? 2 : 1))
        let ordinal = embedded ? 1 : 0
        let decoded = try await run(["-i", item.destination, "-map", "0:s:\(ordinal)", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: f.tools)
        #expect(decoded == f.captionBytes)
        if embedded {
            let retained = try await run(["-i", item.destination, "-map", "0:s:0", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: f.tools)
            #expect(retained == Data("1\n00:00:00,200 --> 00:00:00,900\nEmbedded second\n\n".utf8))
        }
        let recovered = try BatchJournal.read(from: journal)
        #expect(recovered.jobs[0].configuration.externalSubtitle == item.configuration.externalSubtitle)
        #expect(recovered.restoredStatuses()[item.id]?.phase == "Completed")
        try protected(f)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["text", "timing", "trimmed timing", "unicode", "missing", "extra", "oversized extraction"])
    func changedCaptionsCannotPublishEvenWithSuccessfulEncoding(change: String) async throws {
        let f = try await fixture()
        var batch: BatchController?
        defer { cleanup(f, batch: batch) }
        let altered = f.root.appendingPathComponent("altered.srt")
        let text: String
        switch change {
        case "timing": text = plain.replacingOccurrences(of: "00:00:00,083", with: "00:00:00,084")
        case "trimmed timing": text = "1\n00:00:00,001 --> 00:00:00,317\nCafé — 起点\nPlain & text\n\n2\n00:00:00,525 --> 00:00:00,700\nSecond cue\n\n"
        case "unicode": text = plain.replacingOccurrences(of: "Café", with: "Cafe\u{301}")
        case "missing": text = String(plain.components(separatedBy: "\n\n")[0]) + "\n\n"
        case "extra": text = plain + "3\n00:00:00,975 --> 00:00:00,999\nExtra\n\n"
        default: text = plain.replacingOccurrences(of: "Second cue", with: "Changed cue")
        }
        try Data(text.utf8).write(to: altered)
        let body = change == "oversized extraction"
            ? "for target do :; done\nif [ \"$target\" = \"pipe:1\" ]; then exec /usr/bin/head -c 2097153 /dev/zero; fi"
            : "for arg do\ncase \"$arg\" in */external.srt) /bin/cp " + quote(altered.path) + " \"$arg\";; esac\ndone"
        let wrapped = try wrapper(f, body: body)
        var item = job(f)
        if change == "trimmed timing" { item.configuration.picture.start = 0.1; item.configuration.picture.end = 0.8 }
        let next = job(f, name: "next")
        let controller = BatchController(journalURL: f.root.appendingPathComponent("journal.json")); batch = controller
        controller.tools = wrapped; controller.encoders = ["libx264"]; controller.start([item, next]); try await finish(controller)
        let status = try #require(controller.statuses[item.id])
        #expect(status.phase == "Failed", Comment(rawValue: status.detail))
        #expect(status.detail.contains(change == "oversized extraction" ? "output bounds" : "caption text or cue timing changed"))
        #expect(!FileManager.default.fileExists(atPath: item.destination) && !FileManager.default.fileExists(atPath: next.destination))
        #expect(controller.statuses[next.id]?.phase == "Pending")
        try protected(f)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: [false, true])
    func capturedFileDrivesCurrentEncodeAndNextAttemptReadsFreshBytes(trimmed: Bool) async throws {
        let f = try await fixture()
        var batch: BatchController?
        defer { cleanup(f, batch: batch) }
        let changed = Data("1\n00:00:00,100 --> 00:00:00,900\nFresh next attempt\n\n".utf8)
        let replacement = f.root.appendingPathComponent("replacement.srt"); try changed.write(to: replacement)
        let tools = try wrapper(f, body: "for arg do\nif [ \"$arg\" = \"-progress\" ]; then /bin/cp " + quote(replacement.path) + " " + quote(f.captions.path) + "; fi\ndone")
        let controller = BatchController(); batch = controller; controller.tools = tools; controller.encoders = ["libx264"]
        let expectedFiles = trimmed ? [
            Data("1\n00:00:00,000 --> 00:00:00,317\nCafé — 起点\nPlain & text\n\n2\n00:00:00,525 --> 00:00:00,700\nSecond cue\n\n".utf8),
            Data("1\n00:00:00,000 --> 00:00:00,700\nFresh next attempt\n\n".utf8)
        ] : [f.captionBytes, changed]
        for (index, expected) in expectedFiles.enumerated() {
            var item = job(f, name: "attempt-\(index)")
            if trimmed { item.configuration.picture.start = 0.1; item.configuration.picture.end = 0.8 }
            controller.start([item]); try await finish(controller)
            try #require(controller.statuses[item.id]?.phase == "Completed", Comment(rawValue: controller.statuses[item.id]?.detail ?? "Missing status"))
            let decoded = try await run(["-i", item.destination, "-map", "0:s:0", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: f.tools)
            #expect(decoded == expected)
        }
        try protected(f, captionBytes: changed)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func stalePreflightCannotAuthorizeChangedCaptions() async throws {
        let f = try await fixture()
        var batch: BatchController?
        defer { cleanup(f, batch: batch) }
        let item = job(f)
        _ = try await QueuePreflight.inspect(item, tools: f.tools, encoders: ["libx264"])
        let invalid = Data("1\n00:00:00,000 --> 00:00:00,900\n<i>Changed styling</i>\n\n".utf8)
        try invalid.write(to: f.captions)
        await #expect(throws: (any Error).self) { try await QueuePreflight.inspect(item, tools: f.tools, encoders: ["libx264"]) }
        let controller = BatchController(); batch = controller; controller.tools = f.tools; controller.encoders = ["libx264"]
        controller.start([item]); try await finish(controller)
        #expect(controller.statuses[item.id]?.phase == "Failed")
        #expect(controller.statuses[item.id]?.detail.contains("Cue 1") == true)
        #expect(!FileManager.default.fileExists(atPath: item.destination))
        try protected(f, captionBytes: invalid)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func cancelledVerifierSettlesItsProcessBeforeOwnedCleanup() async throws {
        let f = try await fixture()
        var batch: BatchController?
        defer { cleanup(f, batch: batch) }
        let pidFile = f.root.appendingPathComponent("verifier.pid")
        let tools = try wrapper(f, body: "for target do :; done\nif [ \"$target\" = \"pipe:1\" ]; then printf '%s' \"$$\" > " + quote(pidFile.path) + "; exec /bin/sleep 30; fi")
        let item = job(f), next = job(f, name: "next")
        let controller = BatchController(); batch = controller; controller.tools = tools; controller.encoders = ["libx264"]
        controller.start([item, next])
        while controller.running && !FileManager.default.fileExists(atPath: pidFile.path) { try await Task.sleep(for: .milliseconds(10)) }
        try #require(controller.running && controller.statuses[item.id]?.phase == "Verifying")
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        controller.cancel(); try await finish(controller)
        #expect(controller.statuses[item.id]?.phase == "Cancelled")
        #expect(controller.statuses[next.id]?.phase == "Pending")
        let alive = Darwin.kill(pid, 0), code = errno
        #expect(alive == -1 && code == ESRCH)
        #expect(!FileManager.default.fileExists(atPath: item.destination))
        try protected(f)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func collisionPreservesExistingOutputAfterCaptionVerification() async throws {
        let f = try await fixture()
        var batch: BatchController?
        defer { cleanup(f, batch: batch) }
        let item = job(f), next = job(f, name: "next"), prior = Data("competing output".utf8)
        let controller = BatchController(publishOutput: { staged, output in
            try prior.write(to: output, options: .withoutOverwriting)
            try await ExportPublication.publishAsync(staged: staged, destination: output)
        })
        batch = controller; controller.tools = f.tools; controller.encoders = ["libx264"]
        controller.start([item, next]); try await finish(controller)
        #expect(controller.statuses[item.id]?.phase == "Failed")
        #expect(controller.statuses[item.id]?.detail.contains("nothing was overwritten") == true)
        #expect(controller.statuses[next.id]?.phase == "Pending")
        #expect(try Data(contentsOf: URL(fileURLWithPath: item.destination)) == prior)
        try protected(f)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["language", "title", "codec"])
    func alteredStagedMetadataOrCodecCannotPublish(field: String) async throws {
        let f = try await fixture()
        var batch: BatchController?
        defer { cleanup(f, batch: batch) }
        let alteration = field == "language" ? "-metadata:s:s:0 language=eng" : field == "title" ? "-metadata:s:s:0 title=Changed" : "-c:s ass"
        let body = "for target do :; done\ncase \"$target\" in */encoded.mkv)\n"
            + quote(f.tools.ffmpeg.path) + " \"$@\"\n"
            + quote(f.tools.ffmpeg.path) + " -v error -n -i \"$target\" -map 0 -c copy " + alteration + " \"$target.changed.mkv\"\n"
            + "/bin/mv \"$target.changed.mkv\" \"$target\"\nexit 0;; esac"
        let wrapped = try wrapper(f, body: body), item = job(f)
        let controller = BatchController(); batch = controller; controller.tools = wrapped; controller.encoders = ["libx264"]
        controller.start([item]); try await finish(controller)
        let status = try #require(controller.statuses[item.id])
        #expect(status.phase == "Failed")
        #expect(status.detail.contains(field == "codec" ? "wrong codec" : "language or title changed"), Comment(rawValue: status.detail))
        #expect(!FileManager.default.fileExists(atPath: item.destination))
        try protected(f)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func verificationDeadlineDoesNotMutateMediaOrLeaveAWriterRunning() async throws {
        let f = try await fixture()
        var batch: BatchController?
        defer { cleanup(f, batch: batch) }
        let item = job(f), output = URL(fileURLWithPath: item.destination)
        let controller = BatchController(); batch = controller; controller.tools = f.tools; controller.encoders = ["libx264"]
        controller.start([item]); try await finish(controller)
        try #require(controller.statuses[item.id]?.phase == "Completed")
        let before = try Data(contentsOf: output), probe = try await MediaProbe.read(output, tools: f.tools)
        let pidFile = f.root.appendingPathComponent("timed-verifier.pid")
        let wrapped = try wrapper(f, body: "printf '%s' \"$$\" > " + quote(pidFile.path) + "\nexec /bin/sleep 30")
        let contract = ExternalSubtitleExport(reference: try #require(item.configuration.externalSubtitle),
                                             document: try SubRipDocument(data: f.captionBytes), ordinal: 0, codec: "subrip")
        do {
            _ = try await contract.verify(output, probe: probe, tools: wrapped, timeout: 0.2)
            Issue.record("The blocked verifier must reach its deadline")
        } catch { #expect(error.localizedDescription.contains("time limit"), Comment(rawValue: error.localizedDescription)) }
        if FileManager.default.fileExists(atPath: pidFile.path) {
            let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
            let alive = Darwin.kill(pid, 0), code = errno
            #expect(alive == -1 && code == ESRCH)
        }
        #expect(try Data(contentsOf: output) == before)
        try protected(f)
    }
}
