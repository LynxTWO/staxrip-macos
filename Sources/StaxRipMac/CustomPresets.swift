import Foundation
import Combine
import Darwin

struct CustomPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var configuration: EncodeConfiguration

    static func recipe(_ current: EncodeConfiguration) -> EncodeConfiguration {
        var c = current
        c.cropTop = 0; c.cropBottom = 0
        c.picture = PictureOptions(deinterlace: current.picture.deinterlace)
        c.audioTracks = nil; c.subtitleTracks = nil
        return c
    }
    func applying(to current: EncodeConfiguration) throws -> EncodeConfiguration {
        try validate()
        var next = configuration
        next.cropTop = current.cropTop; next.cropBottom = current.cropBottom
        var picture = current.picture; picture.deinterlace = configuration.picture.deinterlace
        next.picture = picture
        next.audioTracks = current.audioTracks; next.subtitleTracks = current.subtitleTracks
        try SessionDocument.validate(next)
        return next
    }
    var key: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    func validate() throws {
        guard name == name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 64, name.utf8.count <= 1024,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw SessionError.invalid("Preset names must contain 1 to 64 characters without control characters or surrounding spaces.")
        }
        try SessionDocument.validate(configuration)
        let p = configuration.picture
        guard configuration.cropTop == 0, configuration.cropBottom == 0, p.cropLeft == 0, p.cropRight == 0,
              p.start == 0, p.end == 0, configuration.audioTracks == nil, configuration.subtitleTracks == nil else {
            throw SessionError.invalid("A reusable preset cannot contain crop, trim or source track selections. Save those in a session instead.")
        }
    }
    var summary: String {
        let c = configuration
        return "\(c.codec) · \(c.rateSummary) · \(c.container) · \(c.colorMode) · \(c.resolution) · \(c.audio)"
    }
}

struct PresetDocument: Codable {
    var format = "staxrip-mac-preset-library"
    var version = 1
    var presets: [CustomPreset]
    func validated() throws -> Self {
        guard format == "staxrip-mac-preset-library", version == 1, presets.count <= 100 else {
            throw SessionError.invalid("Unsupported preset library version or more than 100 presets.")
        }
        var names = Set<String>(), ids = Set<UUID>()
        for p in presets {
            try p.validate()
            guard names.insert(p.key).inserted, ids.insert(p.id).inserted else { throw SessionError.invalid("Preset names and identifiers must be unique.") }
        }
        return self
    }
    func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 1_048_576 else { throw SessionError.invalid("Preset library exceeds 1 MiB.") }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576 else { throw SessionError.invalid("Preset file exceeds 1 MiB.") }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
    static func readBytes(_ url: URL) throws -> Data? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw SessionError.invalid("Cannot inspect preset storage. Check file permissions and retry.")
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw SessionError.invalid("Preset storage must be a regular local file; symbolic links are not replaced.") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw SessionError.invalid("Preset file exceeds 1 MiB.") }
        return data
    }
}

@MainActor
final class CustomPresetStore: ObservableObject {
    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StaxRipMac", isDirectory: true).appendingPathComponent("presets-v1.json")
    }
    @Published private(set) var presets: [CustomPreset] = []
    @Published private(set) var problem: String?
    @Published private(set) var canUndo = false
    private var history: [[CustomPreset]] = []
    private var baseline: Data?
    private var loaded = false
    let url: URL

    init(url: URL = CustomPresetStore.defaultURL) { self.url = url; reload() }
    func reload() {
        do {
            let data = try PresetDocument.readBytes(url)
            let values = try data.map { try PresetDocument.decode($0).presets } ?? []
            presets = values; baseline = data; loaded = true; problem = nil
            history = []; canUndo = false
        } catch { loaded = false; problem = "Library could not be loaded. Its file was preserved. \(error.localizedDescription)" }
    }
    func save(name: String, configuration: EncodeConfiguration) throws {
        let item = CustomPreset(name: name.trimmingCharacters(in: .whitespacesAndNewlines), configuration: CustomPreset.recipe(configuration))
        try change(presets + [item])
    }
    func rename(_ id: UUID, to name: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw SessionError.invalid("Select a saved preset first.") }
        var next = presets; next[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try change(next)
    }
    func remove(_ id: UUID) throws {
        guard presets.contains(where: { $0.id == id }) else { return }
        try change(presets.filter { $0.id != id })
    }
    func undo() throws {
        guard let previous = history.last else { return }
        try persist(previous)
        history.removeLast(); canUndo = !history.isEmpty
    }
    func importRecipe(from file: URL) throws {
        guard let data = try PresetDocument.readBytes(file) else { throw SessionError.invalid("The preset file is missing.") }
        let document = try PresetDocument.decode(data)
        guard document.presets.count == 1 else { throw SessionError.invalid("Import one recipe at a time. This file does not contain exactly one preset.") }
        var item = document.presets[0]; item.id = UUID()
        try change(presets + [item])
    }
    func exportRecipe(_ id: UUID, to file: URL) throws {
        guard let item = presets.first(where: { $0.id == id }) else { throw SessionError.invalid("Select a preset to export.") }
        let data = try PresetDocument(presets: [item]).encoded()
        let staging = file.deletingLastPathComponent().appendingPathComponent(".staxrip-preset-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        var operationError: Error?
        var published = false
        do {
            let completed = staging.appendingPathComponent("recipe.json")
            try data.write(to: completed, options: .withoutOverwriting)
            try ExportPublication.publish(staged: completed, destination: file)
            published = true
        } catch { operationError = error }
        do { try FileManager.default.removeItem(at: staging) }
        catch { throw NativeExportCleanupError(directory: staging, publishedOutput: published ? file : nil, operationError: operationError, cleanupError: error) }
        if let operationError { throw operationError }
    }
    private func change(_ next: [CustomPreset]) throws {
        let previous = presets
        try persist(next)
        history.append(previous)
        if history.count > 10 { history.removeFirst(history.count - 10) }
        canUndo = !history.isEmpty
    }
    private func persist(_ next: [CustomPreset]) throws {
        guard loaded else { throw SessionError.invalid("Reload a valid library before making changes. The existing file will not be overwritten.") }
        let encoded = try PresetDocument(presets: next).encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw SessionError.invalid("Cannot open the preset library lock. Check folder permissions and retry.") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw SessionError.invalid("Another app instance is updating presets. Reload and retry.") }
        defer { flock(fd, LOCK_UN) }
        guard try PresetDocument.readBytes(url) == baseline else {
            throw SessionError.invalid("The preset library changed in another window or app. Reload before changing it.")
        }
        try encoded.write(to: url, options: .atomic)
        presets = next; baseline = encoded; problem = nil
    }
}
