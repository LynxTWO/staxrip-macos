import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct NativeExportPanelTests {
    private final class Panels: WorkspacePanelPresenting {
        var selections: [(WorkspaceFileRequest, @MainActor (URL?) -> Void)] = []
        var available = true
        func select(_ request: WorkspaceFileRequest, completion: @escaping @MainActor (URL?) -> Void) -> Bool {
            guard available else { return false }
            selections.append((request, completion)); return true
        }
        func confirmReplacement(completion: @escaping @MainActor (Bool) -> Void) -> Bool { false }
    }
    private func ready(_ panels: Panels) -> WorkspaceModel {
        let model = WorkspaceModel(filePanels: panels)
        model.sourceURL = URL(fileURLWithPath: "/generated/native-source.mp4")
        model.sourceUnavailable = false
        return model
    }
    @Test func cancelledUnavailableAndOldSelectionsPreserveCurrentResult() {
        let panels = Panels(), model = ready(panels), exporter = ExportController()
        let prior = URL(fileURLWithPath: "/generated/prior.mp4")
        exporter.result = prior; exporter.status = "Export complete"
        let before = model.sessionSnapshot
        model.chooseNativeExport(using: exporter)
        model.chooseNativeExport(using: exporter); model.chooseSource(); model.saveSession()
        #expect(panels.selections.count == 1 && model.filePanelActive)
        #expect(panels.selections[0].0 == .nativeExport(model.sourceURL!))
        panels.selections[0].1(nil)
        #expect(!model.filePanelActive && !exporter.running)
        #expect(exporter.result == prior && exporter.status == "Export complete")
        #expect(model.sessionSnapshot == before)
        model.chooseNativeExport(using: exporter)
        panels.selections[0].1(URL(fileURLWithPath: "/generated/stale.mp4"))
        #expect(model.filePanelActive && !exporter.running)
        panels.selections[1].1(nil)
        panels.available = false
        model.chooseNativeExport(using: exporter)
        #expect(!model.filePanelActive && panels.selections.count == 2)
        #expect(!exporter.running && exporter.result == prior)
        panels.available = true
        model.chooseNativeExport(using: exporter)
        #expect(model.filePanelActive && panels.selections.count == 3)
        panels.selections[2].1(nil)
    }

    @Test func changedIntentAndBusyExecutionCannotStartFromPendingPanel() {
        let output = URL(fileURLWithPath: "/generated/unwritten.mp4")
        for change in ["source", "generation", "preset", "availability", "running", "unavailable", "settings"] {
            let panels = Panels(), model = ready(panels), exporter = ExportController()
            var available = true
            let prior = URL(fileURLWithPath: "/generated/prior.mp4"); exporter.result = prior
            model.chooseNativeExport(using: exporter) { available }
            switch change {
            case "source": model.sourceURL = URL(fileURLWithPath: "/generated/other.mp4")
            case "generation":
                let before = model.sessionSnapshot
                model.showDemo()
                model.sourceURL = before.sourcePath.map { URL(fileURLWithPath: $0) }
                model.config = before.configuration; model.outputStem = before.outputStem
                #expect(model.sessionSnapshot == before) // Only the load identity differs.
                model.notice = ""
            case "preset": exporter.preset = .hevcHD
            case "availability": available = false
            case "running": exporter.running = true
            case "unavailable": model.sourceUnavailable = true
            default: model.config.quality = 19
            }
            let current = model.sessionSnapshot
            panels.selections[0].1(output)
            #expect(!model.filePanelActive && model.sessionSnapshot == current)
            #expect(exporter.result == prior && exporter.sourceName.isEmpty, Comment(rawValue: change))
            #expect(exporter.running == (change == "running"))
            #expect(!model.notice.isEmpty)
            exporter.running = false
        }
        let panels = Panels(), model = ready(panels), exporter = ExportController()
        model.chooseNativeExport(using: exporter) { false }
        exporter.running = true; model.chooseNativeExport(using: exporter); exporter.running = false
        model.sourceUnavailable = true; model.chooseNativeExport(using: exporter)
        model.restoreSession(SessionDocument(sourcePath: "/generated/saved.mp4", configuration: EncodeConfiguration(), outputFolder: "/generated", outputStem: "saved", jobs: []))
        model.sourceUnavailable = false // Review state must independently prohibit bypass.
        model.chooseNativeExport(using: exporter)
        #expect(panels.selections.isEmpty && !model.filePanelActive && !exporter.running)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func currentSelectionExportsOnceAndExistingOutputRemainsProtected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-panel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let panels = Panels(), model = ready(panels), exporter = ExportController()
        defer { if exporter.running { exporter.cancel() } else { try? FileManager.default.removeItem(at: root) } }
        let tools = try #require(FFmpegTools.discover()), source = root.appendingPathComponent("source.mp4"), output = root.appendingPathComponent("output.mp4")
        let generated = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=0.5", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        try #require(generated.status == 0)
        let sourceBytes = try Data(contentsOf: source)
        model.sourceURL = source; exporter.preset = .h264Small
        model.chooseNativeExport(using: exporter)
        panels.selections[0].1(output)
        try #require(exporter.running && !model.filePanelActive)
        panels.selections[0].1(root.appendingPathComponent("duplicate.mp4"))
        model.chooseNativeExport(using: exporter)
        #expect(panels.selections.count == 1)
        do { while exporter.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch { exporter.cancel(); throw error }
        try #require(exporter.failure == nil && exporter.result == output)
        let exported = try Data(contentsOf: output)
        #expect(!exported.isEmpty && !FileManager.default.fileExists(atPath: root.appendingPathComponent("duplicate.mp4").path))
        let probe = try await MediaProbe.read(output, tools: tools)
        #expect(probe.video?.codec_name == "h264")
        model.chooseNativeExport(using: exporter); panels.selections[1].1(nil)
        #expect(exporter.result == output && !exporter.running)
        model.chooseNativeExport(using: exporter); panels.selections[2].1(output)
        do { while exporter.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch { exporter.cancel(); throw error }
        #expect(exporter.failure != nil && exporter.status == "Export failed")
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: output) == exported)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["output.mp4", "source.mp4"])
    }
}
