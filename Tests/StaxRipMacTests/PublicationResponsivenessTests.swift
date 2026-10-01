import Foundation
import Testing
@testable import StaxRipMac

private final class PublicationTrace: @unchecked Sendable {
    private let lock = NSLock()
    private let start = ContinuousClock.now
    private var count = 0
    func record(_ event: String) {
        lock.withLock {
            guard count < 24 else { return }
            count += 1
            print("PUBLICATION_OBSERVATION \(start.duration(to: .now)) \(event) main=\(Thread.isMainThread)")
        }
    }
}

private final class PublicationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var entered = false
    private var mainThread = false
    private var staged: URL?
    private let observe: (@Sendable (String) -> Void)?
    init(observe: (@Sendable (String) -> Void)? = nil) { self.observe = observe }
    var snapshot: (Bool, Bool, URL?) { lock.withLock { (entered, mainThread, staged) } }
    func release() { observe?("gate release requested"); releaseSignal.signal() }
    func publish(_ source: URL, _ destination: URL) throws {
        lock.withLock { entered = true; mainThread = Thread.isMainThread; staged = source }
        observe?("gate entered")
        if let observe { DispatchQueue.main.async { observe("main queue canary") } }
        guard releaseSignal.wait(timeout: .now() + 20) == .success else {
            observe?("gate timed out")
            throw NativeExportError.invalid("Test publication gate timed out")
        }
        observe?("gate released; publishing")
        try ExportPublication.publish(staged: source, destination: destination)
    }
}

@MainActor
struct PublicationResponsivenessTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("publication-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    @Test(.timeLimit(.minutes(1)))
    func mainActorRunsWhileFilesystemWorkerWaits() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("staged"), output = root.appendingPathComponent("output")
        try Data("verified media".utf8).write(to: source)
        let trace = PublicationTrace(); trace.record("test body entered")
        let gate = PublicationGate(observe: { trace.record($0) }); defer { gate.release() }
        let task = Task {
            trace.record("child task entered")
            #if DEBUG
            try await ExportPublication.$observeBoundary.withValue({ trace.record($0) }) {
                try await ExportPublication.publishAsync(staged: source, destination: output, operation: { try gate.publish($0, $1) })
            }
            #else
            try await ExportPublication.publishAsync(staged: source, destination: output, operation: { try gate.publish($0, $1) })
            #endif
            trace.record("publication await returned")
        }
        var firstPoll = true
        while !gate.snapshot.0 {
            if firstPoll { trace.record("first poll suspending") }
            try await Task.sleep(for: .milliseconds(5))
            if firstPoll { trace.record("first poll resumed"); firstPoll = false }
        }
        trace.record("main actor observed gate")
        // This main-actor continuation must run before the blocked worker is released.
        MainActor.preconditionIsolated()
        #expect(!gate.snapshot.1)
        task.cancel()
        #expect(!FileManager.default.fileExists(atPath: output.path))
        gate.release()
        try await task.value
        #expect(try Data(contentsOf: output) == Data(contentsOf: source))
    }

    @Test func cancelledBeforeDispatchDoesNotPublish() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("staged"), output = root.appendingPathComponent("output")
        try Data("keep".utf8).write(to: source)
        let task = Task { @MainActor in
            try await ExportPublication.publishAsync(staged: source, destination: output)
        }
        task.cancel()
        do { try await task.value; Issue.record("Pre-cancelled publication ran") }
        catch { #expect(error is CancellationError) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)), arguments: [false, true])
    func cancelledPublicationSettlesBeforeCleanupAndPreservesOutcome(competingOutput: Bool) async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover())
        let source = root.appendingPathComponent("source.mkv")
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=0.25", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        try #require(generated.status == 0)
        let sourceBytes = try Data(contentsOf: source)
        let prior = root.appendingPathComponent("prior.mkv"), priorBytes = Data("previous output".utf8)
        try priorBytes.write(to: prior)
        var c = EncodeConfiguration(); c.codec = "H.264"; c.encoder = "x264"; c.container = "MKV"
        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"; c.picture.deinterlace = "Off"; c.resolution = "Original"; c.speed = "Fast"
        let jobs = (0..<2).map { QueueJob(id: UUID(), source: source.path, isDemo: false,
            destination: root.appendingPathComponent("result\($0).mkv").path, configuration: c, created: Date()) }
        let gate = PublicationGate(); defer { gate.release() }
        var cleanupCalled = false
        let journal = root.appendingPathComponent("journal.json")
        let batch = BatchController(journalURL: journal, publishOutput: { staged, output in
            try await ExportPublication.publishAsync(staged: staged, destination: output, operation: { try gate.publish($0, $1) })
        }, removeStaging: { directory in
            cleanupCalled = true
            try await ExportStaging.remove(directory)
        })
        defer { if batch.running { batch.cancel() } }
        batch.tools = tools; batch.encoders = ["libx264"]; batch.start(jobs)
        while batch.running && !gate.snapshot.0 { try await Task.sleep(for: .milliseconds(5)) }
        try #require(gate.snapshot.0 && batch.running)
        #expect(!gate.snapshot.1)
        #expect(batch.publicationJobID == jobs[0].id)
        let staged = try #require(gate.snapshot.2)
        let output = URL(fileURLWithPath: jobs[0].destination)
        #expect(!cleanupCalled && FileManager.default.fileExists(atPath: staged.path))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        let inFlight = try BatchJournal.read(from: journal)
        #expect(inFlight.restoredStatuses()[jobs[0].id]?.phase == "Interrupted")
        batch.cancel()
        // Yield while cancelled: cleanup must still await the real filesystem result.
        try await Task.sleep(for: .milliseconds(30))
        #expect(batch.running && !cleanupCalled && batch.publicationJobID == jobs[0].id)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        let competitor = Data("arrived during publication".utf8)
        if competingOutput { try competitor.write(to: output) }
        gate.release()
        while batch.running { try await Task.sleep(for: .milliseconds(5)) }
        #expect(cleanupCalled && batch.publicationJobID == nil)
        #expect(batch.statuses[jobs[1].id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: jobs[1].destination))
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: prior) == priorBytes)
        let restored = try BatchJournal.read(from: journal).restoredStatuses()
        if competingOutput {
            #expect(batch.statuses[jobs[0].id]?.phase == "Failed")
            #expect(batch.statuses[jobs[0].id]?.detail.contains("nothing was overwritten") == true)
            #expect(try Data(contentsOf: output) == competitor)
            #expect(restored[jobs[0].id]?.phase == "Failed")
        } else {
            #expect(batch.statuses[jobs[0].id]?.phase == "Completed")
            #expect(batch.statuses[jobs[0].id]?.detail.contains("stopped after this output") == true)
            #expect(restored[jobs[0].id]?.phase == "Completed")
            let probe = try await MediaProbe.read(output, tools: tools)
            #expect(probe.video?.codec_name == "h264" && probe.video?.width == 160)
        }
    }
}
