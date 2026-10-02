import AppKit
import Testing
@testable import StaxRipMac

@MainActor
struct DockStatusControllerTests {
    @Test func publishedChangesReachNativeBadgeAndMenuOnlyNavigates() async throws {
        let app = NSApplication.shared
        let oldBadge = app.dockTile.badgeLabel
        defer { app.dockTile.badgeLabel = oldBadge }
        app.dockTile.badgeLabel = "old"
        let model = WorkspaceModel(), exporter = ExportController(), batch = BatchController()
        let audio = AudioController(), picture = PicturePreviewController(), motion = MotionPreviewController(), chapters = ChapterEditorController()
        let dock = DockStatusController()
        var destinations: [String] = []
        dock.bind(model: model, exporter: exporter, batch: batch, audio: audio,
                  picture: picture, motion: motion, chapters: chapters) { destinations.append($0) }
        #expect(app.dockTile.badgeLabel == nil)
        exporter.running = true; exporter.progress = 0.427
        await nextMainTurn()
        #expect(app.dockTile.badgeLabel == "42%")
        exporter.progress = 1
        await nextMainTurn()
        #expect(app.dockTile.badgeLabel == "…")
        exporter.running = false; exporter.failure = "Private generated test failure"
        await nextMainTurn()
        #expect(app.dockTile.badgeLabel == "!")
        let menu = dock.menu()
        #expect(menu.items.contains { $0.title == "Attention needed" && !$0.isEnabled })
        #expect(!menu.items.contains { $0.title.contains("Private") })
        let queue = try #require(menu.items.first { $0.title == "Show Queue" })
        #expect(app.sendAction(try #require(queue.action), to: queue.target, from: queue))
        #expect(destinations == ["Queue"])
        #expect(!batch.running && !audio.running && !exporter.running && model.jobs.isEmpty)
        exporter.failure = nil
        await nextMainTurn()
        #expect(app.dockTile.badgeLabel == nil)
    }
    private func nextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
