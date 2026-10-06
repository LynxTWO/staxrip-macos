import Foundation
import Testing
@testable import StaxRipMac

final class VideoCopyStageDiagnosis: @unchecked Sendable {
    enum Case: String { case av1, tenBit, qualification }
    enum Stage: String { case entered, sourceEncoding, sourceRemux, sourceProbe, sourceFrames, sourceHash, sourceSamples, preflight, startingBatch, waitingBatch, outputHash, outputFrames, outputProbe, outputSubtitle, facts, completed, catchEntered, batchWaitEnded }
    private let lock = NSLock()
    private let id: Case
    private var stage = Stage.entered
    private var events: [ChapterPlan.WriteEvent] = []
    private var fixture = 0, batch = 0
    init(_ id: Case) { self.id = id }
    func enter(_ next: Stage) {
        lock.withLock {
            stage = next
            if next == .sourceEncoding { fixture += 1 }
            if next == .startingBatch { batch += 1 }
            print("VIDEO_COPY_CASE id=\(id.rawValue) fixture=\(fixture) batch=\(batch) stage=\(stage.rawValue) chapter=none")
        }
    }
    func chapter(_ event: ChapterPlan.WriteEvent) {
        lock.withLock { events.append(event); print("VIDEO_COPY_CASE id=\(id.rawValue) fixture=\(fixture) batch=\(batch) stage=\(stage.rawValue) chapter=\(event.rawValue)") }
    }
    var chapterEvents: [ChapterPlan.WriteEvent] { lock.withLock { events } }
}

private final class ChapterWriteGate: @unchecked Sendable {
    let entered = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var done = false
    private var expired = false
    private var holding = false
    private var peerWrote = false
    private var task: Task<Void, Error>?
    private var cancelRequested = false
    func install(_ owned: Task<Void, Error>) {
        lock.lock(); task = owned; let cancel = cancelRequested; lock.unlock()
        if cancel { owned.cancel() }
    }
    func cancel() {
        lock.lock(); cancelRequested = true; let owned = task; lock.unlock(); owned?.cancel()
    }
    func beginHold() { lock.withLock { holding = true } }
    func endHold(timedOut: Bool) {
        lock.withLock { holding = false; if timedOut { expired = true } }
    }
    func peerWriteReturned() {
        lock.withLock { if holding && !expired && !done { peerWrote = true } }
        release.signal()
    }
    var peerCompletedInTime: Bool { lock.withLock { peerWrote && !expired } }
    func hold() {
        beginHold()
        entered.continuation.yield(()); entered.continuation.finish()
        let timedOut = release.wait(timeout: .now()+10) != .success
        // An actual timeout always wins final acceptance, even if a late peer
        // recorded its write in the gap before this thread reacquired the lock.
        endHold(timedOut: timedOut)
        if timedOut { Issue.record("Generated chapter gate expired") }
    }
    func finished() { lock.withLock { done = true }; entered.continuation.finish() }
    var completed: Bool { lock.withLock { done } }
    var didExpire: Bool { lock.withLock { expired } }
    func clearAfterJoin() { lock.withLock { task = nil } }
}

