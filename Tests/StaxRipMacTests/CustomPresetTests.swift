import Foundation
import Testing
import Darwin
@testable import StaxRipMac

@MainActor
struct CustomPresetTests {
    private func folder() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("presets-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: false); return d
    }
    @Test func recipesAreSourceIndependentAndRetainCurrentSourceEdits() throws {
        var original = EncodeConfiguration()
        original.cropTop = 12; original.cropBottom = 8; original.picture = PictureOptions(cropLeft: 10, cropRight: 14, deinterlace: "All frames", start: 2, end: 8)
        original.audioTracks = [3]; original.subtitleTracks = [7]; original.resolution = "1280 × 720"
        let recipe = CustomPreset(name: "Cinema", configuration: CustomPreset.recipe(original))
        try recipe.validate()
        #expect(recipe.configuration.cropTop == 0 && recipe.configuration.picture.start == 0)
        #expect(recipe.configuration.audioTracks == nil && recipe.configuration.subtitleTracks == nil)
        var current = EncodeConfiguration(); current.cropTop = 20; current.picture.cropRight = 4; current.picture.start = 10
        current.audioTracks = [1]; current.subtitleTracks = []
        let applied = try recipe.applying(to: current)
        #expect(applied.cropTop == 20 && applied.picture.cropRight == 4 && applied.picture.start == 10)
        #expect(applied.audioTracks == [1] && applied.subtitleTracks == [])
        #expect(applied.resolution == "1280 × 720" && applied.picture.deinterlace == "All frames")
        let data = try PresetDocument(presets: [recipe]).encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("sourcePath") && !text.contains("destination") && !text.contains("audioTracks"))
        #expect(try PresetDocument.decode(data).presets == [recipe])
        #expect(throws: (any Error).self) { try CustomPreset(name: "Invalid", configuration: original).validate() }
    }
    @Test func persistentLibraryRenameRemoveUndoAndImportExport() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("library.json"), exported = dir.appendingPathComponent("recipe.json")
        let store = CustomPresetStore(url: url)
        try store.save(name: " Compact ", configuration: EncodeConfiguration())
        let id = try #require(store.presets.first?.id)
        #expect(store.presets[0].name == "Compact")
        try store.exportRecipe(id, to: exported)
        let bytes = try Data(contentsOf: exported)
        #expect(throws: (any Error).self) { try store.exportRecipe(id, to: exported) }
        #expect(try Data(contentsOf: exported) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-preset-") })
        let reopened = CustomPresetStore(url: url); #expect(reopened.presets == store.presets)
        try store.rename(id, to: "Small film"); #expect(store.presets[0].name == "Small film")
        try store.remove(id); #expect(store.presets.isEmpty)
        try store.undo(); #expect(store.presets.first?.name == "Small film")
        try store.importRecipe(from: exported); #expect(store.presets.count == 2)
        #expect(store.presets[0].id != store.presets[1].id)
        #expect(throws: (any Error).self) { try store.importRecipe(from: exported) }
        #expect(throws: (any Error).self) { try store.save(name: "COMPACT", configuration: EncodeConfiguration()) }
    }
    @Test func corruptFutureOversizedAndSourceBoundRecipesRefuse() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        let malformed = Data("not json".utf8); try malformed.write(to: file)
        let store = CustomPresetStore(url: file)
        #expect(store.problem != nil)
        #expect(throws: (any Error).self) { try store.save(name: "New", configuration: EncodeConfiguration()) }
        #expect(try Data(contentsOf: file) == malformed)
        var doc = PresetDocument(presets: []); doc.version = 99
        #expect(throws: (any Error).self) { try PresetDocument.decode(JSONEncoder().encode(doc)) }
        #expect(throws: (any Error).self) { try PresetDocument.decode(Data(repeating: 32, count: 1_048_577)) }
        for name in ["", "two\nlines", String(repeating: "a", count: 65)] {
            #expect(throws: (any Error).self) { try CustomPreset(name: name, configuration: EncodeConfiguration()).validate() }
        }
        let repeated = CustomPreset(name: "Same", configuration: EncodeConfiguration())
        #expect(throws: (any Error).self) { try PresetDocument(presets: [repeated, repeated]).validated() }
        let many = (0...100).map { CustomPreset(name: "Recipe \($0)", configuration: EncodeConfiguration()) }
        #expect(throws: (any Error).self) { try PresetDocument(presets: many).validated() }
    }
    @Test func conflictsLockAndFailedWritesPreserveState() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("library.json")
        let first = CustomPresetStore(url: url), second = CustomPresetStore(url: url)
        try first.save(name: "First", configuration: EncodeConfiguration())
        let bytes = try Data(contentsOf: url)
        #expect(throws: (any Error).self) { try second.save(name: "Stale", configuration: EncodeConfiguration()) }
        #expect(second.presets.isEmpty && !second.canUndo)
        #expect(try Data(contentsOf: url) == bytes)
        second.reload(); #expect(second.presets == first.presets)
        let fd = open(url.appendingPathExtension("lock").path, O_RDWR)
        try #require(fd >= 0); defer { flock(fd, LOCK_UN); close(fd) }
        try #require(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: (any Error).self) { try second.save(name: "Locked", configuration: EncodeConfiguration()) }
        #expect(try Data(contentsOf: url) == bytes)
        let blockedParent = dir.appendingPathComponent("not-a-directory")
        let blocked = CustomPresetStore(url: blockedParent.appendingPathComponent("library.json"))
        try Data([1]).write(to: blockedParent)
        #expect(throws: (any Error).self) { try blocked.save(name: "Cannot write", configuration: EncodeConfiguration()) }
        #expect(blocked.presets.isEmpty && !blocked.canUndo)
    }
    @Test func settingsUndoIsBoundedAndPresetsAreSingleChanges() throws {
        let model = WorkspaceModel(), initial = model.config
        model.addToQueue(); let queued = model.jobs
        model.applyPreset("Everyday HEVC"); let hevc = model.config
        model.undoSettings(); #expect(model.config == initial && !model.canUndoSettings)
        model.redoSettings(); #expect(model.config == hevc)
        model.undoSettings(); model.config.quality = 20
        #expect(!model.canRedoSettings)
        let recipe = CustomPreset(name: "Saved", configuration: CustomPreset.recipe(hevc))
        let prior = model.config; try model.applyCustomPreset(recipe); model.undoSettings()
        #expect(model.config == prior && model.jobs == queued)
        model.clearSettingsHistory()
        for index in 0..<150 { model.config.quality = Double(index % 40) }
        var count = 0
        while model.canUndoSettings { model.undoSettings(); count += 1 }
        #expect(count == 100)
        model.restoreSession(model.sessionSnapshot)
        #expect(!model.canUndoSettings && !model.canRedoSettings)
        model.config.quality = 11; model.sourceURL = URL(fileURLWithPath: "/generated/new-source.mov")
        #expect(!model.canUndoSettings)
    }
    @Test func coupledControlIntermediateStatesCannotBeRestored() throws {
        let model = WorkspaceModel(), initial = model.config
        model.config.codec = "HEVC" // Invalid until encoder follows.
        model.config.encoder = "x265"
        model.undoSettings(); #expect(model.config == initial)
        model.redoSettings(); #expect(model.config.codec == "HEVC" && model.config.encoder == "x265")
        model.config.picture.end = -1
        model.undoSettings(); try SessionDocument.validate(model.config)
        #expect(!model.canRedoSettings)
    }
}
