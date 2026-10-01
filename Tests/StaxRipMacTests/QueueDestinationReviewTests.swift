import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct QueueDestinationReviewTests {
    private final class Panels: WorkspacePanelPresenting {
        var selections: [(WorkspaceFileRequest, @MainActor (URL?) -> Void)] = []
        var available = true
        func select(_ request: WorkspaceFileRequest, completion: @escaping @MainActor (URL?) -> Void) -> Bool {
            guard available else { return false }
            selections.append((request, completion)); return true
        }
        func confirmReplacement(completion: @escaping @MainActor (Bool) -> Void) -> Bool { false }
    }
    private struct Fixture {
        let root, first, second, journal: URL
        let panels: Panels
        let model: WorkspaceModel
        let batch: BatchController
        let originalJournal: Data
    }
    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("queue-destinations-" + UUID().uuidString)
        let first = root.appendingPathComponent("Output A", isDirectory: true), second = root.appendingPathComponent("Output B", isDirectory: true)
        for folder in [first, second] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let panels = Panels(), model = WorkspaceModel(filePanels: panels)
        var config = EncodeConfiguration(); config.selectCodec("H.264"); config.audio = "No audio"
        config.audioTracks = []; config.subtitleTracks = []; config.subtitleMode = "Remove all subtitles"
        model.jobs = [(first, "one.mkv"), (first, "two.mkv"), (second, "three.mkv")].map { folder, name in
            QueueJob(id: UUID(), source: root.appendingPathComponent("source.mp4").path, isDemo: false,
                     destination: folder.appendingPathComponent(name).path, configuration: config, created: Date(timeIntervalSince1970: 1000))
        }
        let journal = root.appendingPathComponent("previous.json")
        try BatchJournal(jobs: model.jobs, statuses: [:]).write(to: journal)
        let batch = BatchController(journalURL: journal)
        // Non-executing lifecycle cases must never invoke these tools.
        batch.tools = FFmpegTools(ffmpeg: URL(fileURLWithPath: "/usr/bin/false"), ffprobe: URL(fileURLWithPath: "/usr/bin/false"))
        return Fixture(root: root, first: first, second: second, journal: journal, panels: panels,
                       model: model, batch: batch, originalJournal: try Data(contentsOf: journal))
    }
    private func expectUntouched(_ f: Fixture) throws {
        #expect(try Data(contentsOf: f.journal) == f.originalJournal)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.first.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.second.path).isEmpty)
    }

    @Test func sequentialReviewDeduplicatesAndCancellationPreservesRecovery() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let before = f.model.sessionSnapshot
        f.model.chooseQueueStart(using: f.batch)
        #expect(f.panels.selections.map(\.0) == [.reviewQueueDestination(f.first, position: 1, total: 2)])
        #expect(f.model.filePanelActive && !f.batch.running)
        f.model.chooseQueueStart(using: f.batch); f.model.chooseSource(); f.model.saveSession()
        #expect(f.panels.selections.count == 1)
        let old = f.panels.selections[0].1
        old(f.first)
        #expect(f.panels.selections.map(\.0) == [.reviewQueueDestination(f.first, position: 1, total: 2), .reviewQueueDestination(f.second, position: 2, total: 2)])
        old(f.second); old(nil) // Cannot consume the newer folder's selection.
        #expect(f.model.filePanelActive && !f.batch.running && f.panels.selections.count == 2)
        try expectUntouched(f)
        f.panels.selections[1].1(nil)
        #expect(!f.model.filePanelActive && !f.batch.running && f.batch.statuses.isEmpty)
        #expect(f.model.sessionSnapshot == before && f.batch.recovery?.jobs == before.jobs)
        #expect(f.model.notice.contains("cancelled"))
        f.model.chooseQueueStart(using: f.batch)
        f.panels.selections[1].1(f.second)
        #expect(f.model.filePanelActive && f.panels.selections.count == 3 && !f.batch.running)
        f.panels.selections[2].1(nil)
        try expectUntouched(f)
    }

    @Test func mismatchAndUnavailablePresentationReleaseTheRequest() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        for location in [f.second, URL(string: "https://example.invalid/folder")!] {
            f.model.chooseQueueStart(using: f.batch)
            f.panels.selections.last!.1(location)
            #expect(!f.model.filePanelActive && !f.batch.running && f.model.notice.contains("different folder"))
        }
        f.panels.available = false
        f.model.chooseQueueStart(using: f.batch)
        #expect(!f.model.filePanelActive && !f.batch.running && f.model.notice.contains("Bring the workspace"))
        f.panels.available = true
        f.model.chooseQueueStart(using: f.batch)
        f.panels.available = false // Refuse the second sheet after matching the first.
        f.panels.selections.last!.1(f.first)
        #expect(!f.model.filePanelActive && !f.batch.running && f.model.notice.contains("Bring the workspace"))
        try expectUntouched(f)
    }

    @Test func changedIntentOrOperationsRefuseAtEitherFolder() throws {
        for step in 0...1 {
            for change in ["jobs", "order", "settings", "generation", "pending", "available", "running", "tools"] {
                let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
                var available = true
                f.model.chooseQueueStart(using: f.batch) { available }
                if step == 1 { f.panels.selections[0].1(f.first) }
                switch change {
                case "jobs": f.model.jobs[0].destination = f.first.appendingPathComponent("changed.mkv").path
                case "order": f.model.jobs.swapAt(0, 1)
                case "settings": f.model.config.quality = 19
                case "generation":
                    let before = f.model.sessionSnapshot
                    f.model.showDemo()
                    f.model.sourceURL = before.sourcePath.map { URL(fileURLWithPath: $0) }
                    f.model.config = before.configuration; f.model.outputStem = before.outputStem
                    f.model.outputFolder = URL(fileURLWithPath: before.outputFolder); f.model.jobs = before.jobs
                    #expect(f.model.sessionSnapshot == before)
                case "pending": f.batch.statuses[f.model.jobs[0].id] = BatchStatus(phase: "Completed")
                case "available": available = false
                case "running": f.batch.running = true
                default: f.batch.tools = nil
                }
                let current = f.model.sessionSnapshot
                f.panels.selections[step].1(step == 0 ? f.first : f.second)
                #expect(!f.model.filePanelActive && f.model.sessionSnapshot == current, Comment(rawValue: change))
                #expect(f.panels.selections.count == step + 1 && !f.model.notice.isEmpty)
                #expect(f.batch.running == (change == "running"))
                f.batch.running = false
                try expectUntouched(f)
            }
        }
    }

    @Test func emptyCompletedOrUnavailableQueueDoesNotPresent() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        f.model.chooseQueueStart(using: f.batch) { false }
        f.batch.running = true; f.model.chooseQueueStart(using: f.batch); f.batch.running = false
        let tools = f.batch.tools; f.batch.tools = nil; f.model.chooseQueueStart(using: f.batch); f.batch.tools = tools
        for job in f.model.jobs { f.batch.statuses[job.id] = BatchStatus(phase: "Completed") }
        f.model.chooseQueueStart(using: f.batch)
        #expect(f.model.notice.contains("No pending"))
        f.model.jobs = []; f.model.chooseQueueStart(using: f.batch)
        #expect(f.panels.selections.isEmpty && !f.model.filePanelActive && !f.batch.running)
        try expectUntouched(f)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func matchingFoldersStartOneRealBatchAndSkipCompletedDestinations() async throws {
        let started = ContinuousClock.now
        func trace(_ stage: String) { print("DESTINATION_REVIEW \(started.duration(to: .now)) \(stage)") }
        trace("fixture start")
        let f = try fixture()
        defer { if f.batch.running { f.batch.cancel() } else { try? FileManager.default.removeItem(at: f.root) } }
        let tools = try #require(FFmpegTools.discover()), source = f.root.appendingPathComponent("source.mp4")
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=0.5", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        try #require(generated.status == 0)
        trace("generated source ready")
        let original = try Data(contentsOf: source)
        let prior = f.root.appendingPathComponent("prior.mkv"); try Data("Existing completed output".utf8).write(to: prior)
        let completed = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: prior.path,
                                 configuration: f.model.jobs[0].configuration, created: Date(timeIntervalSince1970: 1000))
        f.model.jobs.insert(completed, at: 0); f.batch.statuses[completed.id] = BatchStatus(phase: "Completed", progress: 1, destination: prior)
        f.batch.tools = tools; f.batch.encoders = ["libx264"]
        f.model.chooseQueueStart(using: f.batch)
        #expect(f.panels.selections[0].0 == .reviewQueueDestination(f.first, position: 1, total: 2))
        f.panels.selections[0].1(f.first.appendingPathComponent("..").appendingPathComponent("Output A"))
        #expect(!f.batch.running && f.model.filePanelActive)
        try expectUntouched(f)
        f.panels.selections[1].1(f.second)
        try #require(f.batch.running && !f.model.filePanelActive)
        f.panels.selections[0].1(f.first); f.panels.selections[1].1(f.second)
        f.model.chooseQueueStart(using: f.batch)
        #expect(f.panels.selections.count == 2)
        trace("review complete; batch started")
        var lastPhases = ""
        do {
            while f.batch.running {
                let phases = f.model.jobs.dropFirst().map { f.batch.statuses[$0.id]?.phase ?? "No status" }.joined(separator: ",")
                if phases != lastPhases { trace(phases); lastPhases = phases }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch { trace("cancelled while batch active: " + lastPhases); f.batch.cancel(); throw error }
        trace("batch settled")
        for job in f.model.jobs.dropFirst() {
            try #require(f.batch.statuses[job.id]?.phase == "Completed", Comment(rawValue: f.batch.statuses[job.id]?.detail ?? "No status"))
            let probe = try await MediaProbe.read(URL(fileURLWithPath: job.destination), tools: tools)
            trace("independent probe finished: " + URL(fileURLWithPath: job.destination).lastPathComponent)
            #expect(probe.video?.codec_name == "h264" && abs(probe.seconds - 0.5) < 0.01)
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: prior) == Data("Existing completed output".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.first.path).sorted() == ["one.mkv", "two.mkv"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.second.path) == ["three.mkv"])
        let saved = try BatchJournal.read(from: f.journal)
        #expect(saved.jobs == f.model.jobs && saved.statuses.values.allSatisfy { $0.phase == "Completed" })
        f.model.chooseQueueStart(using: f.batch)
        #expect(f.panels.selections.count == 2 && !f.batch.running)
        trace("all assertions finished")
    }
}
