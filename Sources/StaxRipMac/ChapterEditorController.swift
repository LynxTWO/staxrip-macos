import SwiftUI

struct ChapterDraft: Identifiable, Equatable {
    let id: UUID
    var title, start, end: String
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title.utf8.elementsEqual(rhs.title.utf8) && lhs.start == rhs.start && lhs.end == rhs.end
    }
    init(_ entry: ChapterEntry) {
        id = entry.id; title = entry.title
        start = ChapterEdits.secondsText(entry.startMilliseconds)
        end = ChapterEdits.secondsText(entry.endMilliseconds)
    }
    func entry() throws -> ChapterEntry {
        ChapterEntry(id: id, startMilliseconds: try ChapterEdits.milliseconds(start),
                     endMilliseconds: try ChapterEdits.milliseconds(end), title: title)
    }
}

struct ChapterImport: Sendable {
    let entries: [ChapterEntry]
    let probe: MediaProbe
    static func read(_ source: URL) async throws -> Self {
        guard let tools = FFmpegTools.discover() else { throw ChapterEdits.failure("Install FFmpeg and ffprobe to read source chapters.") }
        return try await withThrowingTaskGroup(of: Self.self) { group in
            group.addTask {
                let probe = try await MediaProbe.read(source, tools: tools)
                guard probe.video?.start_pts == 0, probe.seconds.isFinite, probe.seconds > 0, probe.seconds <= 604800 else {
                    throw ChapterEdits.failure("Import requires a known duration up to seven days and a video timeline starting at zero.")
                }
                let chapters = try ContainerPreservation.readChapters(probe)
                guard chapters.count <= 1000 else { throw ChapterEdits.failure("The editor supports at most 1000 chapters.") }
                let entries = try chapters.map { chapter -> ChapterEntry in
                    guard chapter.start >= 0, chapter.end <= min(probe.seconds, 604800) else {
                        throw ChapterEdits.failure("A source chapter is outside the supported source timeline.")
                    }
                    return ChapterEntry(startMilliseconds: Int64((chapter.start * 1000).rounded()),
                                        endMilliseconds: Int64((chapter.end * 1000).rounded()), title: chapter.title)
                }
                if !entries.isEmpty { try ChapterEdits(mode: .custom, entries: entries).validate() }
                try Task.checkCancellation()
                return Self(entries: entries, probe: probe)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw ChapterEdits.failure("Source chapter reading reached its time limit. Check that the source is available and retry.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

/// App lifetime ownership keeps a cancelled source reader alive until settlement.
@MainActor
final class ChapterEditorController: ObservableObject {
    typealias Reader = @Sendable (URL) async throws -> ChapterImport
    @Published var rows: [ChapterDraft] = []
    @Published private(set) var running = false
    @Published private(set) var status = ""
    private(set) var original = EncodeConfiguration()
    private var source: URL?
    private var importedProbe: MediaProbe?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let read: Reader
    init(read: @escaping Reader = { try await ChapterImport.read($0) }) { self.read = read }

    @discardableResult
    func begin(configuration: EncodeConfiguration, source: URL?) -> Bool {
        guard !running else { return false }
        generation = UUID(); original = configuration; self.source = source; importedProbe = nil
        rows = (configuration.chapterEdits?.entries ?? []).map(ChapterDraft.init)
        status = "Draft only. Apply saves this list to the current recipe."
        return true
    }
    var canImport: Bool { source != nil && !running }
    var issue: String? {
        do { _ = try edits(); return nil }
        catch { return error.localizedDescription }
    }
    func edits() throws -> ChapterEdits {
        let result = ChapterEdits(mode: .custom, entries: try rows.map { try $0.entry() })
        try result.validate()
        if let importedProbe {
            var next = original; next.chapterEdits = result
            _ = try ChapterPlan.make(probe: importedProbe, configuration: next, includeMetadata: false)
        }
        return result
    }
    func applying(to current: EncodeConfiguration, source currentSource: URL?) throws -> EncodeConfiguration {
        guard !running, current == original, currentSource == source else {
            throw ChapterEdits.failure("The source or settings changed while this editor was open. Cancel and reopen it before applying.")
        }
        var result = current; result.chapterEdits = try edits()
        try SessionDocument.validate(result)
        return result
    }
    func add() {
        guard !running, rows.count < 1000 else { return }
        let start = (try? rows.last.map { try ChapterEdits.milliseconds($0.end) }) ?? 0
        let end = min(start + 60_000, ChapterEdits.maximumMilliseconds)
        rows.append(ChapterDraft(.init(startMilliseconds: start, endMilliseconds: end, title: "Chapter \(rows.count + 1)")))
    }
    func remove(_ id: UUID) { guard !running else { return }; rows.removeAll { $0.id == id } }
    func split(_ id: UUID) {
        guard !running, rows.count < 1000, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        do {
            var entry = try rows[index].entry()
            guard entry.endMilliseconds - entry.startMilliseconds >= 2 else { throw ChapterEdits.failure("A chapter needs at least two milliseconds to split.") }
            let midpoint = entry.startMilliseconds + (entry.endMilliseconds - entry.startMilliseconds) / 2
            let second = ChapterEntry(startMilliseconds: midpoint, endMilliseconds: entry.endMilliseconds, title: entry.title + " (part 2)")
            entry.endMilliseconds = midpoint
            rows[index] = ChapterDraft(entry); rows.insert(ChapterDraft(second), at: index + 1)
        } catch { status = error.localizedDescription }
    }
    func sortByTime() {
        guard !running else { return }
        do { rows = try rows.map { (try ChapterEdits.milliseconds($0.start), $0) }.sorted { $0.0 < $1.0 }.map(\.1) }
        catch { status = error.localizedDescription }
    }
    func importSource() {
        guard !running, let source else { return }
        let id = UUID(); generation = id; let previous = rows
        running = true; status = "Reading source chapters…"
        task = Task { [self] in
            defer { running = false; task = nil }
            do {
                let result = try await read(source)
                guard generation == id, !Task.isCancelled else { status = "Source chapter import cancelled. Previous draft retained."; return }
                guard rows == previous else { status = "The draft changed during import. Source chapters were not applied."; return }
                rows = result.entries.map(ChapterDraft.init); importedProbe = result.probe
                status = result.entries.isEmpty ? "No source chapters reported. Add chapters to build a custom list." : "Source chapters copied into the draft. Imported times rounded to the nearest millisecond."
            } catch {
                status = generation != id || error is CancellationError ? "Source chapter import cancelled. Previous draft retained." : error.localizedDescription
            }
        }
    }
    func cancel() {
        generation = UUID(); task?.cancel()
        if running { status = "Stopping source chapter reading…" }
    }
    func report(_ error: Error) { status = error.localizedDescription }
}
