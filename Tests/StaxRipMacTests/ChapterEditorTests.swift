import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct ChapterEditorTests {
    private final class Gate {
        var pending: [CheckedContinuation<ChapterImport, Error>?] = []
        func read(_ source: URL) async throws -> ChapterImport {
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
        func finish(_ index: Int, _ result: Result<ChapterImport, Error>) {
            let continuation = pending[index]; pending[index] = nil; continuation?.resume(with: result)
        }
        func cancelRemaining() {
            for index in pending.indices { finish(index, .failure(CancellationError())) }
        }
    }
    private var source: URL { URL(fileURLWithPath: "/generated/source.mp4") }
    private func imported() throws -> ChapterImport {
        let probe = try JSONDecoder().decode(MediaProbe.self, from: Data(#"{"streams":[{"index":0,"codec_type":"video","start_pts":0}],"format":{"duration":"6"}}"#.utf8))
        return ChapterImport(entries: [.init(startMilliseconds: 0, endMilliseconds: 6000, title: "Imported")], probe: probe)
    }
    private func configuration() -> EncodeConfiguration {
        var c = EncodeConfiguration()
        c.chapterEdits = .init(mode: .custom, entries: [.init(startMilliseconds: 0, endMilliseconds: 2000, title: "Current")])
        return c
    }
    private func settle(_ editor: ChapterEditorController) async {
        while editor.running { await Task.yield() }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledFailedAndStaleImportsRetainTheDraftUntilSettlement() async throws {
        let gate = Gate(); defer { gate.cancelRemaining() }
        let editor = ChapterEditorController(read: { try await gate.read($0) })
        let c = configuration(), imported = try imported()
        #expect(editor.begin(configuration: c, source: source))
        let original = editor.rows
        editor.importSource()
        while gate.pending.count < 1 { await Task.yield() }
        editor.cancel()
        #expect(editor.running && !editor.begin(configuration: c, source: source))
        #expect(throws: (any Error).self) { try editor.applying(to: c, source: source) }
        gate.finish(0, .success(imported)); await settle(editor)
        #expect(editor.rows == original && editor.status.contains("cancelled"))
        editor.importSource()
        while gate.pending.count < 2 { await Task.yield() }
        gate.finish(1, .failure(ChapterEdits.failure("Deliberate read failure"))); await settle(editor)
        #expect(editor.rows == original && editor.status.contains("Deliberate"))
        editor.importSource()
        while gate.pending.count < 3 { await Task.yield() }
        editor.rows[0].title = "Newer draft"
        gate.finish(2, .success(imported)); await settle(editor)
        #expect(editor.rows[0].title == "Newer draft" && editor.status.contains("draft changed"))
        #expect(c.chapterEdits?.entries[0].title == "Current")
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitImportAndApplyRequireCurrentSourceAndSettings() async throws {
        let result = try imported(), editor = ChapterEditorController(read: { _ in result })
        let c = configuration()
        editor.begin(configuration: c, source: source); editor.importSource(); await settle(editor)
        #expect(editor.rows.map(\.title) == ["Imported"] && editor.status.contains("nearest millisecond"))
        let applied = try editor.applying(to: c, source: source)
        #expect(applied.chapterEdits?.entries == result.entries)
        #expect(c.chapterEdits?.entries[0].title == "Current")
        var changed = c; changed.quality = 19
        #expect(throws: (any Error).self) { try editor.applying(to: changed, source: source) }
        #expect(throws: (any Error).self) { try editor.applying(to: c, source: URL(fileURLWithPath: "/generated/other.mp4")) }
        editor.rows[0].end = "6.001"
        #expect(editor.issue != nil)
        #expect(throws: (any Error).self) { try editor.applying(to: c, source: source) }
        editor.begin(configuration: c, source: nil); editor.importSource()
        #expect(!editor.running && !editor.canImport && editor.rows[0].title == "Current")
    }

    @Test func draftEditingPreservesIdentifiersAndInvalidTextCannotApply() throws {
        let editor = ChapterEditorController(), c = configuration()
        editor.begin(configuration: c, source: source)
        let first = try #require(editor.rows.first?.id)
        editor.split(first)
        #expect(editor.rows.count == 2 && editor.rows[0].id == first && editor.rows[1].id != first)
        #expect(editor.rows[0].end == "1.000" && editor.rows[1].start == "1.000")
        let split = try editor.applying(to: c, source: source)
        #expect(split.chapterEdits?.entries.count == 2)
        editor.rows.swapAt(0, 1); #expect(editor.issue != nil)
        editor.sortByTime(); #expect(editor.issue == nil && editor.rows[0].id == first)
        editor.rows[0].start = "1e3"
        #expect(throws: (any Error).self) { try editor.applying(to: c, source: source) }
        editor.remove(first); editor.add()
        #expect(editor.rows.count == 2 && editor.rows.last?.start == "2.000" && editor.rows.last?.end == "62.000")
        for row in editor.rows { editor.remove(row.id) }
        #expect(editor.issue != nil)
        #expect(throws: (any Error).self) { try editor.applying(to: c, source: source) }
    }
}
