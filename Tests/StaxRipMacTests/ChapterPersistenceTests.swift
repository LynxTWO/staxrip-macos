import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct ChapterPersistenceTests {
    private var edits: ChapterEdits {
        .init(mode: .custom, entries: [.init(startMilliseconds: 0, endMilliseconds: 1250, title: "Opening 日本語")])
    }
    private func job(_ config: EncodeConfiguration, index: Int = 0) -> QueueJob {
        .init(id: UUID(), source: "/generated/source.mp4", isDemo: false, destination: "/generated/output-\(index).mkv",
              configuration: config, created: Date(timeIntervalSince1970: 1000))
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chapter-persistence-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); return root
    }
    @Test func byteDistinctChapterTitlesInvalidateIntentAndRemainUndoable() throws {
        let composed = "Caf\u{00E9}", decomposed = "Cafe\u{0301}"
        #expect(composed == decomposed)
        let model = WorkspaceModel(); model.config.chapterEdits = edits
        model.config.chapterEdits?.entries[0].title = composed
        model.clearSettingsHistory()
        let previous = model.sessionSnapshot, originalJob = job(model.config)
        let beforeDraft = ChapterDraft(try #require(model.config.chapterEdits?.entries.first))
        model.config.chapterEdits?.entries[0].title = decomposed
        let afterDraft = ChapterDraft(try #require(model.config.chapterEdits?.entries.first))
        #expect(beforeDraft != afterDraft)
        #expect(model.sessionSnapshot != previous)
        var changedJob = originalJob; changedJob.configuration = model.config
        #expect(changedJob != originalJob)
        #expect(model.canUndoSettings)
        model.undoSettings()
        #expect(model.config.chapterEdits?.entries[0].title.utf8.elementsEqual(composed.utf8) == true)
        model.redoSettings()
        #expect(model.config.chapterEdits?.entries[0].title.utf8.elementsEqual(decomposed.utf8) == true)
        let expected = ContainerPreservation(chapters: [.init(start: 0, end: 1, tick: 0.001, title: composed)], attachments: [])
        let data = try JSONSerialization.data(withJSONObject: ["streams": [], "chapters": [["time_base": "1/1000", "start": 0, "end": 1000, "tags": ["title": decomposed]]]])
        let actual = try JSONDecoder().decode(MediaProbe.self, from: data)
        #expect(throws: (any Error).self) { try expected.verify(actual) }
        #expect(throws: (any Error).self) { try ContainerPreservation.tag(["title": composed, "TITLE": decomposed], "title", limit: 4096) }
    }

    @Test func versionsRetainIntentAndRejectMislabelledLegacyDocuments() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        var config = EncodeConfiguration(); config.chapterEdits = edits
        let document = SessionDocument(sourcePath: "/generated/source.mp4", configuration: config, outputFolder: "/generated", outputStem: "output", jobs: [job(config)])
        #expect(document.version == 7)
        try document.write(to: root.appendingPathComponent("session.json"))
        #expect(try SessionDocument.read(from: root.appendingPathComponent("session.json")) == document)
        for version in 1...6 {
            var old = document; old.version = version
            #expect(throws: (any Error).self) { try old.validated() }
            old.configuration.chapterEdits = nil
            #expect(throws: (any Error).self) { try old.validated() }
            old.jobs[0].configuration.chapterEdits = nil
            _ = try old.validated()
        }
        var future = document; future.version = 8
        #expect(throws: (any Error).self) { try future.validated() }
        let journal = BatchJournal(jobs: document.jobs, statuses: [:])
        #expect(journal.version == 6)
        try journal.write(to: root.appendingPathComponent("journal.json"))
        #expect(try BatchJournal.read(from: root.appendingPathComponent("journal.json")).jobs == document.jobs)
        for version in 1...5 {
            var old = journal; old.version = version
            #expect(throws: (any Error).self) { try old.validated() }
            old.jobs[0].configuration.chapterEdits = nil; _ = try old.validated()
        }
        var unknown = journal; unknown.version = 7
        #expect(throws: (any Error).self) { try unknown.validated() }
        var raw = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        raw["chapterEdits"] = ["mode": "execute", "entries": []]
        #expect(throws: (any Error).self) { try JSONDecoder().decode(EncodeConfiguration.self, from: JSONSerialization.data(withJSONObject: raw)) }
        var invalid = document; invalid.jobs[0].configuration.chapterEdits?.entries[0].endMilliseconds = 0
        #expect(throws: (any Error).self) { try invalid.validated() }
    }

    @Test func oversizedWritesRetainExistingSessionAndRecoveryBytes() throws {
        let started = ContinuousClock.now
        func trace(_ event: String) {
            print("CHAPTER_STORAGE_STRESS uptime=\(ProcessInfo.processInfo.systemUptime) \(started.duration(to: .now)) \(event) main=\(Thread.isMainThread)")
        }
        trace("body entered")
        defer { trace("body returning") }
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        var config = EncodeConfiguration()
        config.chapterEdits = .init(mode: .custom, entries: (0..<1000).map {
            .init(startMilliseconds: Int64($0), endMilliseconds: Int64($0 + 1), title: String(repeating: "x", count: 600))
        })
        let jobs = (0..<10).map { job(config, index: $0) }
        let document = SessionDocument(configuration: EncodeConfiguration(), outputFolder: "/generated", outputStem: "output", jobs: jobs)
        _ = try document.validated() // Structural budget is distinct from encoded bytes.
        trace("structural validation returned")
        let prior = Data("Existing saved document".utf8)
        for name in ["session.json", "journal.json"] { try prior.write(to: root.appendingPathComponent(name)) }
        #expect(throws: (any Error).self) { try document.write(to: root.appendingPathComponent("session.json")) }
        trace("session write refusal returned")
        #expect(throws: (any Error).self) { try BatchJournal(jobs: jobs, statuses: [:]).write(to: root.appendingPathComponent("journal.json")) }
        trace("journal write refusal returned")
        #expect(try Data(contentsOf: root.appendingPathComponent("session.json")) == prior)
        #expect(try Data(contentsOf: root.appendingPathComponent("journal.json")) == prior)
        var excessive = document; excessive.jobs.append(job(config, index: 10))
        #expect(throws: (any Error).self) { try excessive.validated() }
    }

    @Test func presetsUndoAndQueueCopiesKeepSourceIntentSeparate() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let model = WorkspaceModel(); model.outputFolder = root; model.outputStem = "draft"
        model.sourceURL = URL(fileURLWithPath: "/generated/source.mp4")
        model.config.chapterEdits = edits; model.clearSettingsHistory()
        let original = model.config.chapterEdits
        model.addToQueue(); try #require(model.jobs.count == 1)
        model.config.chapterEdits?.entries[0].title = "New workspace title"
        #expect(model.jobs[0].configuration.chapterEdits == original)
        model.undoSettings(); #expect(model.config.chapterEdits == original)
        model.redoSettings(); #expect(model.config.chapterEdits?.entries[0].title == "New workspace title")
        let current = model.config
        let preset = CustomPreset(name: "Reusable", configuration: CustomPreset.recipe(current))
        #expect(preset.configuration.chapterEdits == nil)
        #expect(try preset.applying(to: current).chapterEdits == current.chapterEdits)
        #expect(!String(decoding: try PresetDocument(presets: [preset]).encoded(), as: UTF8.self).contains("chapterEdits"))
        #expect(throws: (any Error).self) { try CustomPreset(name: "Invalid", configuration: current).validate() }
        model.applyPreset("H.264 Quality"); #expect(model.config.chapterEdits == current.chapterEdits)
        model.showDemo(); #expect(model.config.chapterEdits == nil && !model.canUndoSettings)
        model.undoSettings(); #expect(model.config.chapterEdits == nil)
        #expect(model.jobs[0].configuration.chapterEdits == original)
        let restored = SessionDocument(sourcePath: "/generated/source.mp4", configuration: current, outputFolder: root.path, outputStem: "restored", jobs: [])
        model.restoreSession(restored)
        #expect(model.sourceNeedsReview && model.config.chapterEdits == current.chapterEdits)
    }
}
