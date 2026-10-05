import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct ExternalCaptionListTests {
    private let a = ExternalSubtitle(path: "/generated/a.srt", language: "eng", title: "English")
    private let b = ExternalSubtitle(path: "/generated/b.srt", language: "fra", title: "Français e\u{301}")
    private func job(_ c: EncodeConfiguration) -> QueueJob {
        QueueJob(id: UUID(), source: "/generated/source.mp4", isDemo: false, destination: "/generated/output.mkv", configuration: c, created: Date())
    }
    @Test func orderedReferencesHaveExplicitVersionAndPresetBoundaries() throws {
        var c = EncodeConfiguration(); c.externalCaptions = [b, a]
        let item = job(c)
        let session = SessionDocument(sourcePath: item.source, configuration: c, outputFolder: "/generated", outputStem: "workspace", jobs: [item])
        let restored = try JSONDecoder().decode(SessionDocument.self, from: JSONEncoder().encode(session)).validated()
        #expect(restored.version == 11 && restored.configuration.externalCaptions == [b, a])
        #expect(restored.jobs[0].configuration.externalCaptions == [b, a])
        #expect(restored.configuration.externalCaptions.allSatisfy { $0.access == nil })
        for version in 1...7 {
            var old = session; old.version = version
            #expect(throws: (any Error).self) { try old.validated() }
            old.configuration.externalCaptions = [a]
            #expect(throws: (any Error).self) { try old.validated() }
            old.jobs[0].configuration.externalCaptions = [a]
            if version >= 6 { _ = try old.validated() }
            else { old.configuration.externalCaptions = []; old.jobs[0].configuration.externalCaptions = []; _ = try old.validated() }
        }
        let journal = BatchJournal(jobs: [item], statuses: [item.id: BatchStatus(phase: "Verifying")])
        let recovery = try JSONDecoder().decode(BatchJournal.self, from: JSONEncoder().encode(journal)).validated()
        #expect(recovery.version == 10 && recovery.jobs[0].configuration.externalCaptions == [b, a])
        #expect(recovery.restoredStatuses()[item.id]?.phase == "Interrupted")
        for version in 1...6 {
            var old = journal; old.version = version
            #expect(throws: (any Error).self) { try old.validated() }
            old.jobs[0].configuration.externalCaptions = version >= 5 ? [a] : []
            _ = try old.validated()
        }
        let recipe = CustomPreset(name: "Reusable", configuration: CustomPreset.recipe(c))
        #expect(recipe.configuration.externalCaptions.isEmpty && recipe.configuration.additionalExternalSubtitles == nil)
        #expect(try recipe.applying(to: c).externalCaptions == [b, a])
        #expect(throws: (any Error).self) { try CustomPreset(name: "Bad", configuration: c).validate() }
        let model = WorkspaceModel(); model.config = c
        model.config.externalCaptions = [a, b]; model.undoSettings()
        #expect(model.config.externalCaptions == [b, a])
        model.redoSettings(); #expect(model.config.externalCaptions == [a, b])
        c.externalCaptions = [b]; #expect(c.additionalExternalSubtitles == nil && c.externalSubtitle == b)
        c.externalCaptions = []; #expect(c.additionalExternalSubtitles == nil && c.externalSubtitle == nil)
    }
    @Test func invalidListsAndStaleNativeSelectionCannotChangeIntent() throws {
        var c = EncodeConfiguration(); c.externalCaptions = [a, b]
        try c.validateExternalCaptions()
        for list in [[a, a], [a, ExternalSubtitle(path: "/generated/other/../a.srt")],
                     (0..<9).map { ExternalSubtitle(path: "/generated/\($0).srt") }] {
            var bad = c; bad.externalCaptions = list
            #expect(throws: (any Error).self) { try bad.validateExternalCaptions() }
        }
        var bad = c; bad.externalSubtitle = nil
        #expect(throws: (any Error).self) { try bad.validateExternalCaptions() }
        bad = c; bad.additionalExternalSubtitles = []
        #expect(throws: (any Error).self) { try bad.validateExternalCaptions() }
        bad = c; bad.additionalExternalSubtitles?[0].language = "INVALID"
        #expect(throws: (any Error).self) { try bad.validateExternalCaptions() }
        let request = CaptionFileSelection(references: c.externalCaptions, source: "/generated/source.mp4", replacing: 1)
        let selected = URL(fileURLWithPath: "/generated/replacement.srt")
        let changed = try request.applying(selected, current: c, source: "/generated/source.mp4")
        #expect(changed[0] == a && changed[1].path == selected.path && changed[1].language == b.language && changed[1].title == b.title)
        #expect(c.externalCaptions == [a, b])
        for list in [[b, a], [a], [], [a, ExternalSubtitle(path: b.path, language: "deu", title: b.title)]] {
            var newer = c; newer.externalCaptions = list
            #expect(throws: (any Error).self) { try request.applying(selected, current: newer, source: "/generated/source.mp4") }
        }
        #expect(throws: (any Error).self) { try request.applying(selected, current: c, source: "/generated/another.mp4") }
        #expect(throws: (any Error).self) { try request.applying(URL(fileURLWithPath: a.path), current: c, source: "/generated/source.mp4") }
        c.externalCaptions = (0..<8).map { ExternalSubtitle(path: "/generated/\($0).srt") }
        try c.validateExternalCaptions()
        let full = CaptionFileSelection(references: c.externalCaptions, source: "/generated/source.mp4", replacing: nil)
        #expect(throws: (any Error).self) { try full.applying(selected, current: c, source: "/generated/source.mp4") }
    }

    @Test func plansRejectMissingReorderedOrExtraSnapshotsAndMapEachTrack() throws {
        let probe = try JSONDecoder().decode(MediaProbe.self, from: Data(#"{"streams":[{"index":0,"codec_name":"h264","codec_type":"video","width":160,"height":96,"pix_fmt":"yuv420p","start_pts":0},{"index":1,"codec_name":"subrip","codec_type":"subtitle"}],"format":{"format_name":"matroska","duration":"3","start_time":"0"}}"#.utf8))
        let docA = try SubRipDocument(data: Data("1\n00:00:00,000 --> 00:00:01,000\nEnglish\n\n".utf8))
        let docB = try SubRipDocument(data: Data("1\n00:00:01,000 --> 00:00:02,000\nFrançais\n\n".utf8))
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.audio = "No audio"; c.externalCaptions = [b, a]
        c.chapterEdits = ChapterEdits(mode: .custom, entries: [ChapterEntry(startMilliseconds: 0, endMilliseconds: 3000, title: "Whole")])
        let snapshots = [ExternalCaptionSnapshot(reference: b, document: docB), ExternalCaptionSnapshot(reference: a, document: docA)]
        func plan(_ snapshots: [ExternalCaptionSnapshot]) throws -> EncodePlan {
            try EncodePlan.make(job: job(c), probe: probe, encoders: ["libx264"], staged: URL(fileURLWithPath: "/generated/staging/encoded.mkv"), externalSnapshots: snapshots)
        }
        for wrong in [[], Array(snapshots.prefix(1)), snapshots.reversed().map { $0 }, snapshots + [snapshots[0]]] {
            #expect(throws: (any Error).self) { try plan(wrong) }
        }
        let result = try plan(snapshots)
        #expect(result.externalSubtitles.map(\.ordinal) == [1, 2] && result.subtitleCount == 3)
        #expect(result.externalSubtitles.map(\.document) == [docB, docA])
        let args = result.arguments
        #expect(args.indices.filter { args[$0] == "-map" }.map { args[$0 + 1] } == ["0:0", "0:1", "1:0", "2:0", "0:t?"])
        #expect(args[try #require(args.firstIndex(of: "-map_chapters")) + 1] == "3")
        #expect(args.contains("/generated/staging/external.srt") && args.contains("/generated/staging/external-2.srt"))
        #expect(throws: (any Error).self) {
            try EncodePlan.make(job: job(c), probe: probe, encoders: ["libx264"], staged: URL(fileURLWithPath: "/generated/staging/output.mkv"), externalDocument: docB)
        }
    }
    @Test func titleFilesAreLiteralBoundedExclusiveAndPrivate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caption-title-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        var edge = b; edge.title = String(repeating: "é", count: 510) + " =\\"
        #expect(edge.title.utf8.count == 1023)
        let titles = try ExternalCaptionTitles.make([edge, a])
        try await ExternalCaptionTitles.write(titles, to: root)
        for (index, bytes) in titles.enumerated() {
            let file = root.appendingPathComponent(ExternalCaptionTitles.filename(index))
            #expect(try Data(contentsOf: file) == bytes)
            #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        await #expect(throws: (any Error).self) { try await ExternalCaptionTitles.write([Data("title=replacement".utf8)], to: root) }
        #expect(try Data(contentsOf: root.appendingPathComponent(ExternalCaptionTitles.filename(0))) == titles[0])
        let links = root.appendingPathComponent("links")
        try FileManager.default.createDirectory(at: links, withIntermediateDirectories: false)
        let target = root.appendingPathComponent("protected"); try Data("Protected".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: links.appendingPathComponent(ExternalCaptionTitles.filename(0)), withDestinationURL: target)
        await #expect(throws: (any Error).self) { try await ExternalCaptionTitles.write(titles, to: links) }
        #expect(try Data(contentsOf: target) == Data("Protected".utf8))
        for invalid in [[Data(repeating: 65, count: 1031)], Array(repeating: Data("title=x".utf8), count: 9)] {
            await #expect(throws: (any Error).self) { try await ExternalCaptionTitles.write(invalid, to: root) }
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await ExternalCaptionTitles.write(titles, to: root.appendingPathComponent("absent"))
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    #if DEBUG
    @Test(.timeLimit(.minutes(1)))
    func cancelledSnapshotRetainsOwnershipUntilItsWriterSettles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caption-snapshot-cancel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("1\n00:00:00,000 --> 00:00:01,000\nOwned write\n\n".utf8)
        let document = try SubRipDocument(data: data), output = root.appendingPathComponent("snapshot.srt")
        let gate = CaptionSnapshotGate()
        let task = Task {
            defer { gate.markFinished() }
            try await SubRipDocument.$observeSnapshotBoundary.withValue({ gate.observe($0) }) {
                try await document.writeSnapshot(to: output)
            }
        }
        await gate.waitForEntry()
        task.cancel()
        #expect(!gate.finished)
        gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(gate.finished)
        #expect(try Data(contentsOf: output) == data)
        let absent = root.appendingPathComponent("absent.srt")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await document.writeSnapshot(to: absent)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(!FileManager.default.fileExists(atPath: absent.path))
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_CAPTION_SNAPSHOT_STRESS"] == "1"), .timeLimit(.minutes(1)))
    func actualCaptionSnapshotStartsDuringBoundedCPUContention() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount
        try #require((2...32).contains(count))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caption-snapshot-worker-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("1\n00:00:00,000 --> 00:00:01,000\nBounded writer\n\n".utf8)
        let document = try SubRipDocument(data: data), output = root.appendingPathComponent("snapshot.srt")
        let load = WorkerContentionLoad(count: count)
        do {
            try await SubRipDocument.$observeSnapshotBoundary.withValue({ load.observe($0) }) {
                try await document.writeSnapshot(to: output)
            }
        } catch { await load.settle(); throw error }
        await load.settle()
        let timing = load.lock.withLock { (load.ready, load.submitted, load.worker) }
        try #require(timing.0)
        let submitted = try #require(timing.1), entered = try #require(timing.2)
        let delay = submitted.duration(to: entered)
        print("CAPTION_SNAPSHOT_CONTENTION CPUs=\(count) submitted-to-worker=\(delay)")
        #expect(delay < .seconds(1))
        #expect(try Data(contentsOf: output) == data)
        await #expect(throws: (any Error).self) { try await document.writeSnapshot(to: output) }
        #expect(try Data(contentsOf: output) == data)
    }
    #endif

}

#if DEBUG
private final class CaptionSnapshotGate: @unchecked Sendable {
    private let entry = DispatchGroup(), lock = NSLock()
    let release = DispatchSemaphore(value: 0)
    private var didFinish = false
    init() { entry.enter() }
    var finished: Bool { lock.withLock { didFinish } }
    func markFinished() { lock.withLock { didFinish = true } }
    func observe(_ event: String) {
        if event == "worker entered" { entry.leave(); release.wait() }
    }
    func waitForEntry() async {
        await withCheckedContinuation { continuation in
            entry.notify(queue: DispatchQueue(label: "StaxRip.test-caption-snapshot-entry")) { continuation.resume() }
        }
    }
}
#endif
