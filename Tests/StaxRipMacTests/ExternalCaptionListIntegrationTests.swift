import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@MainActor
struct ExternalCaptionListIntegrationTests {
    private let titleB = "Français = #; \\ e\u{301}"
    private let textA = "1\n00:00:00,000 --> 00:00:02,000\nEnglish — e\u{301}\n\n"
    private let textB = "1\n00:00:01,000 --> 00:00:03,000\nFrançais — 起点\n\n"
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func run(_ arguments: [String], tools: FFmpegTools) async throws -> Data {
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n"] + arguments)
        try #require(result.status == 0 && !result.truncated, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
        return result.stdout
    }
    private struct Fixture {
        let root, source, a, b: URL
        let sourceBytes: Data
        let tools: FFmpegTools
    }
    private func fixture(_ container: String, embedded: Bool) async throws -> Fixture {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caption-list-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        var ready = false
        defer { if !ready { try? FileManager.default.removeItem(at: root) } }
        let base = root.appendingPathComponent("base.mp4"), a = root.appendingPathComponent("english.srt"), b = root.appendingPathComponent("french.srt")
        try Data(textA.utf8).write(to: a); try Data(textB.utf8).write(to: b)
        _ = try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=3", "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p", base.path], tools: tools)
        var source = base
        if embedded {
            let cue = root.appendingPathComponent("embedded.srt")
            try Data("1\n00:00:00,200 --> 00:00:01,200\nEmbedded text\n\n".utf8).write(to: cue)
            source = root.appendingPathComponent("source." + container.lowercased())
            _ = try await run(["-i", base.path, "-f", "srt", "-i", cue.path, "-map", "0:v:0", "-map", "1:0", "-c:v", "copy", "-c:s", container == "MP4" ? "mov_text" : "copy", "-metadata:s:s:0", "language=deu", "-metadata:s:s:0", "title=Source German", source.path], tools: tools)
        }
        try Data("Prior output".utf8).write(to: root.appendingPathComponent("prior.mkv"))
        ready = true
        return Fixture(root: root, source: source, a: a, b: b, sourceBytes: try Data(contentsOf: source), tools: tools)
    }
    private func configuration(_ f: Fixture, container: String) -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.speed = "Fast"; c.audio = "No audio"; c.container = container
        c.externalCaptions = [ExternalSubtitle(path: f.b.path, language: "fra", title: titleB), ExternalSubtitle(path: f.a.path, language: "eng", title: "English second")]
        return c
    }
    private func job(_ f: Fixture, _ c: EncodeConfiguration, name: String = "result") -> QueueJob {
        QueueJob(id: UUID(), source: f.source.path, isDemo: false, destination: f.root.appendingPathComponent(name + "." + c.container.lowercased()).path, configuration: c, created: Date())
    }
    private func protected(_ f: Fixture) throws {
        #expect(try Data(contentsOf: f.source) == f.sourceBytes)
        #expect(try Data(contentsOf: f.a) == Data(textA.utf8))
        #expect(try Data(contentsOf: f.b) == Data(textB.utf8))
        #expect(try Data(contentsOf: f.root.appendingPathComponent("prior.mkv")) == Data("Prior output".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["MKV", "MP4", "MKV trim", "MP4 trim", "MKV copy", "MP4 copy"])
    func everyAddedTrackHasIndependentMetadataTextAndTiming(mode: String) async throws {
        let container = mode.hasPrefix("MP4") ? "MP4" : "MKV", trimmed = mode.contains("trim")
        let f = try await fixture(container, embedded: !trimmed)
        let batch = BatchController(journalURL: f.root.appendingPathComponent("journal.json"))
        defer { if batch.running { batch.cancel() } else { try? FileManager.default.removeItem(at: f.root) } }
        var c = configuration(f, container: container)
        if mode.contains("copy") { c.selectCodec("Copy original") }
        if trimmed { c.picture.start = 0.5; c.picture.end = 2.5; c.subtitleMode = "Remove all subtitles" }
        c.chapterEdits = ChapterEdits(mode: .custom, entries: [ChapterEntry(startMilliseconds: 0, endMilliseconds: 1000, title: "First"), ChapterEntry(startMilliseconds: 1000, endMilliseconds: 3000, title: "Second")])
        let item = job(f, c)
        let encoders: Set<String> = c.copiesVideo ? [] : ["libx264"]
        let check = try await QueuePreflight.inspect(item, tools: f.tools, encoders: encoders)
        #expect(check.kind == (c.copiesVideo ? .deferred : .checked))
        batch.tools = f.tools; batch.encoders = encoders; batch.start([item])
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        let status = try #require(batch.statuses[item.id]); try #require(status.phase == "Completed", Comment(rawValue: status.detail))
        #expect(status.detail.contains("Track 1 (fra): Verified 1 external caption cues"))
        #expect(status.detail.contains("Track 2 (eng): Verified 1 external caption cues"))
        let output = URL(fileURLWithPath: item.destination), probe = try await MediaProbe.read(output, tools: f.tools)
        let tracks = probe.streams.filter { $0.codec_type == "subtitle" }
        try #require(tracks.count == (trimmed ? 2 : 3))
        let offset = trimmed ? 0 : 1
        let expected = trimmed ? ["1\n00:00:00,500 --> 00:00:02,000\nFrançais — 起点\n\n", "1\n00:00:00,000 --> 00:00:01,500\nEnglish — e\u{301}\n\n"] : [textB, textA]
        for index in 0..<2 {
            let stream = tracks[offset + index], tags = stream.tags ?? [:]
            #expect(tags.first { $0.key.lowercased() == "language" }?.value == (index == 0 ? "fra" : "eng"))
            let actualTitle = try #require(tags.first { $0.key.lowercased() == (container == "MP4" ? "name" : "title") }?.value)
            #expect(Data(actualTitle.utf8) == Data((index == 0 ? titleB : "English second").utf8))
            let decoded = try await run(["-i", output.path, "-map", "0:\(stream.index)", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: f.tools)
            #expect(decoded == Data(expected[index].utf8))
        }
        if !trimmed {
            let tags = tracks[0].tags ?? [:]
            #expect(tags.first { $0.key.lowercased() == "language" }?.value == "deu")
            if container == "MKV" {
                #expect(tags.first { $0.key.lowercased() == "title" }?.value == "Source German")
            } else {
                // Qualify retained labels against the existing plain-copy muxer behavior.
                let baseline = f.root.appendingPathComponent("plain-copy.mp4")
                _ = try await run(["-i", f.source.path, "-map", "0", "-c", "copy", baseline.path], tools: f.tools)
                let originalCopy = try await MediaProbe.read(baseline, tools: f.tools)
                let baselineTags = originalCopy.streams.first { $0.codec_type == "subtitle" }?.tags ?? [:]
                #expect(tags.first { $0.key.lowercased() == "name" }?.value == baselineTags.first { $0.key.lowercased() == "name" }?.value)
            }
            let embedded = try await run(["-i", output.path, "-map", "0:s:0", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: f.tools)
            #expect(embedded == Data("1\n00:00:00,200 --> 00:00:01,200\nEmbedded text\n\n".utf8))
        }
        let chapters = try ContainerPreservation.readChapters(probe)
        try #require(chapters.count == 2)
        #expect(chapters.map(\.title) == ["First", "Second"])
        #expect(abs(chapters[0].end - (trimmed ? 0.5 : 1)) < 0.001)
        #expect(abs(chapters[1].end - (trimmed ? 2 : 3)) < 0.001)
        try protected(f)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["text", "title", "missing", "invalid file", "outside trim"])
    func laterTrackRefusalStopsPublicationAndFollowingJobs(change: String) async throws {
        let f = try await fixture("MKV", embedded: false)
        let batch = BatchController(journalURL: f.root.appendingPathComponent("journal.json"))
        defer { if batch.running { batch.cancel() } else { try? FileManager.default.removeItem(at: f.root) } }
        var c = configuration(f, container: "MKV"); c.subtitleMode = "Remove all subtitles"
        let wrapper = f.root.appendingPathComponent("encoder-wrapper")
        var body = "#!/bin/sh\nset -e\n"
        if change == "text" {
            let altered = f.root.appendingPathComponent("altered.srt")
            try Data(textA.replacingOccurrences(of: "English", with: "Changed").utf8).write(to: altered)
            body += "for arg do\ncase \"$arg\" in */external-2.srt) /bin/cp " + quote(altered.path) + " \"$arg\";; esac\ndone\n"
        } else if change == "title" || change == "missing" {
            body += "for target do :; done\ncase \"$target\" in */encoded.mkv)\n" + quote(f.tools.ffmpeg.path) + " \"$@\"\n"
            body += quote(f.tools.ffmpeg.path) + " -v error -n -i \"$target\" "
            body += change == "missing" ? "-map 0:v:0 -map 0:s:0 -c copy " : "-map 0 -c copy -metadata:s:s:1 title=Changed "
            body += "\"$target.changed.mkv\"\n/bin/mv \"$target.changed.mkv\" \"$target\"\nexit 0;; esac\n"
        } else if change == "invalid file" {
            c.externalCaptions[1].path = f.root.appendingPathComponent("missing.srt").path
        } else { c.picture.start = 2.1; c.picture.end = 2.9 }
        body += "exec " + quote(f.tools.ffmpeg.path) + " \"$@\"\n"
        try Data(body.utf8).write(to: wrapper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let first = job(f, c), next = job(f, c, name: "next")
        batch.tools = FFmpegTools(ffmpeg: wrapper, ffprobe: f.tools.ffprobe); batch.encoders = ["libx264"]; batch.start([first, next])
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        let status = try #require(batch.statuses[first.id])
        #expect(status.phase == "Failed", Comment(rawValue: status.detail))
        if change != "missing" { #expect(status.detail.contains("Caption track 2"), Comment(rawValue: status.detail)) }
        #expect(batch.statuses[next.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: first.destination) && !FileManager.default.fileExists(atPath: next.destination))
        try protected(f)
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["MKV", "MP4"])
    func maximumTrackListVerifiesEveryIndependentStream(container: String) async throws {
        let f = try await fixture(container, embedded: false)
        let batch = BatchController(journalURL: f.root.appendingPathComponent("journal.json"))
        defer { if batch.running { batch.cancel() } else { try? FileManager.default.removeItem(at: f.root) } }
        var c = configuration(f, container: container); c.subtitleMode = "Remove all subtitles"; c.selectCodec("Copy original")
        var expected: [Data] = []
        c.externalCaptions = []
        for index in 0..<8 {
            let file = f.root.appendingPathComponent("track-\(index).srt")
            let bytes = Data("1\n00:00:00,000 --> 00:00:02,000\nIndependent track \(index)\n\n".utf8)
            try bytes.write(to: file); expected.append(bytes)
            c.externalCaptions.append(ExternalSubtitle(path: file.path, language: index.isMultiple(of: 2) ? "eng" : "fra", title: "Track \(index) é e\u{301} = #; \\"))
        }
        let item = job(f, c); batch.tools = f.tools; batch.encoders = []; batch.start([item])
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        let status = try #require(batch.statuses[item.id]); try #require(status.phase == "Completed", Comment(rawValue: status.detail))
        let output = URL(fileURLWithPath: item.destination), probe = try await MediaProbe.read(output, tools: f.tools)
        let tracks = probe.streams.filter { $0.codec_type == "subtitle" }
        try #require(tracks.count == 8)
        for index in 0..<8 {
            let bytes = try await run(["-i", output.path, "-map", "0:\(tracks[index].index)", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: f.tools)
            #expect(bytes == expected[index])
            let title = try #require(tracks[index].tags?.first { $0.key.lowercased() == (container == "MP4" ? "name" : "title") }?.value)
            #expect(Data(title.utf8) == Data(c.externalCaptions[index].title.utf8))
        }
        try protected(f)
    }

    private enum EntryFailure: Error, Equatable {
        case timedOut(String)
        case batchEnded(String)
    }

    private func waitForEntry(_ marker: URL, batch: BatchController, phase: String,
                              deadline: ContinuousClock.Instant) async throws -> ContinuousClock.Instant {
        let clock = ContinuousClock()
        while true {
            try Task.checkCancellation()
            let now = clock.now
            guard now < deadline else { throw EntryFailure.timedOut(phase) }
            if FileManager.default.fileExists(atPath: marker.path) { return now }
            guard batch.running else { throw EntryFailure.batchEnded(phase) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func cancelAndJoin(_ batch: BatchController) async -> Duration {
        let clock = ContinuousClock(), start = ContinuousClock.now
        batch.cancel()
        // An unstructured join is deliberately independent of cancellation of
        // this test task. Never remove staging while the batch still owns it.
        await Task { @MainActor in
            while batch.running { try? await Task.sleep(for: .milliseconds(10)) }
        }.value
        return start.duration(to: clock.now)
    }

    private func requireChildExited(_ marker: URL) throws {
        let pid = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
        #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH)
    }

    private func markPID(_ marker: URL) -> String {
        // Publish a complete marker; readers must never observe a partial PID.
        "printf '%s' \"$$\" > " + quote(marker.path + ".tmp") +
            "; /bin/mv " + quote(marker.path + ".tmp") + " " + quote(marker.path) + "; "
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func cancellingSecondTrackVerifierSettlesBeforeCleanup() async throws {
        let f = try await fixture("MKV", embedded: false)
        let batch = BatchController(journalURL: f.root.appendingPathComponent("journal.json"))
        defer { if batch.running { batch.cancel() } else { try? FileManager.default.removeItem(at: f.root) } }
        var c = configuration(f, container: "MKV"); c.subtitleMode = "Remove all subtitles"
        let first = f.root.appendingPathComponent("first-verifier.pid")
        let pidFile = f.root.appendingPathComponent("second-verifier.pid"), wrapper = f.root.appendingPathComponent("encoder-wrapper")
        let body = """
        #!/bin/sh
        set -e
        track=0
        for arg do
          case "$arg" in 0:1) track=1 ;; 0:2) track=2 ;; esac
          target="$arg"
        done
        if [ "$target" = "pipe:1" ]; then
          if [ "$track" = 1 ]; then \(markPID(first))fi
          if [ "$track" = 2 ]; then \(markPID(pidFile))exec /bin/sleep 30; fi
        fi
        exec \(quote(f.tools.ffmpeg.path)) "$@"

        """
        try Data(body.utf8).write(to: wrapper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let item = job(f, c), next = job(f, c, name: "next")
        batch.tools = FFmpegTools(ffmpeg: wrapper, ffprobe: f.tools.ffprobe); batch.encoders = ["libx264"]
        let started = ContinuousClock.now
        batch.start([item, next])
        var entryError: Error?
        do {
            let firstObserved = try await waitForEntry(first, batch: batch, phase: "preparation", deadline: started + .seconds(90))
            _ = try await waitForEntry(pidFile, batch: batch, phase: "second verifier", deadline: firstObserved + .seconds(10))
        } catch { entryError = error }
        let settlement = await cancelAndJoin(batch)
        #expect(settlement < .seconds(10))
        #expect(batch.statuses[item.id]?.phase == "Cancelled" && batch.statuses[next.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: item.destination))
        try protected(f)
        if FileManager.default.fileExists(atPath: first.path) { try requireChildExited(first) }
        if let entryError { throw entryError }
        try requireChildExited(pidFile)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["preparation", "second verifier"])
    func stalledCaptionPhaseTimesOutAndJoinsBeforeCleanup(phase: String) async throws {
        let f = try await fixture("MKV", embedded: false)
        let batch = BatchController(journalURL: f.root.appendingPathComponent("journal.json"))
        defer { if !batch.running { try? FileManager.default.removeItem(at: f.root) } }
        var c = configuration(f, container: "MKV"); c.subtitleMode = "Remove all subtitles"
        let childPID = f.root.appendingPathComponent("stalled-child.pid")
        let absentEntry = f.root.appendingPathComponent("absent-entry.pid"), wrapper = f.root.appendingPathComponent("encoder-wrapper")
        let trigger = phase == "preparation" ? "[ \"$encode\" = 1 ]" : "[ \"$first\" = 1 ] && [ \"$target\" = \"pipe:1\" ]"
        let expectedTrack = phase == "preparation" ? "$first" : "$second"
        let body = """
        #!/bin/sh
        set -e
        encode=0
        first=0
        second=0
        for arg do
          case "$arg" in -progress) encode=1 ;; 0:1) first=1 ;; 0:2) second=1 ;; esac
          target="$arg"
        done
        if [ "\(expectedTrack)" = 1 ] && [ "$target" = "pipe:1" ]; then \(markPID(absentEntry))fi
        if \(trigger); then \(markPID(childPID))exec /bin/sleep 30; fi
        exec \(quote(f.tools.ffmpeg.path)) "$@"

        """
        try Data(body.utf8).write(to: wrapper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let item = job(f, c), next = job(f, c, name: "next")
        batch.tools = FFmpegTools(ffmpeg: wrapper, ffprobe: f.tools.ffprobe); batch.encoders = ["libx264"]
        let started = ContinuousClock.now
        batch.start([item, next])
        var observed: Error?
        do {
            let entered = try await waitForEntry(childPID, batch: batch, phase: "stalled child", deadline: started + .seconds(90))
            let pid = try #require(Int32(String(contentsOf: childPID, encoding: .utf8)))
            #expect(Darwin.kill(pid, 0) == 0)
            // The same preparation guard must reject a known blocked child.
            // Only the deliberate preparation negative uses a short budget.
            let budget: Duration = phase == "preparation" ? .milliseconds(100) : .seconds(10)
            _ = try await waitForEntry(absentEntry, batch: batch, phase: phase, deadline: entered + budget)
        } catch { observed = error }
        let settlement = await cancelAndJoin(batch)
        #expect(settlement < .seconds(10))
        #expect(observed as? EntryFailure == .timedOut(phase))
        #expect(!FileManager.default.fileExists(atPath: absentEntry.path))
        #expect(batch.statuses[item.id]?.phase == "Cancelled" && batch.statuses[next.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: item.destination))
        try requireChildExited(childPID)
        try protected(f)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func laterTrackUsesCapturedBytesThenReadsFreshBytesOnRetry() async throws {
        let f = try await fixture("MKV", embedded: false)
        let batch = BatchController(journalURL: f.root.appendingPathComponent("journal.json"))
        defer { if batch.running { batch.cancel() } else { try? FileManager.default.removeItem(at: f.root) } }
        var c = configuration(f, container: "MKV"); c.subtitleMode = "Remove all subtitles"
        let changed = Data("1\n00:00:00,000 --> 00:00:02,000\nFresh second track\n\n".utf8)
        let replacement = f.root.appendingPathComponent("replacement.srt"), wrapper = f.root.appendingPathComponent("encoder-wrapper")
        try changed.write(to: replacement)
        let body = "#!/bin/sh\nset -e\nfor arg do\nif [ \"$arg\" = \"-progress\" ]; then /bin/cp " + quote(replacement.path) + " " + quote(f.a.path) + "; fi\ndone\nexec " + quote(f.tools.ffmpeg.path) + " \"$@\"\n"
        try Data(body.utf8).write(to: wrapper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        batch.tools = FFmpegTools(ffmpeg: wrapper, ffprobe: f.tools.ffprobe); batch.encoders = ["libx264"]
        _ = try await QueuePreflight.inspect(job(f, c), tools: f.tools, encoders: ["libx264"])
        for (index, expected) in [Data(textA.utf8), changed].enumerated() {
            let item = job(f, c, name: "attempt-\(index)"); batch.start([item])
            while batch.running { try await Task.sleep(for: .milliseconds(10)) }
            try #require(batch.statuses[item.id]?.phase == "Completed", Comment(rawValue: batch.statuses[item.id]?.detail ?? "No status"))
            let first = try await run(["-i", item.destination, "-map", "0:s:0", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: f.tools)
            let second = try await run(["-i", item.destination, "-map", "0:s:1", "-c:s", "srt", "-f", "srt", "pipe:1"], tools: f.tools)
            #expect(first == Data(textB.utf8) && second == expected)
        }
        #expect(try Data(contentsOf: f.a) == changed)
        try Data(textA.utf8).write(to: f.a)
        try protected(f)
    }

}
