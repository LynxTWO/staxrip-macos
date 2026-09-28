import Testing
import Foundation
@testable import StaxRipMac

@MainActor
struct QueueTests {
    @Test func conflictingDestinationsAreRejected() {
        let model = WorkspaceModel()
        model.addToQueue()
        #expect(model.jobs.count == 1)
        #expect(model.outputIssue != nil)
        model.addToQueue()
        #expect(model.jobs.count == 1)
        model.outputStem = "Second version"
        #expect(model.outputIssue == nil)
        model.addToQueue()
        #expect(model.jobs.count == 2)
    }

    @Test func copiesAreIndependentAndCanBeReordered() {
        let model = WorkspaceModel()
        model.addToQueue()
        let original = model.jobs[0]
        model.duplicateJob(original)
        model.duplicateJob(original)
        #expect(Set(model.jobs.map(\.destination)).count == 3)
        var edited = model.jobs[1]
        edited.configuration.quality = 19
        model.updateJob(edited)
        #expect(model.jobs[0].configuration.quality == 28)
        #expect(model.config.quality == 28)
        #expect(model.jobs[1].configuration.quality == 19)
        model.moveJob(edited.id, by: -1)
        #expect(model.jobs[0].id == edited.id)
        model.moveJob(edited.id, by: -1)
        #expect(model.jobs[0].id == edited.id)
    }

    @Test func unsafeNamesAndSourceDestinationCollisionAreRejected() {
        for name in ["", "  ", ".", "..", "a/b", "a:b", "a\nb"] {
            #expect(WorkspaceModel.filenameIssue(name) != nil)
        }
        #expect(WorkspaceModel.filenameIssue("Trip – final") == nil)
        let model = WorkspaceModel()
        model.sourceURL = model.outputFolder.appendingPathComponent("clip.mkv")
        model.outputStem = "clip"
        #expect(model.outputIssue != nil)
    }

    @Test func demoResetPreservesQueueAndSettings() {
        let model = WorkspaceModel()
        model.applyPreset("Everyday HEVC")
        model.addToQueue()
        model.sourceURL = URL(fileURLWithPath: "/synthetic/example.mov")
        model.sourceName = "example.mov"
        model.showDemo()
        #expect(model.isDemo)
        #expect(model.sourceName == "Alpine escape.mov")
        #expect(model.config.codec == "HEVC")
        #expect(model.jobs.count == 1)
    }
}