struct ChapterTests {
    @Test func metadataWriteEventsFollowActualExclusiveWriteAndRefusal() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = try ChapterPlan.make(probe: probe(), configuration: configuration())
        let normal = VideoCopyStageDiagnosis(.qualification)
        try await ChapterPlan.$observeMetadataWrite.withValue({ normal.chapter($0) }) {
            try await plan.writeMetadata(to: directory)
        }
        #expect(normal.chapterEvents == [.bodyEntered,.submitting,.workerEntered,.writeReturned,.bodyResumed])
        let file = directory.appendingPathComponent("chapters.ffmetadata")
        let original = try Data(contentsOf: file)
        let refused = VideoCopyStageDiagnosis(.qualification)
        await #expect(throws: (any Error).self) {
            try await ChapterPlan.$observeMetadataWrite.withValue({ refused.chapter($0) }) {
                try await plan.writeMetadata(to: directory)
            }
        }
        #expect(refused.chapterEvents == [.bodyEntered,.submitting,.workerEntered,.writeRefused])
        #expect(try Data(contentsOf: file) == original)
        let absent = VideoCopyStageDiagnosis(.qualification)
        var noChapters = configuration(); noChapters.chapterEdits = ChapterEdits(mode: .remove)
        let empty = try ChapterPlan.make(probe: probe(), configuration: noChapters)
        try await ChapterPlan.$observeMetadataWrite.withValue({ absent.chapter($0) }) {
            try await empty.writeMetadata(to: directory)
        }
        #expect(absent.chapterEvents == [.bodyEntered,.noMetadata])
    }


    @Test func operationQueueCancellationWaitsForSubmittedWriteAndPreservesFailure() async throws {
        for point in ["before", "queued", "worker", "written", "collision"] {
            let directory = try root(), gate = ChapterWriteGate()
            let plan = try ChapterPlan.make(probe: probe(), configuration: configuration())
            let file = directory.appendingPathComponent("chapters.ffmetadata")
            let sentinel = Data("existing generated chapter file".utf8)
            if point == "collision" { try sentinel.write(to: file) }
            let events = VideoCopyStageDiagnosis(.qualification)
            let owned = Task {
                defer { gate.finished() }
                try await ChapterPlan.$prepareMetadataQueue.withValue({ queue in
                    if point == "queued" { queue.async { gate.hold() } }
                }) {
                    try await ChapterPlan.$observeMetadataWrite.withValue({ event in
                        events.chapter(event)
                        if event == .workerEntered { #expect(!Thread.isMainThread) }
                        if point == "before" && event == .bodyEntered { gate.hold() }
                        if (point == "worker" || point == "collision") && event == .workerEntered { gate.hold() }
                        if point == "written" && event == .writeReturned { gate.hold() }
                    }) { try await plan.writeMetadata(to: directory) }
                }
            }
            gate.install(owned)
            var observationError: (any Error)?
            do {
                for await _ in gate.entered.stream { break }
                gate.cancel()
                #expect(!gate.completed)
                if point == "queued" || point == "worker" { #expect(!FileManager.default.fileExists(atPath: file.path)) }
                if point == "written" { #expect(try Data(contentsOf: file) == plan.metadata) }
            } catch { observationError = error }
            gate.release.signal()
            let result = await owned.result // Never remove the directory before actual return.
            gate.clearAfterJoin()
            if let observationError { throw observationError } // Retain root after release and exact join.
            var expectedResult = false
            switch result {
            case .success: Issue.record("Cancelled generated write returned success")
            case .failure(let error):
                expectedResult = point == "collision" ? !(error is CancellationError) : error is CancellationError
                #expect(expectedResult)
            }
            #expect(gate.completed)
            let observed = events.chapterEvents
            if point == "before" {
                #expect(observed == [.bodyEntered])
                #expect(!FileManager.default.fileExists(atPath: file.path))
            } else if point == "collision" {
                #expect(observed == [.bodyEntered,.submitting,.workerEntered,.writeRefused])
                #expect(try Data(contentsOf: file) == sentinel)
            } else {
                #expect(observed == [.bodyEntered,.submitting,.workerEntered,.writeReturned,.bodyResumed])
                #expect(try Data(contentsOf: file) == plan.metadata)
            }
            if expectedResult && !gate.didExpire {
                try FileManager.default.removeItem(at: directory) // Operation joined; no queued write remains.
            }
        }
    }

    @Test func peerWriteWitnessPreservesTimeoutAndRejectsFallbackRelease() {
        let completed = ChapterWriteGate()
        completed.beginHold(); completed.peerWriteReturned(); completed.endHold(timedOut: false)
        #expect(completed.peerCompletedInTime && !completed.didExpire)
        let late = ChapterWriteGate()
        late.beginHold(); late.endHold(timedOut: true); late.peerWriteReturned()
        #expect(!late.peerCompletedInTime && late.didExpire)
        let raced = ChapterWriteGate()
        raced.beginHold(); raced.peerWriteReturned(); raced.endHold(timedOut: true)
        #expect(!raced.peerCompletedInTime && raced.didExpire)
        let fallback = ChapterWriteGate()
        fallback.beginHold(); fallback.release.signal(); fallback.endHold(timedOut: false)
        #expect(!fallback.peerCompletedInTime && !fallback.didExpire)
    }

    @Test func distinctWriteQueuesProgressWhileAnotherOperationIsHeld() async throws {
        let first = try root(), second = try root(), gate = ChapterWriteGate()
        let plan = try ChapterPlan.make(probe: probe(), configuration: configuration())
        final class Queues: @unchecked Sendable {
            let lock = NSLock(); var values: [DispatchQueue] = []
            func add(_ queue: DispatchQueue) { lock.withLock { values.append(queue) } }
        }
        let queues = Queues()
        let held = Task {
            defer { gate.finished() }
            try await ChapterPlan.$prepareMetadataQueue.withValue({ queue in
                queues.add(queue); queue.async { gate.hold() }
            }) { try await plan.writeMetadata(to: first) }
        }
        for await _ in gate.entered.stream { break }
        let other = Task {
            try await ChapterPlan.$prepareMetadataQueue.withValue({ queues.add($0) }) {
                try await ChapterPlan.$observeMetadataWrite.withValue({ event in
                    if event == .writeReturned { gate.peerWriteReturned() }
                }) { try await plan.writeMetadata(to: second) }
            }
        }
        let otherResult = await other.result
        gate.release.signal() // Failure fallback never supplies a positive witness.
        let heldResult = await held.result
        let independent = gate.peerCompletedInTime
        #expect(independent)
        #expect(queues.lock.withLock { queues.values.count == 2 && queues.values[0] !== queues.values[1] })
        try otherResult.get(); try heldResult.get()
        #expect(try Data(contentsOf: first.appendingPathComponent("chapters.ffmetadata")) == plan.metadata)
        #expect(try Data(contentsOf: second.appendingPathComponent("chapters.ffmetadata")) == plan.metadata)
        if independent {
            try FileManager.default.removeItem(at: first); try FileManager.default.removeItem(at: second)
        }
    }

    @Test func operationQueueWriteFailureReturnsWithoutCreatingOutput() async throws {
        let directory = try root()
        let plan = try ChapterPlan.make(probe: probe(), configuration: configuration())
        let events = VideoCopyStageDiagnosis(.qualification)
        let missing = directory.appendingPathComponent("missing-parent")
        await #expect(throws: (any Error).self) {
            try await ChapterPlan.$observeMetadataWrite.withValue({ events.chapter($0) }) {
                try await plan.writeMetadata(to: missing)
            }
        }
        #expect(events.chapterEvents == [.bodyEntered,.submitting,.workerEntered,.writeRefused])
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        try FileManager.default.removeItem(at: directory)
    }

    private func entries() -> [ChapterEntry] {
        [.init(startMilliseconds: 0, endMilliseconds: 2000, title: "Opening = #1; \\ [CHAPTER]"),
         .init(startMilliseconds: 2000, endMilliseconds: 4000, title: "Conversation 日本語"),
         .init(startMilliseconds: 4000, endMilliseconds: 6000, title: "Finale")]
    }
    private func configuration(_ container: String = "MKV") -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.container = container; c.audio = "No audio"
        c.audioTracks = []; c.subtitleTracks = []; c.subtitleMode = "Remove all subtitles"; c.speed = "Fast"
        c.chapterEdits = ChapterEdits(mode: .custom, entries: entries())
        return c
    }
    private func probe(duration: String = "6", start: Int? = 0, chapters: [[String: Any]] = []) throws -> MediaProbe {
        var video: [String: Any] = ["index": 0, "codec_type": "video", "codec_name": "h264", "pix_fmt": "yuv420p", "width": 160, "height": 96]
        if let start { video["start_pts"] = start }
        return try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: ["streams": [video], "format": ["duration": duration], "chapters": chapters]))
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chapters-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    @Test func textualTimesAndUntrustedEntriesHaveStrictBounds() throws {
        for (text, expected): (String, Int64) in [("0", 0), ("92.125", 92125), (" 1.2 ", 1200), ("604800.000", 604800000)] {
            #expect(try ChapterEdits.milliseconds(text) == expected)
            #expect(try ChapterEdits.milliseconds(ChapterEdits.secondsText(expected)) == expected)
        }
        for text in ["", "-1", "+1", "1e3", "NaN", "1,5", ".5", "1.", "1.0001", "604800.001", "999999", "1\n2"] {
            #expect(throws: (any Error).self) { try ChapterEdits.milliseconds(text) }
        }
        let valid = ChapterEdits(mode: .custom, entries: entries()); try valid.validate()
        var invalid: [ChapterEdits] = [.init(mode: .custom), .init(mode: .remove, entries: entries())]
        for change in ["negative", "zero", "overlap", "order", "maximum", "duplicate", "empty", "control", "long"] {
            var c = valid
            switch change {
            case "negative": c.entries[0].startMilliseconds = -1
            case "zero": c.entries[0].endMilliseconds = 0
            case "overlap": c.entries[1].startMilliseconds = 1999
            case "order": c.entries.swapAt(0, 1)
            case "maximum": c.entries[2].endMilliseconds = Int64.max
            case "duplicate": c.entries[1].id = c.entries[0].id
            case "empty": c.entries[0].title = " "
            case "control": c.entries[0].title = "Title\n[CHAPTER]\nSTART=0"
            default: c.entries[0].title = String(repeating: "é", count: 2049)
            }
            invalid.append(c)
        }
        invalid.append(.init(mode: .custom, entries: (0...1000).map { .init(startMilliseconds: Int64($0), endMilliseconds: Int64($0 + 1), title: "Item") }))
        for bad in invalid { #expect(throws: (any Error).self) { try bad.validate() } }
    }

    @Test func trimIntersectionsAndContainerRulesRefuseAmbiguousRanges() throws {
        let source = try probe(); var c = configuration()
        c.picture.start = 2; c.picture.end = 4
        let exact = try ChapterPlan.make(probe: source, configuration: c)
        #expect(exact.expected.count == 1 && exact.expected[0].start == 0 && exact.expected[0].end == 2)
        let text = try #require(exact.metadata).map { $0 }
        #expect(String(decoding: text, as: UTF8.self).components(separatedBy: "[CHAPTER]").count == 2)
        c.picture.start = 1.125123; c.picture.end = 4.375357
        let fractional = try ChapterPlan.make(probe: source, configuration: c)
        #expect(fractional.expected.map(\.start) == [0, 0.874877, 2.874877])
        #expect(fractional.expected.map(\.end) == [0.874877, 2.874877, 3.250234])
        c.chapterEdits?.entries = [.init(startMilliseconds: 0, endMilliseconds: 1000, title: "Outside")]
        let empty = try ChapterPlan.make(probe: source, configuration: c)
        #expect(empty.expected.isEmpty && empty.metadata == nil && !empty.preservesSource)
        for start in [nil, 1, -1] {
            #expect(throws: (any Error).self) { try ChapterPlan.make(probe: probe(start: start), configuration: configuration()) }
        }
        for duration in ["0", "nan", "unknown", "604801"] {
            #expect(throws: (any Error).self) { try ChapterPlan.make(probe: probe(duration: duration), configuration: configuration()) }
        }
        c = configuration(); c.picture.start = 1.9995; c.picture.end = 4
        #expect(throws: (any Error).self) { try ChapterPlan.make(probe: source, configuration: c) }
        c.picture.start = 0.1234567
        #expect(throws: (any Error).self) { try ChapterPlan.make(probe: source, configuration: c) }
        c = configuration("MP4"); c.chapterEdits?.entries[1].startMilliseconds = 2100
        #expect(throws: (any Error).self) { try ChapterPlan.make(probe: source, configuration: c) }
        c.container = "MKV"; _ = try ChapterPlan.make(probe: source, configuration: c)
        c.chapterEdits?.entries[2].endMilliseconds = 6001
        #expect(throws: (any Error).self) { try ChapterPlan.make(probe: source, configuration: c) }
        c.chapterEdits = .init(mode: .remove)
        #expect(try ChapterPlan.make(probe: source, configuration: c).expected.isEmpty)
        c.chapterEdits = nil; c.picture.start = 1
        #expect(try ChapterPlan.make(probe: source, configuration: c).preservesSource == false)
    }

    @Test func outputVerificationRejectsChangedTitlesTimesCountsAndInvalidPrecision() throws {
        let c = configuration(), source = try probe()
        let expected = try ContainerPreservation.make(probe: source, configuration: c)
        var chapters: [[String: Any]] = entries().map { ["time_base": "1/1000", "start": $0.startMilliseconds, "end": $0.endMilliseconds, "tags": ["title": $0.title]] }
        _ = try expected.verify(probe(chapters: chapters))
        for change in ["title", "start", "end", "count", "zero", "coarse"] {
            var bad = chapters
            switch change {
            case "title": bad[0]["tags"] = ["title": "Different"]
            case "start": bad[1]["start"] = 2100
            case "end": bad[2]["end"] = 5900
            case "count": bad.removeLast()
            case "zero": bad[0]["end"] = 0
            default: bad[0]["time_base"] = "1/100"
            }
            #expect(throws: (any Error).self) { try expected.verify(probe(chapters: bad)) }
        }
        chapters[0]["tags"] = ["title": entries()[0].title, "TITLE": "Other"]
        #expect(throws: (any Error).self) { try expected.verify(probe(chapters: chapters)) }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(3)), arguments: ["MKV", "MP4"])
    func actualPlansKeepLiteralTitlesAndSupportedTrimSemantics(container: String) async throws {
        let tools = try #require(FFmpegTools.discover()), root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = root.appendingPathComponent("raw.mp4"), source = root.appendingPathComponent("source.mkv")
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=6", "-c:v", "libx264", "-preset", "ultrafast", raw.path])
        try #require(generated.status == 0)
        let originalPlan = try ChapterPlan.make(probe: probe(), configuration: configuration())
        try await originalPlan.writeMetadata(to: root)
        let mux = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-i", raw.path, "-f", "ffmetadata", "-i", root.appendingPathComponent("chapters.ffmetadata").path, "-map", "0:v:0", "-c:v", "copy", "-map_chapters", "1", source.path])
        try #require(mux.status == 0)
        let original = try Data(contentsOf: source), inspected = try await MediaProbe.read(source, tools: tools)
        for variant in ["authored", "boundary", "fractional", "excluded", "remove", "preserve", "legacy-trim"] {
            let directory = root.appendingPathComponent(variant); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let output = directory.appendingPathComponent("output." + container.lowercased())
            var c = configuration(container)
            c.chapterEdits?.entries[0].title = "  New = #1; \\ [CHAPTER] 日本語 #\u{0301};\u{0301}\\\u{0301}  "
            switch variant {
            case "boundary": c.picture.start = 2; c.picture.end = 4
            case "fractional": c.picture.start = 1.125123; c.picture.end = 4.375357
            case "excluded": c.chapterEdits?.entries = [.init(startMilliseconds: 0, endMilliseconds: 1000, title: "Outside")]; c.picture.start = 2; c.picture.end = 4
            case "remove": c.chapterEdits = .init(mode: .remove)
            case "preserve": c.chapterEdits = nil
            case "legacy-trim": c.chapterEdits = nil; c.picture.start = 2; c.picture.end = 4
            default: break
            }
            let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: c, created: Date())
            let plan = try EncodePlan.make(job: job, probe: inspected, encoders: ["libx264"], staged: output)
            try await plan.chapterPlan.writeMetadata(to: directory)
            let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: plan.arguments)
            try #require(result.status == 0, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
            let actual = try await MediaProbe.read(output, tools: tools)
            _ = try plan.containerPreservation.verify(actual)
            let chapters = try ContainerPreservation.readChapters(actual)
            let expectedCount = ["excluded", "remove", "legacy-trim"].contains(variant) ? 0 : variant == "boundary" ? 1 : 3
            #expect(chapters.count == expectedCount)
            if variant == "authored" { #expect(chapters[0].title == c.chapterEdits?.entries[0].title) }
            if variant == "boundary" { #expect(chapters[0].start == 0 && chapters[0].end == 2) }
            if variant == "fractional" {
                for (actual, expected) in zip(chapters, [(0.0, 0.874877), (0.874877, 2.874877), (2.874877, 3.250234)]) {
                    #expect(abs(actual.start - expected.0) <= actual.tick + 0.0000001)
                    #expect(abs(actual.end - expected.1) <= actual.tick + 0.0000001)
                }
            }
        }
        #expect(try Data(contentsOf: source) == original)
    }

    @MainActor @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["MKV", "MP4"])
    func realBatchAuthorsChaptersAlongsideExternalCaptions(container: String) async throws {
        let tools = try #require(FFmpegTools.discover()), root = try root()
        let batch = BatchController()
        defer { if batch.running { batch.cancel() } else { try? FileManager.default.removeItem(at: root) } }
        let source = root.appendingPathComponent("source.mp4"), output = root.appendingPathComponent("output." + container.lowercased()), caption = root.appendingPathComponent("captions.srt")
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=6", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        try #require(generated.status == 0)
        try Data("1\n00:00:00,250 --> 00:00:01,250\nLiteral caption\n\n".utf8).write(to: caption)
        let sourceBytes = try Data(contentsOf: source), captionBytes = try Data(contentsOf: caption)
        var c = configuration(container); c.externalSubtitle = .init(path: caption.path, language: "eng", title: "Captions")
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: c, created: Date())
        let check = try await QueuePreflight.inspect(job, tools: tools, encoders: ["libx264"])
        #expect(check.kind == .checked)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["captions.srt", "source.mp4"])
        batch.tools = tools; batch.encoders = ["libx264"]; batch.start([job])
        do { while batch.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch { batch.cancel(); throw error }
        try #require(batch.statuses[job.id]?.phase == "Completed", Comment(rawValue: batch.statuses[job.id]?.detail ?? "No status"))
        let actual = try await MediaProbe.read(output, tools: tools)
        #expect(try ContainerPreservation.readChapters(actual).map(\.title) == entries().map(\.title))
        #expect(actual.streams.filter { $0.codec_type == "subtitle" }.count == 1)
        #expect(batch.statuses[job.id]?.detail.contains("external caption cues") == true)
        let savedBytes = try Data(contentsOf: output)
        let collision = BatchController(); collision.tools = tools; collision.encoders = ["libx264"]; collision.start([job])
        while collision.running { try await Task.sleep(for: .milliseconds(10)) }
        #expect(collision.statuses[job.id]?.phase == "Failed")
        #expect(try Data(contentsOf: output) == savedBytes)
        #expect(try Data(contentsOf: source) == sourceBytes && Data(contentsOf: caption) == captionBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["captions.srt", "output." + container.lowercased(), "source.mp4"])
    }
}
