import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct ExternalSubtitlePersistenceTests {
    private var reference: ExternalSubtitle { ExternalSubtitle(path: "/generated/captions.srt", language: "fra", title: "Generated captions") }
    private func job(_ config: EncodeConfiguration) -> QueueJob {
        QueueJob(id: UUID(), source: "/generated/source.mp4", isDemo: false, destination: "/generated/output.mkv", configuration: config, created: Date())
    }
    @Test func byteDistinctTitlesInvalidateIntentAndRemainUndoable() {
        let composed = "Caf\u{00E9}", decomposed = "Cafe\u{0301}"
        #expect(composed == decomposed) // Swift's ordinary equality is canonically equivalent.
        let model = WorkspaceModel()
        model.config.externalSubtitle = ExternalSubtitle(path: "/generated/captions.srt", title: composed)
        model.clearSettingsHistory()
        let previous = model.sessionSnapshot
        let originalJob = job(model.config)
        model.config.externalSubtitle?.title = decomposed
        #expect(model.sessionSnapshot != previous)
        var editedJob = originalJob; editedJob.configuration = model.config
        #expect(editedJob != originalJob) // Queue result invalidation observes this equality.
        #expect(model.canUndoSettings)
        model.undoSettings()
        #expect(model.config.externalSubtitle?.title.utf8.elementsEqual(composed.utf8) == true)
        model.redoSettings()
        #expect(model.config.externalSubtitle?.title.utf8.elementsEqual(decomposed.utf8) == true)
    }

    @Test func versionedDocumentsRetainIntentAndRefuseMislabelledLegacyData() throws {
        var config = EncodeConfiguration(); config.externalSubtitle = reference
        let item = job(config)
        let document = SessionDocument(sourcePath: item.source, configuration: config, outputFolder: "/generated", outputStem: "workspace", jobs: [item])
        #expect(document.version == 12)
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SessionDocument.self, from: data).validated()
        #expect(decoded.configuration.externalSubtitle == reference)
        #expect(decoded.jobs[0].configuration.externalSubtitle == reference)
        #expect(decoded.configuration.externalSubtitle?.access == nil)
        for version in 1...5 {
            var old = document; old.version = version
            #expect(throws: (any Error).self) { try old.validated() }
            old.configuration.externalSubtitle = nil
            #expect(throws: (any Error).self) { try old.validated() }
            old.jobs[0].configuration.externalSubtitle = nil
            _ = try JSONDecoder().decode(SessionDocument.self, from: JSONEncoder().encode(old)).validated()
        }
        var future = document; future.version = 13
        #expect(throws: (any Error).self) { try future.validated() }
        var journal = BatchJournal(jobs: [item], statuses: [item.id: BatchStatus(phase: "Verifying")])
        #expect(journal.version == 11)
        let recovered = try JSONDecoder().decode(BatchJournal.self, from: JSONEncoder().encode(journal)).validated()
        #expect(recovered.jobs[0].configuration.externalSubtitle == reference)
        #expect(recovered.restoredStatuses()[item.id]?.phase == "Interrupted")
        for version in 1...4 {
            var old = journal; old.version = version
            #expect(throws: (any Error).self) { try old.validated() }
            old.jobs[0].configuration.externalSubtitle = nil
            _ = try old.validated()
        }
        journal.version = 12
        #expect(throws: (any Error).self) { try journal.validated() }
    }

    @Test func presetsCannotCarrySourceCaptionsAndApplyingRetainsCurrentReference() throws {
        var current = EncodeConfiguration(); current.externalSubtitle = reference
        let preset = CustomPreset(name: "Reusable", configuration: CustomPreset.recipe(current))
        #expect(preset.configuration.externalSubtitle == nil)
        let encoded = try PresetDocument(presets: [preset]).encoded()
        #expect(!String(decoding: encoded, as: UTF8.self).contains("externalSubtitle"))
        #expect(try preset.applying(to: current).externalSubtitle == reference)
        let bad = PresetDocument(presets: [CustomPreset(name: "Source-bound", configuration: current)])
        #expect(throws: (any Error).self) { try PresetDocument.decode(JSONEncoder().encode(bad)) }
        let model = WorkspaceModel(); model.config.externalSubtitle = reference
        model.applyPreset("H.264 Quality")
        #expect(model.config.externalSubtitle == reference)
        model.showDemo()
        #expect(model.config.externalSubtitle == nil && !model.canUndoSettings)
        model.undoSettings()
        #expect(model.config.externalSubtitle == nil)
        model.config.externalSubtitle = reference
        model.config.externalSubtitle?.title = "invalid\ntitle"
        model.addToQueue()
        #expect(model.jobs.isEmpty && model.error != nil)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)), arguments: ["mp4", "mkv"])
    func sourceLoadingClearsCaptionAndUndoButPreservesQueuedCopy(container: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("subtitle-source-isolation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let model = WorkspaceModel()
        defer { if !model.loading { try? FileManager.default.removeItem(at: root) } }
        let source = root.appendingPathComponent("source." + container)
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=0.25", "-c:v", "libx264", source.path])
        try #require(result.status == 0)
        model.outputFolder = root
        model.sourceURL = root.appendingPathComponent("previous.mp4")
        model.config.externalSubtitle = reference
        let chapters = ChapterEdits(mode: .custom, entries: [.init(startMilliseconds: 0, endMilliseconds: 200, title: "Opening")])
        model.config.chapterEdits = chapters
        model.addToQueue()
        try #require(model.jobs.count == 1)
        for _ in 0..<2 {
            model.config.externalSubtitle = reference
            model.config.chapterEdits = chapters
            model.load(source)
            while model.loading { try await Task.sleep(for: .milliseconds(10)) }
            #expect(model.sourceURL == source && model.error == nil)
            #expect(model.config.externalSubtitle == nil && !model.canUndoSettings)
            #expect(model.jobs[0].configuration.externalSubtitle == reference)
            #expect(model.config.chapterEdits == nil && model.jobs[0].configuration.chapterEdits == chapters)
            model.undoSettings()
            #expect(model.config.externalSubtitle == nil)
        }
        model.showDemo()
    }
}
