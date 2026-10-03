import SwiftUI
import AppKit

@main
struct StaxRipMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = WorkspaceModel()
    @StateObject private var exporter = ExportController()
    @StateObject private var audio = AudioController()
    @StateObject private var presets = CustomPresetStore()
    @StateObject private var picturePreview = PicturePreviewController()
    @StateObject private var motionPreview = MotionPreviewController()
    @StateObject private var chapters = ChapterEditorController()
    @StateObject private var batch = BatchController(journalURL: BatchJournal.defaultURL)
    @AppStorage("appearance") private var appearance = "System"
    var body: some Scene {
        Window("StaxRip", id: "main") {
            WorkspaceView()
                .environmentObject(model)
                .environmentObject(exporter)
                .environmentObject(batch)
                .environmentObject(audio)
                .environmentObject(picturePreview)
                .environmentObject(motionPreview)
                .environmentObject(chapters)
                .environmentObject(presets)
                .task { await batch.discover() }
                .onChange(of: model.jobs) { before, after in
                    batch.invalidateReview()
                    for old in before where !after.contains(old) { batch.reset(old.id) }
                }
                .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
                .frame(minWidth: 1120, minHeight: 750)
                .tint(Color.accent)
                .modifier(DockWindowBinding { openWindow in
                    delegate.dockStatus.bind(model: model, exporter: exporter, batch: batch, audio: audio,
                        picture: picturePreview, motion: motionPreview, chapters: chapters) { section in
                        model.section = section
                        openWindow(id: "main")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                })
                .onAppear {
                    delegate.exporter = exporter
                    delegate.batch = batch
                    delegate.audio = audio
                    delegate.picturePreview = picturePreview
                    delegate.motionPreview = motionPreview
                    delegate.chapters = chapters
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1320, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Source…") { model.chooseSource() }.keyboardShortcut("o").disabled(exporter.running || batch.running || model.filePanelActive)
                Button("Save Session…") { model.saveSession() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.filePanelActive)
                Button("Open Session…") { model.openSession() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(exporter.running || batch.running || model.filePanelActive)
                Button("Add Configuration to Queue") { model.addToQueue() }.keyboardShortcut("j").disabled(model.filePanelActive)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dockStatus = DockStatusController()
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { dockStatus.menu() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    weak var exporter: ExportController?
    weak var batch: BatchController?
    weak var audio: AudioController?
    weak var picturePreview: PicturePreviewController?
    weak var motionPreview: MotionPreviewController?
    weak var chapters: ChapterEditorController?
    func applicationWillTerminate(_ notification: Notification) { audio?.invalidateMaster() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard exporter?.running == true || batch?.running == true || batch?.reviewing == true || audio?.running == true || picturePreview?.running == true || motionPreview?.running == true || chapters?.running == true else {
            guard let motionPreview, motionPreview.workspace != nil else { return .terminateNow }
            Task { @MainActor in
                let cleaned = await motionPreview.finishClosing()
                if !cleaned {
                    let alert = NSAlert(); alert.messageText = "Motion preview cleanup needs attention"
                    alert.informativeText = motionPreview.status; alert.addButton(withTitle: "Keep open"); alert.runModal()
                }
                sender.reply(toApplicationShouldTerminate: cleaned)
            }
            return .terminateLater
        }
        let alert = NSAlert()
        alert.messageText = "An operation is still running"
        alert.informativeText = "Wait for it to finish or cancel the active operation before quitting."
        alert.addButton(withTitle: "Keep open")
        alert.runModal()
        return .terminateCancel
    }
}

// Read the action inside the main window's view environment, then retain the
// action in the Dock navigation closure so a closed window can be shown again.
private struct DockWindowBinding: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let bind: (OpenWindowAction) -> Void
    func body(content: Content) -> some View {
        content.onAppear { bind(openWindow) }
    }
}
