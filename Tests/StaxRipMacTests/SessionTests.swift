import Testing
import Foundation
@testable import StaxRipMac

@MainActor
struct SessionTests {
    @Test func roundTripPreservesWorkspaceAndIndependentQueue() throws {
        let model = WorkspaceModel()
        model.applyPreset("Everyday HEVC")
        model.config.cropTop = 12
        model.addToQueue()
        model.outputStem = "Next clip"
        let original = model.sessionSnapshot
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("session.json")
        try original.write(to: file)
        let result = try SessionDocument.read(from: file)
        #expect(result.configuration == original.configuration)
        #expect(result.jobs.map(\.id) == original.jobs.map(\.id))
        #expect(result.outputStem == "Next clip")
        let restored = WorkspaceModel()
        restored.restoreSession(result)
        #expect(restored.jobs[0].configuration.cropTop == 12)
        #expect(restored.config.codec == "HEVC")
    }

    @Test func malformedSessionsAreRejected() {
        let model = WorkspaceModel()
        model.addToQueue()
        let good = model.sessionSnapshot
        var future = good; future.version = 99
        #expect(throws: (any Error).self) { try future.validated() }
        var invalid = good; invalid.configuration.quality = .infinity
        #expect(throws: (any Error).self) { try invalid.validated() }
        var duplicate = good; duplicate.jobs.append(duplicate.jobs[0])
        #expect(throws: (any Error).self) { try duplicate.validated() }
        var wrongEncoder = good; wrongEncoder.configuration.encoder = "untrusted-binary"
        #expect(throws: (any Error).self) { try wrongEncoder.validated() }
        var path = good; path.sourcePath = "https://example.test/video.mov"
        #expect(throws: (any Error).self) { try path.validated() }
    }

    @Test func missingSourceRemainsAnUnavailableRealSource() {
        let model = WorkspaceModel()
        var document = model.sessionSnapshot
        document.sourcePath = "/nonexistent-synthetic-fixture/clip.mov"
        model.restoreSession(document)
        #expect(!model.isDemo)
        #expect(model.sourceUnavailable)
        #expect(model.player == nil)
        #expect(model.sourceName == "clip.mov")
    }
}
