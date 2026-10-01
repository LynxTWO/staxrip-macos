import Foundation
import Testing
@testable import StaxRipMac

struct WorkspaceRecipeTests {
    @Test func omittedTracksNeverPromiseCopiedOrEncodedMedia() throws {
        var c = EncodeConfiguration()
        let all = WorkspaceRecipe(c).entries
        c.audioTracks = []; c.subtitleTracks = []
        let empty = WorkspaceRecipe(c).entries
        #expect(empty[2].title == "No audio")
        #expect(empty[3].title == "No subtitles")
        #expect(all[2] != empty[2] && all[3] != empty[3])
        c.audioTracks = [1, 3]; c.subtitleTracks = [5]
        let selected = WorkspaceRecipe(c).entries
        #expect(selected[2].detail.contains("1, 3"))
        #expect(selected[3].detail.contains("5"))
        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"
        #expect(WorkspaceRecipe(c).entries[2].title == empty[2].title)
        #expect(WorkspaceRecipe(c).entries[3].title == empty[3].title)
        c.externalSubtitle = ExternalSubtitle(path: "/synthetic/private-folder/captions.srt", language: "eng")
        let external = WorkspaceRecipe(c).entries[3]
        #expect(external.title != "No subtitles")
        #expect(external.detail.contains("captions.srt (eng)"))
        #expect(!external.detail.contains("private-folder"))
    }

    @Test func transformIntentDoesNotPromiseMeasuredDimensionsOrSoftwareSpeedOnHardware() {
        var c = EncodeConfiguration()
        c.picture.start = 2.125; c.cropTop = 12; c.picture.cropLeft = 8
        c.resolution = "1280 × 720"
        let picture = WorkspaceRecipe(c).entries[0]
        #expect(picture.title.hasPrefix("Fit within"))
        #expect(picture.detail.contains(PicturePlan(c).summary))
        #expect(picture.detail.contains("source end"))
        #expect(picture.detail.contains("Chapters omitted"))
        c.selectCodec("HEVC"); c.selectBackend("Apple hardware"); c.speed = "Thorough"
        let video = WorkspaceRecipe(c).entries[1]
        #expect(video.title.contains("Target"))
        #expect(!video.title.contains("CRF"))
        #expect(!video.detail.lowercased().contains("thorough"))
        #expect(video.detail.contains("no software fallback"))
        c.picture.end = 8.5
        #expect(WorkspaceRecipe(c).entries[0].detail != picture.detail)
        c.colorMode = "Preserve static HDR10"
        #expect(WorkspaceRecipe(c).entries[1].detail.contains("requested"))
    }

    @MainActor @Test func recipeEditsFollowUndoAndQueueSnapshotsStayIndependent() {
        let model = WorkspaceModel()
        let initial = WorkspaceRecipe(model.config).entries
        model.config.audioTracks = []
        let omitted = WorkspaceRecipe(model.config).entries
        model.addToQueue()
        model.undoSettings()
        #expect(WorkspaceRecipe(model.config).entries == initial)
        #expect(WorkspaceRecipe(model.jobs[0].configuration).entries == omitted)
        model.redoSettings()
        #expect(WorkspaceRecipe(model.config).entries == omitted)
    }
}
