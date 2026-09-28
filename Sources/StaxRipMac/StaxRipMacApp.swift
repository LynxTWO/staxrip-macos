import SwiftUI
import AppKit

@main
struct StaxRipMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = WorkspaceModel()
    @StateObject private var exporter = ExportController()
    @AppStorage("appearance") private var appearance = "System"
    var body: some Scene {
        Window("StaxRip", id: "main") {
            WorkspaceView()
                .environmentObject(model)
                .environmentObject(exporter)
                .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
                .frame(minWidth: 1120, minHeight: 750)
                .tint(Color.accent)
                .onAppear {
                    delegate.exporter = exporter
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1320, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Source…") { model.chooseSource() }.keyboardShortcut("o").disabled(exporter.running)
                Button("Save Session…") { model.saveSession() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Open Session…") { model.openSession() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(exporter.running)
                Button("Add Configuration to Queue") { model.addToQueue() }.keyboardShortcut("j")
            }
        }
    }
}

extension Color {
    static let accent = Color(red: 0.24, green: 0.73, blue: 0.64)
    static let ink = Color(red: 0.07, green: 0.12, blue: 0.15)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var exporter: ExportController?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard exporter?.running == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "An export is still running"
        alert.informativeText = "Wait for it to finish or use Cancel export before quitting."
        alert.addButton(withTitle: "Keep open")
        alert.runModal()
        return .terminateCancel
    }
}
