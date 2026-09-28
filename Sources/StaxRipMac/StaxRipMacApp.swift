import SwiftUI
import AppKit

@main
struct StaxRipMacApp: App {
    @StateObject private var model = WorkspaceModel()
    var body: some Scene {
        Window("StaxRip", id: "main") {
            WorkspaceView()
                .environmentObject(model)
                .frame(minWidth: 1120, minHeight: 750)
                .tint(Color.accent)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1320, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Source…") { model.chooseSource() }.keyboardShortcut("o")
                Button("Save Session…") { model.saveSession() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Open Session…") { model.openSession() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Add Configuration to Queue") { model.addToQueue() }.keyboardShortcut("j")
            }
        }
    }
}

extension Color {
    static let accent = Color(red: 0.24, green: 0.73, blue: 0.64)
    static let ink = Color(red: 0.07, green: 0.12, blue: 0.15)
}
